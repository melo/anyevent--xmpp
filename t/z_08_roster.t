#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::CM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..8\n";

my $ROST;
my $CM;

sub clean {
   my $cb = shift;
   my $gcv = AnyEvent->condvar;
   $gcv->begin ($cb);
      $gcv->begin;
      $ROST->remove ($FJID1, bare_jid ($FJID2), sub { $gcv->end });
      $gcv->begin;
      $ROST->remove ($FJID1, 'test@bar.org', sub { $gcv->end });
      $gcv->begin;
      $ROST->remove ($FJID2, bare_jid ($FJID1), sub { $gcv->end });
   $gcv->end;
}

sub _check_item {
   my ($expected, $got, $nr, $desc) = @_;

   if ($expected->{groups}) {
      $expected->{groups} = [ sort { $a cmp $b } @{$expected->{groups}} ];
   }
   if ($got->{groups}) {
      $got->{groups} = [ sort { $a cmp $b } @{$got->{groups}} ];
   }

   my $jse = JSON->new->canonical->encode ($expected);
   my $jsg = JSON->new->canonical->encode ($got);

   print (($jse eq $jsg ? "" : "not ") . "ok $nr - $desc\n");
   if ($jse ne $jsg) {
      print "# got     : [$jsg]\n";
      print "# expected: [$jse]\n";
   }
}

my $connected = AnyEvent->condvar;
my $roster_jid1_fetched = AnyEvent->condvar;
my $roster_jid2_fetched = AnyEvent->condvar;

AnyEvent::XMPP::Test::start (
   $connected,
   'AnyEvent::XMPP::Ext::Roster', sub {
      my ($im, $rost) = @_;

      $rost->reg_cb (
         fetched => sub {
            my ($rost, $jid, $roster) = @_;

            $roster_jid1_fetched->send if cmp_jid ($FJID1, $jid);
            $roster_jid2_fetched->send if cmp_jid ($FJID2, $jid);
         }
      );

      $rost->auto_fetch;
   }
);

my $tout =
   AnyEvent->timer (after => 10, cb => sub {
      warn "test timeout, cleaning up roster...\n";
      clean (sub { exit 1 })
   });


($CM, $ROST) = $connected->recv;

$_->recv for ($roster_jid1_fetched, $roster_jid2_fetched);

my $got_roster_change_jid1 = AnyEvent->condvar;
my $got_roster_change_jid2 = AnyEvent->condvar;

$got_roster_change_jid1->begin ($got_roster_change_jid1);

$got_roster_change_jid1->begin;
$got_roster_change_jid1->begin;

$ROST->reg_cb (
   change => sub {
      my ($rost, $jid) = @_;

      if (cmp_jid ($jid, $FJID1)) {
         $got_roster_change_jid1->end;
      } else {
         $got_roster_change_jid2->send;
      }
   }
);

$ROST->set ($FJID1,
   { jid => bare_jid ($FJID2), name => "MR.2", groups => [ 'A', 'B' ] },
   sub {
      $ROST->set ($FJID1, { jid => 'test@bar.org', name => "ME" })
   });

$ROST->set ($FJID2,
   { jid => bare_jid ($FJID1), name => "MR.1", groups => [ 'C', 'D' ] });


$got_roster_change_jid1->end;

$_->recv for ($got_roster_change_jid1, $got_roster_change_jid2);

my $roster1 = $ROST->get ($FJID1);
my $roster2 = $ROST->get ($FJID2);

tp (1, $roster1->{bare_jid ($FJID2)}
      && $roster1->{'test@bar.org'}
      && $roster2->{bare_jid ($FJID1)}, 'first roster change');

_check_item ({
      jid => bare_jid ($FJID2), name => 'MR.2', groups => [ 'A', 'B' ],
      ask => undef, subscription => 'none'
   }, $ROST->get ($FJID1, bare_jid ($FJID2)),
   2, "1st roster first set"
);

_check_item ({
      jid => 'test@bar.org', name => 'ME', groups => [ ],
      ask => undef, subscription => 'none'
   }, $ROST->get ($FJID1, 'test@bar.org'),
   3, "1st roster second set"
);

_check_item ({
      jid => bare_jid ($FJID1), name => 'MR.1', groups => [ 'C', 'D' ],
      ask => undef, subscription => 'none'
   }, $ROST->get ($FJID2, bare_jid ($FJID1)),
   4, "2nd roster first set"
);

my $got_2nd_roster_change = AnyEvent->condvar;

$ROST->reg_cb (
   change => sub {
      my ($rost, $jid) = @_;

      if (cmp_jid ($FJID1, $jid)) {
         $got_2nd_roster_change->send ($rost->get ($FJID1))
      }
   }
);

$ROST->set ($FJID1, { jid => 'test@bar.org', name => 'NOT ME', groups => [ 'Z' ] });

my ($roster1_2) = $got_2nd_roster_change->recv;

tp (5,
   $roster1_2->{'test@bar.org'}->{name} eq 'NOT ME'
   && $roster1_2->{'test@bar.org'}->{groups}->[0] eq 'Z',
   "next roster change");

_check_item ({
      jid => bare_jid ($FJID2), name => 'MR.2', groups => [ 'A', 'B' ],
      ask => undef, subscription => 'none'
   }, $ROST->get ($FJID1, bare_jid ($FJID2)),
   6, "1st roster first set still ok"
);

_check_item ({
      jid => 'test@bar.org', name => 'NOT ME', groups => [ 'Z' ],
      ask => undef, subscription => 'none'
   }, $ROST->get ($FJID1, 'test@bar.org'),
   7, "1st roster second set modified"
);

my $roster1_empty = AnyEvent->condvar;

$ROST->reg_cb (
   gone => sub {
      my ($rost, $jid) = @_;

      if (cmp_jid ($jid, $FJID1)) {
         $roster1_empty->send;
      }
   }
);

my $cleanup_done = AnyEvent->condvar;

clean ($cleanup_done);

$cleanup_done->send;

$CM->get_connection ($FJID1)->send_end;

$roster1_empty->recv;

tp (8, $ROST->item_jids ($FJID1) == 0, "first roster empty");

undef $tout;

AnyEvent::XMPP::Test::end ($CM);
