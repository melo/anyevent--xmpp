package AnyEvent::XMPP::StanzaHandler;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/new_error new_reply/;
use AnyEvent::XMPP::Node qw/simxml/;

=head1 NAME

AnyEvent::XMPP::StanzaHandler - A stanza handler for clients

=head1 SYNOPSIS

   use AnyEvent::XMPP::StanzaHandler;

   my $delivery = AnyEvent::XMPP::IM->new;
   my $hdlr = AnyEvent::XMPP:StanzaHandler->new (delivery => $delivery);

   $delivery->reg_cb (
      recv_message    => sub { ... },
      recv_presence   => sub { ... },
      recv_iq         => sub {
         my ($delivery, $iq_type, $node) = @_;

         if ($node ... is handled by me ...) {
            $$rhandled = 1;
            $delivery->stop_event;
         }
      },
   );

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

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{guard} = $self->{delivery}->reg_cb (
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
            [
               map { $_->add_decl_prefix ($_->namespace, ''); $_ } $node->nodes,
               new_error ($node, 'service-unavailable')
            ],
            type => 'error'
         ));
      }
   );

   return $self
}

=back

=head1 EVENTS

=over 4

=item recv_iq => $node

=item recv_iq_reply => $node

=item recv_presence => $node

=item recv_message => $node

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
