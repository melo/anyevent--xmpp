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
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..16\n";

my $cnt = 1;
sub check_pres {
   my ($c, $p, @set) = @_;
   printf "%sok %d - show correct for $c\n",
          $p->{show} eq $set[0] ? '' : 'not ', $cnt++;
   printf "%sok %d - prio correct for $c\n",
          $p->{priority} eq $set[1] ? '' : 'not ', $cnt++;
   printf "%sok %d - status correct for $c\n",
          $p->{status} eq $set[2] ? '' : 'not ', $cnt++;
   printf "%sok %d - jid correct for $c\n",
          $p->{jid} eq $set[3] ? '' : 'not ', $cnt++;
}

my $prepared = AnyEvent->condvar;

AnyEvent::XMPP::Test::start (
   sub { },
   'AnyEvent::XMPP::Ext::Presence',
   'AnyEvent::XMPP::Ext::Roster',
   sub { $prepared->send (@_) }
);

my ($im, $pres, $roster) = $prepared->recv;

$im->event ('source_available' => 'a@b/X');

$pres->_int_upd_presence ('a@b/X', 'c@d/X', 0, {
   priority => 10,
   all_status => { }, status => "Test",
   show => 'available',
   jid => 'c@d/X'
});

$pres->_int_upd_presence ('a@b/X', 'c@d/Z', 0, {
   priority => 0,
   all_status => { }, status => "Test A",
   show => 'available',
   jid => 'c@d/Z'
});

my ($p) = $pres->highest_prio_presence ('a@b/X', 'c@d');
check_pres ('first', $p, available => 10, 'Test', 'c@d/X');

$pres->_int_upd_presence ('a@b/X', 'c@d/Y', 0, {
   priority => 20,
   all_status => { }, status => "Test 2",
   show => 'available',
   jid => 'c@d/Y'
});

my ($p) = $pres->highest_prio_presence ('a@b/X', 'c@d');
check_pres ('second', $p, available => 20, 'Test 2', 'c@d/Y');

$pres->_int_upd_presence ('a@b/X', 'c@d/Y', 0, {
   priority => 20,
   all_status => { }, status => "Test 2 Gone",
   show => 'unavailable',
   jid => 'c@d/Y'
});

my ($p) = $pres->highest_prio_presence ('a@b/X', 'c@d');
check_pres ('third', $p, available => 10, 'Test', 'c@d/X');

$pres->_int_upd_presence ('a@b/X', 'c@d', 0, {
   all_status => { }, status => "Test Gone",
   show => 'unavailable',
   jid => 'c@d'
});

my ($p) = $pres->highest_prio_presence ('a@b/X', 'c@d');
check_pres ('fourth', $p, unavailable => undef, 'Test Gone', 'c@d');

exit;
