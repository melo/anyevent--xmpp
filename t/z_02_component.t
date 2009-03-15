#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::Socket;
use AnyEvent::XMPP::Stream::Component;

AnyEvent::XMPP::Test::check ('component');

my $cv = AnyEvent->condvar;

my $stream =
   AnyEvent::XMPP::Stream::Component->new (
      domain => $SERVICE, secret => $SECRET . 'a',
   );

my $try = 1;
$stream->reg_cb (
   stream_ready => sub {
      print "ok 2 - connected and stream ready\n";
      $cv->send;
   },
   disconnected => sub {
      my ($stream, $h, $p, $reas) = @_;
      if ($reas =~ /handshake|not-author/i && $try-- > 0) {
         print "ok 1 - disconnected due to wrong password\n";
         $stream->{secret} = $SECRET;
         $stream->connect ($HOST, $PORT);

      } else {
         print "not ok 1 - disconnected from $h:$p ($reas)\n";
         $cv->send;
      }
   },
   error => sub {
      my ($stream, $error) = @_;
      if ($error->isa ('AnyEvent::XMPP::Error::Exception')) {
         warn "exception: " . $error->string . "\n";
      }
      $stream->stop_event;
   },
   connect_error => sub {
      my ($stream, $reas) = @_;
      print "not ok 1 - connect error ($reas)\n";
      $cv->send;
   },
);

$stream->connect ($HOST, $PORT);

print "1..2\n";

$cv->recv;
