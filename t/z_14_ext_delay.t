#!perl
use strict;
no warnings;
use utf8;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::Stream::Client;
use AnyEvent::XMPP::Ext::Registration;
use AnyEvent::XMPP::Util qw/split_jid new_message xmpp_datetime_as_timestamp/;

AnyEvent::XMPP::Test::check ('client');

my $cv = AnyEvent->condvar;

my $stream = AnyEvent::XMPP::Stream::Client->new (
   jid      => $JID1,
   password => $PASS,
);

my $stream2 = AnyEvent::XMPP::Stream::Client->new (
   jid      => $JID2,
   password => $PASS,
);

$stream->add_ext ('Presence');
$stream2->add_ext ('Presence');
my $delay = $stream2->add_ext ('Delay');
$delay->enable_unix_timetamp;

$stream2->reg_cb (
   recv_message => sub {
      my ($stream2, $node) = @_;

      my $now = time;
      my $ts  = xmpp_datetime_as_timestamp ($node->meta->{delay}->{timestamp});

      print (($node->meta->{delay}
                ? '' : 'not ') . "ok 3 - received delayed message\n");
      print (($now - $ts < 5
                ? '' : 'not ') . "ok 4 - received delayed message not very old\n");
      print (($ts == $node->meta->{delay}->{unix_timestamp}
                ? '' : 'not ') . "ok 5 - received delayed message with unix timestamp\n");

      $cv->send;
   },
   error => sub {
      my ($stream2, $error) = @_;
      print "# error: " . $error->string . "\n";
      $stream2->stop_event;
   },
   stream_ready => sub {
      my ($stream2) = @_;
      print "ok 2 - logged in second\n";
   },
   disconnected => sub {
      my ($stream2, $h, $p) = @_;
      warn "disconnected [@_]\n";
      $cv->send;
   }
);

my $t;
$stream->reg_cb (
   error => sub {
      my ($stream, $error) = @_;
      print "# error: " . $error->string . "\n";
      $stream->stop_event;
   },
   stream_ready => sub {
      my ($stream) = @_;
      print "ok 1 - logged in\n";

      $stream->send (
         new_message (
            chat => 'ABC DEF 123',
            to => $JID2,
         )
      );

      $stream->send (
         new_message (
            chat => 'ABC DEF 123',
            to => $JID2,
            sent_cb => sub {
               $t = AnyEvent->timer (
                       after => 0.5, cb => sub { $stream2->connect; undef $t });
            }
         )
      );
   },
   disconnected => sub {
      my ($stream, $h, $p) = @_;
      warn "disconnected [@_]\n";
      $cv->send;
   }
);

$stream->connect;

print "1..5\n";

$cv->recv;
