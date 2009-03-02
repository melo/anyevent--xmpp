#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::XMPP::Stream;
use AnyEvent::XMPP::Util qw/new_iq/;

my $cv = AnyEvent->condvar;

my ($lh, $lp);
my $hdl;
my $buf;

my $stream = AnyEvent::XMPP::Stream->new;

$stream->reg_cb (
   connected => sub {
      my ($stream, $h, $p) = @_;

      print "ok 2 - connected\n";

      $stream->send_header;
      $stream->reg_cb (send_buffer_empty => sub {
         my ($stream) = @_;
         $stream->unreg_me;
         print "ok 4 - called send_buffer_empty\n";
      });
      my $node = new_iq (set =>
         create => { defns => 'test', node => { name => 'test123' } }
      );
      $node->meta->add_sent_cb (sub { $stream->disconnect ('done') });
      $stream->send ($node);
   },
   connect_error => sub {
      my ($stream, $msg) = @_;

      print "ok 1 - connect error ($msg)\n";
      $stream->connect ($lh, $lp);
   },
   disconnected => sub {
      my ($stream, $h, $p, $msg) = @_;
      print "ok 3 - disconnected\n";
   }
);

tcp_server undef, undef, sub {
   my ($fh, $h, $p) = @_;

   $hdl = AnyEvent::Handle->new (
      fh => $fh,
      on_eof => sub { $cv->send },
      on_read => sub {
         $buf .= $hdl->rbuf;
         $hdl->rbuf = '';
      }
   );

}, sub {
   my ($fh, $h, $p) = @_;
   ($lh, $lp) = ($h, $p);

   $stream->connect ($lh, 0);
};

print "1..5\n";

$cv->recv;

if ($buf =~ /<stream:stream.*xmlns="jabber:client".*<iq.*test123/s) {
   print "ok 5 - received stream element and iq\n";
} else {
   print "not ok 5 - didn't recognize stream element ($buf)\n";
}
