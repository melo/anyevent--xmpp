#!perl
use strict;
use utf8;
use Test::More;
use AnyEvent::XMPP::StreamParser;
use JSON -convert_blessed_universally;
use Encode;

my $str = encode ('utf-8', <<INPUT);
   <s:stream xmlns:s="fefe" xmlns="bar">
   <m><fe><foo/><fb/></fe><body> feofoefo ef </body></m>
   <foo>&gt;\015&lt;\015\012</foo>
   <bar a="&#xd;&#xd;A&#xa;&#xa;B&#xd;&#xa;" b="

xyz"/>
   <bÄÄäääooooeeeeÖÖöö xmlns:ää="üüü:üüü" ää:fefe="feofe" fefe="balblal">
   äääPPä
   </bÄÄäääooooeeeeÖÖöö>
   <message 
   
   to
   
   = 
   
   'elmex\@jabber.org'><body
       xml:lang="de">Hallo da!</body></message
   >
   </s:stream>
INPUT

my @stanzas = (
   "<m><fe><foo/><fb/></fe><body> feofoefo ef </body></m>",
   "<foo>&gt;\012&lt;\012</foo>",
   "<bar a=\"\015\015A\012\012B\015\012\" b=\"\x20\x20xyz\"/>",
   "<bÄÄäääooooeeeeÖÖöö xmlns:ns1=\"üüü:üüü\" fefe=\"balblal\" ns1:fefe=\"feofe\">\012   äääPPä\012   </bÄÄäääooooeeeeÖÖöö>",
   "<message to=\"elmex\@jabber.org\"><body xml:lang=\"de\">Hallo da!</body></message>"
);

my (@ss, @se, @st);
my $p = AnyEvent::XMPP::StreamParser->new;
$p->reg_cb (
   stream_start => sub {
      my ($p, $node) = @_;
      push @ss, $node;
   },
   stream_end => sub {
      my ($p, $node) = @_;
      push @se, $node;
   },
   recv => sub {
      my ($p, $node) = @_;
      push @st, $node;
   },
);

my $buf;

while ($str) {
   $buf .= substr $str, 0, 1, '';
   $p->feed_octets (\$buf);
}

plan tests => 3 + 2 + @stanzas;

is (scalar (@ss), 1, "one stream start");
is (scalar (@se), 1, "one stream end");
is (scalar (@st), scalar (@stanzas), "stanza count correct");
is ($ss[0]->as_string, "<ns1:stream xmlns:ns1=\"fefe\">", "stream start as expected");
is ($se[0]->as_string, "</ns1:stream>", "stream end as expected");

while (@stanzas) {
   my $s = shift @stanzas;
   my $o = shift @st;

   my $ser = $o->as_string (0, {
      'http://www.w3.org/XML/1998/namespace' => 'xml',
      'ae:xmpp:stream:default_ns' => ''
   });

   if ($ser eq $s) {
      ok (1, "serialized version matches expected output");
   } else {
      ok (0, "serialized version didn't match expected output");
      print "# got     : [$ser]\n";
      print "# expected: [$s]\n";
      print "# JSON:\n" . JSON->new->convert_blessed->pretty->encode ($o) . "\n";
   }
}
