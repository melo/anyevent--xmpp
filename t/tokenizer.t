#!perl
use strict;
use Test::More;
use AnyEvent::XMPP::StreamParser;
use XML::Parser;
use JSON;

my $xp = XML::Parser->new (Style => 'Tree');

print JSON->new->pretty->encode ($xp->parse ("<fefefef a='f&gt;e'><![CDATA[[efef &gt; ]]></fefefef>"));
print "\n";

my $p = AnyEvent::XMPP::StreamParser->new;

my $toks = $p->tokenize_chunk ("<elfe fefe='fef >' >fe&gt;ife<a/> </b><![CDATA[[foEOFEOFEOFEOFEOFEO >><><><<>[][][]]][]]]] &gt; ]]></elfe>");
for (@$toks) {
   if (ref $_) { 
      print "{@$_}\n";
   } else {
      print "C[$_]\n";
   }
}
