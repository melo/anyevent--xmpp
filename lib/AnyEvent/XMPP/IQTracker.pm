package AnyEvent::XMPP::IQTracker;
use strict;
no warnings;

=head1 NAME

AnyEvent::XMPP::IQTracker - A request tracker for IQ stanzas.

=head1 SYNOPSIS

=head2 DESCRIPTION

This is a simple helper module for tracking IQ requests.
It requires an object which implements the L<AnyEvent::XMPP::Delivery>
API.

=head2 METHODS

=over 4

=item B<new (%args)>

This is the tracker constructor, C<%args> has these special
keys:

=over 4

=item delivery => $delivery

This is the delivery object, which is used to receive and
send stanzas. It must implement the L<AnyEvent::XMPP::Delivery> API.

=item default_iq_timeout => $seconds

This is the default timeout for IQ requests. It's default
is 60 seconds. (If C<$seconds> is 0, timeouts are disabled).

=item pre_auth => $bool

This is an internal flag. Which is mainly used to tell the tracker to register
to the C<handle_stanza> event instead to the C<recv> event of the C<$delivery>
object.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{default_iq_timeout} = 60;

   my $recv_ev = $self->{pre_auth} ? 'handle_stanza' : 'recv';

   $self->{regid} =
      $self->{delivery}->reg_cb (
         $recv_ev => sub {
            my ($del, $stanza) = @_;

            if ($stanza->is_reply && $self->{tracked}->{$stanza->id}) {
               $self->handle_reply ($stanza);
               $del->current->stop;
            }
         }
      );

   return $self
}

=item B<send ($stanza, $cb, $timeout)>

This method will assist you in sending the stanza.
C<$stanza> should be an IQ stanza. C<$timeout> is optional,
use 0 if you want to disable the timeout.

C<$cb> is the callback that will be invoked when a result,
and error or a timeout was received.

   $cb->($result_stanza, $error)

The first argument will be the result stanza if no error
was received. The second argument will be undefined if
the request was successful.

But if an error occurred the first argument will be undefined
and the second will contain an L<AnyEvent::XMPP::Error::IQ>
object, describing the problem.

Here is an example:

   use AnyEvent::XMPP::Stanza;

   # ...

   $tracker->send (
      new_iq ('set', undef, undef, create => {
         defns => 'disco_info',
         node => {
           name => 'query',
           attrs => [ node => 'test_node' ]
         }
      }),
      sub {
         my ($result, $error) = @_;

         if ($error) {
            warn "An error was received: " . $error->string . "\n";
            return;
         }

         # ... do something with $result ...
      }
   );

=cut

sub send {
   my ($self, $stanza, $cb, $timeout) = @_;

   if (not defined $timeout) {
      $timeout = $self->{default_iq_timeout};
   }

   $stanza->set_id ($self->{delivery}->generate_id);
   my $track = $self->{tracked}->{$stanza->id} = [ $cb ];

   if ($timeout) {
      $track->[1] =
         AnyEvent->timer (
            after => $self->{iq_timeout},
            cb => sub {
               delete $self->{tracked}->{$stanza->id};
               $cb->(undef, AnyEvent::XMPP::Error::IQ->new);
            }
         );
   }

   $self->{delivery}->send ($stanza);
}

sub handle_reply {
   my ($self, $stanza) = @_;

   my $track = delete $self->{tracked}->{$stanza->id}
      or return;

   delete $track->[1];

   if ($stanza->iq_type eq 'result') {
      $track->[0]->($stanza);

   } elsif ($stanza->iq_type eq 'error') {
      my $error = AnyEvent::XMPP::Error::IQ->new (stanza => $stanza);
      $track->[0]->(undef, $error);
   }
}

=item B<disconnect>

When the tracker isn't require anymore call this method to cleanup any
registered event callbacks, result callbacks and tracking information.

=cut

sub disconnect {
   my ($self) = @_;
   $self->{delivery}->unreg_cb ($self->{regid});
   delete $self->{tracked};
   delete $self->{delivery};
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

