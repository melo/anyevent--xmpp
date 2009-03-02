#!perl -T

my @MODULES = qw/
AnyEvent::XMPP::Parser
AnyEvent::XMPP::Stream
AnyEvent::XMPP::Stream::Client
AnyEvent::XMPP::Stream::Component
AnyEvent::XMPP::IM
AnyEvent::XMPP::Error
AnyEvent::XMPP::Node
AnyEvent::XMPP
/;

use Test::More;
plan tests => scalar @MODULES;
use_ok $_ for @MODULES;

diag( "Testing AnyEvent::XMPP $AnyEvent::XMPP::VERSION, Perl $], $^X" );

