#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;

AnyEvent::XMPP::Test::check ('client');

print "1..11\n";

my $connected = AnyEvent->condvar;
AnyEvent::XMPP::Test::start (1, $connected);

my ($im) = $connected->recv;

my $finished_first = AnyEvent->condvar;

$im->send (new_iq (
get =>
   to     => $FJID1,
   from   => $FJID1,
   create => { node => { dns => 'abc:def', name => 'query' } },
timeout => 6,
cb => sub {
   my ($node, $error) = @_;

   if ($error) {
      print "ok 1 - got error reply: ".$error->string."\n";
      print (($error->code == 503 ? '' : 'not ')
             . "ok 2 - error code correct.\n");
      print (($error->type eq 'cancel' ? '' : 'not ')
             . "ok 3 - error type correct.\n");
      print (($error->condition eq 'service-unavailable' ? '' : 'not ')
             . "ok 4 - error condition correct.\n");
      print (($error->node->find_all ([qw/abc:def query/]) ? '' : 'not ')
             . "ok 5 - error contained query node.\n");
      print (($error->node->raw_string =~ /<query xmlns=["']abc:def["']\/?>/ ? '' : 'not ')
             . "ok 6 - error contained query node with correct ns decls.\n");
      #d# warn sprintf "FE[%s]\n", $error->node->raw_string;

   } else {
      print "not ok 1 - got reply!\n";
   }

   $finished_first->send;
}));

$finished_first->recv;

my $finished_second = AnyEvent->condvar;

$im->send (new_iq (
set =>
   to     => $FJID1,
   from   => $FJID1,
   create => { node => { name => 'query' } },
timeout => 6,
cb => sub {
   my ($node, $error) = @_;

   if ($error) {
      print "ok 7 - got error reply: ".$error->string."\n";
      print (($error->code == 503 ? '' : 'not ')
             . "ok 8 - error code correct.\n");
      print (($error->type eq 'cancel' ? '' : 'not ')
             . "ok 9 - error type correct.\n");
      print (($error->condition eq 'service-unavailable' ? '' : 'not ')
             . "ok 10 - error condition correct.\n");
      print (($error->node && $error->node->find_all ([qw/stanza query/])
                ? '' : 'not ')
             . "ok 11 - error contained query node.\n");

   } else {
      print "not ok 7 - got reply!\n";
   }

   $finished_second->send;
}));

$finished_second->recv;

AnyEvent::XMPP::Test::end ($im);
