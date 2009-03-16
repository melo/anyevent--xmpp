package AnyEvent::XMPP::Parser;
use strict;
no warnings;
use Encode;
use AnyEvent::XMPP::Node;
use AnyEvent::XMPP::Util qw/xml_unescape/;

use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::StreamParser - XMPP Stream Parser

=head1 SYNOPSIS

   use AnyEvent::XMPP::Parser;

   my $p = AnyEvent::XMPP::Parser->new;

   $p->reg_cb (
      stream_start => sub {
         my ($p, $node) = @_;
         # $node contains the stream start tag and it's attributes
      },
      stream_end => sub {
         my ($p, $node) = @_;
         # $node contains the stream element and it's attributes
      },
      recv => sub {
         my ($p, $node) = @_;
         # $node is the AnyEvent::XMPP:Node structure of an XMPP Stanza.
      },
      feed_text => sub {
         my ($p, $text) = @_;
         warn "debug: processing raw unicode chars: [$text]\n"; 
      }
   );

   my $buf = ... # should be filled with a chunk of bytes from
                 # the TCP socket. 

   $p->feed (\$buf); # will try to decode as much utf-8 data as possible
                     # and process it.

=head1 DESCRIPTION

With L<AnyEvent::XMPP> version 0.9 the original expat parser has been
replaced with a new handwritten, more robust and liberal XMPP stream parser.

The parser can be fed with incoming byte data (usually from a TCP socket) by
passing the reference to the incoming buffer to the C<feed> method.
When the stream header has been completely received the C<stream_start>
event is emitted. All further XMPP stanzas, that have been received completely,
emit the C<recv> event with the stanza, in the form of an L<AnyEvent::XMPP::Node>
structure, as argument.

=head2 WHY XMPP SUCKS

B<First>: Read L<http://xmlsucks.org/> and explore L<http://c2.com/cgi/wiki?XmlSucks>.

I've changed from expat to my own implementation. This is mostly due
to the fact that XMPP B<is not> XML.

One of the main advantages of XML is the vast amount of tools to process it.
The problem with XMPP is, that most servers these days (first quarter of
2009) may forward not well formed XML, or at least not well formed XML
namespaces.

That means that any not well formed incoming XML data that is being parsed and
checked by a real XML parser will lead to an error, and thus close the XMPP
stream.  And this in turn means that anyone who manages to send some mildly not
well formed XML through your server to you is able to disconnect you.

Thus I've chosen to write my own pseudo XML XMPP stream parser, which is quite
liberal in what kind of XML it accepts and in case of undefined XML namespace
prefixes it copes by assigning own namespaces to it.

I deeply dislike the choice of XML as protocol, and I even more dislike the
way XMPP made use of XML. It requires processing partial XML data, which
makes the parsers more complicated than they would have to be.

Using XML for a protocol also introduces bloat and burns CPU cycles unnecessarily.
A JSON based protocol could me much more faster and easier to handle, and
also 'extensible', like XMPP claims to be (due to (ab)use of XML namespaces).
Some argue that one has to write his own XMPP parser anyway, for performance reasons.
But I wonder: Isn't the whole purpose of XML having stable and working tools ready
to process it for you?

So, if you choose XMPP as protocol for solving your problems please think twice
and make sure that performance and scalability requirements are met.

One might wonder why to use XMPP anyway: It's the only free and deployed
instant messaging protocol out there at the moment.  Also the XML buzzword
helped XMPP to have commercial deployments as well.  Other protocols are in
development, like PSYC (L<http://www.psyc.eu/>), but it's still unfinished and
not yet widely deployed. There is of course also IRC (Internet Relay Chat, see
RFC 1459 and RFC 2812), but IRC is more focused on chats between multiple
users. Also is IRC the best choice for multi user chats these days, as the
multi user chats that are based on XMPP suffer from even more serious
scalability problems than IRC ever did.

As a very educating read I recommend this thread on standards@xmpp.org:

L<http://mail.jabber.org/pipermail/standards/2008-October/020171.html>

=head1 A NOTE ABOUT NAMESPACES

This is an XMPP stream parser, and each XMPP stream has a default XML namespace
assigned to it, which is defined in the stream header. The problem here is,
that XMPP streams from client to server, from component to server and from
server to server have different default namespaces ('jabber:client',
'jabber:component:...' and 'jabber:server').

This parser will normalize all these default namespace to
'ae:xmpp:stream:default_ns'.  Other XMPP frameworks do a similar normalization
of the XMPP stream default namespace.

You will find the 'stanza' alias for that namespace in the
L<AnyEvent::XMPP:Namespaces> module, for more convenient processing.

Due to this normalization you don't need to track which kind of XMPP
application you are writing with L<AnyEvent::XMPP>, as the normalized internal
default namespace will be replaced when parsing and writing out XMPP stanzas.

This means that all XMPP stanzas given to you by the events emitted from a
parser object will be in the namespace 'ae:xmpp:stream:default_ns'.

=head1 METHODS

=over 4

=item $parser = AnyEvent::XMPP::Parser->new

Creates a new L<AnyEvent::XMPP::Parser> instance.

=cut

use constant {
   EL_START  => 1,
   ATTR_LIST => 2,

   ELEM       => 1,
   END_ELEM   => 2,
   DECL       => 3,
   ATTR       => 4,
   ATTR_LIST_END => 5,
   PARSED     => 6,

   P_ELEM_START => 1

};
our $S    = qr/[\x20\x09\x0d\x0a]+/;
our $Name = qr/[\p{Letter}_:][^\x20\x09\x0d\x0a>=\/]*/;

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (
      max_buf_len => 102400,
      @_,
      enable_methods => 1,
   );
   bless $self, $class;

   $self->init;

   return $self
}

=item $parser->init

Reinitializes the parser and resets it to the initial state so that a new
stream can be started. (Is implicitly called by the constructor C<new>).

=cut

sub init {
   my ($self) = @_;
   my %init = (
      state       => 0,
      pstate      => 0,
      buf         => '',
      tokens      => [],
      nodestack   => [],
      ns_decl_stack => [ { xml => 'http://www.w3.org/XML/1998/namespace' } ],
      unknown_ns_cnt => 1,
      cur_cdata   => '',
   );
   $self->{$_} = $init{$_} for keys %init;
}

=item $parser->feed (\$buf)

The first argument has to be a reference to a scalar.

This method tries to decode as much of the byte data in the
string buffer C<$buf> as possible. It may not process all data
from C<$buf> as it might contain only partial UTF-8 encoded unicode
text.

=cut

sub feed {
   $_[0]->tokenize_chunk (decode ('utf-8', ${$_[1]}, Encode::FB_QUIET));
}

sub tokenize_chunk {
   my ($self, $buf) = @_;

   $self->feed_text ($buf);

   $buf = $self->{buf} . $buf;

   my $state = $self->{state};
   my $tokens = [];

   while (1) {
      last if length $buf <= 0;

      if ($state == EL_START) {

         if ($buf =~ s/^($Name)($S|>|\/>)/\2/o) {
            push @$tokens, [ELEM, $1];
            push @$tokens, [PARSED, '<' . $1];
            $state = ATTR_LIST;
            next;

         } elsif ($buf =~ s/^\?xml([^>\?]+)\?>//o) {
            push @$tokens, [DECL, $1];
            push @$tokens, [PARSED, '<' . $&];
            $state = 0;
            next;

         } elsif ($buf =~ s/^\/($Name)$S?>//o) {
            push @$tokens, [PARSED, '<' . $&];
            push @$tokens, [END_ELEM, $1];
            $state = 0;
            next;

         } elsif ($buf =~ s/^!\[CDATA\[ ( (?: [^\]]+ | \][^\]] | \]\][^>] )* ) \]\]> //xo) {
            push @$tokens, $1; #TODO decode
            push @$tokens, [PARSED, '<' . $&];
            $state = 0;
            next;

         } else {
            last;
         }

      } elsif ($state == ATTR_LIST) {

         if ($buf =~ s/^$S?>//o) {
            push @$tokens, [PARSED, $&];
            push @$tokens, [ATTR_LIST_END];
            $state = 0;
            next;

         } elsif ($buf =~ s/^($S?)\/>//o) {
            push @$tokens, [PARSED, $&];
            push @$tokens, [ATTR_LIST_END];
            push @$tokens, [END_ELEM];
            $state = 0;
            next;

         } elsif ($buf =~ s/^$S?($Name)$S?=$S?(?:'([^']*)'|"([^"]*)")//o) {
            push @$tokens, [ATTR, $1, $2 . $3];
            push @$tokens, [PARSED, $&];
            next;

         } else {
            last;
         }

      } else {

         if ($buf =~ s/^<//o) {
            $state = EL_START;
            next;

         } elsif ($buf =~ s/^([^<]+)//o) {
            push @$tokens, $1;
            push @$tokens, [PARSED, $&];
            next;

         } else {
            last;
         }
      }
   }

   $self->{buf}   = $buf;
   $self->{state} = $state;

   if (length ($self->{buf}) > $self->{max_buf_len}) {
      die "unprocessed buffer limit ($self->{max_buf_len} bytes) reached\n";
   }

   $self->parse_tokens ($tokens);
}

sub _strip_ns {
   my ($qname, $nsdecl, $runknown_cnt, $attr) = @_;

   if ($qname =~ s/^([^:]+):(.*)$/\1/o) {
      my $ns = $nsdecl->{$1};
      unless (defined $ns) {
         $ns = $nsdecl->{$1} = 'aexmpp:unknown:' . $$runknown_cnt++
      }

      return ($ns, $2);
   } else {
      unless (defined $nsdecl->{''}) {
         $nsdecl->{''} = 'aexmpp:unknown:' . $$runknown_cnt++;
      }
      return (($attr ? undef : $nsdecl->{''}), $qname);
   }
}

sub _normalize_value {
   my ($str, $is_attr) = @_;
   $str =~ s/\xD\xA/\xA/g;
   $str =~ s/\xD/\xA/g;

   if ($is_attr) {
      $str =~ s/[\x09\x0d\x0a]/\x20/g;
      $str = xml_unescape ($str);
   } else {
      $str = xml_unescape ($str);
   }

   $str
}

sub parse_tokens {
   my ($self, $tokens) = @_;

   my $nstack  = $self->{nodestack};
   my $nsdecls = $self->{ns_decl_stack};
   my $curdecl = $nsdecls->[-1];
   my $state   = $self->{pstate};
   my $cdata   = $self->{cur_cdata};
   my $cur     = @$nstack ? $nstack->[-1] : undef;

   while (@$tokens) {
      my $tok = shift @$tokens;
      unless (ref $tok) {
         $cdata .= $tok;
         next;
      }

      my ($type, @args) = @$tok;

      if ($state) {
         my ($state_id, $name, @sattrs) = @$state;

         if ($state_id == P_ELEM_START) {
            if ($type == ATTR) {
               push @$state, @args;

            } elsif ($type == ATTR_LIST_END) {
               push @$nsdecls, $curdecl = { %$curdecl };

               my $parsed;

               my %nsattrs;
               while (@sattrs) {
                  if (ref ($sattrs[0])) {
                     $parsed .= join '', @{shift @sattrs};
                     next;
                  }

                  my ($attr, $val) = (shift @sattrs, _normalize_value (shift @sattrs, 1));

                  if ($attr =~ /^xmlns(?:\:(.*))?$/) {
                     if ($1 ne '') {
                        $curdecl->{$1} = $val;
                     } else {
                        $curdecl->{''} = $val;
                     }
                  } else {
                     $nsattrs{$attr} = $val;
                  }
               }

               my %attrs;

               unless (@$nstack) { # replace toplevel default namespace
                  if (defined $curdecl->{''}) {
                     $curdecl->{''} = 'ae:xmpp:stream:default_ns';
                  }
               }

               for my $nsattrname (keys %nsattrs) {
                  my ($ns, $attrname) = _strip_ns ($nsattrname, $curdecl, \$self->{unknown_ns_cnt}, 1);
                  $attrs{(defined ($ns) ? ($ns . '|') : '') . $attrname} = $nsattrs{$nsattrname};
               }

               my $ns;
               ($ns, $name) = _strip_ns ($name, $curdecl, \$self->{unknown_ns_cnt});
               $cur = AnyEvent::XMPP::Node->new ($ns, $name, \%attrs);
               $cur->append_parsed ($parsed);

               if (@$nstack) {
                  push @$nstack, $cur;

               } else {
                  $cur->set_only_start;
                  $self->stream_start ($cur);
                  $cur = $cur->shallow_clone;
                  $cur->set_only_end;
                  push @$nstack, $cur;
               }

               $state = undef;
            } elsif ($type == PARSED) {
               push @$state, [$args[0]];
            }

            next;
         }
      }

      if ($type == ELEM) {
         if ($cdata ne '') {
            $cur->add (_normalize_value ($cdata)) if $cur;
            $cdata = '';
         }
         $state = [P_ELEM_START, $args[0]];
         next;

      } elsif ($type == END_ELEM) {
         if ($cdata ne '') {
            $cur->add (_normalize_value ($cdata)) if $cur;
            $cdata = '';
         }

         next unless @$nstack;

         my $node = pop @$nstack;
         pop @$nsdecls;
         $curdecl = $nsdecls->[-1];
         $cur = @$nstack ? $nstack->[-1] : undef;

         if (@$nstack == 0) {
            $self->stream_end ($node);

         } elsif (@$nstack == 1) {
            $self->recv ($node);
           
         } else {
            $cur->add ($node) if $cur;
         }

      } elsif ($type == PARSED) {
         next unless $cur;
         $cur->append_parsed ($args[0]);
      }
   }

   $self->{cur_cdata} = $cdata;
   $self->{pstate} = $state;
   ()
}

=back

=head1 EVENTS

The L<AnyEvent::XMPP::Parser> implements the event callback
registration interface of L<Object::Event>. Following events
are emitted by the parser:

=over 4

=item stream_start => $node

=item stream_end => $node

=item recv => $node

=item feed_text => $unicodetext

=cut

sub stream_start { }
sub stream_end { }
sub recv { }
sub feed_text { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<AnyEvent::XMPP::Node>

L<AnyEvent::XMPP>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

