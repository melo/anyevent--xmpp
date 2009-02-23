package AnyEvent::XMPP::Stream::Component;
use strict;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/simxml/;
use Digest::SHA1 qw/sha1_hex/;
use Encode;

use base qw/AnyEvent::XMPP::Stream/;

=head1 NAME

AnyEvent::XMPP::Stream::Component - "XML" stream that implements the XEP-0114

=head1 SYNOPSIS

   use AnyEvent::XMPP::Stream:;Component;

   my $comp = AnyEvent::XMPP::Stream::Component->new (
                 domain => 'chat.jabber.org'
                 secret => 'insecurepasswordforthehackers'
              );

   $comp->reg_cb (
      stream_ready => sub { ... },
      disconnected => sub { ... },
      error        => sub { ... $comp->current->stop ... },
   );

   $comp->connect ('jabber.org', 5554);

=head1 DESCRIPTION

This module represents a XMPP connection to a server that authenticates as
component.

This module is a subclass of C<AnyEvent::XMPP::Stream> and inherits all methods
and events. For example C<reg_cb> and the stanza sending routines.

For additional events that can be registered to look below in the EVENTS section.

Also note that the support for some XEPs in L<AnyEvent::XMPP::Ext> is just thought
for client side usage, if you miss any functionality don't hesitate to ask the
author or send him a patch! (See L<AnyEvent::XMPP> for contact information).

=head1 METHODS

All methods that are available for L<AnyEvent::XMPP::Stream> are also available
for this. Especially C<connect> and C<send> are the most interesting methods
for you.

=over 4

=item B<new (%args)>

This is the constructor. It takes the same arguments as
the constructor of L<AnyEvent::XMPP::Stream> along with a
few others:

=over 4

=item domain => $domain

The domain or service name of the component itself.

=item secret => $secret

C<$secret> is the secret that will be used for authentication with the server.

=back

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;

   my $self = $class->SUPER::new (
      default_stream_namespace => 'component',
      @_
   );

   $self->reg_cb (
      connected => sub {
         my $self = shift;
         $self->send_header (undef, undef, to => $self->{domain});
      },
      stream_start => sub {
         my ($self, $node) = @_;
         my $id = $node->attr ('id');

         my $secret =
            encode ('utf-8',
               $self->{parser}->{parser}->xml_escape ($self->{secret}));
         my $handshake_secret = lc sha1_hex ($id . $secret);

         my $stanza = AnyEvent::XMPP::Stanza->new (type => 'handshake');

         $stanza->add ({ node => $handshake_secret });

         $self->send ($stanza);
      },
      recv => sub {
         my ($self, $stanza) = @_;

         unless ($self->{authenticated}) {
            $self->current->stop;

            if ($stanza->node->eq (component => 'handshake')) {
               $self->{authenticated} = 1;
               $self->event ('stream_ready');
            }
         }
      },
      stream_ready => \&stream_ready,
   );

   $self
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

sub stream_ready { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007-2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP::Component
