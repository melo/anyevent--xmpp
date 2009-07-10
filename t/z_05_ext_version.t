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

my $connected      = AnyEvent->condvar;
my $first_version  = AnyEvent->condvar;
my $second_version = AnyEvent->condvar;
AnyEvent::XMPP::Test::start (1, $connected);
my ($im) = $connected->recv;

my $version = $im->add_ext ('Version');

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

   $first_version->send;
});

$first_version->recv;

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

   $second_version->send;
});

$second_version->recv;
AnyEvent::XMPP::Test::end ($im);
