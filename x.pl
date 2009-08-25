#!/usr/bin/env perl

use strict;
use warnings;
use Devel::TrackObjects qr/^.+/;
use Devel::TrackObjects '-verbose','track_object';
use lib '/Users/melo/work/projects/xmpp/anyevent-xmpp/lib';

use AnyEvent;
use AnyEvent::XMPP;
use AnyEvent::XMPP::IM::Connection;
use AnyEvent::XMPP::Util qw( dump_twig_xml );

use Devel::Peek;

my $reconnect_count = 90;
my $exit = AnyEvent->condvar;

print STDERR "My PID is   $$  \n\n";

xmpp_connect();

$exit->wait;
undef $exit;

Devel::TrackObjects->show_tracked;


sub xmpp_connect {
  my $xmpp = AnyEvent::XMPP::IM::Connection->new(
    jid      => 'test@domain',
    password => 'dontcare',
  
    host => '127.0.0.1',
    port => '11111',
  
    connect_timeout => 2,
  );
  
  $xmpp->reg_cb(
    session_ready => \&xmpp_session_ready,
    disconnect    => \&xmpp_disconnected,
  );
  
  print STDERR "[XMPP] start connect $reconnect_count for $xmpp...\n";
  $xmpp->connect;
  
  return;
}

sub xmpp_session_ready {
  print STDERR "[XMPP] session ready!\n";
}

sub xmpp_disconnected {
  print STDERR "[XMPP] failed connect!\n";
  
  unless ($reconnect_count--) {
    $exit->send;
    return;
  }
  
  my $t; $t = AnyEvent->timer( after => 1, cb => sub {
    xmpp_connect();
    undef $t;
  });
}

