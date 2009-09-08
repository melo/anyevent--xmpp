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

  ### XEP-0115 second example (section 5.3)
  'q07IKJEyjvHSyhy//CH0CxmKi8w=' => {
    node => {
      dns    => 'disco_info',
      name   => 'query',
      attrs  => [node => 'http://psi-im.org#q07IKJEyjvHSyhy//CH0CxmKi8w='],
      childs => [
        { name  => 'identity',
          attrs => [
            category => 'client',
            type     => 'pc',
            name     => 'Psi 0.11',
            ['xml', 'lang'] => 'en',
          ],
        },
        { name  => 'identity',
          attrs => [
            category => 'client',
            type     => 'pc',
            name     => 'Ψ 0.11',
            ['xml', 'lang'] => 'el',
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
        { name   => 'x',
          dns    => 'jabber:x:data',
          attrs  => [type => 'result'],
          childs => [
            { name  => 'field',
              attrs => [
                var  => 'FORM_TYPE',
                type => 'hidden',
              ],
              childs => [
                { name   => 'value',
                  childs => ['urn:xmpp:dataforms:softwareinfo'],
                },
              ]
            },
            { name   => 'field',
              attrs  => [var => 'ip_version',],
              childs => [
                { name   => 'value',
                  childs => ['ipv4'],
                },
                { name   => 'value',
                  childs => ['ipv6'],
                },
              ]
            },
            { name   => 'field',
              attrs  => [var => 'os',],
              childs => [
                { name   => 'value',
                  childs => ['Mac'],
                },
              ]
            },
            { name   => 'field',
              attrs  => [var => 'os_version',],
              childs => [
                { name   => 'value',
                  childs => ['10.5.1'],
                },
              ]
            },
            { name   => 'field',
              attrs  => [var => 'software',],
              childs => [
                { name   => 'value',
                  childs => ['Psi'],
                },
              ]
            },
            { name   => 'field',
              attrs  => [var => 'software_version',],
              childs => [
                { name   => 'value',
                  childs => ['0.11'],
                },
              ]
            },
          ]
        }
      ],
    }
  },
  
  ### Violate section 5.4, bullet 3.3
  undef, {
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
        { name  => 'identity',
          attrs => [
            category => 'client',
            type     => 'pc',
            name     => 'Exodus 0.9.1',
          ],
        },
      ],
    }
  },

  ### Violate section 5.4, bullet 3.3
  undef, {
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
            [xml => 'lang'] => 'en',
          ],
        },
        { name  => 'identity',
          attrs => [
            category => 'client',
            type     => 'pc',
            name     => 'Exodus 0.9.1',
            [xml => 'lang'] => 'en',
          ],
        },
      ],
    }
  },
  
);

## Run over all tests
while (@test_cases) {
  my ($wanted_ver, $spec) = splice(@test_cases, 0, 2);
  my $node = simxml(%$spec);
#  diag("Stanza is " . $node->as_string);
  my $calc_ver = AnyEvent::XMPP::Ext::Caps::_ver_gen($node, 'sha-1');
  if (defined ($wanted_ver)) {
    ok(defined($calc_ver), "calc for '$wanted_ver' defined");
    is($calc_ver, $wanted_ver);
  }
  else {
    ok(!defined($calc_ver));
  }
}


## Just make sure this works
ok(AnyEvent::XMPP::Ext::Caps::_has_dups([1, 1, 2]));
ok(!AnyEvent::XMPP::Ext::Caps::_has_dups([1, 2, 3]));

done_testing();
