#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message new_presence/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

my %pres;
my $cnt = 2;
my $pres_ext;
AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $pres) = @_;

   $im->send (new_presence (
      available => away => "Going out" => -10, src => $FJID1, to => $FJID2
   ));
}, 'AnyEvent::XMPP::Ext::Presence', sub {
      my ($im, $cv, $pres) = @_;

      $pres_ext = $pres;

      $im->reg_cb (
         ext_presence_self => sub {
            my ($im, $resjid, $jid, $old, $new) = @_;
            $pres{$resjid} = [$jid => $new];
         },
         ext_presence_change => sub {
            my ($im, $resjid, $jid) = @_;

            if ($cnt-- <= 0) {
               $cv->send;
            }
         }
      );

      $pres->set_default (available => [
         en => "I'm playing stuff",
         de => "Ich spiele sachen",
         ja => "にほんじん",
      ], 10);
   }
);

sub _tostr {
   my ($t) = @_;
   join "|",
      $t->[0],
      $t->[1]->{priority},
      $t->[1]->{show},
      $t->[1]->{status},
      $t->[1]->{all_status}->{en},
      $t->[1]->{all_status}->{ja},
      $t->[1]->{all_status}->{de},
}

print "1..2\n";

my $n = 1;
for my $jid ($FJID1, $FJID2) {
   my $g = _tostr ($pres{$jid});
   my $e = "$jid|10|available|I'm playing stuff|I'm playing stuff|にほんじん|Ich spiele sachen", "first's presence info correct";

   if ($g eq $e) { print "ok $n - $jid\n" }
   else {
      print "not ok $n - $jid\n";
      print "# got     : [$g]\n";
      print "# expected: [$e]\n";
   }
   $n++;
}

print JSON->new->convert_blessed->pretty->encode ($pres_ext->{p}) . "\n";
