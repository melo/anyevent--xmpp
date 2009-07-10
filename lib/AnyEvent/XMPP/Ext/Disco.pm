package AnyEvent::XMPP::Ext::Disco;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Util qw/new_iq new_reply/;
use AnyEvent::XMPP::Ext::Disco::Items;
use AnyEvent::XMPP::Ext::Disco::Info;
use AnyEvent::XMPP::Ext;
use strict;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Disco - Service discovery manager class for XEP-0030

=head1 SYNOPSIS

   my $disco = $im->add_ext ('Disco');

   $disco->set_identity ('client', 'console', 'AnyEvent::XMPP');

   $disco->request_items ($jid, 'romeo@montague.net', undef,
      sub {
         my ($disco, $items, $error) = @_;
         if ($error) { print "ERROR:" . $error->string . "\n" }
         else {
            ... do something with the $items ...
         }
      }
   );

=head1 DESCRIPTION

This module represents a service discovery manager class.  You make instances
of this class and get a handle to send discovery requests like described in
XEP-0030.

This class is derived from L<AnyEvent::XMPP::Ext> and can be added as extension
to objects that implement the L<AnyEvent::XMPP::Extendable> interface or derive
from it.

This extension will also fetch information about the registered extensions on the
extended object and generate discovery information according to their feedback.

To provide content for item discoveries and other things for disco nodes there
are the three events C<identities>, C<features> and C<items> to let you fullfil
disco queries which are directed to you.

=head1 METHODS

=over 4

=cut

sub disco_feature_standard { ( xmpp_ns ('data_form') ) }
sub disco_feature { ( xmpp_ns ('disco_info'), xmpp_ns ('disco_items') ) }

sub init {
   my ($self) = @_;

   $self->set_identity (client => console => 'AnyEvent::XMPP');

   $self->{cb_id} = $self->{extendable}->reg_cb (
      ext_before_recv_iq => sub {
         my ($ext, $node) = @_;

         if ($node->attr ('type') eq 'get') {
            if ($node->find (disco_info => 'query')) {
               $self->reply_with_disco_info ($node);

            } elsif ($node->find (disco_items => 'query')) {
               $self->reply_with_disco_items ($node);

            }
         }
      }
   );

   $self->reg_cb (
      identities => sub {
         my ($self, $iqnode, $node, $identities, $rname) = @_;

         return if defined $node; # only top node

         $$rname = $self->{iden_name};

         for my $cat (keys %{$self->{iden}}) {
            for my $type (keys %{$self->{iden}->{$cat}}) {
               push @$identities, [$cat, $type]
            }
         }
      },
      features => sub {
         my ($self, $iqnode, $node, $features) = @_;

         return if defined $node; # only top node

         push @$features, keys %{$self->{hardcoded_feat} || {}};
         $self->{extendable}->event (discover_features => $features);
      },
   );
}

=item $disco->set_identity ($category, $type, $name)

This sets the identity of the top info node.

C<$name> is optional and can be undef.  Please note that C<$name> will
overwrite all previous set names! If C<$name> is undefined then
no previous set name is overwritten.

For a list of valid identites look at:

   http://www.xmpp.org/registrar/disco-categories.html

Valid identity C<$type>s for C<$category = "client"> may be:

   bot
   console
   handheld
   pc
   phone
   web

=cut

sub set_identity {
   my ($self, $category, $type, $name) = @_;
   $self->{iden_name} = $name;
   $self->{iden}->{$category}->{$type} = 1;
}

=item $disco->unset_identity ($category, $type)

This function removes the identity C<$category> and C<$type>.
If C<$type> is not defined the whole C<$category> is unset.

=cut

sub unset_identity {
   my ($self, $category, $type) = @_;

   if (defined $type) {
      delete $self->{iden}->{$category}->{$type};
   } else {
      delete $self->{iden}->{$category};
   }
}

=item $disco->enable_feature ($uri, $uri2, ...)

This method enables the feature C<$uri>, where C<$uri>
should be one of the values from the B<Name> column on:

   http://www.xmpp.org/registrar/disco-features.html

You can pass also a list of features you want to enable to C<enable_feature>!

Please note that you should rather just derive from L<AnyEvent::XMPP::Ext>
and overwrite the C<disable_feature> method to return the feature URIs.
That way this extension can automatically keep track of the extensions
that are available.

=cut

sub enable_feature {
   my ($self, @feature) = @_;
   $self->{hardcoded_feat}->{$_} = 1 for @feature;
}

=item $disco->disable_feature ($uri, $uri2, ...)

This method enables the feature C<$uri>, where C<$uri>
should be one of the values from the B<Name> column on:

   http://www.xmpp.org/registrar/disco-features.html

You can pass also a list of features you want to disable to C<disable_feature>!

=cut

sub disable_feature {
   my ($self, @feature) = @_;
   delete $self->{hardcoded_feat}->{$_} for @feature;
}

sub write_feature {
   my ($self, $w, $var) = @_;

   $w->emptyTag ([xmpp_ns ('disco_info'), 'feature'], var => $var);
}

sub write_identity {
   my ($self, $w, $cat, $type, $name) = @_;

   $w->emptyTag ([xmpp_ns ('disco_info'), 'identity'],
      category => $cat,
      type     => $type,
      (defined $name ? (name => $name) : ())
   );
}

sub reply_with_disco_info {
   my ($self, $node) = @_;

   if (my ($q) = $node->find (disco_info => 'query')) {
      my $dnode = $q->attr ('node');

      my $identities = [];
      my $features   = [];
      my $name       = undef;

      $self->event (identities => $node, $dnode, $identities, \$name);
      $self->event (features   => $node, $dnode, $features);
      
      my (@identities, @features);

      for my $iden (@$identities) {
         push @identities, {
            name  => 'identity',
            attrs => [
               category => $iden->[0],
               type     => $iden->[1],
               (defined $name ? (name => $name) : ()),
            ]
         }
      }

      for my $feat (@$features) {
         push @features, { name => 'feature', attrs => [ var => $feat ] };
      }

      my $r = simxml (node => {
         dns => 'disco_info', name => 'query',
         attrs  => [ (defined $dnode ? (node => $dnode) : ()) ],
         childs => [ @identities, @features ]
      });

      my $reply = new_reply ($node, create => $r);
      $self->event (generated_info_reply => $reply);
      $self->{extendable}->send ($reply);
      $self->{extendable}->stop_event;
   }
}

sub reply_with_disco_items {
   my ($self, $node) = @_;

   if (my ($q) = $node->find (disco_items => 'query')) {
      my $dnode = $q->attr ('node');

      my $items = [];

      $self->event (items => $node, $dnode, $items);

      my $r = simxml (node => {
         dns => 'disco_items', name => 'query',
         attrs  => [ (defined $dnode ? (node => $dnode) : ()) ],
         childs => [ map { {
            name  => 'item',
            attrs => [
               jid => $_->[0],
               (defined $_->[1] ? (name => $_->[1]) : ()),
               (defined $_->[2] ? (node => $_->[2]) : ()),
            ]
         } } @$items ],
      });

      my $reply = new_reply ($node, create => $r);
      $self->event (generated_items_reply => $reply);
      $self->{extendable}->send ($reply);
      $self->{extendable}->stop_event;
   }
}

=item $disco->request_items ($jid, $dest, $node, $cb->($disco, $items, $error))

This method does send a items request to the JID entity C<$dest> from the
source C<$jid>. C<$node> is the optional node to send the request to, which
can be undef.

The callback C<$cb> will be called when the request returns with 3 arguments:
The disco handle C<$disco>, an L<AnyEvent::XMPP::Ext::Disco::Items> object (or
undef) in C<$items> and an L<AnyEvent::XMPP::Error::IQ> object in C<$error>
when an error occured and no items were received.

   $disco->request_items ($my_jid, 'a@b.com', undef, sub {
      my ($disco, $items, $error) = @_;
      die $error->string if $error;

      # do something with the items here ;-)
   });

=cut

sub request_items {
   my ($self, $jid, $dest, $dnode, $cb) = @_;

   $self->{extendable}->send (new_iq (
      get =>
         src => $jid,
         (defined $dest ? (to => $dest) : ()),
      create => { node => {
         dns => 'disco_items', name => 'query',
         attrs => [ (defined $dnode ? (node => $dnode) : ()) ]
      }},
      cb => sub {
         my ($node, $error) = @_;
         my $items;

         if ($node) {
            $items = AnyEvent::XMPP::Ext::Disco::Items->new (
               jid => $dest, node => $dnode, xmlnode => $node
            )
         }

         $cb->($self, $items, $error)
      }
   ));
}

=item $disco->request_info ($jid, $dest, $node, $cb->($disco, $info, $error))

This method does send a info request to the JID entity C<$dest> from the
resource C<$jid>. C<$node> is the optional node to send the request to, which
can be undef.

The callback C<$cb> will be called when the request returns with 3 arguments:
The disco handle C<$disco>, an L<AnyEvent::XMPP::Ext::Disco::Info> object (or
undef) in C<$info> and an L<AnyEvent::XMPP::Error::IQ> object in C<$error> when
an error occured and no items were received.

   $disco->request_info ($con, 'a@b.com', undef, sub {
      my ($disco, $info, $error) = @_;
      die $error->string if $error;

      # do something with info here ;_)
   });

=cut

sub request_info {
   my ($self, $jid, $dest, $dnode, $cb) = @_;

   $self->{extendable}->send (new_iq (
      get =>
         src => $jid,
         (defined $dest ? (to => $dest) : ()),
      create => { node => {
         dns => 'disco_info', name => 'query',
         attrs => [ (defined $dnode ? (node => $dnode) : ()) ]
      }},
      cb => sub {
         my ($node, $error) = @_;
         my $info;

         if ($node) {
            $info = AnyEvent::XMPP::Ext::Disco::Info->new (
               jid => $dest, node => $dnode, xmlnode => $node
            )
         }

         $cb->($self, $info, $error)
      }
   ));
}

=back

=head1 EVENTS

=over 4

=item features => $iqnode, $node, $features

This event is emitted whenever a disco info query is answered.
C<$iqnode> is the L<AnyEvent::XMPP::Node> of the IQ get.

C<$node> is the discovery info 'node', which is undef in case
the query is directed to the top node.

C<$features> is an array reference you can fill with the
features of the C<$node>.

=item identities => $iqnode, $node, $identities, $rname

This event is emitted whenever a disco info query is answered.
C<$iqnode> is the L<AnyEvent::XMPP::Node> of the IQ get.

C<$node> is the discovery info 'node', which is undef in case
the query is directed to the top node.

C<$identities> is an array reference which you can fill with this
sort of entries:

   push @$identities, [$category, $type];

Please consult XEP-0030 about the meaning of C<$category> and C<$type>
with regard to disco info identities.

C<$rname> is a reference to a scalar holding the name of the identities.

=item items => $iqnode, $node, $items

This event is emitted whenever a disco items query is answered.
C<$iqnode> is the L<AnyEvent::XMPP::Node> of the IQ get.

C<$node> is the discovery items 'node', which is undef in case
the query is directed to the top node.

C<$items> is an array reference you can fill with this kind of entries:

   push @$items, [$jid, $name, $node];

C<$name> and C<$node> are optional in such an entry and can be undef.
About more details of the items mechanism consult XEP-0030.

=item generated_info_reply => $iqnode

=item generated_items_reply => $iqnode

These events are emitted shortly before the C<$iqnode> disco info/items reply
is sent out. You may use this event to add custom data to the
reply, for example according to XEP-0128.

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
