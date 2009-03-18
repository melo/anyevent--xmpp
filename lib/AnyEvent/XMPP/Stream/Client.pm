package AnyEvent::XMPP::Stream::Client;
use strict;
use AnyEvent;
use AnyEvent::XMPP::IQTracker;
use AnyEvent::XMPP::Authenticator;
use AnyEvent::XMPP::Util qw/split_jid join_jid dump_twig_xml stringprep_jid cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Error;
use AnyEvent::XMPP::ResourceManager;
use Carp qw/croak/;

use base qw/AnyEvent::XMPP::Stream/;

__PACKAGE__->inherit_event_methods_from (qw/AnyEvent::XMPP::Stream/);
__PACKAGE__->hand_event_methods_down_from (qw/AnyEvent::XMPP::Stream/);

our $DEBUG = 1;

=head1 NAME

AnyEvent::XMPP::Stream - XMPP client stream (RFC 3920).

=head1 SYNOPSIS

   use AnyEvent::XMPP::Stream::Client;

   my $con =
      AnyEvent::XMPP::Stream::Client->new (
         jid => "abc@jabber.org/AnyEvent::XMPP",
         password => 'secret123',
      );

   $con->reg_cb (stream_ready => sub { print "XMPP stream ready!\n" });

   $con->connect; # will do non-blocking connect

=head1 DESCRIPTION

This module represents a XMPP stream as described in RFC 3920.

It implements the L<AnyEvent::XMPP::Delivery> interface for stanza delivery.
It's a subclass of L<AnyEvent::XMPP::Stream> and it inherits the event
interface of L<Object::Event>. Please see L<Object::Event> for further
information about registering event callbacks.

This module only handles basic XMPP stream connecting, authentication and
resource binding and not advanced stuff like roster management, presence
handling and account management. For a more advanced class see
L<AnyEvent::XMPP::IM>, which provides most of the features described in RFC
3921.

=head1 METHODS

=over 4

=item $con = AnyEvent::XMPP::Stream->new (%args)

Following arguments can be passed in C<%args>:

=over 4

=item jid => $jid

This can be used to set the settings C<username>, C<domain>
(and optionally C<resource>) from a C<$jid>.

=item username => $username

This is your C<$username> (the userpart in the JID);

Note: You have to take care that the stringprep profile for
nodes can be applied at: C<$username>. Otherwise the server
might signal an error. See L<AnyEvent::XMPP::Util> for utility functions
to check this.

B<NOTE:> This field has no effect if C<jid> is given!

=item domain => $domain

If you didn't provide a C<jid> (see above) you have to set the
C<username> which you want to connect as (see above) and the
C<$domain> to connect to.

B<NOTE:> This field has no effect if C<jid> is given!

=item resource => $resource

If this argument is given C<$resource> will be passed as desired
resource on resource binding.

Note: You have to take care that the stringprep profile for
resources can be applied at: C<$resource>. Otherwise the server
might signal an error. See L<AnyEvent::XMPP::Util> for utility functions
to check this.

=item password => $password

This is the password for the C<username> above.

=item host => $host

This parameter specifies the hostname where we are going
to connect to. The default for this is the C<domain> of the C<jid>.

B<NOTE:> To disable DNS SRV lookup you need to specify the port B<number>
yourself. See C<port> below.

=item port => $port

This is optional, the default value for C<$port> is 'xmpp-client=5222', which
will used as C<$service> argument to C<tcp_connect> of L<AnyEvent::Socket>.
B<NOTE:> If you specify the port number here (instead of 'xmpp-client=5222'),
B<no> DNS SRV lookup will be done when connecting.

=item connect_timeout => $timeout

This sets the connection timeout. If the socket connect takes too long
a C<disconnect> event will be generated with an appropriate error message.
If this argument is not given no timeout is installed for the connects.

=item whitespace_ping_interval => $interval

This will set the whitespace ping interval (in seconds). The default interval
is 60 seconds.  You can disable the whitespace ping by setting C<$interval> to
0.

=item use_host_as_sasl_hostname => $bool

This is a special parameter for people who might want to use GSSAPI SASL
mechanism. It will cause the value of the C<host> parameter (see above) to be
passed to the SASL mechanisms, instead of the C<domain> of the JID.

This flag is provided until support for XEP 0233 is deployed, which
will fix the hostname issue w.r.t. GSSAPI SASL.

=item disable_ssl => $bool

If C<$bool> is true no SSL will be used.

=item old_style_ssl => $bool

If C<$bool> is true the TLS handshake will be initiated when the TCP
connection was established. This is useful if you have to connect to
an old Jabber server, with old-style SSL connections on port 5223.

But that practice has been discouraged in XMPP, and a TLS handshake is done
after the XML stream has been established. Only use this option if you know
what you are doing.

=item disable_sasl => $bool

If C<$bool> is true SASL will NOT be used to authenticate with the server, even
if it advertises SASL through stream features.  Alternative authentication
methods will be used, such as IQ Auth (XEP-0078) if the server offers it.

=item disable_iq_auth => $bool

This disables the use of IQ Auth (XEP-0078) for authentication, you might want
to exclude it because it's deprecated and insecure. (However, I want to reach a
maximum in compatibility with L<AnyEvent::XMPP> so I'm not disabling this by
default.

See also C<disable_old_jabber_authentication> below.

=item anal_iq_auth => $bool

This enables the anal iq auth mechanism that will first look in the stream
features before trying to start iq authentication. Yes, servers don't always
advertise what they can. I only implemented this option for my test suite.

=item disable_old_jabber_authentication => $bool

If C<$bool> is a true value, then the B<VERY> old style authentication method
with B<VERY> old jabber server won't be used when a <stream> start tag from the server
without version attribute is received.

The B<VERY> old style authentication method is per default enabled to ensure
maximum compatibility with old jabber implementations. The old method works as
follows: When a <stream> start tag is received from the server with no
'version' attribute IQ Auth (XEP-0078) will be initiated to authenticate with
the server.

Please note that the old authentication method will fail if C<disable_iq_auth>
is true.

=item default_stream_namespace => $namespace_uri

B<NOTE:> Only use this if you B<really> know what you are doing!

This will set the default stream "XML" namespace. The default is 'client'.

=item stream_version_override => $version

B<NOTE:> Only use if you B<really> know what you are doing!

This will override the stream version which is sent in the XMPP stream
initiation element. This is currently only used by the tests which
set C<$version> to '0.9' for testing IQ authentication with ejabberd.

=back

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = $class->SUPER::new (@_);

   if ($self->{jid}) {
      my ($user, $host, $res) = split_jid (delete $self->{jid});
      $self->{username} = $user;
      $self->{domain}   = $host;
      $self->{resource} = $res if defined $res;
   }

   unless (defined $self->{username}) {
      croak "username or node part of JID required\n";
   }

   unless (defined $self->{username}) {
      croak "password required\n";
   }

   $self->{host} = $self->{domain}    unless defined $self->{host};
   $self->{port} = 'xmpp-client=5222' unless defined $self->{port};

   $self->reg_cb (
      ext_before_stream_start => sub {
         my ($self, $node) = @_;

         $self->{stream_id}  = $node->attr ('id');
         $self->{server_jid} = $node->attr ('from');
         $self->{stream_start_cnt}++;
      },
      ext_after_stream_start => sub {
         my ($self, $node) = @_;

         # This is some very bad "hack" for _very_ old jabber
         # servers to work with AnyEvent::XMPP
         if ($self->{stream_start_cnt} == 1 # only for first stream!
             && not (defined $node->attr ('version'))
             && not ($self->{disable_iq_auth})
             && not ($self->{disable_old_jabber_authentication})
             && not ($self->{authenticated})) {

            $self->pre_authentication;
         }
      },
      connected => sub {
         my ($self) = @_;

         if ($self->{connect_timeout}) {
            $self->{timeout} =
               AnyEvent->timer (after => $self->{connect_timeout}, cb => sub {
                  delete $self->{timeout};
                  $self->disconnect ("connection timeout reached in authentication.");
               });
         }

         if ($self->{old_style_ssl}) {
            $self->starttls;
         }

         $self->send_header;
      },
      ext_before_stream_ready => sub {
         my ($self) = @_;
         delete $self->{timeout};
      },
      recv_features => 50 => sub {
         my ($self, $node) = @_;

         if (not ($self->{disable_ssl}) && $node->meta->{tls}) {
            if (not $self->{ssl_enabled}) {
               $self->stop_event;

               $self->send (simxml (node => { dns => 'tls', name => 'starttls' }));

               $self->reg_cb (
                  ext_before_recv => sub {
                     my ($self, $node) = @_;

                     my $type = $node->meta->{type};

                     if ($type eq 'tls_proceed') {
                        $self->starttls;
                        $self->unreg_me;
                        $self->send_header;

                     } elsif ($type eq 'tls_failure') {
                        $self->error (
                           AnyEvent::XMPP::Error->new (text => 'tls negotiation failed')
                        );
                        $self->disconnect ("TLS handshake failure");
                        $self->unreg_me;
                     }
                  }
               );
            }
         }
      },
      recv_features => 40 => sub {
         my ($self, $node) = @_;

         if (not $self->{authenticated}) {
            $self->stop_event;
            $self->pre_authentication ($node);
         }
      },
      ext_after_pre_authentication => sub {
         my ($self, $node) = @_;

         $self->start_authenticator ($node);
      },
      recv_features => 30 => sub {
         my ($self, $node) = @_;

         if (not defined ($self->{jid}) && $node->meta->{bind}) {
            $self->{res_manager}->bind ($self->{resource}, sub {
               my ($jid, $error) = @_;

               if ($error) {
                  # TODO FIXME: make proper error?!
                  $self->error ($error);

               } else {
                  $self->{jid} = $jid;
                  $self->stream_ready ($jid);
               }
            });
         }
      }
   );

   return $self;
}

sub cleanup_state {
   my ($self) = @_;

   delete $self->{jid};
   delete $self->{timeout};
   delete $self->{server_jid};
   delete $self->{stream_id};
   delete $self->{authenticated};
   delete $self->{res_manager};
   delete $self->{stream_start_cnt};

   if ($self->{tracker}) {
      $self->{tracker}->disconnect;
      delete $self->{tracker};
   }

   if ($self->{authenticator}) {
      $self->{authenticator}->disconnect;
      delete $self->{authenticator};
   }

   if ($self->{res_manager}) {
      delete $self->{res_manager};
   }
}

sub cleanup {
   my ($self) = @_;

   $self->cleanup_state;
   $self->SUPER::cleanup;
}

sub init {
   my ($self) = @_;

   $self->cleanup_state;

   $self->{tracker} = AnyEvent::XMPP::IQTracker->new;
   $self->{res_manager} =
      AnyEvent::XMPP::ResourceManager->new (
         connection => $self
      );
}

sub send_header {
   my ($self) = @_;

   $self->SUPER::send_header (
      $self->{stream_version_override}, to => $self->{domain}
   );
}

=item $con->connect ()

This method will try to connect to the XMPP server, specified by the
C<domain> or C<host> parameters to C<new>. The emitted events
are the same as documented for the C<connect> method of L<AnyEvent::XMPP::Stream>.

=cut

sub connect {
   my ($self) = @_;

   $self->init;

   $self->SUPER::connect ($self->{host}, $self->{port}, $self->{connect_timeout});
}

=item $con->jid ()

After the stream has been bound to a resource the JID can be retrieved via this
method.

=cut

sub jid { $_[0]->{jid} }

=item $con->credentials ()

This method returns the configured account credentials as list:
username, domain, password and desired resource (may be undefined).

=cut

sub credentials {
   my ($self) = @_;
   ($self->{username}, $self->{domain}, $self->{password}, $self->{resource})
}

=item $con->features ()

Returns the last received C<features> stanza in form of an
L<AnyEvent::XMPP::Node> object.

=cut

sub features { $_[0]->{features} }

=item $con->stream_id ()

This is the ID of this stream that was given us by the server.

=cut

sub stream_id { $_[0]->{stream_id} }

=item $con->is_ready ()

Returns a true value if the stream is ready (connected, authenticated and
a resource is bound).

=cut

sub is_ready {
   $_[0]->is_connected && $_[0]->{authenticated} && defined $_[0]->{jid}
}

=item $con->send ($node)

This method is used to send an XMPP stanza directly over
the connection. The type of C<$node> is L<AnyEvent::XMPP::Node>.

=cut

sub start_authenticator {
   my ($self, $node) = @_;

   $self->{authenticator}
      = AnyEvent::XMPP::Authenticator->new (connection => $self);

   $self->{authenticator}->reg_cb (
      auth => sub {
         my ($auth, $jid) = @_;
         $self->{authenticated} = 1;

         if (defined $jid) {
            $self->{jid} = $jid;
            $self->stream_ready ($jid);

         } else {
            $self->reinit;
            $self->send_header;
         }

         $self->{authenticator}->disconnect;
         delete $self->{authenticator};
      },
      auth_fail => sub {
         my ($auth, $error) = @_;
         $self->error ($error);
         $self->disconnect ("authentication failed");

         $self->{authenticator}->disconnect;
         delete $self->{authenticator};
      }
   );

   $self->{authenticator}->start ($node);
}

=back

=head1 EVENTS

The L<AnyEvent::XMPP::Stream::Client> class is derived from
L<AnyEvent::XMPP::Stream>, all events that are emitted there are also emitted
by objects of this class.  Please consult the documentation for
L<AnyEvent::XMPP:Stream> and L<Object::Event> for details about registering
event callbacks.

NODE: Every callback gets as it's first argument the L<AnyEvent::XMPP::Stream>
object. 

These events are additional or changed events are available:

=over 4

=item pre_authentication

This is an event that is emitted when the XMPP stream reached a
stage when all preliminary handshaking is done and authentication
is about to begin.

This is a good place to start in band registration, see also
L<AnyEvent::XMPP::Ext::Registration>.

=cut

__PACKAGE__->hand_event_methods_down (qw/pre_authentication/);
sub pre_authentication { }

=item stream_ready

This event is emitted when authentication was performed and a resource
was bound.

=cut

__PACKAGE__->hand_event_methods_down (qw/stream_ready/);
sub stream_ready { 
   my ($self) = @_;

   $self->source_available (stringprep_jid $self->{jid});

   if ($DEBUG) {
      print "stream ready!\n";
   }
}

=item recv => $node

See also L<AnyEvent::XMPP::Stream> about the semantics of this event.

The special thing with L<AnyEvent::XMPP::Stream::Client> is that all C<recv>
events for stanzas before the stream C<is_ready> (see above) are intercepted.
This means, you will only receive this event for iq, message and presence
stanzas when the stream was successfully established, authenticated and bound.

This is also the main event for L<AnyEvent::XMPP::Stream::Client> to handle any
kind of incoming stanzas. So if you register an event callback for
C<before_recv> you are able to intercept any stanzas before this class gets a
chance to look at them. (Please only do this if you know what you are doing, of
course).

Please note that upon receiving a stanza the C<src> and C<dest> meta fields of
it are defaulted to the server JID (C<src>) and your full JID (C<dest>).

=cut

sub recv {
   my ($self, $node) = @_;

   unless ($self->is_ready) {
      $self->stop_event;
   }

   if (defined $self->{jid}) {
      $node->meta->{dest} = stringprep_jid $self->{jid};
   }

   if (defined $self->{server_jid}) {
      $node->meta->{src} = stringprep_jid $self->{server_jid};
   }

   $self->{tracker}->handle_stanza ($node);

   my $type = $node->meta->{type};

   if ($type eq 'features') {
      $self->{features} = $node;
      $self->recv_features ($node);
   }
}

sub send {
   my ($self, $node) = @_;

   $self->{tracker}->register ($node);

   # XXX: This was code before we found out that from/to are not
   #      good for storing the source/dest for internal routing...
   #if ($node->name eq 'iq'
   #    || $node->name eq 'message' 
   #    || $node->name eq 'presence') {

   #   #if (cmp_jid ($node->attr ('to'), $self->{server_jid})) {
   #   #  # $node->attr (to => undef);
   #   #}

   #   if (cmp_jid ($node->attr ('from'), $self->{jid})) {
   #      $node->attr (from => undef);
   #   }
   #}
}

=item recv_features => $node

Emitted whenever the stream features have been received.
This event is used to drive the handshake process.

=cut

__PACKAGE__->hand_event_methods_down (qw/recv_features/);
sub recv_features { }

=item source_available => $jid

This is emitted whenever the client resource C<$jid> was successfully bound.
This event is emitted when the C<stream_ready> event is emitted and has
nearly the same semantics, only that it's provided to meet the requirements
of the L<AnyEvent::XMPP::Delivery> interface.

=cut

__PACKAGE__->hand_event_methods_down (qw/source_available/);
sub source_available { }

=item source_unavailable => $jid

This is emitted whenever the client resource C<$jid> lost the connection
to the server and thus becomes unavailable for sending. This event
is emitted whenever a C<disconnected> event is emitted and is
provided to meed the requirements of the L<AnyEvent::XMPP::Delivery>
interface.

=cut

sub disconnected {
   my ($self) = @_;
   $self->source_unavailable (stringprep_jid $self->{jid});
}

__PACKAGE__->hand_event_methods_down (qw/source_unavailable/);
sub source_unavailable { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 CONTRIBUTORS

melo - design suggestions

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP
