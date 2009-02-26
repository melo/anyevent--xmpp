#!perl
use strict;
use Test::More;
use AnyEvent::XMPP::Parser;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Node qw/simxml/;

my %def = (
   xmpp_ns ('stream') => 'stream',
   xmpp_ns ('client') => ''
);

my $stream_el = AnyEvent::XMPP::Node->new ('http://etherx.jabber.org/streams' => 'stream');
$stream_el->add_decl_prefix ('jabber:client' => '');
$stream_el->add_decl_prefix ('http://etherx.jabber.org/streams' => 'stream');

my @input = (
   $stream_el->as_string,
   "<message>FOOAREE&amp;lt;&amp;lt;&amp;gt;&amp;gt;&amp;gt;</message>",
   simxml (defns => 'jabber:client', node => {
      name => 'iq', attrs => [ type => 'set' ], childs => [
         { name => 'query', dns => 'roster' }
      ]
   })->as_string,
);

my @expected_output = (
   "<stream xmlns=\"http://etherx.jabber.org/streams\"/>",
   "<message xmlns=\"jabber:client\">FOOAREE&amp;lt;&amp;lt;&amp;gt;&amp;gt;&amp;gt;</message>",
);

plan tests => scalar @input;

my $p = AnyEvent::XMPP::Parser->new;

$p->reg_cb (received_stanza_xml => sub {
   my ($p, $node) = @_;
   is (
      $node->as_string,
      (shift @expected_output),
      "stanza was parsed correctly and serialized correctly"
   );
});

$p->init;

for (@input) { warn "FEED[$_]\n"; $p->feed ($_) }
