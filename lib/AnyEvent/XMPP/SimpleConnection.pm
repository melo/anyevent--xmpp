package AnyEvent::XMPP::SimpleConnection;
use strict;
no warnings;

use AnyEvent;
use IO::Handle;
use Encode;
use AnyEvent::Socket;
use AnyEvent::Handle;

=head1 NAME

AnyEvent::XMPP::SimpleConnection - Low level TCP/TLS connection

=head1 DESCRIPTION

This module only implements the basic low level socket and SSL handling stuff.
It is used by L<AnyEvent::XMPP::Connection> and you shouldn't have to mess
with this module at all.

It uses L<AnyEvent::Socket> and L<AnyEvent::Handle> for TCP and SSL.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = {
      @_
   };
   bless $self, $class;
   return $self;
}

sub connect {
   my ($self, $host, $service, $timeout) = @_;

   $self->{handle}
      and return 1;

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
               $self->disconnect ("EOF on connection to $self->{peer_host}:$self->{peer_port}: $!");
            },
            autocork => 1,
            on_error => sub {
               $self->disconnect ("Error on connection to $self->{peer_host}:$self->{peer_port}: $!");
            },
            on_read => sub {
               my ($hdl) = @_;
               my $data   = $hdl->rbuf;
               $hdl->rbuf = '';
               $data      = decode_utf8 $data;
               $self->handle_data (\$data);
            },
         );
      
      $self->connected
      
   }, sub {
      $timeout
   };

   return 1;
}

sub end_sockets {
   my ($self) = @_;
   delete $self->{handle};
}

sub write_data {
   my ($self, $data) = @_;

   $self->{handle}->push_write (encode_utf8 ($data));
   $self->{handle}->on_drain (sub {
      $self->send_buffer_empty;
   });
}

sub enable_ssl {
   my ($self) = @_;

   $self->{handle}->starttls ('connect');
   $self->{ssl_enabled} = 1;
}

sub disconnect {
   my ($self, $msg) = @_;
   $self->end_sockets;
   $self->disconnected ($self->{peer_host}, $self->{peer_port}, $msg);
   $self->remove_all_callbacks;
}

sub connected {
   # subclass responsibility
}

sub handle_data {
   # subclass responsibility
}

sub send_buffer_empty {
   # subclass responsibility
}

sub block_until_send_buffer_empty {
   # subclass responsibility
}

sub disconnected {
   # subclass responsibility
}

1;
