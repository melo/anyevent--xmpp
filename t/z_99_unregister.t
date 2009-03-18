#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Ext::Registration;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq/;
use AnyEvent::XMPP::Node qw/simxml/;

AnyEvent::XMPP::Test::check ('client');

my $cv = AnyEvent->condvar;
my $im = AnyEvent::XMPP::IM->new;

my $cnt = 2;
my $n = 0;
my $t = 0;
$im->reg_cb (
   connected => sub {
      my ($self, $jid) = @_;
      my $reg = AnyEvent::XMPP::Ext::Registration->new (delivery => $self->get_connection ($jid));
      $reg->send_unregistration_request (sub {
         my ($reg, $ok, $error, $form) = @_;
         $n++;
         if ($ok) {
            print "ok $n - unregistered ($jid)\n";
         } else {
            print "not ok $n - unregistered ($jid): " . $error->string . "\n";
         }
         $reg->{delivery}->disconnect ("done");
      });
   },
   error => sub {
      my ($self, $jid, $error) = @_;
      print "# error $jid: " . $error->string . "\n";
      $self->stop_event;
   },
   disconnected => sub {
      my ($self, $jid, $ph, $pp, $reaso) = @_;
      print "# disconnected $jid: $reaso\n";
      $cv->send if --$cnt <= 0;
   }
);


$im->add_account ($JID1, $PASS);
$im->add_account ($JID2, $PASS);

$im->update_connections;

print "1..2\n";

$cv->recv;
