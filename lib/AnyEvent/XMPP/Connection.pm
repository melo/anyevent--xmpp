package AnyEvent::XMPP::Connection;
use strict;
no warnings;

use base qw/Object::Event::Methods/;

=head1 NAME

AnyEvent::XMPP::Connection - TCP/TLS connection with XMPP "XML" protocol messages.

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

   return $self
}

sub cleanup {
   my ($self) = @_;

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

   delete $self->{connected};
   delete $self->{ssl_enabled};
   delete $self->{peer_host};
   delete $self->{peer_port};
   delete $self->{timeout};
}

sub init {
   my ($self) = @_;

   $self->cleanup;

   $self->{parser} = new AnyEvent::XMPP::Parser $self->{default_stream_namespace};
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

   $self->{writer} =
      AnyEvent::XMPP::Writer->new (
         stream_ns => $self->{default_stream_namespace}
      );
}

sub reinit {
   my ($self, $first) = @_;

   $self->{parser}->init;
   $self->{writer}->init;
   $self->write_data (
      # version override should only be neccessary at the first init stream.
      $self->{writer}->init_stream (
         $self->{language}, $self->{domain},
         ($first ? ($self->{stream_version_override}) : ())
      )
   );
}

=item $con->connect ()

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
         
         if ($timeout) {
            $self->{timeout} =
               AnyEvent->timer (after => $timeout, cb => sub {
                  $self->disconnect ("XMPP stream establishment timeout");
               });
         }

         $self->connected ($peerhost, $peerport);
         
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

=item $con->close ()

This method will send a closing stream stanza if we are connected.
Please use this method whenever you want to close a connection gracefully.

=cut

sub close {
   my ($self) = @_;

   if ($self->{connected}) {
      $self->write_data ($self->{writer}->end_of_stream);
   }
}

=item $con->disconnect ($msg)

Call this method if you want to kill the connection forcefully.
C<$msg> is a human readable message for logging purposes.

=cut

sub disconnect {
   my ($self, $msg) = @_;

   if ($self->{connected}) {
      $self->disconnected ($self->{peer_host}, $self->{peer_port}, $msg);
   } else {
      $self->connect_error ($self->{peer_host}, $self->{peer_port}, $msg);
   }

   $self->cleanup;
}

=item $con->is_connected ()

Returns true if the connection is still connected and authenticated, so
stanzas can be sent.

=cut

sub is_connected {
   my ($self) = @_;
   $self->{authenticated}
}

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

