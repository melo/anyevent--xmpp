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

print "1..3\n";

my $hdl;
AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv) = @_;

   my $version = $im->add_extension ('AnyEvent::XMPP::Ext::Version');

   $version->request_version ($FJID1, $im->get_connection ($FJID1)->{server_jid}, sub {
      my ($v, $e) = @_;

      if ($e) {
         print "not ok 1 - retrieving version from server\n";
      } else {
         for (keys %$v) {
            print "# $_: $v->{$_}\n";
         }
         print "ok 1 - retrieving version from server\n";
      }

      $version->request_version ($FJID1, $FJID1, sub {
         my ($v, $e) = @_;

         if ($e) {
            print "not ok 2 - retrieving version from ourself\n";
         } else {
            for (keys %$v) {
               print "# $_: $v->{$_}\n";
            }
            print "ok 2 - retrieving version from ourself\n";
            print (($v->{name} eq 'AnyEvent::XMPP' ? '' : 'not ')
                   . "ok 3 - own name ok\n");
         }

         $cv->send;
      });
   });
});
