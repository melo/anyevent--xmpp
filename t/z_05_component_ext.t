#!perl
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::Stream::Component;
use AnyEvent::XMPP::Util qw/new_message/;

AnyEvent::XMPP::Test::check ('client');
AnyEvent::XMPP::Test::check ('component');

my $cv = AnyEvent->condvar;

my $comp =
   AnyEvent::XMPP::Stream::Component->new (
      domain => $SERVICE, secret => $SECRET
   );

my $cl = AnyEvent::XMPP::Stream::Client->new (
   jid      => $JID1,
   password => $PASS,
);

my $disco = $comp->add_ext ('Disco');
$disco->set_identity ('component', 'generic', "AnyEvent::XMPP Test Component");
$disco->unset_identity ('client');

$comp->add_ext ('LangExtract');

my $disco_cl = $cl->add_ext ('Disco');

sub end {
   $cl->send_end;
   $comp->send_end;
}

my $cnt = 2;

push @DEF_HANDLERS, (
   test_end => sub { if ($_[1] eq 'end') { $cv->send if --$cnt <= 0 } },
   test_end => sub { unless ($_[1] eq 'end') { $cv->send } }
);

$cl->reg_cb (
   stream_ready => sub {
      my ($cl) = @_;
      $disco_cl->request_info ($cl->jid, $SERVICE, undef, sub {
         my ($disco_cl, $info, $error) = @_;
         if ($error) {
            print "# disco error: " . $error->string . "\n";
            $cv->send;
            return;
         }

         print ((($info->identities ())[0]->{category} eq 'component'
                  ? "" : "not ") . "ok 1 - got disco result from component\n");

         $disco->request_info ($SERVICE, $cl->jid, undef, sub {
            my ($disco_cl, $info, $error) = @_;

            if ($error) {
               print "# comp disco error: " . $error->string . "\n";
               $cv->send;
               return;
            }

            print ((($info->identities ())[0]->{category} eq 'client'
                     ? "" : "not ") . "ok 2 - got disco result from client\n");

            $cl->send (new_message (chat => "Hi there!", to => $SERVICE));
         });
      });
   },
   @DEF_HANDLERS,
);

$comp->reg_cb (
   stream_ready => sub {
      $cl->connect;
   },
   recv_message => sub {
      my ($comp, $node) = @_;

      if ($node->meta->{body} =~ /there!/) {
         print "ok 3 - component received message from client\n";

         end;
      }
   },
   @DEF_HANDLERS,
);

$comp->connect ($HOST, $PORT);

print "1..3\n";

$cv->recv;
