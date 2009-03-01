#!perl
use strict;
use Test::More tests => 2;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;

my %def = (
   xmpp_ns ('stream') => 'stream',
   xmpp_ns ('client') => ''
);

my $stream_el =
   AnyEvent::XMPP::Node->new ('http://etherx.jabber.org/streams' => 'stream');

$stream_el->attr (test => 10);

my ($k_before) = grep { /\|test$/ } keys %{$stream_el->attrs};

$stream_el->namespace ('jabber:client');

my ($k_after) = grep { /\|test$/ } keys %{$stream_el->attrs};


is ($k_before, 'http://etherx.jabber.org/streams|test', 'before key got correct namesapace');
is ($k_after,  'jabber:client|test', 'after key got correct namesapace');
