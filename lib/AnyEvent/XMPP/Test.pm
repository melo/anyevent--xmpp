package AnyEvent::XMPP::Test;
use strict;
no warnings;

use Test::More;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/cmp_jid cmp_bare_jid new_presence stringprep_jid/;
use Time::HiRes qw/usleep/;

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

our $TOUT;

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

      ($JID1, $JID2, $PASS, $HOST, $PORT) =
         split /:/, $ENV{ANYEVENT_XMPP_TEST_CLIENT};
   }
}

sub start {
   my ($cnt, $cb, @exts) = @_;

   if (ref $cnt) {
      unshift @exts, $cb if defined $cb;
      $cb = $cnt;
      $cnt = 2;
   }

   my $cv = AnyEvent->condvar;
   my $im = AnyEvent::XMPP::IM->new;

   my @aexts;
   my $two_accs = $cnt > 1;
   my $has_presence;

   for my $e (@exts) {
      if (ref ($e) eq 'CODE') {
         $e->($im, $cv, @aexts);
      } else {
         push @aexts, $im->add_extension ($e);
         $has_presence = $aexts[-1] if $e eq 'AnyEvent::XMPP::Ext::Presence';
      }
   }

   $im->reg_cb (
      connected => sub {
         my ($im, $jid) = @_;

         if (cmp_bare_jid ($jid, $JID1)) {
            $FJID1 = stringprep_jid $jid;
         } else {
            $FJID2 = stringprep_jid $jid;
         }

         if (--$cnt <= 0) {
            $im->send (new_presence (
               available => undef, undef, undef, src => $FJID1
            )) unless $has_presence;

            if ($two_accs) {
               # sending directed presence for IQ exchange:

               if ($has_presence) {
                  $has_presence->send_directed ($FJID1, $FJID2);
                  $has_presence->send_directed ($FJID2, $FJID1);

               } else {
                  $im->send (new_presence (
                     available => undef, undef, undef, src => $FJID2
                  ));
                  $im->send (new_presence (
                     available => undef, undef, undef, src => $FJID1, to => $FJID2));
                  $im->send (new_presence (
                     available => undef, undef, undef, src => $FJID2, to => $FJID1));
               }

               my $one_to_2 = 0;
               my $two_to_1 = 0;

               $im->reg_cb (
                  recv_presence => sub {
                     my ($im, $pres) = @_;
                     if (cmp_jid ($pres->attr ('from'), $FJID1)
                         && cmp_jid ($pres->attr ('to'), $FJID2)) {
                        $one_to_2 = 1;
                     } elsif (cmp_jid ($pres->attr ('from'), $FJID2)
                         && cmp_jid ($pres->attr ('to'), $FJID1)) {
                        $two_to_1 = 1;
                     }

                     if ($one_to_2 && $two_to_1) {
                        $im->unreg_me;

                        $TOUT = AnyEvent->timer (after => 20, cb => sub { $cv->send });
                        $cb->($im, $cv, @aexts);
                     }
                  }
               );
            } else {
               $TOUT = AnyEvent->timer (after => 20, cb => sub { $cv->send });
               $cb->($im, $cv, @aexts);
            }
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

         if ($reaso ne 'done') {
            print "# disconnected $jid,$ph:$pp: $reaso\n";
            $cv->send;
         }
      },
   );

   $im->add_account ($JID1, $PASS,
       (defined $HOST ? (host => $HOST) : ()),
       (defined $PORT ? (port => $PORT) : ()));

   if ($two_accs) {
      $im->add_account ($JID2, $PASS,
          (defined $HOST ? (host => $HOST) : ()),
          (defined $PORT ? (port => $PORT) : ()));
   }

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

