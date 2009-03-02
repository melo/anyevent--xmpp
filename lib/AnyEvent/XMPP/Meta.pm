package AnyEvent::XMPP::Meta;
use strict;
no warnings;

=head1 NAME

AnyEvent::XMPP::Meta - Meta information for AnyEvent::XMPP::Node

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item B<new (%args)>

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { };
   bless $self, $class;

   $self->analyze (@_);

   return $self
}

sub analyze_features {
   my ($self, $node) = @_;

   my @mechs = $node->find_all ([qw/sasl mechanisms/], [qw/sasl mechanism/]);
   $self->{sasl_mechs} = [ map { $_->text } @mechs ]
      if @mechs;

   $self->{tls}     = 1 if $node->find_all ([qw/tls starttls/]);
   $self->{bind}    = 1 if $node->find_all ([qw/bind bind/]);
   $self->{session} = 1 if $node->find_all ([qw/session session/]);

   # and yet another weird thingie: in XEP-0077 it's said that
   # the register feature MAY be advertised by the server. That means:
   # it MAY not be advertised even if it is available... so we don't
   # care about it...
   # my @reg   = $node->find_all ([qw/register register/]);
}

sub analyze {
   my ($self, $node, $stream_ns) = @_;

   $self->{stream_ns} = $stream_ns;

   my $type;

   if ($node->eq ($stream_ns => 'presence')) {
      $type = 'presence';

   } elsif ($node->eq ($stream_ns => 'iq')) {
      $type = 'iq';

   } elsif ($node->eq ($stream_ns => 'message')) {
      $type = 'message';

   } elsif ($node->eq (stream => 'features')) {
      $type = 'features';

   } elsif ($node->eq (tls => 'proceed')) {
      $type = 'tls_proceed';

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

   } else {
      $type = 'unknown';
   }

   $self->{type} = $type;
}

sub add_sent_cb {
   my ($self, $cb) = @_;
   push @{$self->{sent_cb}}, $cb;
}

sub sent_cbs {
   my ($self) = @_;
   @{$self->{sent_cb} || []}
}

sub set_reply_cb {
   my ($self, $cb, $tout) = @_;
   $self->{reply_cb}      = $cb;
   $self->{reply_timeout} = $tout;
}

=back

=head1 PUBLIC KEYS

The meta information is basically a hash, containing some
defined keys:

=over 4

=item B<type>

This key contains the type of the stanza, which is one of these:

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

   unknown

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

