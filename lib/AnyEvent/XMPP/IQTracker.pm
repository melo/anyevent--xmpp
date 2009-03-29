package AnyEvent::XMPP::IQTracker;
use strict;
no warnings;

=head1 NAME

AnyEvent::XMPP::IQTracker - A request tracker for IQ stanzas.

=head1 SYNOPSIS

=head2 DESCRIPTION

This is a simple helper module for tracking IQ requests.
It's used by L<AnyEvent::XMPP::Stream>. And can also be used by
any other module that would like to track IQ requests.

=head2 METHODS

=over 4

=item B<new (%args)>

This is the tracker constructor, C<%args> has these special
keys:

=over 4

=item default_iq_timeout => $seconds

This is the default timeout for IQ requests. It's default
is 60 seconds. (If C<$seconds> is 0, timeouts are disabled).

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = {
      default_iq_timeout => 60,
      id                 => 0,
      @_
   };
   bless $self, $class;

   return $self
}

=item B<register ($node)>

This method will inspect the C<$node> and if required it will store tracking
information about the stanza.

=cut

sub register {
   my ($self, $node) = @_;

   my $meta = $node->meta;

   return unless $meta->{type} eq 'iq';
   return if not ($meta->{reply_cb}) || defined $node->attr ('id');

   my ($cb, $timeout) = ($meta->{reply_cb}, $meta->{reply_timeout});

   return unless $cb;

   if (not defined $timeout) {
      $timeout = $self->{default_iq_timeout};
   }

   my $id = ++$self->{id};
   $node->attr (id => $id);
   my $track = $self->{tracked}->{$id} = [ $cb ];

   if ($timeout) {
      $track->[1] =
         AnyEvent->timer (
            after => $timeout,
            cb => sub {
               delete $self->{tracked}->{$id};
               $cb->(undef, AnyEvent::XMPP::Error::IQ->new);
            }
         );
   }
}

=item B<handle_stanza ($node)>

This method inspects the incoming C<$node> if it is a reply
to some request which was C<register>ed before.

=cut

sub handle_stanza {
   my ($self, $node) = @_;

   return if $node->meta->{type} ne 'iq';
   return if $node->attr ('type') eq 'get' 
             || $node->attr ('type') eq 'set';

   my $track = delete $self->{tracked}->{$node->attr ('id')}
      or return;

   delete $track->[1];

   if ($node->attr ('type') eq 'result') {
      $track->[0]->($node);

   } elsif ($node->meta->{error}) {
      $track->[0]->(undef, $node->meta->{error});
   }
}

=item B<disconnect>

When the tracker isn't require anymore call this method to cleanup any
registered event callbacks, result callbacks and tracking information.

=cut

sub disconnect {
   my ($self) = @_;
   delete $self->{tracked};
}

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

