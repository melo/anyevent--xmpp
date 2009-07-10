#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message new_presence bare_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

my %pres;
my $pres_ext;

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

sub check_test {
   print "1..17\n";

   my $n = 1;
   for my $jid ($FJID1, $FJID2) {
      my $g = _tostr ($pres{$jid});
      my $e = bare_jid ($jid) . "|10|available|I'm playing stuff|I'm playing stuff|にほんじん|Ich spiele sachen", "first's presence info correct";

      if ($g eq $e) { print "ok $n - $jid\n" }
      else {
         print "not ok $n - $jid\n";
         print "# got     : [$g]\n";
         print "# expected: [$e]\n";
      }
      $n++;
   }

   sub _check_pres {
      my ($struct, $p, $desc) = @_;

      for (keys %$struct) {
         if ($struct->{$_} eq $p->{$_}) {
            print "ok $n - $_ of $desc presence\n";
         } else {
            print "not ok $n - $_ of $desc presence\n";
            print "# got     : [$p->{$_}]\n";
            print "# expected: [$struct->{$_}]\n";
            print "# => " . JSON->new->pretty->convert_blessed->encode ($p) . "\n";
         }
         $n++;
      }
   }

   my @ps  = $pres_ext->presences ($FJID2, bare_jid ($FJID1));
   my @ps2 = $pres_ext->presences ($FJID2, $FJID1);
   my @ps3 = $pres_ext->presences ($FJID1);
   my @ps4 = $pres_ext->highest_prio_presence ($FJID1);
   my @ps5 = $pres_ext->highest_prio_presence ($FJID2);

   _check_pres ({
      show => 'away', priority => -10, status => 'Going out'
   }, $ps[-1], "bare jid1");
   _check_pres ({
      show => 'away', priority => -10, status => 'Going out'
   }, $ps2[-1], "jid1");
   _check_pres ({
      show => 'available', priority => 10, status => "I'm playing stuff"
   }, $ps3[-1], "any jid1 other");
   _check_pres ({
      show => 'available', priority => 10, status => "I'm playing stuff"
   }, $ps4[-1], "highest of jid1");
   _check_pres ({
      show => 'away', priority => -10, status => 'Going out'
   }, $ps5[-1], "highest of jid2");
}


AnyEvent::XMPP::Test::check ('client');

my $cnt = 2;
my $end;

my $connected = AnyEvent->condvar;
my $done      = AnyEvent->condvar;
AnyEvent::XMPP::Test::start (
   $connected,
   'AnyEvent::XMPP::Ext::Presence', sub {
      my ($im, $pres) = @_;

      $pres_ext = $pres;

      $pres->reg_cb (
         self => sub {
            my ($pres, $resjid, $jid, $old, $new) = @_;
            unless ($end) {
               $pres{$resjid} = [$jid => $new];
            }
         },
         change => sub {
            my ($pres, $resjid, $jid) = @_;

            if ($cnt-- <= 0) {
               unless ($end) {
                  check_test ();
                  $end = 1;
                  $done->send;
               }
            }
         }
      );

      $pres->set_default (available => {
         en => "I'm playing stuff",
         de => "Ich spiele sachen",
         ja => "にほんじん",
      }, 10);
   }
);

my ($im, $pres) = $connected->recv;

$im->send (new_presence (
   available => away => "Going out" => -10, src => $FJID1, to => $FJID2
));

$done->recv;
AnyEvent::XMPP::Test::end ($im);
