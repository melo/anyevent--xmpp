package AnyEvent::XMPP::Stream;
use strict;
no warnings;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::XMPP::Parser;
use AnyEvent::XMPP::Writer;
use AnyEvent::XMPP::Error::Exception;
use Encode;

use base qw/Object::Event::Methods/;

=head1 NAME

AnyEvent::XMPP::Stream - TCP/TLS connection with XMPP "XML" protocol messages.

=head1 SYNOPSIS

=head2 DESCRIPTION

This module provides basic TCP/TLS connectivity and knows how to parse
XMPP stanzas and partial "XML" tags. And provides the ability to send stanzas.

It's used by L<AnyEvent::XMPP::Stream> and L<AnyEvent::XMPP::Component>.

=head2 METHODS

=over 4

=item B<new (%args)>

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (
      language                 => 'en',
      default_stream_namespace => 'client',
   );

   $self->{writer} =
      AnyEvent::XMPP::Writer->new (
         stream_ns => $self->{default_stream_namespace}
      );

   $self->{parser} =
      AnyEvent::XMPP::Parser->new ($self->{default_stream_namespace});

   $self->{parser}->reg_cb (
      stream_start => sub {
         my ($parser, $node) = @_;
         $self->stream_start ($node);
      },
      received_stanza_xml => sub {
         my ($parser, $node) = @_;
         $self->recv_stanza ($node);
      },
      received_stanza => sub {
         my ($parser, $stanza) = @_;
         $self->recv ($stanza);
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

   $self->set_exception_cb (sub {
      my ($ev, $ex) = @_;

      $self->error (
         AnyEvent::XMPP::Error::Exception->new (
            exception => "(" . $ev->dump . "): $ex",
            context   => 'stream event callback'
         )
      );
   });

   $self->reg_cb (
      ext_after_send => sub {
         my ($self, $stanza) = @_;

         $self->write_data ($stanza->serialize ($self->{writer}));
      },
      ext_after_error => sub {
         my ($self, $error) = @_;

         warn "unhandled error in AnyEvent::XMPP::Stream: " . $error->string . "."
              ." Please read the documentation of the 'error' event, to inhibit this"
              ." warning!\n";
      }
   );

   return $self
}

sub cleanup_flags {
   my ($self) = @_;

   delete $self->{connected};
   delete $self->{ssl_enabled};
   delete $self->{peer_host};
   delete $self->{peer_port};
}

sub reinit {
   my ($self) = @_;

   $self->{parser}->init;
   $self->{writer}->init;
}

=item $con->connect ($host, $service, $timeout)

Try to connect (non blocking) to the domain and port passed in C<new>.

The connection is performed non blocking, so this method will just
trigger the connection process. The event C<connected> will be emitted
when the connection was successfully established.

When the C<connected> event was triggered the connection will do further
authentication and resource registration handshakes. When all handshakes
are done the C<stream_ready> event will be emitted.

If the connection try was not successful a C<disconnected> event
will be generated and maybe also an C<error> event with a more detailed
error report.

You can reconnect anytime by calling this method again, which
will close an existing connection and reinitialize everything.

=cut

sub connect {
   my ($self, $host, $service, $timeout) = @_;

   if ($self->{handle}) {
      $self->disconnect ("reconnecting");
   }

   $self->cleanup_flags;

   $self->{handle} =
      tcp_connect $host, $service, sub {
         my ($fh, $peer_host, $peer_port) = @_;

         unless ($fh) {
            $self->disconnect ("Couldn't create socket to $host:$service: $!");
            return;
         }

         $self->set_handle ($fh, $peer_host, $peer_port);
         
      }, sub { $timeout };
}

sub set_handle {
   my ($self, $fh, $peer_host, $peer_port) = @_;

   $self->cleanup_flags;

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

   $self->{connected} = 1;
   $self->{peer_host} = $peer_host;
   $self->{peer_port} = $peer_port;
   
   $self->reinit;
   $self->connected ($peer_host, $peer_port);
}

sub write_data {
   my ($self, $data) = @_;

   $self->{handle}->push_write (encode_utf8 ($data));
   $self->debug_send ($data);
   $self->{handle}->on_drain (sub { $self->send_buffer_empty })
      if $self->is_connected;
}

sub enable_ssl {
   my ($self) = @_;

   $self->{handle}->starttls ('connect');
   $self->{ssl_enabled} = 1;
}

=item $stream->send_header ($lang, $version, %attrs)

This method sends the XMPP stream header. For more details about the
meaning of the arguments C<$lang>, C<$version> and C<%attrs>
consult the documentation of the C<init_stream> method of C<AnyEvent::XMPP::Writer>.

=cut

sub send_header {
   my ($self, $lang, $version, %attrs) = @_;
   return unless $self->{connected};

   $self->write_data ($self->{writer}->init_stream ($lang, $version, %attrs));
}

=item $con->send_end ()

This method will send a closing stream stanza if we are connected.
Please use this method whenever you want to close a connection gracefully.

=cut

sub send_end {
   my ($self) = @_;
   return unless $self->{connected};

   $self->write_data ($self->{writer}->end_of_stream);
}

=item $con->disconnect ($msg)

Call this method if you want to kill the connection forcefully.
C<$msg> is a human readable message for logging purposes.

=cut

sub disconnect {
   my ($self, $msg) = @_;

   delete $self->{handle};

   if ($self->{connected}) {
      $self->disconnected ($self->{peer_host}, $self->{peer_port}, $msg);
   } else {
      $self->connect_error ($self->{peer_host}, $self->{peer_port}, $msg);
   }

   $self->cleanup_flags;
}

=item $con->is_connected ()

Returns true if the connection is connected and ready to send and receive
any kind of stanzas or protocol messages.

=cut

sub is_connected {
   my ($self) = @_;
   $self->{handle} && $self->{connected}
}

=item $stream->cleanup ()

=cut

sub cleanup {
   my ($self) = @_;

   $self->cleanup_flags;

   if ($self->{handle}) {
      delete $self->{handle};
   }

   if ($self->{writer}) {
      delete $self->{writer};
   }

   if ($self->{parser}) {
      $self->{parser}->remove_all_callbacks;
      $self->{parser}->cleanup;
      delete $self->{parser};
   }
}

=back

=head1 EVENTS

=over 4

=item error => $error

=cut

sub error { }

=item connected => $peer_host, $peer_port

=cut

sub connected { }

=item connect_error => $peer_host, $peer_port

=cut

sub connect_error { }

=item disconnected => $peer_host, $peer_port, $reason

=cut

sub disconnected { }

=item stream_start => $node

=cut

sub stream_start { }

=item recv_stanza_xml => $node

=cut

sub recv_stanza_xml { }

=item recv => $stanza

=cut

sub recv { }

=item send => $stanza

=cut

sub send { }

=item send_buffer_empty

=cut

sub send_buffer_empty { }

=item debug_recv => $data

=cut

sub debug_recv { }

=item debug_send => $data

=cut

sub debug_send { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

