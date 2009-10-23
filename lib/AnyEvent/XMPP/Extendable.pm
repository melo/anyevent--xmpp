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

   sub new {
      my $this  = shift;
      my $class = ref($this) || $this;
      my $self = $class->AnyEvent::XMPP::Stream::new (@_);
      $self
   }

   package main;
   my $con = MyCon->new (...);

   $con->add_extension ('AnyEvent::XMPP::Ext::Ping'); # same as: $con->add_ext ('Ping')
   $con->add_ext ('Disco');
   ...


=head1 DESCRIPTION

This class is designed to be a super class for anything that:

=over 4

=item 1. Implements the L<AnyEvent::XMPP::Delivery> interface.

=item 2. Provides the L<AnyEvent::XMPP::StanzaHandler> interface.

=item 3. Provides IQ tracking similar to L<AnyEvent::XMPP::IQTracker>.

=item 4. Wants to be extendable by L<AnyEvent::XMPP::Ext> extensions.

(Note: Those extensions are mainly client side currently, use with care for
components!)

=back

You use this class by inheriting from it, calling the
C<inherit_event_methods_from> package routine (see also L<Object::Event> for
more information), and then call the C<init> function to prepare your object
for acting as an extendable thing.

=head1 METHODS

=over 4

=item $extendable->add_ext ($shortcut)

The same as C<add_extension> just that C<AnyEvent::XMPP::Ext::>
is put in front of C<$shortcut>. That means this:

   $extendable->add_ext ('Disco');

Is the same as this:

   $extendable->add_extension ('AnyEvent::XMPP::Ext::Disco');

=cut

sub add_ext {
   my ($self, $short) = @_;
   $self->add_extension ('AnyEvent::XMPP::Ext::' . $short);
}

=item $extendable->add_extension ($full_classname)

This method adds an extension to the C<$extendable> object.
It does so by trying to load C<$full_classname> (with require).
After that it loads the packages returned by the C<autoload_extensions>
method of the C<$full_classname> package and checks for the presence of
extensions returned by the C<required_extensions> method of the C<$full_classname>
package.

Then it constructs a new object instance of C<$full_classname> and adds it to the
internal list of extensions. You can retrieve the extension object anytime
with C<get_ext>/C<get_extension> (see below).

=cut

sub add_extension {
   my ($self, $pkg) = @_;

   return $self->{_ext_ids}->{$pkg} if $self->{_ext_ids}->{$pkg};

   eval "require $pkg";
   if ($@) {
      croak "Failed to load extension '$pkg': $@\n";
   }

   my @autoload = $pkg->autoload_extensions;

   for (@autoload) {
      $self->add_extension ($_) unless $self->{_ext_ids}->{$_};
   }

   my @required = $pkg->required_extensions;

   for (@required) {
      unless ($self->{_ext_ids}->{$_}) {
         croak "Extension $pkg requires extension with id $_!\n"
      }
   }

   $self->{_ext_ids}->{$pkg}
      = $pkg->new (extendable => $self)
}

=item $extendable->get_ext ($shortcut)

The same as:

   my $extobj = $extendable->get_extension ('AnyEvent::XMPP::Ext::' . $shortcut)

=cut

sub get_ext {
   my ($self, $ext) = @_;
   $self->get_extension ('AnyEvent::XMPP::Ext::' . $ext)
}

=item $extendable->get_extension ($pkg)

Returns the extension with the package name C<$pkg>:

  my $extobj = $extendable->get_extension ('My::Custom::XMPP::Ext::Foo');

=cut

sub get_extension {
   my ($self, $pkg) = @_;
   unless ($self->{_ext_ids}->{$pkg}) {
      croak "Runtime requirement for extension $pkg in object $self not met!\n";
   }

   $self->{_ext_ids}->{$pkg}
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<AnyEvent::XMPP:Delivery>

L<AnyEvent::XMPP::StanzaHandler>

L<AnyEvent::XMPP::IQTracker>

L<AnyEvent::XMPP::Ext>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
