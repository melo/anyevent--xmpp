package AnyEvent::XMPP::Ext::Presence;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/stringprep_jid new_iq new_reply new_presence cmp_jid
                            cmp_bare_jid/;
use Scalar::Util qw/weaken/;
no warnings;
use strict;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Presence - Presence tracker

=head1 SYNOPSIS

   my $pres = $im->add_extension ('AnyEvent::XMPP::Ext::Presence');

   # setting default presence for all connected resources:
   $pres->set_default ('available', 'working on something', 10);

   # setting resource specific presence:
   $pres->set_presence ($resource1_jid, 'available', 'working on something', 10);

   # unsetting resource specific presence:
   $pres->set_presence ($resource1_jid);

   $im->reg_cb (
      ext_presence_self => sub {
         my ($im, $resjid, $jid, $old_presence_struct, $presence_struct) = @_;

         # called when the presence for one of
         # our own resources changes.
      },
      ext_presence_change => sub {
         my ($im, $resjid, $jid, $old_presence_struct, $presence_struct) = @_;

         # called when presence of some contact or other
         # XMPP entity changed.
      },
   );

   my @presences = $pres->my_presences; # returns list of presence structs

   my @jids = $pres->presences ($my_jid1); # returns list of jids we have received 
                                           # presence for, w.r.t. a connected resource

   my $struct = $pres->get ($my_jid1, $jids[0]); # returns presence struct

   # to send out an presence update for a specific resource:
   $pres->update ($my_jid1);

   # or all resources:
   $pres->update;

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub disco_feature { }

sub init {
   my ($self) = @_;

   weaken $self;

   $self->{guard} = $self->{extendable}->reg_cb (
      source_available => sub {
         my ($ext, $jid) = @_;

         $self->{p}->{$jid}     = { };
         $self->{own_p}->{$jid} = { };

         $self->update ($jid);
      },
      source_unavailable => sub {
         my ($ext, $jid) = @_;

         for my $rjid (keys %{$self->{own_p}->{$jid} || {}}) {
            $ext->event (ext_presence_self => $jid, $rjid, $self->{own_p}->{$jid}, undef);
         }

         for my $pjid (keys %{$self->{p}->{$jid} || {}}) {
            $ext->event (ext_presence_change => $jid, $pjid, $self->{p}->{$jid}, undef);
         }

         delete $self->{own_p}->{$jid};
         delete $self->{p}->{$jid};
      },
      recv_presence => sub {
         my ($ext, $node) = @_;
         $self->analyze_stanza ($node);
      }
   );
}

sub _to_pres_struct {
   my ($node) = @_;

   my $struct = { };

   my (@show)   = $node->find_all ([qw/stanza show/]);
   my (@status) = $node->find_all ([qw/stanza status/]);
   my (@prio)   = $node->find_all ([qw/stanza priority/]);

   $struct->{show}     = @show ? $show[0]       : 'available';
   $struct->{priority} = @prio ? $prio[0]->text : 0;

   my $def_status;

   for my $s (@status) {
      if (defined (my $lang = $s->attr_ns (xml => 'lang'))) {
         if ($lang eq $node->meta->{lang}) {
            $def_status = $s->text;
         }

         $struct->{all_status}->{$lang} = $s->text;
      } else {
         $struct->{all_status}->{''} = $s->text;
      }
   }

   $def_status = $struct->{all_status}->{''} unless defined $def_status;
   $def_status = $status[-1]->text           if ((not defined $def_status) && @status);

   $struct->{status}   = $def_status;

   $struct
}

sub _eq_pres {
   my ($a, $b) = @_;

   return 0 if defined ($a) != defined ($b);
   return 0 if $a->{status}   ne $b->{status};
   return 0 if $a->{show}     ne $b->{show};
   return 0 if $a->{priority} ne $b->{priority};

   return 0 if scalar (keys %{$a->{all_status} || {}})
               != scalar (keys %{$b->{all_status} || {}});

   my @k = keys %{$a->{all_status} || {}},
           keys %{$b->{all_status} || {}};

   for (@k) {
      return 0 if $a->{all_status}->{$_} ne $b->{all_status}->{$_};
   }

   return 1;
}

sub analyze_stanza {
   my ($self, $node) = @_;

   my $meta   = $node->meta;
   my $resjid = $meta->{dest};

   my $from   = stringprep_jid $node->attr ('from');
   my $to     = stringprep_jid $node->attr ('to');

   return unless cmp_jid ($to, $resjid);

   if ($meta->{presence}) {
      $self->_int_upd_presence (
         $resjid, $from, $meta->{is_resource_presence}, _to_pres_struct ($node));
   } else {
   }
}

sub _int_upd_presence {
   my ($self, $resjid, $jid, $is_own, $new) = @_;

   my ($key, $ev) =
      $is_own
         ? (own_p => 'ext_presence_self')
         : (p     => 'ext_presence_change');

   my $prev = $self->{$key}->{$resjid}->{$jid};
   $self->{$key}->{$resjid}->{$jid} = $new;

   unless (_eq_pres ($prev, $new)) {
      $self->{extendable}->event ($ev => $resjid, $jid, $prev, $new);
   }
}

sub set_default {
   my ($self, $show, $status, $prio) = @_;
   $self->{def} = [$show, $status, $prio];

   for (keys %{$self->{own_p}}) {
      $self->update ($_) unless exists $self->{set}->{$_};
   }
}

sub set_presence {
   my ($self, $jid, @args) = @_;
   
   if (@args) {
      $self->{set}->{stringprep_jid $jid} = [@args];
   } else {
      delete $self->{set}->{stringprep_jid $jid};
   }

   $self->update ($jid)
}

sub update {
   my ($self, $jid) = @_;

   unless (defined $jid) {
      $self->update ($_) for keys %{$self->{own_p}};
      return;
   }

   $jid = stringprep_jid $jid;

   my ($show, $status, $prio) = @{
      $self->{set}->{$jid}
      || $self->{def}
      || [available => undef, undef]
   };

   $show = undef if $show eq 'available';

   my $node = new_presence (available => $show, $status, $prio, src => $jid);
   $self->{extendable}->send ($node);

   # non-bis behavior:
   $self->_int_upd_presence ($jid, $jid, 1, _to_pres_struct ($node));
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
