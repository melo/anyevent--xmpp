package AnyEvent::XMPP::Parser;
use strict;
no warnings;
use Encode;
use AnyEvent::XMPP::Node;
use AnyEvent::XMPP::Util qw/xml_unescape/;

use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::StreamParser - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item B<new (%args)>

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

sub feed {
   $_[0]->tokenize_chunk (decode ('utf-8', ${$_[1]}, Encode::FB_QUIET));
}

sub tokenize_chunk {
   my ($self, $buf) = @_;

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

         } elsif ($buf =~ s/^\?xml([^>]+)\?>//o) {
            push @$tokens, [DECL, $1];
            push @$tokens, [PARSED, '<' . $&];
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

               for my $nsattrname (keys %nsattrs) {
                  my ($ns, $attrname) = _strip_ns ($nsattrname, $curdecl, \$self->{unknown_ns_cnt});
                  $attrs{(defined ($ns) ? ($ns . '|') : '') . $attrname} = $nsattrs{$nsattrname};
               }

               my $ns;
               ($ns, $name) = _strip_ns ($name, $curdecl, \$self->{unknown_ns_cnt});
               $cur = AnyEvent::XMPP::Node->new ($ns, $name, \%attrs);
               $cur->append_parsed ($parsed);

               if (@$nstack) {
                  push @$nstack, $cur;

               } else {
                  if (defined $curdecl->{''}) {
                     $curdecl->{''} = 'ae:xmpp:stream:default_ns';
                  }

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

sub stream_start { }
sub stream_end { }
sub recv { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

