package AnyEvent::XMPP::IM;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/stringprep_jid/;
use AnyEvent::XMPP::Connection;
use base qw/Object::Event::Methods/;

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

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { };
   bless $self, $class;

   return $self
}

sub add_account {
   my ($self, $jid, $password, %args) = @_;

   $self->{accs}->{stringprep_jid $jid} = {
      jid      => $jid,
      password => $password,
      %args
   };
}

sub spawn_connection {
   my ($self, $jid) = @_;

   my $conhdl = $self->{conns}->{$jid} = {
      con => AnyEvent::XMPP::Connection->new (%{$self->{accs}->{$jid}}),
      timeout => $self->{initial_reconnect_interval},
   };

   $conhdl->{regid} = $conhdl->{con}->reg_cb (
      stream_ready => sub {
         $conhdl->{timeout} = $self->{initial_reconnect_interval};
      },
      disconnected => sub {
         my ($con, $h, $p, $reason) = @_;

         $conhdl->{timeout} *= 2;
      },
   );
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

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
