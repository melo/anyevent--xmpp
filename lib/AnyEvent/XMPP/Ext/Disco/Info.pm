package AnyEvent::XMPP::Ext::Disco::Info;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use strict;

=head1 NAME

AnyEvent::XMPP::Ext::Disco::Info - Service discovery info

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the result of a disco info request
sent by a C<AnyEvent::XMPP::Ext::Disco> handler.

=head1 METHODS

=over 4

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = bless { @_ }, $class;
   $self->init;
   $self
}

=item B<jid ()>

Returns the JID these items belong to.

=cut

sub jid { $_[0]->{jid} }

=item B<node ()>

Returns the node this info belong to (may be undef).

=cut

sub node { $_[0]->{node} }

sub init {
   my ($self) = @_;
   my $node = $self->{xmlnode};
   return unless $node;

   my ($query) = $node->find (disco_info => 'query');

   my (@ids) = $query->find (disco_info => 'identity');
   for (@ids) {
      push @{$self->{identities}}, {
         category => $_->attr ('category'),
         type     => $_->attr ('type'),
         name     => $_->attr ('name'),
      };
   }

   my (@fs) = $query->find (disco_info => 'feature');
   $self->{features}->{$_->attr ('var')} = 1 for @fs;

}

=item B<identities ()>

Returns a list of hashrefs which contain following keys:

   category, type, name

C<category> is the category of the identity. C<type> is the 
type of the identity. C<name> is the human readable name of
the identity and might be undef. 

C<category> and C<type> may be one of those defined on:

   http://www.xmpp.org/registrar/disco-categories.html

=cut

sub identities {
   my ($self) = @_;
   @{$self->{identities} || []}
}

=item B<features ()>

Returns a hashref of key/value pairs where the key is the feature name
as listed on:

   http://www.xmpp.org/registrar/disco-features.html

=cut

sub features { $_[0]->{features} || {} }

=item B<has_feature ($uri)>

Returns true if this disco info has the feature C<$uri>.

=cut

sub has_feature { exists $_[0]->{features}->{$_[1]} }

=item B<debug_dump ()>

Prints the information of this Info object to stdout.

=cut

sub debug_dump {
   my ($self) = @_;
   printf "INFO FOR %s (%s):\n", $self->jid, $self->node;
   for ($self->identities) {
      printf "   ID     : %20s/%-10s (%s)\n", $_->{category}, $_->{type}, $_->{name}
   }
   for (sort keys %{$self->features}) {
      printf "   FEATURE: %s\n", $_;
   }
   print "END INFO\n";

}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
