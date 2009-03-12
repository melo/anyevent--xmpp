package AnyEvent::XMPP::Test;
use strict;
no warnings;

use Test::More;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/cmp_bare_jid new_presence/;

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT = qw/$HOST $PORT $SECRET $SERVICE $JID1 $JID2 $FJID1 $FJID2 $PASS/;

=head1 NAME

AnyEvent::XMPP::Test - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=over 4

=cut

our ($HOST, $PORT, $SECRET, $SERVICE);
our ($JID1, $JID2, $PASS);
our ($FJID1, $FJID2);

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

sub start {
   my ($cb) = @_;

   my $cv = AnyEvent->condvar;

   my $im = AnyEvent::XMPP::IM->new;
   my $cnt = 0;

   $im->reg_cb (
      connected => sub {
         my ($im, $jid) = @_;
         if (cmp_bare_jid ($jid, $JID1)) {
            $FJID1 = $jid;
         } else {
            $FJID2 = $jid;
         }

         if (++$cnt >= 2) {
            # sending directed presence for IQ exchange:
            $im->send (new_presence (undef, undef, undef, src => $FJID1, to => $FJID2));
            $im->send (new_presence (undef, undef, undef, src => $FJID2, to => $FJID1));

            $cb->($im, $cv) if ++$cnt >= 2;
         }
      },
      connect_error => sub {
         my ($im, $jid, $reason, $recon_tout) = @_;
         print "# connect error $jid: $reason\n";
         $cv->send;
      },
      error => sub {
         my ($im, $jid, $error) = @_;
         print "# error $jid: " . $error->string . "\n";
         $im->stop_event;
      },
      disconnected => sub {
         my ($self, $jid, $ph, $pp, $reaso) = @_;
         print "# disconnected $jid,$ph:$pp: $reaso\n";
         $cv->send;
      },
   );

   $im->add_account ($JID1, $PASS, host => $HOST, port => $PORT);
   $im->add_account ($JID2, $PASS, host => $HOST, port => $PORT);

   $im->update_connections;

   $cv->recv;
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

