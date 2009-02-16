package AnyEvent::XMPP::Stanza;
use strict;
no warnings;

=head1 NAME

AnyEvent::XMPP::Stanza - XMPP Stanza base class

=head1 SYNOPSIS

=head2 DESCRIPTION

This class represents a generic XMPP stanza. There are 3 subclasses,
which are used to represent the 3 main stanza types of XMPP:

  AnyEvent::XMPP::Message
  AnyEvent::XMPP::IQ
  AnyEvent::XMPP::Presence

=head2 FUNCTIONS

=item B<analyze ($node, $stream_ns)>

This class function analyzes the L<AnyEvent::XMPP::Node>
and tries to figure out what stanza type C<$node> is of
and returns a wrapper object around it with the corresponding
type.

C<$stream_ns> is the 'XML' namespace of the stream.

=cut

sub analyze {
   my ($node, $stream_ns) = @_;

   my $type;
   my $obj;

   if (not defined $node) {
      $type = 'end'

   } elsif ($node->eq ($def_ns => 'presence')) {
      return AnyEvent::XMPP::Presence->new (node => $node, type => 'presence');

   } elsif ($node->eq ($def_ns => 'iq')) {
      return AnyEvent::XMPP::IQ->new (node => $node, type => 'iq');

   } elsif ($node->eq ($def_ns => 'message')) {
      return AnyEvent::XMPP::Message->new (node => $node, type => 'message');

   } elsif ($node->eq (stream => 'features')) {
      $type = 'features'

   } elsif ($node->eq (tls => 'proceed')) {
      $type = 'tls_proceed'

   } elsif ($node->eq (tls => 'failure')) {
      $type = 'tls_failure';

   } elsif ($node->eq (sasl => 'challenge')) {
      $type = 'sasl_challenge'

   } elsif ($node->eq (sasl => 'success')) {
      $type = 'sasl_success'

   } elsif ($node->eq (sasl => 'failure')) {
      $type = 'sasl_failure'

   } elsif ($node->eq (stream => 'error')) {
      $type = 'error'

   }

   AnyEvent::XMPP::Stanza->new (node => $node, type => $type);
}

=head2 METHODS

=over 4

=item B<new (%args)>

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

=item B<type>

This method returns the type of the stanza, which is
one of these:

   presence
   iq
   message

   features
   error

   tls_proceed
   tls_failure

   sasl_challenge
   sasl_success
   sasl_failure

=cut

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

package AnyEvent::XMPP::Message;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Stanza/;

package AnyEvent::XMPP::IQ;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Stanza/;

package AnyEvent::XMPP::Presence;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Stanza/;

1;

