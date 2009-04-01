package AnyEvent::XMPP::Ext::Roster;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/stringprep_jid new_iq new_reply cmp_bare_jid node_jid/;
use Scalar::Util qw/weaken/;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Roster - RFC 3921 Roster handling

=head1 SYNOPSIS

   my $rost = $im->add_ext ('Roster');

   $rost->reg_cb (
      fetched => sub {
         my ($rost, $jid, $roster) = @_;
         # when the roster was fetched
      },
      change => sub {
         my ($rost, $jid, $item_jid, $old_item, $new_item) = @_;
         # when a roster item was updated
      },
      gone => sub {
         my ($rost, $jid) = @_;
         # emitted when the roster is not available anymore
      }
   );

   $rost->auto_fetch; # enables automatic roster retrieval on login for all

   $rost->fetch ($jid); # initiates roster fetch for C<$jid>.

   # remove roster item C<$item_jid> from roster of C<$jid>:
   $rost->remove ($jid, $item_jid, sub {
      my ($e) = @_;
      # ...
   });

   my $item = {
      jid => $item_jid,
      groups => [ 'Goats' ],
      name => 'some guy'
   };

   $rost->set ($jid, $item, sub {
      my ($e) = @_;
      # ...
   });

   my @jids   = $rost->item_jids ($jid);
   my @items  = $rost->items ($jid);
   my $roster = $rost->get ($jid);
   my $item   = $rost->get ($jid, $jids[-1]);

   if ($rost->has_roster_for ($jid)) {
      # you fetched the roster
   }

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub disco_feature { }

sub init {
   my ($self) = @_;

   $self->{iq_guard} = $self->{extendable}->reg_cb (
      ext_before_source_available => sub {
         my ($ext, $jid) = @_;
         $self->{online}->{$jid} = 1;
         $self->fetch ($jid)
            if $self->{auto_fetch};
      },
      ext_before_source_unavailable => sub {
         my ($ext, $jid) = @_;

         if (exists $self->{r}->{$jid}) {
            $self->gone ($jid);
         }

         delete $self->{r}->{$jid};
         delete $self->{online}->{$jid};
      },
      ext_before_recv_iq => sub {
         my ($ext, $node) = @_;

         if ($node->find (roster => 'query')
             && $node->attr ('type') eq 'set') {

            my $from = $node->attr ('from');

            if (not (defined $from)
                || cmp_bare_jid ($from, $node->meta->{dest})) {
               $self->_handle_push ($node);
               $ext->stop_event;
            } 
         }
      }
   );
}

sub _item2struct {
   my ($item) = @_;

   {
      jid          => $item->attr ('jid'),
      name         => $item->attr ('name'),
      ask          => $item->attr ('ask'),
      subscription => $item->attr ('subscription'),
      groups       => [ map $_->text, $item->find (roster => 'group') ]
   }
}

sub _recv_fetch {
   my ($self, $jid, $node) = @_;

   my $roster = $self->{r}->{$jid} = { };

   my ($q) = $node->find (roster => 'query')
      or return;

   for my $item (map _item2struct ($_), $q->find (roster => 'item')) {
      $roster->{stringprep_jid $item->{jid}} = $item;
   }

   $self->fetched ($jid, $roster);
}

sub _handle_push {
   my ($self, $node) = @_;
   my $jid = $node->meta->{dest};

   my ($query) = $node->find (roster => 'query');

   for my $item ($query->find (roster => 'item')) {
      my $item_jid = stringprep_jid $item->attr ('jid');

      my ($old, $new) = ($self->{r}->{$jid}->{$item_jid}, undef);

      if ($item->attr ('subscription') ne 'remove') {
         $new = $self->{r}->{$jid}->{$item_jid} = _item2struct ($item);
      } else {
         delete $self->{r}->{$jid}->{$item_jid}
      }

      $self->change ($jid, $item_jid, $old, $new);
   }

   $self->{extendable}->send (new_reply ($node));
}

sub fetch {
   my ($self, $jid) = @_;

   $self->{extendable}->send (new_iq (
      get => src => $jid,
      create => { node => { dns => 'roster', name => 'query' } },
      cb => sub {
         my ($n, $e) = @_;

         if (defined $e) {
            $self->fetch_error ($jid, $e);
            return;
         }

         $self->_recv_fetch ($jid, $n);
      }
   ));
}

sub auto_fetch {
   my ($self) = @_;

   return if $self->{auto_fetch};
   $self->{auto_fetch} = 1;
   $self->fetch ($_) for keys %{$self->{res}};
}

sub remove {
   my ($self, $jid, $item_jid, $cb) = @_;

   $item_jid = $item_jid->{jid} if ref $item_jid;

   $self->{extendable}->send (new_iq (
      set => src => $jid,
      create => { node => { 
         dns => 'roster', name => 'query', childs => [
            { name => 'item', attrs => [ jid => $item_jid, subscription => 'remove' ] }
         ]
      } },
      cb => sub {
         my ($n, $e) = @_;
         $cb->($e) if $cb;
      }
   ));
}

sub set {
   my ($self, $jid, $item, $cb) = @_;

   $self->{extendable}->send (new_iq (
      set => src => $jid,
      create => { node => { 
         dns => 'roster', name => 'query', childs => [
            { name => 'item', attrs => [
                  jid => $item->{jid},
                  (defined $item->{name} ? (name => $item->{name}) : ()),
               ], childs => [
                  map {
                     { name => 'group', childs => [ $_ ] }
                  } @{$item->{groups} || []}
               ]
            }
         ]
      } },
      cb => sub {
         my ($n, $e) = @_;
         $cb->($e) if $cb;
      }
   ));
}

sub items {
   my ($self, $jid) = @_;
   $jid = stringprep_jid $jid;
   return () unless exists $self->{r}->{$jid};
   values %{$self->{r}->{$jid}};
}

sub item_jids {
   my ($self, $jid) = @_;
   map { $_->{jid} } $self->items ($jid)
}

sub get {
   my ($self, $jid, $item_jid) = @_;
   $jid      = stringprep_jid $jid;
   return undef unless exists $self->{r}->{$jid};
   unless (defined $item_jid) {
      return $self->{r}->{$jid};
   }

   $item_jid = stringprep_jid $item_jid;

   $self->{r}->{$jid}->{$item_jid}
}

sub has_roster_for {
   my ($self, $jid) = @_;
   exists $self->{r}->{$jid}
}

=back

=head1 EVENTS

=over 4

=item fetched => $jid, $roster

=cut

sub fetched { }

=item change => $jid, $item_jid, $old_item, $new_item

=cut

sub change { }

=item gone => $jid

=cut

sub gone { }

=item fetch_error => $jid, $error

This event is emitted when a roster fetch resulted in an error.
C<$error> is an L<AnyEvent::XMPP::Error::IQ> object and
C<$jid> is the resource on which the fetch failed.

=cut

sub fetch_error { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
