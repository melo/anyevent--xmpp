package AnyEvent::XMPP::Ext::Ping;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/stringprep_jid new_iq new_reply domain_jid/;
use Scalar::Util qw/weaken/;
use strict;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Ping - Implementation of XMPP Ping XEP-0199

=head1 SYNOPSIS

   my $con = AnyEvent::XMPP::CM->new (...);
   my $ext = $con->add_ext ('Ping');
   $ext->auto_timeout (10);

   $ext->reg_cb (
      ping_timeout => sub {
         my ($ext, $srcjid, $timeout) = @_;

         $con->get_connection ($srcjid)->disconnect ("XMPP Ping timeouted!");
      }
   );

   $ext->ping ($my_src_jid, 'ping_dest@server.tld', sub {
      my ($time, $error) = @_;
      if ($error) {
         # we got an error
      }
      # $time is a float (seconds) of the rtt/latency
   });

=head1 DESCRIPTION

This extension implements XEP-0199: XMPP Ping.
It allows you to define a automatic ping timeouter that will disconnect
dead connections (which didn't reply to a ping after N seconds). See also
the documentation of the C<enable_timeout> method below.

It also allows you to send pings to any XMPP entity you like and
will measure the time it took if you got L<Time::HiRes>.

=head1 METHODS

=over 4

=item $ext->auto_timeout ($timeout)

This method enables automatic connection timeout of new connections. It calls
C<enable_timeout> (see below) for every new source that became available
(see C<source_available> event of the L<AnyEvent::XMPP::Delivery> interface).

This is useful if you want connections that have this extension automatically
timeouted. In particular this is useful with classes like L<AnyEvent::XMPP::CM>
and L<AnyEvent::XMPP::Stream::Client>.

=cut

sub auto_timeout {
   my ($self, $timeout) = @_;

   $self->{autotimeout} = $timeout;

   return if defined $self->{auto_tout_guard};

   weaken $self;

   $self->{auto_tout_guard} =
      $self->{extendable}->reg_cb (
         ext_before_source_available => sub {
            my ($self, $jid) = @_;
            $self->enable_timeout ($jid, \$self->{autotimeout});
         },
         ext_before_source_unavailable => sub {
            my ($self, $jid) = @_;
            $self->disable_timeout ($jid);
         }
      );
}

=item $ext->enable_timeout ($src, $timeout)

This enables a periodical ping from the source JID C<$src> to it's server,
C<$timeout> must be the seconds that the ping intervals last.

If the reply didn't come until the next ping would be sent the C<ping_timeout>
event is emitted on the extension object C<$ext>.

Please note that there already is a basic timeout mechanism
for dead TCP connections in L<AnyEvent::XMPP::Stream> already: See
the C<whitespace_ping_interval> configuration variable for a stream
there. It then will depend on TCP timeouts to disconnect the connection.

Use C<enable_timeout> and C<auto_timeout> only if you really feel
like you need an explicit timeout for your connections.

=cut

sub enable_timeout {
   my ($self, $jid, $timeout) = @_;
   my $rt = $timeout;
   unless (ref $timeout) {
      $rt = \$timeout;
   }
   $self->_start_cust_timeout ($jid, $rt);
}

sub disable_timeout {
   my ($self, $jid) = @_;
   delete $self->{cust_timeouts}->{stringprep_jid $jid};
}

sub _start_cust_timeout {
   my ($self, $jid, $rtimeout) = @_;

   weaken $self;

   $self->{cust_timeouts}->{stringprep_jid $jid} =
      AnyEvent->timer (after => $$rtimeout, cb => sub {
         delete $self->{cust_timeouts}->{stringprep_jid $jid};

         $self->ping ($jid, undef, sub {
            my ($t, $e) = @_;

            if (defined ($e) && $e->condition eq 'client-timeout') {
               $self->ping_timeout ($jid, $$rtimeout);

            } else {
               $self->_start_cust_timeout ($jid, $rtimeout)
            }
         }, $$rtimeout);
      });
}

sub init {
   my ($self) = @_;

   if (eval "require Time::HiRes;") {
      $self->{has_time_hires} = 1;
   }

   weaken $self;

   $self->{iq_guard} = $self->{extendable}->reg_cb (
      ext_before_recv_iq => sub {
         my ($ext, $node) = @_;

         if ($self->handle_ping ($node)) {
            $ext->stop_event;
            return 1;
         }

         ()
      }
   );
}

sub disco_feature { xmpp_ns ('ping') }

sub handle_ping {
   my ($self, $node) = @_;

   if (my ($q) = $node->find_all ([qw/ping ping/])) {
      unless ($self->{ignore_pings}) {
         $self->{extendable}->send (new_reply ($node));
      }
      return 1
   }

   0
}

=item $ext->ping ($src, $dest, $cb->($latency, $error), $timeout)

This method sends a ping request to C<$dest> via the source JID C<$src>.
If C<$dest> is undefined the ping will be sent to the connected
server.

C<$timeout> is an optional timeout for the ping request, if C<$timeout> is not
given the default IQ timeout for the connection is the relevant timeout.

The first argument (C<$latency>) to C<$cb> will be the seconds of the round
trip time for that request (If you have L<Time::HiRes> it will also have
sub-second accuracy).
And the second argument (C<$error>) will be an L<AnyEvent::XMPP::Error::IQ>
if the ping failed either due to an error or an IQ timeout.

=cut

sub ping {
   my ($self, $src, $jid, $cb, $timeout) = @_;

   my $time = 0;
   if ($self->{has_time_hires}) {
      $time = [Time::HiRes::gettimeofday ()];
   } else {
      $time = time;
   }

   $self->{extendable}->send (new_iq (
      get =>
         src => $src,
         (defined $jid     ? (to      => $jid)     : ()),
         (defined $timeout ? (timeout => $timeout) : ()),
      create => { node => { dns => 'ping', name => 'ping' } },
      cb => sub {
         my ($n, $e) = @_;

         my $elap = 0;
         if ($self->{has_time_hires}) {
            $elap = Time::HiRes::tv_interval ($time, [Time::HiRes::gettimeofday ()]);
         } else {
            $elap = time - $time;
         }

         $cb->($elap, $e);
      },
   ));
}

=item B<ignore_pings ($bool)>

This method is mostly for testing, it tells this extension
to ignore all ping requests and will prevent any response from
being sent.

=cut

sub ignore_pings {
   my ($self, $enable) = @_;
   $self->{ignore_pings} = $enable;
}

=back

=head1 EVENTS

These events are emitted by this extension:

=over 4

=item ping_timeout => $srcjid

Please consult the C<enable_timeout> method for documentation of this event.

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
