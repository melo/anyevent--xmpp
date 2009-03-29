#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message new_reply
                           new_presence bare_jid cmp_jid domain_jid extract_lang_element/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::StanzaHandler;
use Predicates;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

my $CV;
my $PRES;
my $MUC;
my $IM;

print "1..0\n";

my $ctx;
$ctx = pred_ctx {
   pred_decl 'start';
   pred_action start => sub {
   };
};

AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $pres, $muc) = @_;

   undef $AnyEvent::XMPP::Test::TOUT;

   $IM      = $im;
   $PRES    = $pres;
   $MUC     = $muc;
   $CV      = $cv;

   $MUC->reg_cb (
      created => sub {
         my ($self, $resjid, $mucjid) = @_;
         warn "on $resjid created $mucjid\n";
      },
      subject_changed => sub {
         my ($self, $resjid, $mucjid, $occjid, $new_subject) = @_;
         warn "on $resjid in $mucjid $occjid changed subject: $new_subject->{subject}\n";
      },
      nick_changed => sub {
         my ($self, $resjid, $mucjid, $occjid, $newjid) = @_;
         warn "on $resjid in $mucjid $occjid changed nick: $newjid\n";
      },
      message => sub {
         my ($self, $resjid, $mucjid, $occjid, $node) = @_;
         my $msg_struct = {};
         extract_lang_element ($node, 'body', $msg_struct);
         warn "on $resjid in $mucjid $occjid said: " . $msg_struct->{body} . "\n";
      },
      message_echo => sub {
         my ($self, $resjid, $mucjid, $occjid, $node) = @_;
         my $msg_struct = {};
         extract_lang_element ($node, 'body', $msg_struct);
         warn "on $resjid in $mucjid !you! said: " . $msg_struct->{body} . "\n";
      },
      entered => sub {
         my ($self, $resjid, $mucjid) = @_;
         warn "on $resjid entered $mucjid\n";

         my @list = $PRES->presences ($FJID1, 'test@conference.ejabberd.test');
         for (grep { $_->{show} ne 'unavailable' } @list) {
            print "INROOM: " . $_->{jid} . "\n";
         }

         #$IM->send (new_message (
         #   groupchat => "Hi there!", src => $resjid, to => $mucjid));
      },
      joined => sub {
         my ($self, $resjid, $mucjid, $occjid) = @_;
         warn "on $resjid joined $mucjid: $occjid\n";
         my @list = $PRES->presences ($FJID1, 'test@conference.ejabberd.test');
         for (grep { $_->{show} ne 'unavailable' } @list) {
            print "INROOM: " . $_->{jid} . "\n";
         }

      },
      parted => sub {
         my ($self, $resjid, $mucjid, $occjid) = @_;
         warn "on $resjid parted $mucjid: $occjid\n";
         my @list = $PRES->presences ($FJID1, 'test@conference.ejabberd.test');
         for (grep { $_->{show} ne 'unavailable' } @list) {
            print "INROOM: " . $_->{jid} . "\n";
         }
      },
      left => sub {
         my ($self, $resjid, $mucjid) = @_;
         warn "on $resjid left $mucjid\n";
      },
   );

   $PRES->set_default (away => 'chatting with gf');

   $MUC->join ($FJID1, 'test@conference.ejabberd.test', "elmex");

   pred_set ($ctx, 'start');
}, 'AnyEvent::XMPP::Ext::Presence', 'AnyEvent::XMPP::Ext::MUC');
