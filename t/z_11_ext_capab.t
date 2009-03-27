#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message new_reply
                           new_presence bare_jid cmp_jid domain_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::StanzaHandler;
use Predicates;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

my $CV;
my $PRES;
my $DISCO;
my $VERSION;
my $IM;

my %TEST_CAPA = (
xep_test => <<CAPA,
<identity xml:lang='en' category='client' name='Psi 0.11' type='pc'/>
<identity xml:lang='el' category='client' name='Ψ 0.11' type='pc'/>
<feature var='http://jabber.org/protocol/caps'/>
<feature var='http://jabber.org/protocol/disco#info'/>
<feature var='http://jabber.org/protocol/disco#items'/>
<feature var='http://jabber.org/protocol/muc'/>
<x xmlns='jabber:x:data' type='result'>
<field var='FORM_TYPE' type='hidden'>
   <value>urn:xmpp:dataforms:softwareinfo</value>
</field>
<field var='ip_version'>
   <value>ipv4</value>
   <value>ipv6</value>
</field>
<field var='os'>
   <value>Mac</value>
</field>
<field var='os_version'>
   <value>10.5.1</value>
</field>
<field var='software'>
   <value>Psi</value>
</field>
<field var='software_version'>
   <value>0.11</value>
</field>
</x>
CAPA
tkabber_test => <<CAPA,
<identity category="client" name="Tkabber" type="pc"/>
<x type="result" xmlns="jabber:x:data">
  <field type="hidden" var="FORM_TYPE">
    <value>urn:xmpp:dataforms:softwareinfo</value>
  </field>
  <field var="software">
    <value>Tkabber</value>
  </field>
  <field var="software_version">
    <value>0.11.0 (Tcl/Tk 8.4.19)</value>
  </field>
  <field var="os">
    <value>Debian GNU/Linux 5.0 (lenny) 5.0 lenny</value>
  </field>
  <field var="os_version">
    <value>2.6.26-1-amd64</value>
  </field>
</x>
<feature var="http://jabber.org/protocol/activity"/>
<feature var="http://jabber.org/protocol/bytestreams"/>
<feature var="http://jabber.org/protocol/chatstates"/>
<feature var="http://jabber.org/protocol/commands"/>
<feature var="http://jabber.org/protocol/commands"/>
<feature var="http://jabber.org/protocol/disco#info"/>
<feature var="http://jabber.org/protocol/disco#items"/>
<feature var="http://jabber.org/protocol/feature-neg"/>
<feature var="http://jabber.org/protocol/geoloc"/>
<feature var="http://jabber.org/protocol/ibb"/>
<feature var="http://jabber.org/protocol/iqibb"/>
<feature var="http://jabber.org/protocol/mood"/>
<feature var="http://jabber.org/protocol/muc"/>
<feature var="http://jabber.org/protocol/rosterx"/>
<feature var="http://jabber.org/protocol/si"/>
<feature var="http://jabber.org/protocol/si/profile/file-transfer"/>
<feature var="http://jabber.org/protocol/tune"/>
<feature var="jabber:iq:avatar"/>
<feature var="jabber:iq:browse"/>
<feature var="jabber:iq:last"/>
<feature var="jabber:iq:oob"/>
<feature var="jabber:iq:privacy"/>
<feature var="jabber:iq:time"/>
<feature var="jabber:iq:version"/>
<feature var="jabber:x:data"/>
<feature var="jabber:x:event"/>
<feature var="jabber:x:oob"/>
<feature var="urn:xmpp:ping"/>
<feature var="urn:xmpp:time"/>
CAPA
);

my %TEST_CAPA_VERSTR = (
   xep_test => 'client/pc/el/Ψ 0.11<client/pc/en/Psi 0.11<http://jabber.org/protocol/caps<http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<http://jabber.org/protocol/muc<urn:xmpp:dataforms:softwareinfo<ip_version<ipv4<ipv6<os<Mac<os_version<10.5.1<software<Psi<software_version<0.11<',
   tkabber_test => 'client/pc//Tkabber<http://jabber.org/protocol/activity<http://jabber.org/protocol/bytestreams<http://jabber.org/protocol/chatstates<http://jabber.org/protocol/commands<http://jabber.org/protocol/commands<http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<http://jabber.org/protocol/feature-neg<http://jabber.org/protocol/geoloc<http://jabber.org/protocol/ibb<http://jabber.org/protocol/iqibb<http://jabber.org/protocol/mood<http://jabber.org/protocol/muc<http://jabber.org/protocol/rosterx<http://jabber.org/protocol/si<http://jabber.org/protocol/si/profile/file-transfer<http://jabber.org/protocol/tune<jabber:iq:avatar<jabber:iq:browse<jabber:iq:last<jabber:iq:oob<jabber:iq:privacy<jabber:iq:time<jabber:iq:version<jabber:x:data<jabber:x:event<jabber:x:oob<urn:xmpp:ping<urn:xmpp:time<urn:xmpp:dataforms:softwareinfo<os<Debian GNU/Linux 5.0 (lenny) 5.0 lenny<os_version<2.6.26-1-amd64<software<Tkabber<software_version<0.11.0 (Tcl/Tk 8.4.19)<',
);

my %TEST_CAPA_HASH = (
   xep_test     => 'q07IKJEyjvHSyhy//CH0CxmKi8w=',
   tkabber_test => '3Ms9tfXJFs4QHlrJScnZOnQpBSU=',
);

print "1.." . (scalar (keys %TEST_CAPA) * 2) . "\n";

my $ctx;
$ctx = pred_ctx {
   pred_decl 'start';
   pred_action start => sub {
      $IM->reg_cb (recv_iq => 10 => sub {
         my ($IM, $node) = @_;

         if (my ($Q) = $node->find (disco_info => 'query')) {
            my $rep = new_reply ($node, {
               node => {
                  name => 'query', dns => 'disco_info',
                  attrs => [ node => $Q->attr ('node') ],
                  childs => [ \$TEST_CAPA{$Q->attr ('node')} ]
               }
            });
            $IM->send ($rep);
            $IM->stop_event;
         }
      });

      my $gcv = AnyEvent->condvar;
      $gcv->begin (sub { $CV->send });

      my $cnt = 0;
      for (keys %TEST_CAPA) {
         my $capanode = $_;
         $gcv->begin;
         $DISCO->request_info ($FJID1, $FJID2, $capanode, sub {
            my ($DISCO, $info, $error) = @_;

            if ($error) {
               print "# error getting disco info: " . $error->string . "\n";
               $CV->send;
               return;
            }

            $cnt++;
            print (($info->as_verification_string eq $TEST_CAPA_VERSTR{$capanode}
                       ? '' : 'not ')
                   . "ok $cnt - verification string matches\n");
            $cnt++;
            print (($info->as_verification_hash eq $TEST_CAPA_HASH{$capanode}
                       ? '' : 'not ')
                   . "ok $cnt - verification hash matches\n");
            $gcv->end;
         });
      }

      $gcv->end;
   };
};

AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $disco) = @_;

   $IM      = $im;
   $DISCO   = $disco;
   $CV      = $cv;

   pred_set ($ctx, 'start');
}, 'AnyEvent::XMPP::Ext::Disco');
