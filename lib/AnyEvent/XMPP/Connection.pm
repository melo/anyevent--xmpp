package AnyEvent::XMPP::Connection;
use strict;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::XMPP::Parser;
use AnyEvent::XMPP::Writer;
use AnyEvent::XMPP::Authenticator;
use AnyEvent::XMPP::Util qw/split_jid join_jid simxml dump_twig_xml/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Error;
use AnyEvent::XMPP::Stanza;
use Object::Event;
use Digest::SHA1 qw/sha1_hex/;
use Encode;

use base qw/Object::Event/;

our $DEBUG = 1;

=head1 NAME

AnyEvent::XMPP::Connection - XML stream that implements the XMPP RFC 3920.

=head1 SYNOPSIS

   use AnyEvent::XMPP::Connection;

   my $con =
      AnyEvent::XMPP::Connection->new (
         username => "abc",
         domain   => "jabber.org",
         resource => "AnyEvent::XMPP",
         password => 'secret123',
      );

   $con->reg_cb (stream_ready => sub { print "XMPP stream ready!\n" });

   $con->connect; # will do non-blocking connect

=head1 DESCRIPTION

This module represents a XMPP stream as described in RFC 3920. You can issue
the basic XMPP XML stanzas with methods like C<send_iq>, C<send_message> and
C<send_presence>.

FIXME: DOCUMENTATION

And receive events with the C<reg_cb> event framework from the connection.

If you need instant messaging stuff please take a look at
C<AnyEvent::XMPP::IM::Connection>.

=head1 METHODS

=over 4

=item B<new (%args)>

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

=item language => $tag

This should be the language of the human readable contents that
will be transmitted over the stream. The default will be 'en'.

Please look in RFC 3066 how C<$tag> should look like.

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

=item stream_version_override => $version

B<NOTE:> Only use if you B<really> know what you are doing!

This will override the stream version which is sent in the XMPP stream
initiation element. This is currently only used by the tests which
set C<$version> to '0.9' for testing IQ authentication with ejabberd.

=back

=cut

sub default_namespace {
   return 'client';
}

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self =
      $class->SUPER::new (
         language                 => 'en',
         whitespace_ping_interval => 60,
         @_
      );

   if ($self->{jid}) {
      my ($user, $host, $res) = split_jid ($self->{jid});
      $self->{username} = $user;
      $self->{domain}   = $host;
      $self->{resource} = $res if defined $res;
   }

   $self->{host} = $self->{domain}    unless defined $self->{host};
   $self->{port} = 'xmpp-client=5222' unless defined $self->{port};

   $self->set_exception_cb (sub {
      my ($ex) = @_;
      $self->event (error =>
         AnyEvent::XMPP::Error::Exception->new (
            exception => $ex, context => 'event callback'
         )
      );
   });

   return $self;
}

sub cleanup {
   my ($self) = @_;

   if ($self->{handle}) {
      delete $self->{handle};
   }

   delete $self->{server_jid};
   delete $self->{connected};
   delete $self->{authenticator};
   delete $self->{authenticated};
   delete $self->{ssl_enabled};
   delete $self->{peer_host};
   delete $self->{peer_port};

   if ($self->{writer}) {
      delete $self->{writer};
   }

   if ($self->{parser}) {
      $self->{parser}->remove_all_callbacks;
      $self->{parser}->cleanup;
      delete $self->{parser};
   }
}

sub init {
   my ($self) = @_;

   $self->cleanup;
   $self->{stanza_id_cnt} = 0;

   $self->{parser} = new AnyEvent::XMPP::Parser $self->default_namespace;
   $self->{parser}->reg_cb (
      stream_start => sub {
         my ($parser, $node) = @_;

         $self->{stream_id} = $node->attr ('id');
         $self->{server_jid} = $node->attr ('from');

         # This is some very bad "hack" for _very_ old jabber
         # servers to work with AnyEvent::XMPP
         if (not (defined $node->attr ('version'))
             && not ($self->{disable_iq_auth})
             && not ($self->{disable_old_jabber_authentication})) {

            $self->start_authenticator;
         }
      },
      received_stanza_xml => sub {
         my ($parser, $node) = @_;

         $self->recv_stanza ($node);
      },
      received_stanza => sub {
         eval { $self->handle_stanza ($_[1]) };
         if ($@) {
            $self->error (
               AnyEvent::XMPP::Error::Exception->new (
                  exception => $@, context => 'stanza handling'
               )
            );
         }
      },
      parse_error => sub {
         my ($parser, $ex, $data) = @_;

         $self->error (
            AnyEvent::XMPP::Error::Parser->new (
               exception => $ex, data => $data
            )
         );

         $self->disconnect ("xml error: $ex: $data");
      }
   );

   $self->{writer} = AnyEvent::XMPP::Writer->new (stream_ns => $self->default_namespace);
}

=item B<connect ()>

Try to connect (non blocking) to the domain and port passed in C<new>.

The connection is performed non blocking, so this method will just
trigger the connection process. The event C<connect> will be emitted
when the connection was successfully established.

If the connection try was not successful a C<disconnect> event
will be generated with an error message.

NOTE: Please note that you can't reconnect a L<AnyEvent::XMPP::Connection>
object. You need to recreate it if you want to reconnect.

NOTE: The "XML" stream initiation is sent when the connection
was successfully connected.

=cut

sub connect {
   my ($self) = @_;

   if ($self->{connected}) {
      $self->disconnect ("reconnecting");
   }

   $self->init;

   my ($host, $service, $timeout) =
      ($self->{host}, $self->{port}, $self->{connect_timeout});

   $self->{handle} =
      tcp_connect $host, $service, sub {
         my ($fh, $peerhost, $peerport) = @_;

         unless ($fh) {
            $self->disconnect ("Couldn't create socket to $host:$service: $!");
            return;
         }

         $self->{peer_host} = $peerhost;
         $self->{peer_port} = $peerport;

         binmode $fh, ":raw";

         $self->{handle} =
            AnyEvent::Handle->new (
               fh => $fh,
               on_eof => sub {
                  $self->disconnect (
                     "EOF on connection to $self->{peer_host}:$self->{peer_port}: $!"
                  );
               },
               on_error => sub {
                  $self->disconnect (
                     "Error on connection to $self->{peer_host}:$self->{peer_port}: $!"
                  );
               },
               on_read => sub {
                  my ($hdl) = @_;
                  my $data   = $hdl->rbuf;
                  $hdl->rbuf = '';
                  $data      = decode_utf8 $data;

                  $self->debug_recv ($data);
                  $self->{parser}->feed ($data);
               },
            );
         
         $self->connected
         
      }, sub { $timeout };
}

sub write_data {
   my ($self, $data) = @_;

   $self->{handle}->push_write (encode_utf8 ($data));
   $self->{handle}->on_drain (sub {
      $self->send_buffer_empty;
   });

   $self->debug_send ($data);
}

sub enable_ssl {
   my ($self) = @_;

   $self->{handle}->starttls ('connect');
   $self->{ssl_enabled} = 1;
}


=item B<close>

This method will send a closing stream stanza if we are connected.
Please use this method whenever you want to close a connection gracefully.

=cut

sub close {
   my ($self) = @_;

   if ($self->{connected}) {
      $self->write_data ($self->{writer}->end_of_stream);
   }
}

=item B<disconnect ($msg)>

Call this method if you want to kill the connection forcefully.
C<$msg> is a human readable message for logging purposes.

=cut

sub disconnect {
   my ($self, $msg) = @_;

   $self->cleanup;

   return unless $self->{connected};

   $self->disconnected ($self->{peer_host}, $self->{peer_port}, $msg);
}

=item B<is_connected ()>

Returns true if the connection is still connected and authenticated, so
stanzas can be sent.

=cut

sub is_connected {
   my ($self) = @_;
   $self->{authenticated}
}

=item B<jid>

After the stream has been bound to a resource the JID can be retrieved via this
method.

=cut

sub jid { $_[0]->{jid} }

=item B<features>

Returns the last received C<features> stanza in form of a
L<AnyEvent::XMPP::FeatureStanza> object.

=cut

sub features { $_[0]->{features} }

=item B<stream_id>

This is the ID of this stream that was given us by the server.

=cut

sub stream_id { $_[0]->{stream_id} }

=item B<send ($stanza)>

This method is used to send an XMPP stanza directly over
the connection. 

=cut

sub send {
   my ($self, $stanza) = @_;

   if ($stanza->want_id) {
      $stanza->set_id ('c_' . ++$self->{stanza_id_cnt})
   }

   $self->send_stanza ($stanza);
   $self->write_data ($stanza->serialize ($self->{writer}));
}

sub start_authenticator {
   my ($self, $stanza) = @_;

   $self->send (new_iq (set => undef, 'elmex@192.168.5.10', create => sub {
      $_[0]->emptyTag ('def');
   }));

   return;

   $self->{authenticator}
      = AnyEvent::XMPP::Authenticator->new (connection => $self);
   $self->{authenticator}->reg_cb (
      auth => sub {
         delete $self->{authenticator};
         $self->{authenticated} = 1;
      },
      auth_fail => sub {
         my ($auth, $error) = @_;
         $self->error ($error);
         $self->disconnect ("authentication failed");
      }
   );

   $self->{authenticator}->start ($stanza);
}

sub bind_resource {
   my ($self) = @_;

}

sub get_first_bound_resource_jid {
   my ($self) = @_;
   return unless %{$self->{bound_resources} || {}};

   my ($k) = keys %{$self->{bound_resources}};
   $self->{bound_resources}->{$k}
}

sub handle_stanza {
   my ($self, $stanza) = @_;

   if (defined (my $resjid = $self->get_first_bound_resource_jid)) {
      $stanza->set_default_to ($resjid);
   }

   if (defined $self->{server_jid}) {
      $stanza->set_default_from ($self->{server_jid});
   }

   if ($stanza->type eq 'end') {
      $self->disconnect ("end of 'XML' stream encountered");
      return;
   }

   if ($self->is_connected
       && grep { $stanza->type eq $_ } qw/iq presence message/) {
       $self->recv ($stanza);
       return;
   }

   my $type = $stanza->type;

   if ($type eq 'features') {
      $self->{features} = $stanza;

      if (not ($self->{disable_ssl})
          && not ($self->{ssl_enabled})
          && $stanza->tls) {
         $self->write_data ($self->{writer}->starttls);

      } elsif (not $self->{authenticated}) {
         $self->start_authenticator ($stanza);

      } elsif ($stanza->bind) {
         $self->bind_resource;
      }

   } elsif ($type eq 'tls_proceed') {
      $self->enable_ssl;
      $self->{parser}->init;
      $self->{writer}->init;
      $self->write_data (
         $self->{writer}->init_stream ($self->{language}, $self->{domain})
      );

   } elsif ($type eq 'tls_failure') {
      $self->error (
         my $err = AnyEvent::XMPP::Error->new (text => 'tls negotiation failed')
      );
      $self->disconnect ("TLS handshake failure");

   } elsif ($type eq 'error') {
      $self->error (
         my $err = AnyEvent::XMPP::Error::Stream->new (node => $stanza->{node})
      );
      $self->disconnect ("stream error");
   }
}

=back

=head1 EVENTS

The L<AnyEvent::XMPP::Connection> class is derived from the L<Object::Event> class,
and thus inherits the event callback registering system from it. Consult the
documentation of L<Object::Event> about more details.

NODE: Every callback gets as it's first argument the L<AnyEvent::XMPP::Connection>
object. The further callback arguments are described in the following listing of
events.

These events can be registered on with C<reg_cb>:

=over 4

=item connected

This event is emitted when the TCP connection could be established.
Please wait for the C<stream_ready> event before you start sending
data.

=cut

sub connected {
   my ($self) = @_;

   if ($DEBUG) {
      print "connected to $self->{peer_host}:$self->{peer_port}\n";
   }

   if ($self->{old_style_ssl}) {
      $self->enable_ssl;
   }

   $self->write_data (
      $self->{writer}->init_stream (
         $self->{language},
         $self->{domain},
         $self->{stream_version_override}
      )
   );

   $self->{connected} = 1;
}

=item disconnected => $peer_host, $peer_port, $reason

This event is emitted when the TCP connection was disconnected, either remotely
or locally. C<$peerhost> and C<$peerport> are the host and port of the other
TCP endpoint. And C<$reason> is a human readable string which indicates the
reason for the disconnect.

=cut

sub disconnected {
   my ($self, $host, $port, $message) = @_;

   if ($DEBUG) {
      print "disconnected from $host:$port: $message\n";
   }

   $self->cleanup;
};

=item recv => $stanza

This event is emitted whenever either an IQ, presence or message XMPP stanza
has been received over a connected and authenticated connection.

This is the even you usually want to register callbacks on.

=cut

sub recv {}

=item send_buffer_empty

Whenever the write queue to the TCP connection becomes empty this
event is emitted. It is useful if you want to wait until all the
messages you've given to the connection is written out to the kernel.

FIXME: insert example here when stanza handling/sending is done

=cut

sub send_buffer_empty {
   my ($self) = @_;

   # event
}

=item handle_stanza => $stanza

This event is emitted whenever a L<AnyEvent::XMPP::Stanza> object is being
received from the parser. This event is mainly aimed at people who are up to no
good and want to intercept a stanza before L<AnyEvent::XMPP::Connection> gets a
chance to look at it. Here is an example if you want to do that:

   $con->reg_cb (before_handle_stanza => sub {
      my ($con, $stanza) = @_;

      if ($stanza ...) {
         # this stops further handling of the event
         $con->current->stop;
      }
   });

B<NOTE>: Please only do this if you know what you are doing. For normal stanza
handling please see the C<recv> event.

=item send_stanza => $stanza

This event is emitted when an L<AnyEvent::XMPP::Stanza> object is about to be
written out.

=cut

sub send_stanza {
}

=item recv_stanza => $node

This event is emitted when a complete stanza has been received.
C<$node> is the L<AnyEvent::XMPP::Node> object which represents the XML stanza.
You might want to use the C<as_string> method of L<AnyEvent::XMPP::Node> for
debugging output:

   $con->reg_cb (recv_stanza => sub {
      my ($con, $node) = @_;
      warn "recv: " . $node->as_string . "\n";
   });

=cut

sub recv_stanza {
   my ($self, $node) = @_;

   if ($DEBUG) {
      print ">>>>> $self->{peer_host}:$self->{peer_port} >>>>>\n"
            . dump_twig_xml ($node->as_string)
            . "\n";
   }
}

=item debug_recv => $data

Whenever a chunk of data has been received from the TCP/TLS connection this
event is emitted with that chunk in C<$data>. Please note that that chunk might
B<NOT> contain a complete XML stanza, it might contain a partial one or
multiple stanzas.

If you want to debug which stanzas have actually been received use
the C<recv_stanza> event!

=cut

sub debug_recv {}

=item debug_send => $data

The C<debug_send> event is emitted when the data has been given to
L<AnyEvent::Handle> for writing. C<$data> is the unicode encoded XML string
which contains exactly one stanza which has been sent.

=cut

sub debug_send {
   my ($self, $data) = @_;

   if ($DEBUG) {
      print "<<<<< $self->{peer_host}:$self->{peer_port} <<<<<\n"
            . dump_twig_xml ($data)
            . "\n";
   }
}

=item error => $error

This event is generated whenever some error occurred. C<$error> is an instance
of L<AnyEvent::XMPP::Error>. Trivial error reporting may look like this:

   $con->reg_cb (error => sub { warn "xmpp error: " . $_[1]->string . "\n" });

=cut

sub error {
   my ($self, $errorobj) = @_;

   if ($DEBUG) {
      print "EEEEE $self->{peer_host}:$self->{peer_port} EEEE: "
            . $errorobj->string . "\n";
   }
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 CONTRIBUTORS

melo - minor fixes

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP
