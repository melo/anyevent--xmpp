#!perl
use strict;
no warnings;
use utf8;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::Stream::Client;
use AnyEvent::XMPP::Ext::Registration;
use AnyEvent::XMPP::Util qw/split_jid new_message/;

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
$stream2->add_ext ('LangExtract');

$stream2->reg_cb (
   recv_message => sub {
      my ($stream2, $node) = @_;

      print (($node->meta->{body} =~ /ABC DEF 123/
               ? '' : 'not ') . "ok 3 - received message with body meta\n");
      print (($node->meta->{all_body}->{ja} =~ /にほん/
               ? '' : 'not ') . "ok 4 - received message with all_body meta\n");

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

      $stream->send (
         new_message (
            chat => {
               en => 'ABC DEF 123',
               ja => 'にほんじん'
            },
            to => $stream2->jid
         )
      );
   },
   disconnected => sub {
      my ($stream2, $h, $p) = @_;
      warn "disconnected [@_]\n";
      $cv->send;
   }
);

$stream->reg_cb (
   error => sub {
      my ($stream, $error) = @_;
      print "# error: " . $error->string . "\n";
      $stream->stop_event;
   },
   stream_ready => sub {
      my ($stream) = @_;
      print "ok 1 - logged in\n";

      $stream2->connect;
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

if ($stream2->get_ext ('LangExtract')) {
   print "ok 5 - Stream::Client extendable\n";
}
