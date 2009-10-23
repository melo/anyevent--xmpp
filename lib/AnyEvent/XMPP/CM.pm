package AnyEvent::XMPP::CM;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/prep_bare_jid new_iq new_presence stringprep_jid/;
use AnyEvent::XMPP::Stream::Client;
use AnyEvent::XMPP::Node qw/simxml/;
use base qw/Object::Event AnyEvent::XMPP::StanzaHandler AnyEvent::XMPP::Extendable/;

__PACKAGE__->inherit_event_methods_from (qw/
   AnyEvent::XMPP::StanzaHandler
   AnyEvent::XMPP::Extendable
/);

our $DEBUG = 0;

=head1 NAME

AnyEvent::XMPP::CM - An instant messaging connection manager

=head1 SYNOPSIS

=head2 DESCRIPTION

This class acts as highlevel XMPP client connection manager.
It poses as connection manager to multiple XMPP accounts and does things
such as reconnecting with exponential backoff.

It inherits the L<AnyEvent::XMPP::StanzaHandler> interface and interface, and
can be extended using the L<AnyEvent::XMPP::Extendable> interface.

=head2 METHODS

=over 4

=item my $cm = AnyEvent::XMPP::CM->new (%args)

This is the constructor for an L<AnyEvent::XMPP::CM> objects.

The objects created by this class also provide you with a C<heap> member that
stores a hash which lets you store some associated information.
(See also L<AnyEvent::XMPP::Stream> about this.)

It takes these arguments in the argument hash C<%args>:

=over 4

=item initial_reconnect_interval => $seconds

TODO

Default: 5 seconds

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (
      initial_reconnect_interval => 5,
      heap => { },
      @_,
      enable_methods => 1,
   );

   AnyEvent::XMPP::StanzaHandler::init ($self);

   $self->reg_cb (
      ext_after_error => sub {
         my ($self, $jid, $error) = @_;

         warn "unhandled error in AnyEvent::XMPP::CM: " . $error->string . "."
              ." Please read the documentation of the 'error' event, to inhibit this"
              ." warning!\n";
      }
   );

   return $self
}

=item $cm->send ($node)

This method will send the XMPP stanza C<$node>. The connection
that is used to send the message is determined by the meta value
C<src> (See also L<AnyEvent::XMPP::Meta>).

=cut

sub send {
   my ($self, $node) = @_;

   my $src_jid = $node->meta->{src};
   $src_jid = $node->attr ('from') unless defined $src_jid;
   unless (defined $src_jid) {
      my ($any) = (values %{$self->{conns}});
      $src_jid = $any->jid if $any
   }

   my $con = $self->get_connection ($src_jid);
   unless ($con) {
      warn "No connection to send message from '$src_jid':\n"
           . $node->as_string (1) . "\n";
      return;
   }

   $con->send ($node);
}

=item $cm->add_account ($jid, $pw, %args)

This method adds an account and will try to initiate a connection immediately.
C<$jid> is the JID of the account, C<$pw> is the password and C<%args> are
additional arguments to the L<AnyEvent::XMPP::Stream::Client> constructor.

=cut

sub add_account {
   my ($self, $jid, $password, %args) = @_;

   $self->{accs}->{prep_bare_jid $jid} = {
      jid      => $jid,
      password => $password,
      %args
   };

   $self->update_connections;
}

=item $cm->remove_account ($jid)

This method removes the account C<$jid> and it's connection
if it exists.

=cut

sub remove_account {
   my ($self, $jid) = @_;

   delete $self->{accs}->{prep_bare_jid $jid};
   $self->remove_connection ($jid);
}

=item $cm->set_accounts (%accs)

This method sets a bunch of accounts that should be connected.
The keys for the C<%accs> hash are the bare JIDs of the accounts.

The value should be an array reference to an array where the first element is
the password and the second element are additional arguments to the constructor
of L<AnyEvent::XMPP::Stream::Client> as hash reference.

If you pass nothing at all to this function all currently connected accounts
will be disconnected. Generally connections are not reconnected if their
configuration changes. You will have to do that yourself.

=cut

sub set_accounts {
   my ($self, %accs) = @_;

   $self->{accs} = {};

   for my $jid (keys %accs) {
      my ($pw, $args) = ref $accs{$jid} ? @{$accs{$jid}} : ($accs{$jid}, {});
      $self->add_account ($jid, $pw, %$args);
   }

   $self->update_connections;
}

sub _install_retry {
   my ($conhdl) = @_;

   $conhdl->{imhp}->{timeout} *= 2;
   $conhdl->{imhp}->{timer} =
      AnyEvent->timer (after => $conhdl->{imhp}->{timeout}, cb => sub {
         $conhdl->connect;
      });
}

sub spawn_connection {
   my ($self, $jid) = @_;

   $jid = prep_bare_jid $jid;

   my $conhdl = $self->{conns}->{$jid} =
      AnyEvent::XMPP::Stream::Client->new (%{$self->{accs}->{$jid}});
   $conhdl->{imhp}->{timeout} = $self->{initial_reconnect_interval};

   $conhdl->{imhp}->{regid} = $conhdl->reg_cb (
      stream_ready => sub {
         my ($con, $njid) = @_;

         $conhdl->{imhp}->{timeout} = $self->{initial_reconnect_interval};
         delete $conhdl->{imhp}->{timer};

         $self->connected ($con->jid, $con->{peer_host}, $con->{peer_port});
      },
      connect_error => sub {
         my ($con, $msg) = @_;

         _install_retry ($conhdl);

         $self->connect_error ($jid, $msg, $conhdl->{imhp}->{timeout});
      },
      error => sub {
         my ($con, $error) = @_;
         $self->error ($con->jid, $error);
         $con->stop_event;
      },
      recv => -1 => sub {
         my ($con, $node) = @_;
         $self->recv ($node); # $node is already tagged with 'from' attr.
         $con->stop_event;
      },
      disconnected => sub {
         my ($con, $h, $p, $reason) = @_;

         _install_retry ($conhdl);

         $self->disconnected ($jid, $h, $p, $reason, $conhdl->{imhp}->{timeout});
      },
      source_unavailable => sub {
         my ($con, $jid) = @_;
         $self->source_unavailable ($jid);
      }
   );

   $conhdl->connect;
}

=item $cm->remove_connection ($jid)

This method will forcefully remove the connection for the account C<$jid> and
reconnect it.

=cut

sub remove_connection {
   my ($self, $jid) = @_;

   $jid = prep_bare_jid $jid;
   my $c = delete $self->{conns}->{$jid};
   $c->disconnect ('removed account');
   $c->unreg_cb ($c->{imhp}->{regid});
   delete $c->{imhp};
}

sub update_connections {
   my ($self) = @_;

   for my $conjid (keys %{$self->{conns}}) {
      unless (grep { $conjid eq $_ } keys %{$self->{accs}}) {
         $self->remove_connection ($conjid);
      }
   }

   for (keys %{$self->{accs}}) {
      unless ($self->{conns}->{$_}) {
         $self->spawn_connection ($_);
      }
   }
}

=item my $con = $cm->get_connection ($jid)

Returns the L<AnyEvent::XMPP::Stream::Client> object
for the account C<$jid>.

Returns undef if no such connection exists.

=cut

sub get_connection {
   my ($self, $jid) = @_;
   my $c = $self->{conns}->{prep_bare_jid $jid}
      or return;
   $c->is_ready
      or return;
   $c
}

=back

=head1 EVENTS

These events are emitted by this object via the L<Object::Event> API:

=over 4

=item connected => $jid, $peer_host, $peer_port

This event is generated when the XMPP session for the account C<$jid>
was initiated and everything is ready to send CM stanzas (iq, presence, messages).

=cut

sub connected {
   my ($self, $jid, $ph, $pp) = @_;

   $self->source_available (stringprep_jid $jid);

   if ($DEBUG) {
      print "$jid: connected and session ready for $ph:$pp!\n";
   }
}

=item error => $jid, $error

This event is emitted when an error occurred on the connection to the account C<$jid>.

FIXME: Put error event doc from ::Stream here.

=cut

sub error {
   my ($self, $jid, $error) = @_;

   if ($DEBUG) {
      print "$jid: ERROR: " . $error->string . "\n";
   }
}

=item connect_error => $jid, $reason, $reconnect_timeout

This error is emitted when a problem occurred while the TCP connection
was being made. C<$jid> is the account, C<$reason> is the human readable error
message and C<$reconnect_timeout> contains the seconds to the next
retry.

=cut

sub connect_error {
   my ($self, $jid, $reason, $recon_tout) = @_;

   if ($DEBUG) {
      print "$jid: CONNECT ERROR: $reason, reconnect in $recon_tout seconds.\n";
   }
}

=item disconnected => $jid, $peer_host, $peer_port, $reason, $reconnect_timeout

Connection to account with the JID C<$jid> was lost or couldn't be established
due to C<$reason>.  Next connection attempt will be done in
C<$reconnect_timeout> seconds.

=cut

sub disconnected {
   my ($self, $jid, $ph, $pp, $reason, $recontout) = @_;

   if ($DEBUG && $reason !~ /expected stream end/) {
      print "$jid: disconnected from $ph:$pp: $reason,"
           ." reconnecting in $recontout seconds\n";
   }
}

sub source_available   { }
sub source_unavailable { }
sub recv { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
