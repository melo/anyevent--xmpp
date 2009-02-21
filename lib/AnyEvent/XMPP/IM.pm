package AnyEvent::XMPP::IM;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/stringprep_jid/;
use AnyEvent::XMPP::Connection;
use AnyEvent::XMPP::Stanza;
use base qw/Object::Event::Methods/;

our $DEBUG = 1;

=head1 NAME

AnyEvent::XMPP::IM - An instant messaging connection

=head1 SYNOPSIS

=head2 DESCRIPTION

This class implements functionality for RFC 3921 by using
L<AnyEvent::XMPP::Connection> and adding some components.

It also poses as connection manager, reconnecting lost
connections and managing multiple accounts.

=head2 METHODS

=over 4

=item new (%args)

This is the constructor for L<AnyEvent::XMPP::IM> and it takes these
arguments in the argument hash C<%args>:

=over 4

=item initial_reconnect_interval => $seconds

TODO

Default: 5 seconds

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = {
      initial_reconnect_interval => 5,
      @_,
   };
   bless $self, $class;

   return $self
}

sub send_session_iq {
   my ($self, $con, $jid) = @_;

   $con->send (new_iq (set => create => {
      defns => 'session',
      node => { name => 'session' }
   }, cb => sub {
      my ($stanza, $error) = @_;

      if ($stanza) {
         $self->connected ($jid, $con->{peer_host}, $con->{peer_port});

      } else {
         $self->error ($jid, $error);
      }
   }));
}

sub init_connection {
   my ($self, $con, $jid) = @_;

   if ($con->features->session) {
      $self->send_session_iq ($con, $jid);

   } else {
      $self->connected ($jid, $con->{peer_host}, $con->{peer_port});
   }
}

sub send {
   my ($self, $stanza) = @_;
}

sub add_account {
   my ($self, $jid, $password, %args) = @_;

   $self->{accs}->{stringprep_jid $jid} = {
      jid      => $jid,
      password => $password,
      %args
   };
}

sub set_accounts {
   my ($self, %accs) = @_;

   $self->{accs} = {};
   $self->update_connections;

   for my $jid (keys %accs) {
      $self->add_account ($jid, $accs{$jid});
   }
}

sub spawn_connection {
   my ($self, $jid) = @_;

   my $conhdl = $self->{conns}->{$jid} = {
      con => AnyEvent::XMPP::Connection->new (%{$self->{accs}->{$jid}}),
      timeout => $self->{initial_reconnect_interval},
   };

   $conhdl->{regid} = $conhdl->{con}->reg_cb (
      stream_ready => sub {
         my ($con) = @_;

         $conhdl->{timeout} = $self->{initial_reconnect_interval};
         delete $conhdl->{timer};

         $self->init_connection ($con, $jid);
      },
      error => sub {
         my ($con, $error) = @_;

         $self->error ($jid, $error);
      },
      disconnected => sub {
         my ($con, $h, $p, $reason) = @_;

         $conhdl->{timeout} *= 2;
         $conhdl->{timer} =
            AnyEvent->timer (after => $conhdl->{timeout}, cb => sub {
               $conhdl->{con}->connect;
            });
            
         $self->disconnected ($jid, $h, $p, $reason, $conhdl->{timeout});
      },
   );

   $conhdl->{con}->connect;
}

sub remove_connection {
   my ($self, $jid) = @_;

   my $c = delete $self->{conns}->{$jid};
   $c->{con}->disconnect ('removed account');
   $c->{con}->unreg_cb ($c->{regid});
   delete $c->{con};
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

=back

=head1 EVENTS

These events are emitted by this object via the L<Object::Event::Methods> API:

=over 4

=item connected => $jid, $peer_host, $peer_port

This event is generated when the XMPP session for the account C<$jid>
was initiated and everything is ready to send IM stanzas (iq, presence, messages).

=cut

sub connected {
   my ($self, $jid, $ph, $pp) = @_;

   if ($DEBUG) {
      print "$jid: connected and session ready for $ph:$pp!\n";
   }
}

=item error => $jid, $error

This event is emitted when an error occured on the connection to the account C<$jid>.

=cut

sub error {
   my ($self, $jid, $error) = @_;

   if ($DEBUG) {
      print "$jid: ERROR: " . $error->string . "\n";
   }
}

=item disconnected => $jid, $peer_host, $peer_port, $reason, $reconnect_timeout

Connection to account with the JID C<$jid> was lost or couldn't be established
due to C<$reason>.  Next connection attempt will be done in
C<$reconnect_timeout> seconds.

=cut

sub disconnected {
   my ($self, $jid, $ph, $pp, $reason, $recontout) = @_;

   if ($DEBUG) {
      print "$jid: disconnected from $ph:$pp: $reason,"
           ." reconnecting in $recontout seconds\n";
   }
}

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
