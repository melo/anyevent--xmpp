package AnyEvent::XMPP::Stream::Component;
use strict;
use AnyEvent::XMPP::IQTracker;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/xml_escape stringprep_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use Digest::SHA1 qw/sha1_hex/;
use Encode;

use base qw/
   AnyEvent::XMPP::Stream
   AnyEvent::XMPP::StanzaHandler
   AnyEvent::XMPP::Extendable
/;

__PACKAGE__->inherit_event_methods_from (qw/
   AnyEvent::XMPP::Stream
   AnyEvent::XMPP::StanzaHandler
   AnyEvent::XMPP::Extendable
/);

__PACKAGE__->hand_event_methods_down_from (qw/
   AnyEvent::XMPP::Stream
   AnyEvent::XMPP::StanzaHandler
   AnyEvent::XMPP::Extendable
/);

=head1 NAME

AnyEvent::XMPP::Stream::Component - "XML" stream that implements the XEP-0114

=head1 SYNOPSIS

   use AnyEvent::XMPP::Stream::Component;

   my $comp = AnyEvent::XMPP::Stream::Component->new (
                 domain => 'chat.jabber.org'
                 secret => 'insecurepasswordforthehackers'
              );

   $comp->reg_cb (
      stream_ready => sub { ... },
      disconnected => sub { ... },
      error        => sub { ... $comp->stop_event ... },
   );

   $comp->connect ('jabber.org', 5554);

=head1 DESCRIPTION

This module represents a XMPP connection to a server that authenticates as
component.

This module is a subclass of C<AnyEvent::XMPP::Stream> and inherits all methods
and events. For example C<reg_cb> and the stanza sending routines.

For additional events that can be registered to look below in the EVENTS section.

This component implements the L<AnyEvent::XMPP::Delivery> interface, along with
the L<AnyEvent::XMPP::StanzaHandler> and L<AnyEvent::XMPP::Extendable>
interfaces. This means it's ready to be extended by from L<AnyEvent::XMPP::Ext>
derived extensions. B<But> please note that B<not all> extensions are usable by
components as they usually implement client side semantics. So please look into
the extension's code before you use them and find out if it does what you want. 
For example the L<AnyEvent::XMPP::Ext::Disco> extension should be usable
without problems in components, but the L<AnyEvent::XMPP::Ext::Presence>
extension is probably not very useful.

If you miss any functionality or find a bug: Don't hesitate to ask the author
and/or send him a patch! (See L<AnyEvent::XMPP> for contact information).

=head1 METHODS

All methods that are available for L<AnyEvent::XMPP::Stream> are also available
for this. Especially C<connect> and C<send> are the most interesting methods
for you.

=over 4

=item my $comp = AnyEvent::XMPP::Stream::Component->new (%args)

This is the constructor. It takes the same arguments and provides the same
guarantees as the constructor of L<AnyEvent::XMPP::Stream> along with a few
others:

=over 4

=item domain => $domain

The domain or service name of the component itself.

=item secret => $secret

C<$secret> is the secret that will be used for authentication with the server.

=item disable_iq_tracker => $bool

By default this component will use L<AnyEvent::XMPP::IQTracker> to track
outgoing IQ requests for you. If you don't want that and want your own IQ
tracking, just pass a true value as C<$bool> to C<disable_iq_tracker>.

=item default_iq_timeout => $seconds

This will set the default IQ timeout for IQs that are sent
over this connection. If this argument is not given the default for C<$seconds>
will be as specified in the L<AnyEvent::XMPP::IQTracker> module.

B<NOTE>: Will only be effective if you didn't C<disable_iq_tracker>

=back

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = $class->SUPER::new (
      default_stream_namespace => 'component',
      @_
   );

   $self->{jid} = $self->{domain};

   unless ($self->{disable_tracker}) {
      $self->{tracker} =
         AnyEvent::XMPP::IQTracker->new (
            (defined $self->{default_iq_timeout}
               ? (default_iq_timeout => $self->{default_iq_timeout})
               : ()));

      $self->reg_cb (
         send => sub {
            my ($self, $node) = @_;
            $self->{tracker}->register ($node);
         },
         recv => sub {
            my ($self, $node) = @_;
            $self->{tracker}->handle_stanza ($node);
         },
      );
   }

   AnyEvent::XMPP::StanzaHandler::init ($self);

   $self->reg_cb (
      send => -400 => sub {
         my ($self, $node) = @_;

         return if $node->eq (stream => 'stream');

         unless (defined $node->attr ('from')) {
            $node->attr (from => $self->jid);
         }
      }
   );

   $self
}

sub connected {
   my $self = shift;
   $self->send_header (undef, to => $self->{domain});
};

sub stream_start {
   my ($self, $node) = @_;
   my $id = $node->attr ('id');

   my $handshake_secret =
      lc sha1_hex ($id . encode ('utf-8', xml_escape ($self->{secret})));

   $self->send (simxml (
      defns => 'stanza', node => {
         name => 'handshake',
         childs => [ $handshake_secret ]
      }
   ));
}

=item $comp->jid

Returns the component's JID. (This is basically the value you passed as
C<domain> to the constructor.

=cut

sub jid {
   my ($self) = @_;
   $self->{jid}
}

__PACKAGE__->hand_event_methods_down (qw/recv/);
sub recv {
   my ($self, $node) = @_;

   unless ($self->{authenticated}) {
      $self->stop_event;

      if ($node->eq (stanza => 'handshake')) {
         $self->{authenticated} = 1;
         $self->stream_ready;
      }
   }

   if (defined $self->{jid}) {
      $node->meta->{dest} = stringprep_jid $self->{jid};
   }
}

=back

=head1 EVENTS

All events that are emitted by L<AnyEvent::XMPP::Stream> are also
emitted by this class.

These addition events can be registered on with C<reg_cb>:

=over 4

=item stream_ready

This event indicates that the component has connected successfully
and can now be used to transmit stanzas.

=cut

__PACKAGE__->hand_event_methods_down (qw/stream_ready/);
sub stream_ready {
   my ($self) = @_;

   $self->source_available (stringprep_jid $self->{jid});
}

__PACKAGE__->hand_event_methods_down (qw/disconnected/);
sub disconnected {
   my ($self) = @_;

   $self->source_unavailable (stringprep_jid $self->{jid});
}

__PACKAGE__->hand_event_methods_down (qw/source_available/);
sub source_available {
}

__PACKAGE__->hand_event_methods_down (qw/source_unavailable/);
sub source_unavailable {
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007-2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP::Component
