#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid domain_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..6\n";

my $connected = AnyEvent->condvar;

AnyEvent::XMPP::Test::start (
   $connected, 'AnyEvent::XMPP::Ext::Presence', 'AnyEvent::XMPP::Ext::VCard');

my ($im, $pres, $vcard) = $connected->recv;


$vcard->store ($FJID1, {
   NICKNAME => ['elmex'],
   EMAIL => ['elmex@ta-sa.org']
}, my $scv = AE::cv);


my ($e) = $scv->recv;

tp 1, not (defined $e), 'stored vcard ok';

$vcard->retrieve ($FJID1, undef, my $cv = AE::cv);

my ($v, $e) = $cv->recv;

tp 2, not (defined $e),               "retrieved ok";
tp 3, $v->{NICKNAME}->[0] eq 'elmex', "retrieved data correctly";

AnyEvent::XMPP::Test::end ($im);
