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

$buf = "<s:stream> <m><fe><foo/><fb/></fe><body> feofoefo ef </body></m> <foo/> <bar/> </s:stream>";

$p = AnyEvent::XMPP::StreamParser->new;
$p->reg_cb (
   stream_start => sub {
      my ($p, $node) = @_;
      
      print "SS: " . $node->raw_string . "\n";
      print "    [\n" . $node->as_string (1) . "\n]\n";
   },
   stream_end => sub {
      my ($p, $node) = @_;

      print "SE: " . $node->raw_string . "\n";
      print "    [\n" . $node->as_string (1) . "\n]\n";
   },
   recv => sub {
      my ($p, $node) = @_;

      print "ST: " . $node->raw_string . "\n";
      print "    [\n" . $node->as_string (1) . "\n]\n";
   },
);

$p->feed_octets (\$buf);
