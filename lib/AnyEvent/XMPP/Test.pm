package AnyEvent::XMPP::Test;
use strict;
no warnings;

use Test::More;

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT = qw/$HOST $PORT $SECRET $SERVICE $JID1 $JID2 $PASS/;

=head1 NAME

AnyEvent::XMPP::Test - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=over 4

=cut

our ($HOST, $PORT, $SECRET, $SERVICE);
our ($JID1, $JID2, $PASS);

sub check {
   my ($what) = @_;

   if ($ENV{ANYEVENT_XMPP_TEST_DEBUG}) {
      $AnyEvent::XMPP::Stream::DEBUG = $ENV{ANYEVENT_XMPP_TEST_DEBUG};
   }

   if ($what eq 'component') {
      unless ($ENV{ANYEVENT_XMPP_TEST_COMPONENT}) {
         plan skip_all => "ANYEVENT_XMPP_TEST_COMPONENT environment variable not set.";
         exit 0;
      }

      ($HOST, $PORT, $SERVICE, $SECRET) =
         split /:/, $ENV{ANYEVENT_XMPP_TEST_COMPONENT};

   } elsif ($what eq 'client') {
      unless ($ENV{ANYEVENT_XMPP_TEST_CLIENT}) {
         plan skip_all => "ANYEVENT_XMPP_TEST_CLIENT environment variable not set.";
         exit 0;
      }

      ($HOST, $PORT, $JID1, $JID2, $PASS) =
         split /:/, $ENV{ANYEVENT_XMPP_TEST_CLIENT};
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

