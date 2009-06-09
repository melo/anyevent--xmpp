#!perl
use strict;
use Test::More;
use AnyEvent::XMPP::Parser;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Node qw/simxml/;

my %def = (
   xmpp_ns ('xml') => 'xml',
   xmpp_ns ('stream') => 'stream',
   xmpp_ns ('component') => ''
);

my $stream_el = AnyEvent::XMPP::Node->new ('http://etherx.jabber.org/streams' => 'stream');
$stream_el->add_decl_prefix ($_ => $def{$_}) for keys %def;
$stream_el->set_only_start;

my $iq_el = 
   simxml (defns => 'stanza', node => {
      name => 'iq', attrs => [ type => 'set' ], childs => [
         { name => 'query', dns => 'roster',
            childs => [
               { name => 'immed', ns => 'component', childs => [
                  { name => 'test' },
               ]},
               { name => 'test2' }
            ]
         }
      ]
   });

my @input = (
   $stream_el->as_string (0, { STREAM_NS => xmpp_ns ('component') }),
   simxml (defns => 'component', node => {
      name => 'message', attrs => [ to => "elmex\@jabber.org" ], childs => [
         { name => 'body', childs => [ "Hi!" ] }
      ]
   })->as_string (0, { %def, STREAM_NS => xmpp_ns ('component') }),
   $iq_el->as_string (0, { %def, STREAM_NS => xmpp_ns ('component') }),
);

my @expected_output = (
   '<stream:stream>',
   '<message to="elmex@jabber.org"><body>Hi!</body></message>',
   '<iq type="set"><query xmlns="jabber:iq:roster"><ns1:immed xmlns:ns1="jabber:component:accept"><test/></ns1:immed><test2/></query></iq>',
);

plan tests => scalar @input;

my $p = AnyEvent::XMPP::Parser->new;

my $anal = sub {
   my ($p, $node) = @_;
   my $str;
   is (
      $str = $node->as_string (0, { %def, STREAM_NS => xmpp_ns ('component') }),
      (shift @expected_output),
      "[" . substr ($str, 0, 16) . "...] stanza was parsed correctly and serialized correctly"
   );
};

$p->reg_cb (stream_start => $anal, recv => $anal);

$p->init;

for my $in (@input) { $p->feed (\$in) }
