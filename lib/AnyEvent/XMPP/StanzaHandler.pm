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

   __PACKAGE__->inherit_event_methods_from (qw/
      AnyEvent::XMPP::Stream
      AnyEvent::XMPP::StanzaHandler
   /);

   sub new {
      my $this  = shift;
      my $class = ref($this) || $this;
      my $self = $class->AnyEvent::XMPP::Stream::new (@_);

      AnyEvent::XMPP::StanzaHandler::init ($self);

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

=head1 METHODS

=over 4

=item B<new (%args)>

=cut

sub init {
   my ($self) = @_;

   $self->reg_cb (
      send => -100 => sub {
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
      },
      recv => sub {
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
      },
      ext_after_recv_iq => sub {
         my ($delivery, $node) = @_;

         $delivery->send (new_reply (
            $node,
            [ $node->nodes, new_error ($node, 'service-unavailable') ],
            type => 'error'
         ));
      }
   );
}

=back

=cut

__PACKAGE__->hand_event_methods_down (qw/
   recv_presence recv_message recv_iq recv_iq_reply
   send_presence send_message send_iq send_iq_reply
/);

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
