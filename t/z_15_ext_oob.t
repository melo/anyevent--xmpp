#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid domain_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..6\n";

sub p {
   my ($nr, $cond, $desc) = @_;
   printf "%sok %d - %s\n", ($cond ? '' : 'not '), $nr, $desc;
}

AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $oob) = @_;

   my $cv_request_done = AnyEvent->condvar;
   my $cv_got_oob_req  = AnyEvent->condvar;

   $oob->reg_cb (oob_recv => sub {
      my ($oob, $node, $oob_data) = @_;
      $oob->unreg_me;

      p (1, $node->meta->{dest} eq $FJID2,
         "destination of oob send");
      p (2, $oob_data->{url}    eq "http://www.test.de/blabla",
         "url");
      p (3, $oob_data->{desc}   eq "Have something...",
         "description");

      $oob->reply_success ($node);
   });

   $oob->send_url (
      $FJID1, $FJID2, 'http://www.test.de/blabla', "Have something...", sub {
         my ($error) = @_;

         p (4, (not $error), "no error on reply");

         $oob->reg_cb (oob_recv => sub {
            my ($oob, $node, $oob_data) = @_;

            p (5, $oob_data->{url} eq 'http://err.eu', "got second request");
            $oob->reply_failure ($node, 'reject');
         });

         $oob->send_url ($FJID2, $FJID1, "http://err.eu", "Nothing", sub {
            my ($error) = @_;

            p (6, $error eq 'reject', "got failure response");
            $cv->send;
         });
      });

}, 'AnyEvent::XMPP::Ext::OOB');
