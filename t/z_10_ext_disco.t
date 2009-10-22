#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::CM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid domain_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..16\n";

my $connected = AnyEvent->condvar;
AnyEvent::XMPP::Test::start (
   $connected,
   'AnyEvent::XMPP::Ext::Presence',
   'AnyEvent::XMPP::Ext::Version',
   'AnyEvent::XMPP::Ext::Disco');

my ($im, $pres, $version, $disco) = $connected->recv;

my $first_req = AnyEvent->condvar;

$disco->request_info ($FJID1, $FJID2, undef, sub {
   my ($disco, $info, $error) = @_;

   if ($error) {
      print "# error getting disco info: " . $error->string . "\n";
      $first_req->send;
      return;
   }

   my $mi = ($info->identities ())[0];
   print ((($mi->{category} eq 'client') ? '' : 'not ')
          . "ok 1 - identity category\n");
   print (($info->has_feature (xmpp_ns ('version')) ? '' : 'not ')
          . "ok 2 - version feature loaded\n");
   print (($info->has_feature (xmpp_ns ('disco_info')) ? '' : 'not ')
          . "ok 3 - disco info feature loaded\n");
   print (($info->has_feature (xmpp_ns ('disco_items')) ? '' : 'not ')
          . "ok 4 - disco items feature loaded\n");

   $first_req->send;
});

$first_req->recv;

my $server_req = AnyEvent->condvar;

$disco->request_info ($FJID1, domain_jid ($FJID1), undef, sub {
   my ($disco, $info, $error) = @_;

   if ($error) {
      print "# error getting disco info of server: " . $error->string . "\n";
      $server_req->send;
      return;
   }

   my $mi = (grep { $_->{category} eq 'server' } $info->identities ())[0];

   if ($FJID1 =~ /jabberd-145a/) {
      print "ok 5 # skipped due to legacy server\n";
      print "ok 6 # skipped due to legacy server\n";
      print "ok 7 # skipped due to legacy server\n";
      print "ok 8 # skipped due to legacy server\n";

   } else {
      print ((($mi->{category} eq 'server') ? '' : 'not ')
             . "ok 5 - identity category of server\n");
      print (($info->has_feature (xmpp_ns ('version')) ? '' : 'not ')
             . "ok 6 - version feature on server\n");
      print (($info->has_feature (xmpp_ns ('disco_info')) ? '' : 'not ')
             . "ok 7 - disco info feature on server\n");
      print (($info->has_feature (xmpp_ns ('disco_items')) ? '' : 'not ')
             . "ok 8 - disco items feature on server\n");
   }

   $server_req->send;
});

$server_req->recv;

my $items_req = AnyEvent->condvar;

$disco->reg_cb (items => sub {
   my ($disco, $iqnode, $node, $items) = @_;
   if ($node eq 'test' && cmp_jid ($iqnode->meta->{dest}, $FJID2)) {
      push @$items, [ 'test@bar.org', 'something interesting' ];
      push @$items, [ 'test2@bar.org', 'bad stuff', 'subnode' ];
   }
});

$disco->request_items ($FJID1, $FJID2, 'test', sub {
   my ($disco, $items, $error) = @_;

   if ($error) {
      print "# error getting disco items of server: " . $error->string . "\n";
      $items_req->send;
      return;
   }

   print ((cmp_jid ($items->jid, $FJID2) ? '' : 'not ')
          . "ok 9 - items jid\n");
   print (($items->node eq 'test' ? '' : 'not ')
          . "ok 10 - items node\n");

   print ((($items->items)[0]->{jid} eq 'test@bar.org' ? '' : 'not ')
          . "ok 11 - first item jid\n");
   print ((($items->items)[0]->{name} eq 'something interesting' ? '' : 'not ')
          . "ok 12 - first item name\n");
   print ((not (defined (($items->items)[0]->{node})) ? '' : 'not ')
          . "ok 13 - first item node\n");

   print ((($items->items)[1]->{jid} eq 'test2@bar.org' ? '' : 'not ')
          . "ok 14 - second item jid\n");
   print ((($items->items)[1]->{name} eq 'bad stuff' ? '' : 'not ')
          . "ok 15 - second item name\n");
   print ((($items->items)[1]->{node} eq 'subnode' ? '' : 'not ')
          . "ok 16 - second item node\n");

   $items_req->send;
});

$items_req->recv;

AnyEvent::XMPP::Test::end ($im);
