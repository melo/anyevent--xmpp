package AnyEvent::XMPP::Test;
use strict;
no warnings;

use Test::More;

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT = qw/$HOST $PORT $SECRET $SERVICE/;

=head1 NAME

AnyEvent::XMPP::Test - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=over 4

=cut

our ($HOST, $PORT, $SECRET, $SERVICE);

sub check {
   my ($what) = @_;

   if ($what eq 'component') {
      if ($ENV{ANYEVENT_XMPP_TEST_COMPONENT}) {
         ($HOST, $PORT, $SERVICE, $SECRET) =
            split /:/, $ENV{ANYEVENT_XMPP_TEST_COMPONENT};
      } else {
         plan skip_all => "ANYEVENT_XMPP_TEST_COMPONENT environment variable not set.";
         exit 0;
      }
   }
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

