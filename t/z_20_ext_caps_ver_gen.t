#!perl

use strict;
use utf8;
use Test::More;
use AnyEvent::XMPP::Node qw( simxml );
use AnyEvent::XMPP::Ext::Caps;

my @test_cases = (
  ### XEP-0115 first example (section 5.2)
  'QgayPKawpkPSDYmwT/WM94uAlu0=' => {
    node => {
      dns   => 'disco_info',
      name  => 'query',
      attrs => [
        node => 'http://code.google.com/p/exodus#q07IKJEyjvHSyhy//CH0CxmKi8w='
      ],
      childs => [
        { name  => 'identity',
          attrs => [
            category => 'client',
            type     => 'pc',
            name     => 'Exodus 0.9.1',
          ],
        },
        { name  => 'feature',
          attrs => [var => 'http://jabber.org/protocol/caps']
        },
        { name  => 'feature',
          attrs => [var => 'http://jabber.org/protocol/disco#info']
        },
        { name  => 'feature',
          attrs => [var => 'http://jabber.org/protocol/disco#items']
        },
        { name  => 'feature',
          attrs => [var => 'http://jabber.org/protocol/muc']
        },
      ],
    }
  },
);

## Run over all tests
while (@test_cases) {
  my ($wanted_ver, $spec) = splice(@test_cases, 0, 2);
  my $node = simxml(%$spec);
  diag("Stanza is " . $node->as_string);
  my $calc_ver = AnyEvent::XMPP::Ext::Caps::_ver_gen($node, 'sha-1');
  is($calc_ver, $wanted_ver);
}

done_testing();
