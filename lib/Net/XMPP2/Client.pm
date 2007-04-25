package Net::XMPP2::Client;
use strict;
use AnyEvent;
use Net::XMPP2::IM::Connection;
use Net::XMPP2::Util qw/stringprep_jid prep_bare_jid/;
use Net::XMPP2::Namespaces qw/xmpp_ns/;
use Net::XMPP2::Event;
use Net::XMPP2::IM::Account;

use XML::Twig;

sub _dumpxml {
   my $data = shift;
   my $t = XML::Twig->new;
   if ($t->safe_parse ("<deb>$data</deb>")) {
      $t->set_pretty_print ('indented');
      $t->print;
      print "\n";
   } else {
      print "[$data]\n";
   }
}

our @ISA = qw/Net::XMPP2::Event/;

=head1 NAME

Net::XMPP2::Client - A XMPP Client abstraction

=head1 SYNOPSIS

   use Net::XMPP2::Client;
   use AnyEvent;

   my $j = AnyEvent->condvar;

   my $cl = Net::XMPP2::Client->new;
   $cl->start;

   $j->wait;

=head1 DESCRIPTION

This module tries to implement a straight forward and easy to
use API to communicate with XMPP entities. L<Net::XMPP2::Client>
handles connections and timeouts and all such stuff for you.

For more flexibility please have a look at L<Net::XMPP2::Connection>
and L<Net::XMPP2::IM::Connection>, they allow you to control what
and how something is being sent more precisely.

=head1 METHODS

=head2 new (%args)

Following arguments can be passed in C<%args>:

=over 4

=back

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = { @_ };
   bless $self, $class;
   return $self;
}

=head2 add_account ($jid, $password, $host, $port)

This method adds a jabber account for connection with the JID C<$jid>
and the password C<$password>.

C<$host> and C<$port> are optional and can be undef. C<$host> overrides the
host to connect to.

Returns 1 on success and undef when the account already exists.

=cut

sub add_account {
   my ($self, $jid, $password, $host, $port) = @_;

   $jid = stringprep_jid $jid;
   my $bj = prep_bare_jid $jid;

   return if exists $self->{accounts}->{$bj};

   my $acc =
      $self->{accounts}->{$bj} =
         Net::XMPP2::IM::Account->new (
            jid      => $jid,
            password => $password,
            host     => $host,
            port     => $port,
         );

   $self->update_connections
      if $self->{started};

   $acc
}

=head2 start ()

This method initiates the connections to the XMPP servers.

=cut

sub start {
   my ($self) = @_;
   $self->{started} = 1;
   $self->update_connections;
}

sub update_connections {
   my ($self) = @_;

   for my $acc (values %{$self->{accounts}}) {
      unless ($acc->is_connected) {
         my $con = $acc->spawn_connection;

         $con->reg_cb (
            session_ready => sub {
               my ($con) = @_;
               $self->event (connected => $acc);
               warn "ADDED ACCOUNT $acc->{jid} [$con]\n";
               0 # do once
            },
            debug_recv      => sub { print "RRRRRRRRECVVVVVV:\n"; _dumpxml ($_[1]); 1 },
            debug_send      => sub { print "SSSSSSSSENDDDDDD:\n"; _dumpxml ($_[1]); 1 },
            message         => sub {
               my ($con, $msg) = @_;
               $self->event (message => $acc, $msg);
               1
            },
            roster_update => sub {
               my ($con, $roster, $contacts) = @_;
               $self->event (roster_update => $acc, $roster, $contacts);
               1
            },
            sasl_error => sub {
               my ($con, $error) = @_;
               $self->event (sasl_error => $acc, $error);
               1
            },
            presence_update => sub {
               my ($con, $roster, $contact, $old, $new) = @_;
               $self->event (presence_update => $acc, $roster, $contact, $old, $new);
               1
            }
         );

         $con->connect
            or die "Couldn't connect to ".($acc->jid).": $!";
         $con->init
      }
   }
}

=item send_message ($msg, $dest_jid, $src)

Sends a message to the destination C<$dest_jid>.
C<$msg> can either be a string or a L<Net::XMPP2::IM::Message> object.
If C<$msg> is such an object C<$dest_jid> is optional, and will, when
passed, override the destination of the message.

C<$src> is optional. It specifies which account to use
to send the message. If it is not passed L<Net::XMPP2::Client> will try
to find an account itself. First it will look through all rosters
to find C<$dest_jid> and if none found it will pick any of the accounts that
are connected.

C<$src> can either be a JID or a L<Net::XMPP2::IM::Account> object as returned
by C<add_account> and C<get_account>.

=cut

sub send_message {
   my ($self, $msg, $dest_jid, $src) = @_;

   unless (ref $msg) {
      $msg = Net::XMPP2::IM::Message->new (body => $msg);
   }

   if (defined $dest_jid) {
      my $jid = stringprep_jid $dest_jid
         or die "send_message: \$dest_jid is not a proper JID";
      $msg->to ($jid);
   }

   my $srcacc;
   if (ref $src) {
      $srcacc = $src;
   } elsif (defined $src) {
      $srcacc = $self->get_account ($src)
   } else {
      $srcacc = $self->find_account_for_dest_jid ($dest_jid);
   }

   unless ($srcacc && $srcacc->is_connected) {
      die "send_message: Couldn't get connected account for sending"
   }

   $msg->send ($srcacc->connection)
}

=item get_account ($jid)

Returns the L<Net::XMPP2::IM::Account> account object for the JID C<$jid>
if there is any such account added. (returns undef otherwise).

=cut

sub get_account {
   my ($self, $jid) = @_;
   $self->{accounts}->{prep_bare_jid $jid}
}

sub find_account_for_dest_jid {
   my ($self, $jid) = @_;

   my $any_acc;
   for my $acc (values %{$self->{accounts}}) {
      next unless $acc->is_connected;

      # take "first" active account
      $any_acc = $acc unless defined $any_acc;

      my $roster = $acc->connection ()->get_roster;
      if (my $c = $roster->get_contact ($jid)) {
         return $acc;
      }
   }

   $any_acc
}

=head1 EVENTS

These events can be registered on with C<reg_cb>:

In the following event descriptions the argument C<$account>
is always a L<Net::XMMP2::IM::Account> object.

=over 4

=item connected => $account

This event is sent when the C<$account> was successfully connected.

=item connect_error => $account

This event is emitted when an error occured in the connection process for the
account C<$account>.

=item error => $account

This event is emitted when any error occured while communicating
over the connection to the C<$account> - after a connection was established.

=item presence_update => $account, $roster, $contact, $old_presence, $new_presence

This event is emitted when a presence update was received on the C<$account>.
For a description of the other argument please look at the documentation
of the C<presence_update> event in L<Net::XMPP2::IM::Connection>.

=item message => $account, $msg

This event is emited when a message has been received on the C<$account>.
C<$msg> is a L<Net::XMPP2::IM::Message> object.

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Net::XMPP2::Client