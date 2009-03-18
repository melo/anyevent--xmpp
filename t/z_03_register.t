#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::Stream::Client;
use AnyEvent::XMPP::Ext::Registration;
use AnyEvent::XMPP::Util qw/split_jid/;

AnyEvent::XMPP::Test::check ('client');

my $cv = AnyEvent->condvar;

my $stream = AnyEvent::XMPP::Stream::Client->new (
   jid      => $JID1,
   password => $PASS,
);

my $reg = AnyEvent::XMPP::Ext::Registration->new (delivery => $stream);

my $registered = 0;
my $logged_in  = 0;
my $unregistered = 1;
my $recon_cnt = 1;

$stream->reg_cb (
   connected => sub {
      my ($stream, $h, $p) = @_;

      print "ok 1 - connected\n";
   },
   pre_authentication => sub {
      my ($stream) = @_;

      my $ev = $stream->stop_event;

      my ($username, $domain, $pass) = $stream->credentials;

      $reg->quick_registration ($username, $pass, sub {
         my ($error) = @_;

         if ($error) {
            print "# Couldn't register: " . $error->string . "\n";
            print "not ok 2 - registered first JID\n";

         } else {
            print "ok 2 - registered first JID\n";
         }

         my ($username2) = split_jid ($JID2);
         $reg->quick_registration ($username2, $pass, sub {
            my ($error) = @_;

            if ($error) {
               print "# Couldn't register second: " . $error->string . "\n";
               print "not ok 3 - registered second JID\n";

            } else {
               print "ok 3 - registered second JID\n";
            }

            $ev->();
         });
      });
   },
   stream_ready => sub {
      my ($stream) = @_;
      $logged_in = 1;
      $cv->send;
   },
   disconnected => sub {
      my ($stream, $h, $p) = @_;
      $cv->send;
   }
);

$stream->connect;

print "1..4\n";

$cv->recv;

print (($logged_in ? '' : 'not ') . "ok 4 - logged in successfully\n");
