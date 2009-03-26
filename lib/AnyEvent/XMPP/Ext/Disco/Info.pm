package AnyEvent::XMPP::Ext::Disco::Info;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Ext::DataForm;
use strict;

=head1 NAME

AnyEvent::XMPP::Ext::Disco::Info - Service discovery info

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the result of a disco info request
sent by a C<AnyEvent::XMPP::Ext::Disco> handler.

NOTE: This class also handles XEP-0128 Service Discovery Extensions
and will get all provided data forms.

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
         lang     => $_->attr_ns (xml => 'lang'),
      };
   }

   my (@fs) = $query->find (disco_info => 'feature');
   $self->{features}->{$_->attr ('var')} = 1 for @fs;

   for my $dnode ($query->find (data_form => 'x')) {
      push @{$self->{extended}}, AnyEvent::XMPP::Ext::DataForm->from_node ($dnode);
   }
}

=item B<identities ()>

Returns a list of hashrefs which contain following keys:

   category, type, name, lang

C<category> is the category of the identity. C<type> is the 
type of the identity. C<name> is the human readable name of
the identity and might be undef. 
C<lang> is the C<xml:lang> attribute that belongs to the C<name>,
and may be undef.

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

=item B<extended>

This method returns a list of service discovery
extensions as L<AnyEvent::XMPP::Ext::DataForm> objects.
See also XEP-0128.

=cut

sub extensions {
   my ($self) = @_;
   @{$self->{extended} || []}
}

=item B<debug_dump ()>

Prints the information of this Info object to stdout.

=cut

sub debug_dump {
   my ($self) = @_;
   printf "INFO FOR %s (%s):\n", $self->jid, $self->node;
   for ($self->identities) {
      printf "   ID     : %20s/%-10s[%s] (%s)\n", $_->{category}, $_->{type}, $_->{name}, $_->{lang}
   }
   for (sort keys %{$self->features}) {
      printf "   FEATURE: %s\n", $_;
   }
   for ($self->extensions) {
      printf "EXTENDED INFO:\n--------------------\n";
      print $_->as_debug_string;
      print "---------------------\n";
   }
   print "END INFO\n";

}

sub as_verification_string {
   my ($self) = @_;

   use sort 'stable';

   my $s = '';

   my @identities =
      sort { $a->{lang} cmp $b->{lang} }
         sort { $a->{type} cmp $b->{type} }
            sort { $a->{category} cmp $b->{category} }
               $self->identities;

   $s .= $_ for map {
      sprintf "%s/%s/%s/%s<", $_->{category}, $_->{type}, $_->{lang}, $_->{name}
   } @identities;

   my @features = sort { $a cmp $b } keys %{$self->features};
   $s .= $_ for map { "$_<" } @features;

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
