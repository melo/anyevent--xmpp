package AnyEvent::XMPP::Test;
use strict;
no warnings;

use Test::More;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/cmp_jid cmp_bare_jid new_presence stringprep_jid/;
use Time::HiRes qw/usleep/;

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT = qw/$COMP_HOST $COMP_PORT $HOST $PORT $SECRET $SERVICE $JID1
                 $JID2 $FJID1 $FJID2 $PASS @DEF_HANDLERS &tp/;

=head1 NAME

AnyEvent::XMPP::Test - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=over 4

=cut

our ($COMP_HOST, $COMP_PORT, $HOST, $PORT, $SECRET, $SERVICE);
our ($JID1, $JID2, $PASS);
our ($FJID1, $FJID2);

our $TOUT;

our @DEF_HANDLERS = (
   disconnected => sub {
      my ($s, $h, $p, $reaso) = @_;
      if ($reaso eq 'done'
          || $reaso =~ /recevied expected stream end/
          || (($s->jid =~ /jabberd14|jabberd-14/
               || ref ($s) =~ /Component/)
              && $reaso =~ /EOF/)) {
         $s->event (test_end => 'end', $reaso);
      } else {
         print "# disconnected ".$s->jid.",$h:$p: $reaso\n";
         $s->event (test_end => 'disconnected', $reaso);
      }
   },
   connect_error => sub {
      my ($s, $reason) = @_;
      print "# connect error ".$s->jid.": $reason\n";
      $s->event ('test_end' => 'connect_error', $reason);
   },
   error => sub {
      my ($s, $error) = @_;
      print "# error " . $s->jid. ": " . $error->string . "\n";
      $s->event ('test_end' => 'error', $error->string);
      $s->stop_event;
   },
);


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

      ($COMP_HOST, $COMP_PORT, $SERVICE, $SECRET) =
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

   my $im = AnyEvent::XMPP::IM->new (initial_reconnect_interval => 180);

   my @aexts;
   my $two_accs = $cnt > 1;
   my $has_presence;
   my $has_langextract;
   my $dis_cnt = $two_accs ? 2 : 1;

   for my $e (@exts) {
      if (ref ($e) eq 'CODE') {
         $e->($im, @aexts);
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

                        $TOUT = AnyEvent->timer (after => 20, cb => sub { exit 1 });
                        $cb->($im, @aexts);
                     }
                  }
               );

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

            } else {
               $TOUT = AnyEvent->timer (after => 20, cb => sub { exit 1 });
               $cb->($im, @aexts);
            }
         }
      },
      connect_error => sub {
         my ($im, $jid, $reason, $recon_tout) = @_;
         print "# connect error $jid: $reason\n";
         exit 1;
      },
      error => sub {
         my ($im, $jid, $error) = @_;
         print "# error $jid: " . $error->string . "\n";
         $im->stop_event;
      },
      disconnected => sub {
         my ($self, $jid, $ph, $pp, $reaso) = @_;

         if ($reaso eq 'done'
             || $reaso =~ /recevied expected stream end/
             || ($jid =~ /jabberd14|jabberd-14/ && $reaso =~ /EOF/)) {
            exit (0) if --$dis_cnt <= 0;

         } else {
            print "# disconnected $jid,$ph:$pp: $reaso\n";
            exit 1;
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
}

sub end {
   my ($im) = @_;
   $im->get_connection ($FJID1)->send_end if $im->get_connection ($FJID1);
   my $nd_con = $im->get_connection ($FJID2);
   $nd_con->send_end if $nd_con;
   AnyEvent->condvar->recv;
}

sub tp($$$) {
   my ($nr, $cond, $desc) = @_;
   printf "%sok %d - %s\n", ($cond ? '' : 'not '), $nr, $desc;
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

