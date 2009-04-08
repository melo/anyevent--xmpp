package AnyEvent::XMPP::Ext::Presence;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/stringprep_jid new_iq new_reply new_presence cmp_jid
                            cmp_bare_jid res_jid prep_bare_jid prep_res_jid
                            extract_lang_element bare_jid node_jid res_jid
                            is_bare_jid/;
use Scalar::Util qw/weaken/;
no warnings;
use strict;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Presence - RFC 3921 Presence handling

=head1 SYNOPSIS

   my $pres = $im->add_ext ('Presence');

   # setting default presence for all connected resources:
   $pres->set_default ('available', 'working on something', 10);

   # setting resource specific presence:
   $pres->set_presence ($resource1_jid, 'available', 'working on something', 10);

   # unsetting resource specific presence:
   $pres->set_presence ($resource1_jid);

   $ext->reg_cb (
      self => sub {
         my ($ext, $resjid, $bare_jid, $old_presence_struct, $presence_struct) = @_;

         # called when the presence for one of
         # our own resources changes.
      },
      change => sub {
         my ($ext, $resjid, $bare_jid, $old_presence_struct, $presence_struct) = @_;

         # called when presence of some contact or other
         # XMPP entity changed.
      },
   );

   my @presences = $pres->presences ($my_jid);
   my @presences = $pres->presences ($my_jid, $bare_jid);
   my $presence  = $pres->presences ($my_jid, $full_jid);

   my @presences = $pres->highest_prio_presence ($my_jid);
   my @presences = $pres->highest_prio_presence ($my_jid, $bare_jid);
   my @presences = $pres->highest_prio_presence ($my_jid, $full_jid);

   # to send out an presence update for a specific resource:
   $pres->update ($my_jid1);

   # or all resources:
   $pres->update;

   # subscription handling:

   $ext->reg_cb (
      subscription_request => sub { },
   );

   $pres->send_subscription_request (
      $my_jid, $your_jid, 1, "Hi! I would love to have a mutual subscription!");

   my @pres_reqs = $pres->pending_subscription_requests ($my_jid);

   $pres->handle_subscription_request (
      $my_jid, $pres_reqs[-1], 1, 1, "Ok, I want to subscribe to you too!");

   $pres->handle_subscription_request (
      $my_jid, $pres_reqs[-1]->{from}, 1, 0, "Ok, but I don't want to see u!");

   $pres->handle_subscription_request (
      $my_jid, $pres_reqs[-1], 0, 0, "No, I don't like you!");

=head1 DESCRIPTION

This extension handles all presence handling that is defined in RFC 3921.

It will track presence of contacts and other people that share presence with
you. It also provides an interface for tracking, answering and initiating
presence subscriptions.

I've split up this documentation into two parts: PRESENCE METHODS and
SUBSCRIPTION METHODS. This is just for documentation purposes.

See also below in the EVENTS sections about the events that are emitted
on the L<AnyEvent::XMPP::Extendable> object that this extension extends.

=head1 DEPENDENCIES

This extension autoloads and requires the L<AnyEvent::XMPP::Ext::LangExtract>
extension.

=cut

sub required_extensions { 'AnyEvent::XMPP::Ext::LangExtract' } 
sub autoload_extensions { 'AnyEvent::XMPP::Ext::LangExtract' }

=head1 PRESENCE METHODS

=over 4

=cut

sub disco_feature { }

sub init {
   my ($self) = @_;

   weaken $self;

   $self->{guard} = $self->{extendable}->reg_cb (
      source_available => 490 => sub {
         my ($ext, $jid) = @_;

         $self->{p}->{$jid}          = { };
         $self->{own_p}->{$jid}      = { };
         $self->{subsc_reqs}->{$jid} = { };

         $self->update ($jid);
      },
      source_unavailable => 490 => sub {
         my ($ext, $jid) = @_;

         for my $pres ($self->my_presences ($jid)) {
            $self->_int_upd_presence ($jid, $pres->{jid}, 1, undef);
         }

         for my $pres ($self->presences ($jid)) {
            $self->_int_upd_presence ($jid, $pres->{jid}, 0, undef);
         }

         delete $self->{own_p}->{$jid};
         delete $self->{p}->{$jid};
         delete $self->{subsc_reqs}->{$jid};
         delete $self->{direct}->{$jid};
      },
      recv_presence => 490 => sub {
         my ($ext, $node) = @_;
         $self->_analyze_stanza ($node);
      }
   );
}

sub _analyze_stanza {
   my ($self, $node) = @_;

   my $meta   = $node->meta;
   my $resjid = $meta->{dest};

   return if $meta->{error};

   my $from   = stringprep_jid $node->attr ('from');
   my $to     = stringprep_jid $node->attr ('to');

   $to = $resjid unless defined $to;

   unless (defined (node_jid $to)) {
      warn "$resjid: Ignoring badly addressed presence stanza: "
           . $node->raw_string . "\n";
      return;
   }

   if ($meta->{presence}) {
      $self->_int_upd_presence (
         $resjid, $from, $meta->{is_resource_presence}, _to_pres_struct ($node));

   } else {
      $self->_int_handle_subscription ($resjid, $from, $node);
   }
}

# $jid needs to be stringprepped
sub _build_own_presence {
   my ($self, $jid, $to) = @_;

   my ($show, $status, $prio) = @{
      $self->{set}->{$jid}
      || $self->{def}
      || [available => undef, undef]
   };

   $show = undef if $show eq 'available';

   my $node = new_presence (available => $show, $status, $prio, src => $jid);
   if (defined $to) {
      $node->attr ('to', $to);
   }
   $self->generated_presence ($node);
   $node
}

sub _to_pres_struct {
   my ($node, $jid) = @_;

   my $struct = { };

   my (@show)   = $node->find_all ([qw/stanza show/]);
   my (@prio)   = $node->find_all ([qw/stanza priority/]);

   $struct->{jid}      = defined $jid ? $jid : $node->attr ('from');
   $struct->{show}     =
      @show
         ? $show[0]->text
         : ($node->attr ('type') eq 'unavailable' ? 'unavailable' : 'available');
   $struct->{priority}   = @prio ? $prio[0]->text : 0;

   # in case we sent this stanza:
   if (not (defined ($node->meta->{status})) && $node->find (stanza => 'status')) {
      extract_lang_element ($node, 'status', $node->meta);
   }

   $struct->{status}     = $node->meta->{status};
   $struct->{all_status} = $node->meta->{all_status};

   $struct
}

sub _eq_pres {
   my ($a, $b) = @_;

   return 0 if defined ($a) != defined ($b);
   return 0 if not cmp_jid ($a->{jid}, $b->{jid});
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

# $resjid and $jid needs to be stringprepped
sub _int_upd_presence {
   my ($self, $resjid, $jid, $is_own, $new) = @_;

   my ($key, $ev) =
      $is_own
         ? (own_p => 'self')
         : (p     => 'change');

   my $bjid = prep_bare_jid ($jid);
   my $res  = prep_res_jid ($jid);
   $res = "$res"; # stringify, undef becomes '' (empty resource)

   my $respres = $self->{$key}->{$resjid};
   my $prev    =
      exists ($respres->{$bjid})
      && exists ($respres->{$bjid}->{$res})
        ? $respres->{$bjid}->{$res}
        : {
            priority   => 0,
            all_status => { },
            status     => undef,
            show       => 'unavailable',
            jid        => $jid
        };

   if (defined $new) {
      $self->{$key}->{$resjid}->{$bjid}->{$res} = $new;

   } else {
      $self->{$key}->{$resjid}->{$bjid}->{$res} = $new = {
         priority   => 0,
         all_status => { },
         status     => undef,
         show       => 'unavailable',
         jid        => $jid
      };
   }

   if (($res eq '' && $new->{show} eq 'unavailable')
       || not (grep { $_->{show} ne 'unavailable' }
                 values %{$self->{$key}->{$resjid}->{$bjid}})) {

      # no available resources anymore, set the 'last received' unavailable
      # presence (which has been received now) on the empty resource:

      # (in case we got an unavailable presence from a bare jid we assume
      #  there is no available presence anymore!)

      $self->{$key}->{$resjid}->{$bjid} = { '' => $new };
   }

   unless (_eq_pres ($prev, $new)) {
      $self->event ($ev => $resjid, bare_jid ($jid), $prev, $new);
   }
}

=item $pres->set_default ($show, $status, $prio)

This method will set the default presence information for client resources that
are connected by the extended L<AnyEvent::XMPP::Extendable> object.

For setting the presence information for a special resource use the C<set_presence>
method (see below).

About the possible values for C<$show>, C<$status> and C<$prio> please consult
the documentation of the C<new_presence> function of L<AnyEvent::XMPP::Util>.

See documentation about the C<generated_presence> event if you want to attach
further information to presence status messages that are emitted by this
extension.

=cut

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

sub send_directed {
   my ($self, $resjid, $jid, $auto_update) = @_;

   my $node = $self->_build_own_presence (stringprep_jid ($resjid), $jid);
   $self->{extendable}->send ($node);

   if ($auto_update) {
      $self->{direct}->{stringprep_jid ($resjid)}->{stringprep_jid ($jid)} = 1;
   }
}

sub update {
   my ($self, $jid) = @_;

   unless (defined $jid) {
      $self->update ($_) for keys %{$self->{own_p}};
      return;
   }

   $jid = stringprep_jid $jid;

   my $node = $self->_build_own_presence ($jid);
   $self->{extendable}->send ($node);

   for my $directed_jid (keys %{$self->{direct}->{$jid} || {}}) {
      my $direct_node = $self->_build_own_presence ($jid, $directed_jid);
      $self->{extendable}->send ($direct_node);
   }

   # non-bis behavior:
   $self->_int_upd_presence ($jid, $jid, 1, _to_pres_struct ($node, $jid));
}

sub my_presences {
   my ($self, $resjid) = @_;

   unless (defined $resjid) {
      return map { $self->my_presences ($_) } keys %{$self->{own_p}};
   }

   $resjid = stringprep_jid $resjid;

   my $bjids = $self->{own_p}->{$resjid};

   my @pres;
   for my $bjid (keys %{$bjids || {}}) {
      push @pres, values %{$bjids->{$bjid}};
   }

   @pres
}

sub presences {
   my ($self, $jid, $pjid) = @_;

   $jid = stringprep_jid $jid;
   return () unless exists $self->{p}->{$jid};

   if (defined $pjid) {
      $pjid = stringprep_jid $pjid;
      my $bpjid = bare_jid $pjid;
      return () unless exists $self->{p}->{$jid}->{$bpjid};
      my $res = res_jid ($pjid);

      if (defined $res) {
         return $self->{p}->{$jid}->{$bpjid}->{$res}
      } else {
         return values %{$self->{p}->{$jid}->{$bpjid}}
      }

   } else {

      my @p;
      for my $bjid (keys %{$self->{p}->{$jid}}) {
         push @p, $self->presences ($jid, $bjid);
      }
      return @p;
   }
}

sub highest_prio_presence {
   my ($self, $jid, $bjid) = @_;

   if (defined $bjid) {
      my @p = $self->presences ($jid, bare_jid $bjid);

      use sort 'stable';

      @p = sort {
         ($a->{show} eq 'unavailable') <=> ($b->{show} eq 'unavailable')
      } sort {
         $b->{priority} <=> $a->{priority}
      } @p;

      #d# warn "PRESENCES:\n------------------\n"
      #d#      . join (",\n", map { "$_->{show} <<< $_->{priority} <<< $_->{jid}" } @p)
      #d#      . "\n-----------------\n";

      return @p ? $p[0] : ();

   } else {
      $jid = stringprep_jid $jid;
      return undef unless exists $self->{p}->{$jid};

      my @p;
      for my $bjid (keys %{$self->{p}->{$jid}}) {
         my ($p) = $self->highest_prio_presence ($jid, $bjid);
         push @p, $p if defined $p;
      }

      return @p;
   }
}

sub clear_contact_presences {
   my ($self, $jid, $bjid) = @_;
   delete $self->{p}->{stringprep_jid $jid}->{prep_bare_jid $bjid};
}

=back

=head1 PRESENCE METHODS

=over 4

=cut

sub _int_handle_subscription {
   my ($self, $resjid, $from, $node) = @_;

   my $type   = $node->attr ('type');
   my $status = {
      status     => $node->meta->{status},
      all_status => $node->meta->{all_status}
   };

   if ($type eq 'subscribe') {
      $self->{subsc_reqs}->{$resjid}->{bare_jid $from} = {
         from    => bare_jid ($from),
         node    => $node, 
         comment => $status
      };

      if (delete $self->{subsc_mutual}->{$resjid}->{stringprep_jid $from}) {
         $self->handle_subscription_request ($resjid, $from, 1, 0);
         return;
      }

      $self->subscription_request ($resjid, bare_jid ($from), $status);
   }
}

sub send_subscription_request {
   my ($self, $resjid, $jid, $allow_mutual, $comment) = @_;

   $resjid = stringprep_jid $resjid;
   $jid    = stringprep_jid $jid;

   $self->{extendable}->send (new_presence (
       subscribe => undef, $comment, undef, src => $resjid, to => $jid));

   if ($allow_mutual) {
      $self->{subsc_mutual}->{$resjid}->{$jid} = 1;
   }
}

sub send_unsubscription {
   my ($self, $resjid, $jid, $mutual, $comment) = @_;

   $self->{extendable}->send (new_presence (
       unsubscribe => undef, $comment, undef, src => $resjid, to => $jid));

   if ($mutual) {
      $self->{extendable}->send (new_presence (
          unsubscribed => undef, $comment, undef, src => $resjid, to => $jid));
   }
}

sub pending_subscription_requests {
   my ($self, $resjid) = @_;
   values %{$self->{subsc_reqs}->{stringprep_jid $resjid}}
}

sub handle_subscription_request {
   my ($self, $resjid, $jid, $subscribe, $mutual, $comment) = @_;

   $jid = $jid->{from} if ref $jid;

   $resjid = stringprep_jid $resjid;
   $jid    = prep_bare_jid $jid;

   return unless (exists $self->{subsc_reqs}->{$resjid})
                 && (exists $self->{subsc_reqs}->{$resjid}->{$jid});

   delete $self->{subsc_reqs}->{$resjid}->{$jid};
   my $pres;

   if ($subscribe) {
      $self->{extendable}->send (new_presence (
         subscribed => undef, $comment, undef, src => $resjid, to => $jid));

      if ($mutual) {
         $self->{extendable}->send (new_presence (
            subscribe => undef, $comment, undef, src => $resjid, to => $jid));
      }

   } else {
      $self->{extendable}->send (new_presence (
         unsubscribed => undef, $comment, undef, src => $resjid, to => $jid));
   }
}

=back

=head1 EVENTS

These events are emitted (via the L<Object::Event> interface)
by an extension object:

=over 4

=item generated_presence => $node

Whenever this extension generates a presence update for some
entity this event is emitted. It can be used (for example by the
'Entity Capabilities' extension) to add further children elements
to the presence.

=cut

sub generated_presence { }

sub self { }

sub change { }

sub subscription_request { }

sub subscribed { }

sub unsubscribed { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
