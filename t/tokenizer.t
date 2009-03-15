#!perl
use strict;
use utf8;
use Test::More;
use AnyEvent::XMPP::StreamParser;
use XML::Parser;
use JSON;
use Encode;

my $xp = XML::Parser->new (Style => 'Tree');

print JSON->new->pretty->encode ($xp->parse ("<fefefef a='f&gt;e'><![CDATA[[efef &gt; ]]></fefefef>"));
print "\n";

my $p = AnyEvent::XMPP::StreamParser->new;

my $e = encode ('utf-8', "ÄÄÄÄÄ");

my $buf = '';
while (length $e) {
   $buf .= substr $e, 0, 1, '';
   $p->feed_octets (\$buf);
}

my $toks = $p->tokenize_chunk ("<elfe fefe='fef >' >fe&gt;ife<a/> </b><![CDATA[[foEOFEOFEOFEOFEOFEO >><><><<>[][][]]][]]]] &gt; ]]></elfe>");
for (@$toks) {
   if (ref $_) { 
      print "{@$_}\n";
   } else {
      print "C[$_]\n";
   }
}
