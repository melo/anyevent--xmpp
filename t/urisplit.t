#!perl
use strict;
use Test::More;
use AnyEvent::XMPP::Util qw/split_uri/;

my @data = (
   ['xmpp:pubsub.example.com?pubsub;node=/some/node', 'pubsub.example.com', '/some/node'],
   ['/some/node', undef, '/some/node'],
);

plan tests => (scalar @data) * 2;

for (@data) {
   my ($d, $n) = split_uri ($_->[0]);

   is ($d, $_->[1], "uri [$_->[0]]: node part");
   is ($n, $_->[2], "uri [$_->[0]]: service part");
}
