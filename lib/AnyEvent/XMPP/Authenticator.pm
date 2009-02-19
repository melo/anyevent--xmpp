package AnyEvent::XMPP::Authenticator;
use strict;
no warnings;

=head1 NAME

AnyEvent::XMPP::Authenticator - Authenticator helper module

=head1 SYNOPSIS

   use AnyEvent::XMPP::Authenticator qw/start_auth/;

=head2 DESCRIPTION

This is a helper module for L<AnyEvent::XMPP::Connection>, it
handles all the tiny bigs of client authentication.

=head2 METHODS

=over 4

=item B<new (connection => $con)>

Creates a new authenticator object for the L<AnyEvent::XMPP::Connection>
C<$con>.

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{connection}->reg_cb (
      ext_before_handle_stanza => sub {
         my ($con, $stanza) = @_;

#   } elsif ($node->eq (sasl => 'challenge')) {
#      $self->handle_sasl_challenge ($node);
#
#   } elsif ($node->eq (sasl => 'success')) {
#      $self->handle_sasl_success ($node);
#
#   } elsif ($node->eq (sasl => 'failure')) {
#      my $error = AnyEvent::XMPP::Error::SASL->new (node => $node);
#      $self->event (sasl_error => $error);
#      $self->disconnect ('SASL authentication failure: ' . $error->string);
#

      }
   );

   return $self
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


sub start {
   my ($self, $stanza) = @_;

   unless ($stanza) {
      $self->start_old_style_authentication;
      return;
   }
}

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

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

