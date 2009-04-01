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

print "1..6\n";

my $hdl;
AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $pres) = @_;

   $im->reg_cb (
      recv_message => sub {
         my ($im, $node) = @_;

         if (($node->find_all ([qw/stanza body/]))[0]->text =~ /Hi There/) {
            print "ok 2 - received message\n";
            print ((($node->attr ('type') eq 'chat')
                      ? '' : 'not ')
                   . "ok 3 - message type correct.\n");
            print ((($node->attr ('from') eq $FJID1)
                      ? '' : 'not ')
                   . "ok 4 - message from correct.\n");
            print ((($node->attr ('to') eq $FJID2)
                      ? '' : 'not ')
                   . "ok 5 - message to correct.\n");
            print ((($node->meta->{dest} eq $FJID2)
                      ? '' : 'not ')
                   . "ok 6 - message meta destination correct.\n");
         } else {
            print "# received bad message: " . $node->as_string . "\n";
            print "not ok 2 - received bogus message\n";
         }

         AnyEvent::XMPP::Test::end ($im);
      }
   );

   $im->send (new_message (
      chat => "Hi There!",
      to   => $FJID2,
      src  => $FJID1,
      sent_cb => sub { print "ok 1 - sent message\n" }
   ));
}, 'AnyEvent::XMPP::Ext::Presence', sub {
   my ($im, $cv, $pres) = @_;
   $pres->set_default (available => 'online and ready for messages', 10);
});
