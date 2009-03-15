package AnyEvent::XMPP::StreamParser;
use strict;
no warnings;

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
   ENDTAG     => 5,
   ATTR       => 6,

};
our $S    = qr/[\x20\x09\x0d\x0a]+/;
our $Name = qr/[\p{Letter}_:][^\x20\x09\x0d\x0a>=\/]*/;

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{status} = 0;
   $self->{buf}    = '';
   $self->{tokens} = [];

   return $self
}

sub tokenize_chunk {
   my ($self, $buf) = @_;

   $buf = $self->{buf} . $buf;

   my $status = $self->{status};
   my $tokens = [];

   while (1) {
      last if length $buf <= 0;

      if ($status == EL_START) {

         if ($buf =~ s/^($Name)($S|>|\/>)/\2/o) {
            push @$tokens, [ELEM, $1];
            $status = ATTR_LIST;
            next;

         } elsif ($buf =~ s/^\?xml([^>]+)\?>//o) {
            push @$tokens, [DECL, $1];
            next;

         } elsif ($buf =~ s/^\/($Name)$S?>//o) {
            push @$tokens, [END_ELEM, $1];
            $status = 0;
            next;

         } elsif ($buf =~ s/^!\[CDATA\[ ( (?: [^\]]+ | \][^\]] | \]\][^>] )* ) \]\]> //xo) {
            push @$tokens, $1; #TODO decode
            $status = 0;
            next;

         } else {
            last;
         }

      } elsif ($status == ATTR_LIST) {

         if ($buf =~ s/^$S?>//o) {
            $status = 0;
            next;

         } elsif ($buf =~ s/^$S?\/>//o) {
            push @$tokens, [EMPTY_ELEM];
            $status = 0;
            next;

         } elsif ($buf =~ s/^$S?($Name)$S?=$S?(?:'([^']*)'|"([^"]*)")//o) {
            push @$tokens, [ATTR, $1 => $2 . $3];
            next;

         } else {
            last;
         }

      } else {

         if ($buf =~ s/^<//o) {
            $status = EL_START;
            next;

         } elsif ($buf =~ s/^([^<]+)//o) {
            push @$tokens, $1;
            next;

         } else {
            last;
         }
      }
   }

   $self->{buf} = $buf;
   $self->{status} = $status;

   warn "[$buf][$status]\n";

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

