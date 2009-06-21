package AnyEvent::XMPP::Ext::Version;
use AnyEvent::XMPP;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/new_iq new_reply/;
use AnyEvent::XMPP::Node qw/simxml/;
use Scalar::Util qw/weaken/;
use strict;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Version - XEP-0092: Software version

=head1 SYNOPSIS

   my $version = $extendable->add_ext ('Version');
   $version->set_name    ("My client");
   $version->set_version ("0.3");
   $version->set_os      (`uname -a`);

=head1 DESCRIPTION

This module defines an extension to provide the abilities
to answer to software version requests and to request software
version from other entities.

See also XEP-0092.

This class is derived from L<AnyEvent::XMPP::Ext> and can be added as extension to
objects that implement the L<AnyEvent::XMPP::Extendable> interface or derive from
it.

=head1 METHODS

=over 4

=cut

sub disco_feature { xmpp_ns ('version') }

sub init {
   my ($self) = @_;

   $self->set_name    ("AnyEvent::XMPP");
   $self->set_version ("$AnyEvent::XMPP::VERSION");

   weaken $self;
   weaken $self->{extendable};

   $self->{_guard1} = $self->{extendable}->reg_cb (
      ext_before_recv_iq => sub {
         my ($extdbl, $node) = @_;

         if ($node->attr ('type') eq 'get'
             && $node->find_all ([qw/version query/])) {

            $self->handle_query ($node);
            $extdbl->stop_event;
         }
      }
   );
}

=item $ext->set_name ($name)

This method sets the software C<$name> string, the default is "AnyEvent::XMPP".

=cut

sub set_name {
   my ($self, $name) = @_;
   $self->{name} = $name;
}

=item $ext->set_version ($version)

This method sets the software C<$version> string that is replied.

The default is C<$AnyEvent::XMPP::VERSION>.

=cut

sub set_version {
   my ($self, $version) = @_;
   $self->{version} = $version;
}

=item $ext->set_os ($os)

This method sets the operating system string C<$os>. If you pass
undef the string will be removed.

The default is no operating system string at all.

You may want to pass something like this:

   $version->set_os (`uname -s -r -m -o`);

=cut

sub set_os {
   my ($self, $os) = @_;
   $self->{os} = $os;
   delete $self->{os} unless defined $os;
}

sub version_result {
   my ($self) = @_;
   (
      { name => 'name'   , childs => [ $self->{name}    ] },
      { name => 'version', childs => [ $self->{version} ] },
      (defined $self->{os}
         ? { name => 'os', childs => [ $self->{os} ] }
         : ()
      ),
   )
}

sub handle_query {
   my ($self, $node) = @_;

   my ($q) = $node->find_all ([qw/version query/]);
   my @result = $self->version_result;

   $self->{extendable}->send (new_reply ($node, {
      node => {
         dns    => 'version',
         name   => 'query',
         childs => \@result
      }
   }));
}

sub _version_from_node {
   my ($node) = @_;
   my (@vers) = $node->find_all ([qw/version query/], [qw/version version/]);
   my (@name) = $node->find_all ([qw/version query/], [qw/version name/]);
   my (@os)   = $node->find_all ([qw/version query/], [qw/version os/]);

   my $v = {};

   $v->{jid}     = $node->attr ('from');
   $v->{version} = $vers[0]->text if @vers;
   $v->{name}    = $name[0]->text if @name;
   $v->{os}      = $os[0]->text   if @os;

   $v
}

=item $ext->request_version ($src, $dest, $cb->($version, $error), $timeout)

This method sends a version request to C<$dest> from the (full) JID C<$src>.

C<$cb> is the callback that will be called if either an error occurred or the
result was received.  C<$timeout> is an optional argument, which lets you
disable (= 0) or specify a custom timeout.

The second argument for the callback will be either undef if no error occurred
or an L<AnyEvent::XMPP::Error::IQ> error.  The first argument will be a hash
reference with the following fields:

=over 4

=item jid

The JID of the entity this version reply belongs to.

=item version

The software version string of the entity.

=item name 

The software name of the entity.

=item os

The operating system of the entity, which might be undefined if none
was provided.

=back

Here an example of the structure of the hash reference:

  {
     jid     => 'juliet@capulet.com/balcony',
     name    => 'Exodus',
     version => '0.7.0.4',
     os      => 'Windows-XP 5.01.2600',
  }

=cut

sub request_version {
   my ($self, $src, $dest, $cb, $tout) = @_;

   $self->{extendable}->send (new_iq (
      get =>
         src => $src,
         to  => $dest,
      create => { node  => { dns => 'version', name => 'query' } },
      cb => sub {
         my ($n, $e) = @_;
         $cb->($n ? _version_from_node ($n) : undef, $e);
      },
      timeout => $tout
   ));
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007-2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
