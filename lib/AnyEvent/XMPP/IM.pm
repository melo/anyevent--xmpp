package AnyEvent::XMPP::IM;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/prep_bare_jid new_iq/;
use AnyEvent::XMPP::Stream::Client;
use AnyEvent::XMPP::Node qw/simxml/;
use base qw/Object::Event AnyEvent::XMPP::StanzaHandler AnyEvent::XMPP::Extendable/;

__PACKAGE__->inherit_event_methods_from (qw/
   AnyEvent::XMPP::StanzaHandler
   AnyEvent::XMPP::Extendable
/);

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
   my $self  = $class->SUPER::new (
      initial_reconnect_interval => 5,
      @_,
      enable_methods => 1,
   );

   AnyEvent::XMPP::StanzaHandler::init ($self);
   AnyEvent::XMPP::Extendable::init ($self);

   $self->reg_cb (
      ext_after_error => sub {
         my ($self, $jid, $error) = @_;

         warn "unhandled error in AnyEvent::XMPP::IM: " . $error->string . "."
              ." Please read the documentation of the 'error' event, to inhibit this"
              ." warning!\n";
      },
      ext_after_initial_presence => sub {
         my ($self, $jid) = @_;
         $self->send (simxml (node =>
            { name => 'presence', attrs => [ from => $jid ] }
         ));
      }
   );

   return $self
}

sub finish_session {
   my ($self, $con) = @_;
   $con->{_im_session_ready} = 1;
   $self->initial_presence ($con->jid);
   $self->connected ($con->jid, $con->{peer_host}, $con->{peer_port});
}

sub init_connection {
   my ($self, $con) = @_;

   if ($con->features->meta->{session}) {
      $con->send (new_iq (set => create => {
         node => { dns => 'session', name => 'session' }
      }, cb => sub {
         my ($node, $error) = @_;

         if ($node) {
            $self->finish_session ($con);

         } else {
            $self->error ($con->jid, $error);
         }
      }));

   } else {
      $self->finish_session ($con);
   }
}

sub send {
   my ($self, $node) = @_;

   my $src_jid = $node->meta->{src};
   $src_jid = $node->attr ('from') unless defined $src_jid;
   unless (defined $src_jid) {
      my ($any) = (values %{$self->{conns}});
      $src_jid = $any->{con}->jid if $any
   }

   my $con = $self->get_connection ($src_jid);
   unless ($con) {
      warn "No connection to send message from '$src_jid':\n"
           . $node->as_string (1) . "\n";
      return;
   }

   $con->send ($node);
}

sub recv {
   my ($self, $node) = @_;
}

sub add_account {
   my ($self, $jid, $password, %args) = @_;

   $self->{accs}->{prep_bare_jid $jid} = {
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

sub _install_retry {
   my ($conhdl) = @_;

   $conhdl->{timeout} *= 2;
   $conhdl->{timer} =
      AnyEvent->timer (after => $conhdl->{timeout}, cb => sub {
         $conhdl->{con}->connect;
      });
}

sub spawn_connection {
   my ($self, $jid) = @_;

   $jid = prep_bare_jid $jid;

   my $conhdl = $self->{conns}->{$jid} = {
      con => AnyEvent::XMPP::Stream::Client->new (%{$self->{accs}->{$jid}}),
      timeout => $self->{initial_reconnect_interval},
   };

   $conhdl->{regid} = $conhdl->{con}->reg_cb (
      stream_ready => sub {
         my ($con, $njid) = @_;

         $conhdl->{timeout} = $self->{initial_reconnect_interval};
         delete $conhdl->{timer};

         $self->init_connection ($con);
      },
      connect_error => sub {
         my ($con, $msg) = @_;
         
         _install_retry ($conhdl);
         
         $self->connect_error ($jid, $msg, $conhdl->{timeout});
      },
      error => sub {
         my ($con, $error) = @_;
         $self->error ($con->jid, $error);
         $con->stop_event;
      },
      recv => sub {
         my ($con, $node) = @_;
         $self->recv ($node); # $node is already tagged with 'from' attr.
      },
      disconnected => sub {
         my ($con, $h, $p, $reason) = @_;

         _install_retry ($conhdl);

         $self->disconnected ($jid, $h, $p, $reason, $conhdl->{timeout});
      },
   );

   $conhdl->{con}->connect;
}

sub remove_connection {
   my ($self, $jid) = @_;

   $jid = prep_bare_jid $jid;
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

sub get_connection {
   my ($self, $jid) = @_;
   my $c = $self->{conns}->{prep_bare_jid $jid}
      or return;
   $c = $c->{con};
   $c->is_ready 
      or return;
   $c->{_im_session_ready}
      or return;
   $c
}

=back

=head1 EVENTS

These events are emitted by this object via the L<Object::Event> API:

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

=item initial_presence => $jid

This event is emitted shortly before the C<connected> event and gives
the user the chance to specify his own initial presence. If the event
is not stopped via a C<stop_event> call, it will send out a default initial
presence.

=cut

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
