package AnyEvent::XMPP::Extendable;
use strict;
no warnings;
use Carp qw/croak/;
use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::Extendable - Superclass for extendable things.

=head1 SYNOPSIS

   package MyCon;
   use base qw/
      AnyEvent::XMPP::Stream
      AnyEvent::XMPP::StanzaHandler
      AnyEvent::XMPP::Extendable
   /;

   __PACKAGE__->inherit_event_methods_from (qw/
      AnyEvent::XMPP::Stream
      AnyEvent::XMPP::StanzaHandler
      AnyEvent::XMPP::Extendable
   /);

   sub new {
      my $this  = shift;
      my $class = ref($this) || $this;
      my $self = $class->AnyEvent::XMPP::Stream::new (@_);
      AnyEvent::XMPP::StanzaHandler::init ($self);
      AnyEvent::XMPP::Extendable::init ($self);
      $self
   }

   package main;
   my $con = MyCon->new (...);

   $con->add_extension ('AnyEvent::XMPP::Ext::Disco');
   $con->add_extension ('AnyEvent::XMPP::Ext::Ping');
   ...


=head1 DESCRIPTION

This class is designed to be a super class for anything that:

=over 4

=item 1. Implements the L<AnyEvent::XMPP::Delivery> interface.

=item 2. Provides the L<AnyEvent::XMPP::StanzaHandler> interface.

=item 3. Wants to be extendable by L<AnyEvent::XMPP::Ext> extensions.

(Note: Those extensions are mainly client side currently)

=back

You use this class by inheriting from it, calling the
C<inherit_event_methods_from> package routine (see also L<Object::Event> for
more information), and then call the C<init> function to prepare your object
for acting as an extendable thing.

=head1 FUNCTIONS

=over 4

=item AnyEvent::XMPP::Extendable::init ($self)

=cut

sub init {
   my ($self) = @_;

}

sub add_extension {
   my ($self, $pkg) = @_;
   eval "require $pkg";
   if ($@) {
      croak "Failed to load extension '$pkg': $@\n";
   }

   my @required = $pkg->required_extensions;

   for (@required) {
      unless ($self->{_ext_ids}->{$_}) {
         croak "Extension $pkg required extension with id $_!\n"
      }
   }

   $self->{_ext_ids}->{$pkg}
      = $pkg->new (extendable => $self)
}

sub get_extension {
   my ($self, $id) = @_;
   unless ($self->{_ext_ids}->{$id}) {
      croak "Runtime requirement for extension $id in object $self not met!\n";
   }

   $self->{_ext_ids}->{$id}
}

=back

=head1 METHODS

=over 4

=back

=head1 EVENTS

=over 4

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
