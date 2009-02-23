#!perl
use strict;
no warnings;

use Test::More tests => 2;
use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Ext::Registration;
use AnyEvent::XMPP::Util qw/split_jid/;
use AnyEvent::XMPP::Stanza;

AnyEvent::XMPP::Test::check ('client');

my $cv = AnyEvent->condvar;

$AnyEvent::XMPP::Stream::DEBUG = 10;

my $im = AnyEvent::XMPP::IM->new;

$im->reg_cb (
   connected => sub {
      my ($self, $jid) = @_;
      warn "connected $jid!\n";
   },
);


$im->add_account ($JID1, $PASS, host => $HOST, port => $PORT);
$im->add_account ($JID2, $PASS, host => $HOST, port => $PORT);

$im->update_connections;

#my $reg = AnyEvent::XMPP::Ext::Registration->new (delivery => $stream);

$cv->recv;
