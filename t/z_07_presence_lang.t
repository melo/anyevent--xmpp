#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

my %pres;
my $cnt = 2;
AnyEvent::XMPP::Test::start (sub { },
   'AnyEvent::XMPP::Ext::Presence', sub {
      my ($im, $cv, $pres) = @_;

      $im->reg_cb (
         ext_presence_self => sub {
            my ($im, $resjid, $jid, $old, $new) = @_;
            $pres{$resjid} = [$jid => $new];

            if ($new->{status} =~ /playing/) {
               $cv->send if --$cnt <= 0;
            }
         },
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
