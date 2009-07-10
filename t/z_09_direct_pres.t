#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                            new_presence bare_jid cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use Predicates;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

my $change_1st = 0;
my $change_2nd = 0;
my $change_3rd = 0;

my $connected = AnyEvent->condvar;

AnyEvent::XMPP::Test::start ($connected, 'AnyEvent::XMPP::Ext::Presence');

my ($im, $pres) = $connected->recv;

my $presence_x_change_done = AnyEvent->condvar;
my $cnt = 2;

$pres->reg_cb (
   self => sub {
      my ($pres, $resjid, $jid, $old, $new) = @_;

      if ($new->{status} eq 'testing1') {
         if (--$cnt == 0) {
            $pres->set_default (away => 'testing2', 10);
            $pres->send_directed ($FJID1, $FJID2);
         }
      }
   },
   change => sub {
      my ($pres, $resjid, $jid, $old, $new) = @_;
      $change_1st = 1 if $new->{status} eq 'testing1';

      if (cmp_jid ($resjid, $FJID2) && $new->{status} eq 'testing2') {
         $change_2nd++;
         if ($change_2nd == 1) {
            $pres->send_directed ($FJID1, $FJID2, 1);
            $pres->set_default (away => 'testing3', 10);
         }
      }

      if (cmp_jid ($resjid, $FJID2) && $new->{status} eq 'testing3') {
         $change_3rd++;
         $presence_x_change_done->send;
      }
   }
);

$pres->set_default (away => 'testing1', 10);

$presence_x_change_done->recv;

print "1..3\n";

print (($change_1st == 0 ? "" : "not ") . "ok 1 - broadcast didn't change presence\n");
print (($change_2nd == 1 ? "" : "not ") . "ok 2 - directed presence changed\n");
print (($change_3rd == 1 ? "" : "not ") . "ok 3 - directed presence auto changed\n");


AnyEvent::XMPP::Test::end ($im);
