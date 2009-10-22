#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::CM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..3\n";

my $connected = AnyEvent->condvar;

AnyEvent::XMPP::Test::start (
   $connected,
   'AnyEvent::XMPP::Ext::Presence',
   'AnyEvent::XMPP::Ext::Roster', sub {
      my ($im, $pres, $roster) = @_;
      $roster->auto_fetch;
   });

my ($im, $pres, $roster) = $connected->recv;

my $tout = AnyEvent->timer (after => 10, cb => sub {
   my $cnt = 0;
   $im->get_connection ($FJID1)->reg_cb (send_buffer_empty => sub {
      if (++$cnt >= 2) { AnyEvent::XMPP::Test::end ($im) }
   });
   $im->get_connection ($FJID2)->reg_cb (send_buffer_empty => sub {
      if (++$cnt >= 2) { AnyEvent::XMPP::Test::end ($im) }
   });
   $pres->send_unsubscription ($FJID1, bare_jid ($FJID2), 1, "Nope! NONE ANYMROE!");
   $pres->send_unsubscription ($FJID2, bare_jid ($FJID1), 1, "Nope! NONE ANYMROE!");
});

my $subscription_req = AnyEvent->condvar;
$pres->reg_cb (subscription_request => sub {
   my ($pres, $resjid, $jid, $req) = @_;

   if (cmp_jid ($resjid, $FJID2) && $req->{status} =~ /friends/) {
      $pres->unreg_me;
      $subscription_req->send (1);
   } else {
      $subscription_req->send (0);
   }
});

$pres->send_subscription_request (
   $FJID1, bare_jid ($FJID2), 1, "Hi! Lets be friends!");

my ($st) = $subscription_req->recv;

tp (1, $st, "sent subscription request");

my $subscription_handled = AnyEvent->condvar;

$roster->reg_cb (change => sub {
   my ($roster, $jid, $bjid, $old_item, $new_item) = @_;

   if (cmp_jid ($jid, $FJID2) && $new_item->{subscription} eq 'both') {
      $roster->unreg_me;
      $subscription_handled->send;
   }
});

$pres->handle_subscription_request ($FJID2, bare_jid ($FJID1), 1, 1, "Ok, lets be!");

$subscription_handled->recv;

tp (2, 1, "subscription successful, sending unsubscr.");

my $unsubscribed = AnyEvent->condvar;

$roster->reg_cb (change => sub {
   my ($roster, $jid, $bjid, $old_item, $new_item) = @_;

   if (cmp_jid ($jid, $FJID2)
       && $new_item->{subscription} eq 'none') {

      $roster->unreg_me;
      $unsubscribed->send;
   }
});

$pres->send_unsubscription ($FJID1, bare_jid ($FJID2), 1, "Lets NOT be friends!");

$unsubscribed->recv;

tp (3, 1, "unsubscription successful!");

undef $tout;

AnyEvent::XMPP::Test::end ($im);

# print JSON->new->convert_blessed->pretty->encode ($pres_ext->{p}) . "\n";
