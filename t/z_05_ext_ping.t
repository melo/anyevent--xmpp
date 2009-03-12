#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;

AnyEvent::XMPP::Test::check ('client');

print "1..2\n";

my $hdl;
AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv) = @_;

   $im->add_extension ('AnyEvent::XMPP::Ext::Ping');

   # while we are at it, test the Extendable interface:
   my $ext = $im->get_extension ('AnyEvent::XMPP::Ext::Ping');
   
   $ext->ping ($FJID1, undef, sub {
      my ($latency, $error) = @_;

      if ($error) {
         if ($error->condition eq 'feature-not-implemented'
             || $error->condition eq 'service-unavailable') {
            print "ok 1 # skip received error from server: $latency seconds\n";
         } else {
            print "not ok 1 - received error from server: $latency seconds\n";
         }
      } else {
         print "ok 1 - received ping reply from server: $latency seconds\n";
      }

      $ext->ping ($FJID1, $FJID2, sub {
         my ($latency, $error) = @_;

         if ($error) {
            print "not ok 2 - received error from second jid: $latency seconds\n";
         } else {
            print "ok 2 - received ping reply from second jid: $latency seconds\n";
         }

         $cv->send;
      });
   });
});
