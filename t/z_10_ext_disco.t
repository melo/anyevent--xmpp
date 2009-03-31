#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid domain_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::StanzaHandler;
use Predicates;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..16\n";

my $CV;
my $PRES;
my $DISCO;
my $VERSION;
my $IM;

my $ctx;
$ctx = pred_ctx {
   pred_decl 'start';
   pred_action start => sub {
      $DISCO->request_info ($FJID1, $FJID2, undef, sub {
         my ($DISCO, $info, $error) = @_;

         if ($error) {
            print "# error getting disco info: " . $error->string . "\n";
            $CV->send;
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

         pred_set ($ctx, 'got_disco_info');
      });
   };

   pred_decl 'got_disco_info';
   pred_action got_disco_info => sub {
      $DISCO->request_info ($FJID1, domain_jid ($FJID1), undef, sub {
         my ($DISCO, $info, $error) = @_;

         if ($error) {
            print "# error getting disco info of server: " . $error->string . "\n";
            $CV->send;
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

         pred_set ($ctx, 'got_server_info');
      });
   };

   pred_decl 'got_server_info';
   pred_action got_server_info => sub {
      $DISCO->reg_cb (items => sub {
         my ($DISCO, $iqnode, $node, $items) = @_;
         if ($node eq 'test' && cmp_jid ($iqnode->meta->{dest}, $FJID2)) {
            push @$items, [ 'test@bar.org', 'something interesting' ];
            push @$items, [ 'test2@bar.org', 'bad stuff', 'subnode' ];
         }
      });

      $DISCO->request_items ($FJID1, $FJID2, 'test', sub {
         my ($DISCO, $items, $error) = @_;

         if ($error) {
            print "# error getting disco items of server: " . $error->string . "\n";
            $CV->send;
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

         $CV->send;
      });
   };
};

AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $pres, $version, $disco) = @_;

   $IM      = $im;
   $PRES    = $pres;
   $VERSION = $version;
   $DISCO   = $disco;
   $CV      = $cv;

   pred_set ($ctx, 'start');
},
'AnyEvent::XMPP::Ext::Presence',
'AnyEvent::XMPP::Ext::Version',
'AnyEvent::XMPP::Ext::Disco');
