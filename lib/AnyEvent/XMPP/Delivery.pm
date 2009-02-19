package AnyEvent::XMPP::Delivery;
use strict;
no warnings;

=head1 NAME

AnyEvent::XMPP::Delivery - A stanza delivery interface

=head2 DESCRIPTION

This is just the definition of an interface for sending and receiving stanzas.
Following modules implement it:

   AnyEvent::XMPP::Connection

This module merely defines a convention which methods and
events are provided.

=head2 METHODS

Every 'delivery' object must implement following methods:

=over 4

=item B<send ($stanza)>

C<$stanza> must be an object of the class L<AnyEvent::XMPP::Stanza>
or a subclass of it.

This method should deliver the C<$stanza> as if it was 'sent'.  For
L<AnyEvent::XMPP::Connection> this means that the C<$stanza> will be sent to
the server.

Other delivery objects might have other semantics w.r.t. sending a stanza.

=item B<generate_id>

Every delivery object has to provide a way to generate unique IDs
for use as the 'id' attribute of XMPP stanzas.

This method should return a unique ID as string.

=back

=head2 EVENTS

Every 'delivery' object must provide these events:

=over 4

=item recv => $stanza

This event should be generated whenever a stanza for
further processing was received. Interested parties should
register to this event and stop it if the stanza was handled
and shouldn't be processed further.

If someone is just interested in parts of a stanza he should
register to the C<before_recv> event and NOT stop the stanza.

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

