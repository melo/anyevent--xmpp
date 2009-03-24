package AnyEvent::XMPP::Authenticator;
use strict;
no warnings;
use MIME::Base64;
use Digest::SHA1 qw/sha1_hex/;
use Authen::SASL qw/Perl/;
use AnyEvent::XMPP::IQTracker;
use AnyEvent::XMPP::Util qw/join_jid new_iq/;
use AnyEvent::XMPP::Node qw/simxml/;
use Encode;
use Digest::SHA1 qw/sha1_hex/;

use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::Authenticator - Authenticator helper module

=head1 SYNOPSIS

   use AnyEvent::XMPP::Authenticator qw/start_auth/;

=head2 DESCRIPTION

This is a helper module for L<AnyEvent::XMPP::Stream>, it
handles all the tiny bigs of client authentication.

=head2 METHODS

=over 4

=item new (connection => $con)

Creates a new authenticator object for the L<AnyEvent::XMPP::Stream>
C<$con>.

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (@_, enable_methods => 1);

   $self->{regid} =
      $self->{connection}->reg_cb (
         ext_before_recv => sub {
            my ($con, $node) = @_;

            my $type = $node->meta->{type};

            if ($type eq 'sasl_challenge') {
               $self->construct_sasl_response ($node->text);

            } elsif ($type eq 'sasl_success') {
               $self->auth;
               $con->unreg_me;

            } elsif ($type eq 'sasl_failure') {
               my $error = AnyEvent::XMPP::Error::SASL->new (node => $node);
               $self->auth_fail ($error);
               $con->unreg_me;
            }
         }
      );

   return $self
}

sub construct_sasl_auth {
   my ($self, $mechs, $user, $hostname, $pass) = @_;

   my $data;
    
   my $found_mech = 0;
   while (!$found_mech) {
      my $sasl = Authen::SASL->new (
         mechanism => join (' ', @$mechs),
         callback => {
            # XXX: removed authname, because it ensures maximum connectivitiy
            #      along multiple server implementations - XMPP is such a crap
            #        authname => $user . '@' . $domain,
            user => $user,
            pass => $pass,
         }
      );

      my $mech = $sasl->client_new ('xmpp', $hostname);
      $data = $mech->client_start;

      if (my $e = $mech->error) {
         @$mechs = grep { $_ ne $mech->mechanism } @$mechs;
         die "No usable SASL mechanism found (tried: "
             . join (', ', @$mechs)
             . ")!\n"
            unless @$mechs;
         next;
      }

      $found_mech = 1;
      $self->{sasl} = $mech;
   }

   $self->{connection}->send (simxml (
      node => {
         dns => 'sasl',
         name => 'auth', attrs => [ mechanism => $self->{sasl}->mechanism ],
         childs => [
            MIME::Base64::encode_base64 ($data, '')
         ]
      }
   ));
}

sub construct_sasl_response {
   my ($self, $challenge) = @_;

   $challenge = MIME::Base64::decode_base64 ($challenge);
   my $ret = '';

   unless ($challenge =~ /rspauth=/) { # rspauth basically means: we are done
      $ret = $self->{sasl}->client_step ($challenge);

      if (my $e = $self->{sasl}->error) {
         die "Error in SASL authentication in client step with challenge: '" . $e . "'\n";
      }
   }

   $self->{connection}->send (simxml (
      node => {
         dns => 'sasl',
         name => 'response', childs => [ MIME::Base64::encode_base64 ($ret, '') ]
      }
   ));
}

sub send_sasl_auth {
   my ($self, $mechs) = @_;

   my $con = $self->{connection};

   my ($username, $domain, $password, $resource) = $con->credentials;

   $self->construct_sasl_auth (
      $mechs,
      $username,
      ($con->{use_host_as_sasl_hostname} ? $con->{host} : $domain),
      $password
   );
}

sub request_iq_fields {
   my ($self, $cb) = @_;

   $self->{connection}->send (new_iq (get => create => {
      node => { dns => 'auth', name => 'query',
         # heh, something i've seen on some ejabberd site:
         # childs => [ { name => 'username', childs => [ $self->{username} ] } ] 
      }
   }, cb => sub {
      my ($node, $err) = @_;

      if ($err) {
         $cb->();
         
      } else {
         my (@query) = $node->find_all ([qw/auth query/]);

         if (@query) {
            my $fields = {};

            for (qw/username password digest resource/) {
               if ($query[0]->find_all ([qw/auth/, $_])) {
                  $fields->{$_} = 1;
               }
            }

            $cb->($fields);
         } else {
            $cb->();
         }
      }
   }));
}

sub send_iq_auth {
   my ($self, $fields) = @_;

   my ($username, $domain, $password, $resource) =
      $self->{connection}->credentials;

   my $want_resource = $fields->{resource};
   $resource ||= 'AnyEvent::XMPP';

   if ($fields->{digest}) {
      my $out_password = encode ("utf-8", $password);
      my $stream_id    = $self->{connection}->stream_header->attr ('id');
      my $out          = lc sha1_hex ($stream_id . $out_password);

      $fields = {
         username => $username,
         digest   => $out,
      }

   } else {
      $fields = {
         username => $username,
         password => $password
      }
   }

   if ($want_resource && defined $resource) {
      $fields->{resource} = $resource
   }

   $self->{connection}->send (new_iq (
      set => create => {
         node => {
            dns => 'auth',
            name => 'query',
            childs => [
               map { {
                  name => $_,
                  childs => [ $fields->{$_} ]
               } } reverse sort keys %$fields
            ]
         }
      }, cb => sub {
         my ($res, $err) = @_;

         if ($err) {
            $self->auth_fail ($err);
         } else {
            $self->auth (join_jid ($username, $domain, $resource));
         }
      }
   ));
}

sub start {
   my ($self, $node) = @_;

   my $default_iq_fields = { username => 1, password => 1, resource => 1 };

   unless ($node) {
      # This is a hack for jabberd 1.4.2, VERY OLD Jabber stuff.
      $self->send_iq_auth ($default_iq_fields);
      return;
   }

   # Yes, and also iq-auth isn't correctly advertised in the
   # stream features! We all love the depreacted XEP-0078, eh?
   # => this means we don't check it ...

   if (not ($self->{connection}->{disable_sasl}) && $node->meta->{sasl_mechs}) {
      $self->send_sasl_auth ($node->meta->{sasl_mechs});

   } elsif (not $self->{connection}->{disable_iq_auth}) {
      $self->request_iq_fields (sub {
         my ($fields) = @_;

         if (defined $fields) {
            $self->send_iq_auth ($fields);
         } else {
            $self->send_iq_auth ($default_iq_fields);
         }
      });

   } else {
      die "No authentication method left, neither SASL or IQ auth.\n";
   }
}

=back

=head2 EVENTS

=over 4

=item auth => $jid

This event is emitted when we successfully authenticated.
C<$jid> is defined if the authentication also bound a resource for
you. If C<$jid> is undefined no resource was bound yet and the XMPP stream
needs to be reinitiated (because we are finished with SASL authentication).

=cut

sub auth { }

=item auth_fail => $error

This event is emitted when an authentication failure occurred.
The C<$error> object will either be a L<AnyEvent::XMPP::Error::IQ>
object or ...

FIXME TODO

=cut

sub auth_fail { }

sub disconnect {
   my ($self) = @_;
   $self->remove_all_callbacks;
   $self->{connection}->unreg_cb ($self->{regid});
   delete $self->{sasl};
   delete $self->{connection};
}

=back

=head1 AnyEvent::XMPP::Error::SASL

AnyEvent::XMPP::Error::SASL - SASL authentication error

Subclass of L<AnyEvent::XMPP::Error>

=cut

package AnyEvent::XMPP::Error::SASL;
use AnyEvent::XMPP::Error;
use strict;
our @ISA = qw/AnyEvent::XMPP::Error/;

sub init {
   my ($self) = @_;

   my $error;
   for ($self->{node}->nodes) {
      $error = $_->name;
      last
   }

   $self->{error_cond} = $error;
}

=head2 METHODS

=over 4

=item B<condition ()>

Returns the error condition, which might be one of:

   aborted
   incorrect-encoding
   invalid-authzid
   invalid-mechanism
   mechanism-too-weak
   not-authorized
   temporary-auth-failure

=cut

sub condition {
   $_[0]->{error_cond}
}

sub string {
   my ($self) = @_;

   sprintf "sasl error: %s",
      $self->condition
}

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

