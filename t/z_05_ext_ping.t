#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::CM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;

AnyEvent::XMPP::Test::check ('client');

print "1..3\n";

my $connected   = AnyEvent->condvar;
my $first_ping  = AnyEvent->condvar;
my $second_ping = AnyEvent->condvar;
my $timeouted   = AnyEvent->condvar;
AnyEvent::XMPP::Test::start ($connected);
my ($im) = $connected->recv;

$im->add_ext ('Ping');

# while we are at it, test the Extendable interface:
my $ext = $im->get_ext ('Ping');

$ext->ping ($FJID1, undef, sub {
   my ($latency, $error) = @_;

   if ($error) {
      if ($error->condition eq 'feature-not-implemented'
          || $error->condition eq 'service-unavailable') {
         print "ok 1 # skip received error from server: $latency seconds\n";
      } else {
         print "not ok 1 - received error from server: $latency seconds\n";
      }
   } else {
      print "ok 1 - received ping reply from server: $latency seconds\n";
   }

   $first_ping->send;
});

$first_ping->recv;

$ext->ping ($FJID1, $FJID2, sub {
   my ($latency, $error) = @_;

   if ($error) {
      print "not ok 2 - received error from second jid: $latency seconds\n";
   } else {
      print "ok 2 - received ping reply from second jid: $latency seconds\n";
   }

   $second_ping->send;
});

$second_ping->recv;

$ext->enable_timeout ($FJID1, 1);

my $cnt = 1;

my @ping_ids;
$im->get_connection ($FJID1)->reg_cb (
   send => sub {
      my ($im, $node) = @_;
      push @ping_ids, $node->attr ('id') if $node->find (ping => 'ping');
   },
   recv => 1 => sub {
      my ($im, $node) = @_;
      if (grep { $node->attr ('id') eq $_ } @ping_ids) {
         $im->stop_event if --$cnt <= 0;
      }
   }
);

$ext->reg_cb (
   ping_timeout => sub {
      my ($ext, $jid) = @_;

      print ((cmp_jid ($jid, $FJID1) ? "" : "not ")
             . "ok 3 - received ping timeout\n");

      $timeouted->send;
   }
);

$timeouted->recv;

AnyEvent::XMPP::Test::end ($im);
