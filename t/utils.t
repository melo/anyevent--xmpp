#!perl
use strict;
use Test::More;
use AnyEvent::XMPP::Util qw/new_iq new_iq_error_reply/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;

my $iq = new_iq(
  'get',
  to => 'me@domain/noway',
  create => [
    simxml(
      defns => xmpp_ns('disco_info'),
      node  => { name => 'query' },
    ),
  ],
);
ok($iq);


### Test new_iq_error_reply
my $err = new_iq_error_reply($iq, 'bad-request');
ok($err);
is($err->attr('from'), 'me@domain/noway');
is($err->attr('type'), 'error');

my @nodes = $err->nodes;
is(scalar(@nodes), 2);

@nodes = $err->find(xmpp_ns('disco_info'), 'query');
is(scalar(@nodes), 1);

@nodes = $err->find('stanza', 'error'); ## stanza is the default stream namespace
is(scalar(@nodes), 1);

$err = shift @nodes;
is($err->attr('code'), '400');
is($err->attr('type'), 'modify');

@nodes = $err->nodes;
is(scalar(@nodes), 1);

($err) = $err->find('stanzas', 'bad-request');
ok($err);

done_testing();