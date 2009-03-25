#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use Predicates;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..8\n";

my %fetched;
my $roster1;
my $roster2;
my $CV;
my $ROST;
my $IM;


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

my $flags = { };
my $tout;
my $ctx;
$ctx = pred_ctx {
   pred_decl 'start';

   pred_action start => sub {
      $tout = AnyEvent->timer (after => 10, cb => sub { clean (sub { $CV->send }) });
   };

   pred_decl fetched_rosters =>
      sub { pred ('start') && $fetched{$FJID1} && $fetched{$FJID2} };
   pred_action fetched_rosters => sub {
      clean (sub { pred_set ($ctx => 'cleaned_rosters') })
   };

   pred_decl 'cleaned_rosters';
   pred_action cleaned_rosters => sub {
      $ROST->set ($FJID1,
         { jid => bare_jid ($FJID2), name => "MR.2", groups => [ 'A', 'B' ] },
         sub {
            $ROST->set ($FJID1, { jid => 'test@bar.org', name => "ME" })
         });

      $ROST->set ($FJID2,
         { jid => bare_jid ($FJID1), name => "MR.1", groups => [ 'C', 'D' ] });
   };

   pred_decl 'got_items', sub {
      pred ('cleaned_rosters')
      && $roster1->{bare_jid ($FJID2)}
      && $roster1->{'test@bar.org'}
      && $roster2->{bare_jid ($FJID1)}
   };
   pred_action got_items => sub {
      _check_item ({
            jid => bare_jid ($FJID2), name => 'MR.2', groups => [ 'A', 'B' ],
            ask => undef, subscription => 'none'
         }, $ROST->get ($FJID1, bare_jid ($FJID2)),
         1, "1st roster first set"
      );

      _check_item ({
            jid => 'test@bar.org', name => 'ME', groups => [ ],
            ask => undef, subscription => 'none'
         }, $ROST->get ($FJID1, 'test@bar.org'),
         2, "1st roster second set"
      );

      _check_item ({
            jid => bare_jid ($FJID1), name => 'MR.1', groups => [ 'C', 'D' ],
            ask => undef, subscription => 'none'
         }, $ROST->get ($FJID2, bare_jid ($FJID1)),
         3, "2nd roster first set"
      );

      $ROST->set ($FJID1, { jid => 'test@bar.org', name => 'NOT ME', groups => [ 'Z' ] });
   };

   pred_decl 'updated_items', sub {
      pred ('got_items')
      && $roster1->{'test@bar.org'}->{name} eq 'NOT ME'
      && $roster1->{'test@bar.org'}->{groups}->[0] eq 'Z'
   };
   pred_action updated_items => sub {
      _check_item ({
            jid => bare_jid ($FJID2), name => 'MR.2', groups => [ 'A', 'B' ],
            ask => undef, subscription => 'none'
         }, $ROST->get ($FJID1, bare_jid ($FJID2)),
         4, "1st roster first set still ok"
      );

      _check_item ({
            jid => 'test@bar.org', name => 'NOT ME', groups => [ 'Z' ],
            ask => undef, subscription => 'none'
         }, $ROST->get ($FJID1, 'test@bar.org'),
         5, "1st roster second set modified"
      );

      clean (sub {
         $IM->get_connection ($FJID1)->disconnect ("done");
         $IM->get_connection ($FJID2)->disconnect ("done");
         pred_check $ctx;
      });
   };

   pred_decl 'cleanup', sub {
      pred ('updated_items')
      && $ROST->item_jids ($FJID1) == 0
      && $ROST->item_jids ($FJID2) == 0
      && not (defined $roster1)
      && not (defined $roster2)
   };
   pred_action cleanup => sub {
      print "ok 6 - first roster empty\n";
      print "ok 7 - second roster empty\n";
      print "ok 8 - cleanup okay\n";
      $CV->send;
   };
};


AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $rost) = @_;

   pred_set ($ctx, 'start');

}, 'AnyEvent::XMPP::Ext::Roster', sub {
   my ($im, $cv, $rost) = @_;

   $IM   = $im;
   $ROST = $rost;
   $CV   = $cv;

   $rost->reg_cb (
      fetched => sub {
         my ($rost, $jid, $roster) = @_;

         $fetched{$jid} = 1;
         pred_check ($ctx);
      },
      change => sub {
         my ($rost, $jid) = @_;

         if (cmp_jid ($jid, $FJID1)) {
            $roster1 = $rost->get ($FJID1);
         } else {
            $roster2 = $rost->get ($FJID2);
         }

         pred_check ($ctx);
      },
      gone => sub {
         my ($rost, $jid) = @_;

         if (cmp_jid ($jid, $FJID1)) {
            undef $roster1;
         } else {
            undef $roster2;
         }

         pred_check ($ctx);
      }
   );

   $rost->auto_fetch;
});

undef $tout;

# print JSON->new->convert_blessed->pretty->encode ($pres_ext->{p}) . "\n";
