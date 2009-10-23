package AnyEvent::XMPP::StanzaHandler;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/new_error new_reply/;
use AnyEvent::XMPP::Node qw/simxml/;
use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::StanzaHandler - A stanza handler super class for clients

=head1 SYNOPSIS

   package MyCon;
   use base qw/AnyEvent::XMPP::Stream AnyEvent::XMPP::StanzaHandler/;

   sub new {
      my $this  = shift;
      my $class = ref($this) || $this;
      my $self = $class->AnyEvent::XMPP::Stream::new (@_);

      $self
   }

   package main;
   my $con = MyCon->new (...);

   $con->reg_cb (
      send_message    => sub { ... },
      recv_message    => sub { ... },

      recv_iq         => sub {
         my ($con, $iq_type, $node) = @_;

         if ($node ... is handled by me ...) {
            $$rhandled = 1;
            $con->stop_event;
         }
      },
   );
   ...

=head1 DESCRIPTION

This class provides some generic mechanism to attach to a
L<AnyEvent::XMPP::Delivery> object and extend it with some new events for the
three major stanza types: message, presence and IQ (requests).

Along with that it will provide some means to say that a stanza was 'handled'
and in some cases it will provide default behavior if a stanza was not handled.

=cut

sub send : event_cb(-100) {
   my ($delivery, $node) = @_;
   my $t = $node->meta->{type};

   if ($t eq 'presence') {
      $delivery->event (send_presence => $node);

   } elsif ($t eq 'message') {
      $delivery->event (send_message => $node);

   } elsif ($t eq 'iq') {
      my $iq_t = $node->attr ('type');

      if ($iq_t eq 'set' || $iq_t eq 'get') {
         $delivery->event (send_iq => $node);

      } else {
         $delivery->event (send_iq_reply => $node);
      }
   }
}

sub recv : event_cb(-100) {
   my ($delivery, $node) = @_;
   my $t = $node->meta->{type};

   if ($t eq 'presence') {
      $delivery->event (recv_presence => $node);

   } elsif ($t eq 'message') {
      $delivery->event (recv_message => $node);

   } elsif ($t eq 'iq') {
      my $iq_t = $node->attr ('type');

      if ($iq_t eq 'set' || $iq_t eq 'get') {
         $delivery->event (recv_iq => $node);

      } else {
         $delivery->event (recv_iq_reply => $node);
      }
   }
}

sub recv_iq : event_cb(ext_after) {
   my ($delivery, $node) = @_;

   my $errnode = new_reply (
      $node,
      create => [
         $node->nodes,
         new_error ($node, 'service-unavailable')
      ],
      type => 'error'
   );

   $errnode->refresh_meta;

   $delivery->send ($errnode);
}

=head1 EVENTS

=over 4

=item recv_iq => $node

=item recv_iq_reply => $node

=item recv_presence => $node

=item recv_message => $node

=item send_iq => $node

=item send_iq_reply => $node

=item send_presence => $node

=item send_message => $node

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
