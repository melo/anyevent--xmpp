package AnyEvent::XMPP::Error::Stream;
use AnyEvent::XMPP::Error;
use strict;
our @ISA = qw/AnyEvent::XMPP::Error/;

=head1 NAME

AnyEvent::XMPP::Error::Stream - XML Stream errors

Subclass of L<AnyEvent::XMPP::Error>

=cut

sub init {
   my ($self) = @_;
   my $node = $self->stanza->node;

   my @txt = $node->find_all ([qw/streams text/]);
   my $error;
   for my $er (
      qw/bad-format bad-namespace-prefix conflict connection-timeout host-gone
         host-unknown improper-addressing internal-server-error invalid-from
         invalid-id invalid-namespace invalid-xml not-authorized policy-violation
         remote-connection-failed resource-constraint restricted-xml
         see-other-host system-shutdown undefined-condition unsupported-stanza-type
         unsupported-version xml-not-well-formed/)
   {
      if (my (@n) = $node->find_all ([streams => $er])) {
         $error = $n[0]->name;
         last;
      }
   }

   unless ($error) {
      #d# warn "got undefined error stanza, trying to find any undefined error...";
      for my $n ($node->nodes) {
         if ($n->eq_ns ('streams')) {
            $error = $n->name;
         }
      }
   }

   $self->{error_name} = $error ne '' ? $error : 'unknown-error';
   $self->{error_text} = @txt ? $txt[0]->text : $node->text;
}

=head2 METHODS

=over 4

=item B<stanza ()>

Returns the L<AnyEvent::XMPP::Stanza> object for this stream error.

=cut

sub stanza {
   $_[0]->{stanza}
}

=item B<name ()>

Returns the name of the error. That might be undef, one of the following
strings or some other string that has been discovered by a heuristic
(because some servers send errors that are not in the RFC).

   bad-format
   bad-namespace-prefix
   conflict
   connection-timeout
   host-gone
   host-unknown
   improper-addressing
   internal-server-error
   invalid-from
   invalid-id
   invalid-namespace
   invalid-xml
   not-authorized
   policy-violation
   remote-connection-failed
   resource-constraint
   restricted-xml
   see-other-host
   system-shutdown
   undefined-condition
   unsupported-stanza-type
   unsupported-version
   xml-not-well-formed

And in case we've got an error we couldn't analyze, due to
old protocol for instance:

   unknown-error

=cut

sub name { $_[0]->{error_name} }

=item B<text ()>

The humand readable error portion. Might be undef if none was received.

=cut

sub text { $_[0]->{error_text} }

sub string {
   my ($self) = @_;

   sprintf ("stream error: %s: %s",
      $self->name,
      $self->text)
}

=back

=cut


=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP
