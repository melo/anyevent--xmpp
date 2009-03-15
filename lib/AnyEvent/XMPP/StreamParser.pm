package AnyEvent::XMPP::StreamParser;
use strict;
no warnings;
use Encode;
use AnyEvent::XMPP::Node;

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
   EMPTY_ELEM => 2,
   END_ELEM   => 3,
   DECL       => 4,
   ATTR       => 5,
   ATTR_LIST_END => 6,
   PARSED     => 7

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
      state       => 0,
      pstate      => 0,
      buf         => '',
      tokens      => [],
      nodestack   => [],
      ns_decl_stack => [ { xml => 'http://www.w3.org/XML/1998/namespace' } ],
      unknown_ns_cnt => 1,
   );
   bless $self, $class;

   return $self
}

sub feed_octets {
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
            push @$tokens, [ATTR_LIST_END];
            push @$tokens, [PARSED, $&];
            push @$tokens, [END_ELEM];
            $state = 0;
            next;

         } elsif ($buf =~ s/^$S?($Name)$S?=$S?(?:'([^']*)'|"([^"]*)")//o) {
            push @$tokens, [ATTR, $1 => $2 . $3];
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

sub parse_tokens {
   my ($self, $tokens) = @_;

   my $nstack  = $self->{nodestack};
   my $nsdecls = $self->{ns_decl_stack};
   my $curdecl = $nsdecls->[-1];
   my $state   = $self->{pstate};
   my $cur;

   while (@$tokens) {
      my $tok = shift @$tokens;
      unless (ref $tok) {
         $cur->add ($tok) if $cur;
         next;
      }

      my ($type, @args) = @$tok;
      warn "TOK {$type} [@args]\n";

      if ($type == ELEM) {
         push @$nsdecls, $curdecl = { %$curdecl };
         my ($ns, $name) = _strip_ns ($args[0], $curdecl, \$self->{unknown_ns_cnt});
         $cur = AnyEvent::XMPP::Node->new ($ns, $name);

      } elsif ($type == ATTR_LIST_END) {
         # FIXME: delay namespacing to ATTR_LIST_END, due to decls!
         if (@$nstack) {
            push @$nstack, $cur;

         } else {
            $cur->set_only_start;
            $self->stream_start ($cur);
            $cur = $cur->shallow_clone;
            $cur->set_only_end;
            push @$nstack, $cur;
         }

      } elsif ($type == EMPTY_ELEM || $type == END_ELEM) {
         next unless @$nstack;

         my $node = pop @$nstack;
         pop @$nsdecls;
         $cur = @$nstack ? $nstack->[-1] : undef;

         warn "NSTACK: " . scalar (@$nstack) . "\n";

         if (@$nstack == 0) {
            $self->stream_end ($node);

         } elsif (@$nstack == 1) {
            $self->recv ($node);
           
         } else {
            $cur->add ($node) if $cur;
         }

      } elsif ($type == ATTR) {
         next unless $cur;

         my ($ns, $attr) = _strip_ns ($args[0], $curdecl, \$self->{unknown_ns_cnt});
         if (not defined $ns) {
            $cur->attr ($attr, $args[1]);
         } else {
            $cur->attr_ns ($ns, $attr, $args[1]);
         }

      } elsif ($type == PARSED) {
         unless ($cur) {
            warn "CAN'T APPEND PARSED DATA: [$args[0]]\n";
            next;
         }
         $cur->append_parsed ($args[0]);
      }
   }

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

