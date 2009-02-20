package AnyEvent::XMPP::Component;
use strict;
use AnyEvent::XMPP::Connection;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;

use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::Component - "XML" stream that implements the XEP-0114

=head1 SYNOPSIS

   use AnyEvent::XMPP::Component;

   my $con = AnyEvent::XMPP::Component->new (
                domain => 'chat.jabber.org'
                host   => 'jabber.org',
                port   => 5347,
                secret => 'insecurepasswordforthehackers'
             );
   $con->reg_cb (stream_ready => sub { ... });
   $con->connect;

=head1 DESCRIPTION

This module represents a XMPP connection to a server that authenticates as
component.

This module is a subclass of C<AnyEvent::XMPP::Connection> and inherits all methods.
For example C<reg_cb> and the stanza sending routines.

For additional events that can be registered to look below in the EVENTS section.

Please note that for component several functionality in L<AnyEvent::XMPP::Connection>
might have no effect or not the desired effect. Basically you should
use the L<AnyEvent::XMPP::Component> as component and only handle events
the handle with incoming data. And only use functions that send stanzas.

No effect has the event C<stream_pre_authentication> and the C<authenticate>
method of L<AnyEvent::XMPP::Connection>, because those handle the usual SASL or iq-auth
authentication. "Jabber" components have a completly different authentication
mechanism.

Also note that the support for some XEPs in L<AnyEvent::XMPP::Ext> is just thought
for client side usage, if you miss any functionaly don't hesitate to ask the
author or send him a patch! (See L<AnyEvent::XMPP> for contact information).

=head1 METHODS

=over 4

=item B<new (%args)>

This is the constructor. It takes the same arguments as
the constructor of L<AnyEvent::XMPP::Connection> along with a
few others:

B<NOTE>: Please note that some arguments that L<AnyEvent::XMPP::Connection>
usually takes have no effect when using this class. (That would be
the 'username', 'password', 'resource' and 'jid' arguments for example.)

=over 4

=item secret => $secret

C<$secret> is the secret that will be used for authentication with the server.

=back

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;

   my $self = $class->SUPER::new (@_);

   my $con = $self->{con} = AnyEvent::XMPP::Connection->new (
      host => $self->{host} || $self->{server},
      port => $self->{port} || 5347,
      default_stream_namespace => 'component',
      %{$self->{connection_args} || {}},
      username => 'test',
      domain => $self->{host} || $self->{server},
   );

   $con->reg_cb (
      [stream_start => -1] => sub {
         my ($con, $node) = @_;
         $con->current->stop;

         my $secret = $con->{parser}->{parser}->xml_escape ($self->{secret});

         $con->write_data ($con->{writer}->component_handshake ($con->{stream_id}, $secret));
      },
      [handle_stanza => 1] => sub {
         my ($con, $stanza) = @_;

         # intercept _all_ stanzas
         $con->current->stop;

         if ($self->{authenticated}) {
            $self->recv ($stanza);
         } else {
            if ($stanza->node->eq (component => 'handshake')) {
               $self->{authenticated} = 1;
               $self->stream_ready;
            }
         }
      },
      connected => sub {
         my ($con, @args) = @_;
         $self->connected (@args);
      },
      error => sub {
         my ($con, @args) = @_;
         $self->error (@args);
      },
      disconnected => sub {
         my ($con, @args) = @_;
         $self->disconnected (@args);
      }
   );

   $self->reg_cb (
      ext_after_send => sub {
         my ($self, $stanza) = @_;
         $self->{con}->send ($stanza);
      }
   );

   $self
}

sub connect {
   my ($self) = @_;
   $self->{con}->connect;
}

=item $comp->send ($stanza)

Sends an L<AnyEvent::XMPP::Stanza> to the server.

=back

=head1 EVENTS

These events can be registered on with C<reg_cb>:

=over 4

=item stream_ready

This event indicates that the component has connected successfully
and can now be used to transmit stanzas.

=cut

sub stream_ready { }

=item send => $stanza

Emitted when a stanza is about to be sent to the server.
Stopping the event will result in the stanza not being sent.

=item recv => $stanza

Emitted when a stanza has been received from the server.

=item connected => ...

TODO

=item error => ...

TODO

=item disconnected => ...

TODO

=cut

sub connected    { }
sub error        { }
sub disconnected { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP::Component
