#!perl
use strict;
use utf8;
use Test::More;
use AnyEvent::XMPP::Parser;
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

   <sex><![CDATA[BLAIFIEJFEIFEIfei fe <><> .>>,> <><> &gt;&lt;]]></sex>
   </s:stream>
INPUT

my @stanzas = (
   "<m><fe><foo/><fb/></fe><body> feofoefo ef </body></m>",
   "<foo>&gt;\012&lt;\012</foo>",
   "<bar a=\"\015\015A\012\012B\015\012\" b=\"\x20\x20xyz\"/>",
   "<bÄÄäääooooeeeeÖÖöö xmlns:ns1=\"üüü:üüü\" fefe=\"balblal\" ns1:fefe=\"feofe\">\012   äääPPä\012   </bÄÄäääooooeeeeÖÖöö>",
   "<message to=\"elmex\@jabber.org\"><body xml:lang=\"de\">Hallo da!</body></message>",
   "<sex>BLAIFIEJFEIFEIfei fe &lt;&gt;&lt;&gt; .&gt;&gt;,&gt; &lt;&gt;&lt;&gt; &amp;gt;&amp;lt;</sex>",
);

my (@ss, @se, @st);
my $p = AnyEvent::XMPP::Parser->new;
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

plan tests => (3 + 2 + @stanzas) * 2;

my @stanzas2 = @stanzas;
my $str2     = $str;

{
   my $buf;

   while ($str) {
      $buf .= substr $str, 0, 1, '';
      $p->feed (\$buf);
   }

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
}

@ss = ();
@se = ();
@st = ();

{
   $p->init;

   my $buf;

   $p->feed (\$str2);

   is (scalar (@ss), 1, "one stream start");
   is (scalar (@se), 1, "one stream end");
   is (scalar (@st), scalar (@stanzas2), "stanza count correct");
   is ($ss[0]->as_string, "<ns1:stream xmlns:ns1=\"fefe\">", "stream start as expected");
   is ($se[0]->as_string, "</ns1:stream>", "stream end as expected");

   while (@stanzas2) {
      my $s = shift @stanzas2;
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
}
