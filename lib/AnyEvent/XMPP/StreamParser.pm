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

};
our $S    = qr/[\x20\x09\x0d\x0a]+/;
our $Name = qr/[\p{Letter}_:][^\x20\x09\x0d\x0a>=\/]*/;

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = {
      max_buf_len => 102400,
      @_,
      state       => 0,
      pstate      => 0,
      buf         => '',
      tokens      => [],
      nodestack   => [],
   };
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
            $state = ATTR_LIST;
            next;

         } elsif ($buf =~ s/^\?xml([^>]+)\?>//o) {
            push @$tokens, [DECL, $1];
            next;

         } elsif ($buf =~ s/^\/($Name)$S?>//o) {
            push @$tokens, [END_ELEM, $1];
            $state = 0;
            next;

         } elsif ($buf =~ s/^!\[CDATA\[ ( (?: [^\]]+ | \][^\]] | \]\][^>] )* ) \]\]> //xo) {
            push @$tokens, $1; #TODO decode
            $state = 0;
            next;

         } else {
            last;
         }

      } elsif ($state == ATTR_LIST) {

         if ($buf =~ s/^$S?>//o) {
            push @$tokens, [ATTR_LIST_END];
            $state = 0;
            next;

         } elsif ($buf =~ s/^$S?\/>//o) {
            push @$tokens, [ATTR_LIST_END];
            push @$tokens, [EMPTY_ELEM];
            $state = 0;
            next;

         } elsif ($buf =~ s/^$S?($Name)$S?=$S?(?:'([^']*)'|"([^"]*)")//o) {
            push @$tokens, [ATTR, $1 => $2 . $3];
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

sub parse_tokens {
   my ($self, $tokens) = @_;

   my $nstack = $self->{nodestack};
   my $cur;

   for my $tok (@$tokens) {
      unless (ref $tok) {
         $cur->add ($tok) if $cur;
         next;
      }

      my ($type, @args) = @$tok;
      if ($type == ELEM) {
      } elsif ($type == EMPTY_ELEM) {
      } elsif ($type == END_ELEM) {
      } elsif ($type == ATTR) {
      } elsif ($type == DECL) {
      }
   }
   $tokens
}

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

