package AnyEvent::XMPP::Connection;
use strict;
use AnyEvent;
use AnyEvent::XMPP::Parser;
use AnyEvent::XMPP::Writer;
use AnyEvent::XMPP::Util qw/split_jid join_jid simxml/;
use AnyEvent::XMPP::SimpleConnection;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Extendable;
use AnyEvent::XMPP::Error;
use Object::Event;
use Digest::SHA1 qw/sha1_hex/;
use Encode;

use base qw/Object::Event/;

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
      $self->{handle}->on_drain;
      delete $self->{handle};
   }

   delete $self->{connected};
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

   $self->{parser} = new AnyEvent::XMPP::Parser $self->default_namespace;
   $self->{parser}->reg_cb (
      stream_start => sub {
         my ($parser, $node) = @_;

         $self->{stream_id} = $node->attr ('id');

         # This is some very bad "hack" for _very_ old jabber
         # servers to work with AnyEvent::XMPP
         if (not defined $node->attr ('version')) {
            $self->start_old_style_authentication
               if (not $self->{disable_iq_auth})
                  && (not $self->{disable_old_jabber_authentication})
         }
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
            );
         );

         $self->disconnect ("xml error: $ex: $data");
      }
   );

   $self->{writer} = AnyEvent::XMPP::Writer->new (
      write_cb => sub { $self->write_data ($_[0]) }
   );
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
      ($self->{host}, $self->{port}, $self->{connect_timeout})

   $self->{handle} = tcp_connect $host, $service, sub {
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
   $self->send_stanza_data ($data);

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

Returns the last received <features> tag in form of an L<AnyEvent::XMPP::Node> object.

=cut

sub features { $_[0]->{features} }

=item B<stream_id>

This is the ID of this stream that was given us by the server.

=cut

sub stream_id { $_[0]->{stream_id} }

sub send_sasl_auth {
   my ($self, @mechs) = @_;

   for (qw/username password domain/) {
      die "No '$_' argument given to new, but '$_' is required\n"
         unless defined $self->{$_};
   }

   $self->{writer}->send_sasl_auth (
      [map { $_->text } @mechs],
      $self->{username},
      ($self->{use_host_as_sasl_hostname}
         ? $self->{host}
         : $self->{domain}),
      $self->{password}
   );
}

sub handle_stream_features {
   my ($self, $node) = @_;
   my @bind  = $node->find_all ([qw/bind bind/]);
   my @tls   = $node->find_all ([qw/tls starttls/]);

   # and yet another weird thingie: in XEP-0077 it's said that
   # the register feature MAY be advertised by the server. That means:
   # it MAY not be advertised even if it is available... so we don't
   # care about it...
   # my @reg   = $node->find_all ([qw/register register/]);

   if (not ($self->{disable_ssl}) && not ($self->{ssl_enabled}) && @tls) {
      $self->{writer}->send_starttls;

   } elsif (not $self->{authenticated}) {
      my $continue = 1;
      my (@ret) = $self->event (stream_pre_authentication => \$continue);
      $continue = pop @ret if @ret;
      if ($continue) {
         $self->authenticate;
      }

   } elsif (@bind) {
      $self->do_rebind ($self->{resource});
   }
}

=item B<authenticate>

This method should be called after the C<stream_pre_authentication> event
was emitted to continue authentication of the stream.

Usually this method only has to be called when you want to register before
you authenticate. See also the documentation of the C<stream_pre_authentication>
event below.

=cut

sub authenticate {
   my ($self) = @_;
   my $node = $self->{features};
   my @mechs = $node->find_all ([qw/sasl mechanisms/], [qw/sasl mechanism/]);

   # Yes, and also iq-auth isn't correctly advertised in the
   # stream features! We all love the depreacted XEP-0078, eh?
   my @iqa = $node->find_all ([qw/iqauth auth/]);

   if (not ($self->{disable_sasl}) && @mechs) {
      $self->send_sasl_auth (@mechs)

   } elsif (not $self->{disable_iq_auth}) {
      if ($self->{anal_iq_auth} && !@iqa) {
         if (@iqa) {
            $self->do_iq_auth;
         } else {
            die "No authentication method left after anal iq auth, neither SASL or IQ auth.\n";
         }
      } else {
         $self->do_iq_auth;
      }

   } else {
      die "No authentication method left, neither SASL or IQ auth.\n";
   }
}

sub handle_sasl_challenge {
   my ($self, $node) = @_;
   $self->{writer}->send_sasl_response ($node->text);
}

sub handle_sasl_success {
   my ($self, $node) = @_;
   $self->{authenticated} = 1;
   $self->{parser}->init;
   $self->{writer}->init;
   $self->{writer}->send_init_stream (
      $self->{language}, $self->{domain}, $self->{stream_namespace}
   );
}

sub handle_error {
   my ($self, $node) = @_;
   my $error = AnyEvent::XMPP::Error::Stream->new (node => $node);

   $self->event (stream_error => $error);
   $self->{writer}->send_end_of_stream;
}

# This is a hack for jabberd 1.4.2, VERY OLD Jabber stuff.
sub start_old_style_authentication {
   my ($self) = @_;

   $self->{features}
      = AnyEvent::XMPP::Node->new (
          'http://etherx.jabber.org/streams', 'features', [], $self->{parser}
        );

   my $continue = 1;
   my (@ret) = $self->event (stream_pre_authentication => \$continue);
   $continue = pop @ret if @ret;
   if ($continue) {
      $self->do_iq_auth;
   }
}

sub do_iq_auth {
   my ($self) = @_;

   if ($self->{anal_iq_auth}) {
      $self->send_iq (get => {
         defns => 'auth', node => { ns => 'auth', name => 'query',
            # heh, something i've seen on some ejabberd site:
            # childs => [ { name => 'username', childs => [ $self->{username} ] } ] 
         }
      }, sub {
         my ($n, $e) = @_;
         if ($e) {
            $self->event (iq_auth_error =>
               AnyEvent::XMPP::Error::IQAuth->new (context => 'iq_error', iq_error => $e)
            );
         } else {
            my $fields = {};
            my (@query) = $n->find_all ([qw/auth query/]);
            if (@query) {
               for (qw/username password digest resource/) {
                  if ($query[0]->find_all ([qw/auth/, $_])) {
                     $fields->{$_} = 1;
                  }
               }

               $self->do_iq_auth_send ($fields);
            } else {
               $self->event (iq_auth_error =>
                  AnyEvent::XMPP::Error::IQAuth->new (context => 'no_fields')
               );
            }
         }
      });
   } else {
      $self->do_iq_auth_send ({ username => 1, password => 1, resource => 1 });
   }
}

sub do_iq_auth_send {
   my ($self, $fields) = @_;

   for (qw/username password resource/) {
      die "No '$_' argument given to new, but '$_' is required\n"
         unless defined $self->{$_};
   }

   my $do_resource = $fields->{resource};
   my $password = $self->{password};

   if ($fields->{digest}) {
      my $out_password = encode ("UTF-8", $password);
      my $out = lc sha1_hex ($self->stream_id () . $out_password);
      $fields = {
         username => $self->{username},
         digest => $out,
      }

   } else {
      $fields = {
         username => $self->{username},
         password => $password
      }
   }

   if ($do_resource && defined $self->{resource}) {
      $fields->{resource} = $self->{resource}
   }

   $self->send_iq (set => {
      defns => 'auth',
      node => { ns => 'auth', name => 'query', childs => [
         map { { name => $_, childs => [ $fields->{$_} ] } } reverse sort keys %$fields
      ]}
   }, sub {
      my ($n, $e) = @_;
      if ($e) {
         $self->event (iq_auth_error =>
            AnyEvent::XMPP::Error::IQAuth->new (context => 'iq_error', iq_error => $e)
         );
      } else {
         $self->{authenticated} = 1;
         $self->{jid} = join_jid ($self->{username}, $self->{domain}, $self->{resource});
         $self->event (stream_ready => $self->{jid});
      }
   });
}

# TODO TODO
# TODO TODO
# TODO TODO
# TODO TODO
# TODO TODO
# TODO TODO
# TODO TODO
# TODO TODO
sub handle_stanza {
   my ($self, $p, $node) = @_;

   if (not defined $node) { # got stream end
      $self->disconnect ("end of 'XML' stream encountered");
      return;
   }

   my (@res) = $self->event (recv_stanza_xml => $node);
   @res = grep $_, @res;
   return if @res;

   my $def_ns = $self->default_namespace;

   if ($node->eq (stream => 'features')) {
      $self->event (stream_features => $node);
      $self->{features} = $node;
      $self->handle_stream_features ($node);

   } elsif ($node->eq (tls => 'proceed')) {
      $self->enable_ssl;
      $self->{parser}->init;
      $self->{writer}->init;
      $self->{writer}->send_init_stream (
         $self->{language}, $self->{domain}, $self->default_namespace
      );

   } elsif ($node->eq (tls => 'failure')) {
      $self->event ('tls_error');
      $self->disconnect ('TLS failure on TLS negotiation.');

   } elsif ($node->eq (sasl => 'challenge')) {
      $self->handle_sasl_challenge ($node);

   } elsif ($node->eq (sasl => 'success')) {
      $self->handle_sasl_success ($node);

   } elsif ($node->eq (sasl => 'failure')) {
      my $error = AnyEvent::XMPP::Error::SASL->new (node => $node);
      $self->event (sasl_error => $error);
      $self->disconnect ('SASL authentication failure: ' . $error->string);

   } elsif ($node->eq ($def_ns => 'iq')) {
      $self->event (iq_xml => $node);

   } elsif ($node->eq ($def_ns => 'message')) {
      $self->event (message_xml => $node);

   } elsif ($node->eq ($def_ns => 'presence')) {
      $self->event (presence_xml => $node);

   } elsif ($node->eq (stream => 'error')) {
      $self->handle_error ($node);
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

=item error => $error

This event is generated whenever some error occurred. C<$error> is an instance
of L<AnyEvent::XMPP::Error>. Trivial error reporting may look like this:

   $con->reg_cb (error => sub { warn "xmpp error: " . $_[1]->string . "\n" });

=cut

sub error { my ($self, $errorobj) = @_ }

# TODO: document events and extend Object::Event to allow attribute based
#       priorities of these methods.

sub connected {
   my ($self) = @_;

   if ($self->{old_style_ssl}) {
      $self->enable_ssl;
   }

   $self->{writer}->send_init_stream (
      $self->{language},
      $self->{domain},
      $self->default_namespace,
      $self->{stream_version_override}
   );

   $self->{connected} = 1;
}

sub disconnected {
   my ($self, $host, $port, $message) = @_;
   $self->cleanup;
};

sub send_buffer_empty {
   my ($self) = @_;
   # event
}

sub send_stanza_data {}
sub debug_recv {}
sub debug_send {}

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
