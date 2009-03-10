package AnyEvent::XMPP::Ext::Registration;
use strict;
use AnyEvent::XMPP::Util qw/new_iq/;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Ext::RegisterForm;

=head1 NAME

AnyEvent::XMPP::Ext::Registration - Handles all tasks of in band registration

=head1 SYNOPSIS

   my $con = AnyEvent::XMPP::Connection->new (...);
   my $reg = AnyEvent::XMPP::Ext::Registration->new (delivery => $con);

   $con->reg_cb (pre_authentication => sub {
      my ($con) = @_;
      my $event = $con->stop_event;

      $reg->send_registration_request (sub {
         my ($reg, $form, $error) = @_;

         if ($error) {
            # error handlin
         } else {
            my $af = $form->try_fillout_registration ("tester", "secret");

            $reg->submit_form ($af, sub {
               my ($reg, $ok, $error, $form) = @_;

               if ($ok) { # registered successfully!
                  $event->(); # continue authentication

               } else {   # error
                  if ($form) { # we got an alternative form!
                     # fill it out and submit it with C<submit_form> again
                  }
               }
            });

         }
      });
   });

=head1 DESCRIPTION

This module handles all tasks of in band registration that are possible and
specified by XEP-0077. It's mainly a helper class that eases some tasks such
as submitting and retrieving a form.

=cut

=head1 METHODS

=over 4

=item new (%args)

This is the constructor for a registration object.

=over 4

=item delivery

This must be an object implementing the L<AnyEvent::XMPP::Delivery> interface.
This argument is required.

=back

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = bless { @_ }, $class;
   $self
}

=item $reg->quick_registration ($username, $password, $cb->($error))

This method will invoke C<send_registration_request>, C<try_fillout_registration>
and C<submit_form> for you in a quick and dirty fashion. It's more or less a
heuristic, as the information required for a registration form might differ
a lot from server to server, and deployment to deployment. And it usually requires
user interaction.

If C<$error> is undef the registration was 'probably' successful :-)

=cut

sub quick_registration {
   my ($self, $username, $password, $cb) = @_;

   $self->send_registration_request (sub {
      my ($reg, $form, $error) = @_;

      if ($error) {
         $cb->($error);
         return;
      } 

      my $af = $form->try_fillout_registration ($username, $password);
      $reg->submit_form ($af, sub {
         my ($reg, $ok, $error, $form) = @_;

         if ($ok) {
            $cb->();
         } else {
            $cb->($error);
         }
      });
   });
}

=item $reg->send_registration_request ($cb->($reg, $form, $error))

This method sends a register form request.
C<$cb> will be called when either the form arrived or
an error occured.

The first argument of C<$cb> is always C<$self>.
If the form arrived the second argument of C<$cb> will be
a L<AnyEvent::XMPP::Ext::RegisterForm> object.
If an error occured the second argument will be undef
and the third argument will be a L<AnyEvent::XMPP::Error::Register>
object.

For hints how L<AnyEvent::XMPP::Ext::RegisterForm> should be filled
out look in XEP-0077. Either you have legacy form fields, out of band
data or a data form.

See also L<try_fillout_registration> in L<AnyEvent::XMPP::Ext::RegisterForm>.

=cut

sub send_registration_request {
   my ($self, $cb) = @_;

   $self->{delivery}->send (new_iq (get => create => {
      defns => 'register', node => { name => 'query' }
   }, cb => sub {
      my ($node, $error) = @_;

      my $form;
      if ($node) {
         $form = AnyEvent::XMPP::Ext::RegisterForm->new;
         $form->init_from_node ($node);

      } else {
         $error =
            AnyEvent::XMPP::Error::Register->new (
               node => $error->node, register_state => 'register'
            );
      }

      $cb->($self, $form, $error);
   }));
}

sub _error_or_form_cb {
   my ($self, $e, $cb) = @_;

   $e = $e->node;

   my $error =
      AnyEvent::XMPP::Error::Register->new (
         node => $e, register_state => 'submit'
      );

   if ($e->node->find_all ([qw/register query/], [qw/data_form x/])) {
      my $form = AnyEvent::XMPP::Ext::RegisterForm->new;
      $form->init_from_node ($e);

      $cb->($self, 0, $error, $form)
   } else {
      $cb->($self, 0, $error, undef)
   }
}

=item send_unregistration_request ($cb->($reg, $ok, $error, $form))

This method sends an unregistration request.

For description of the semantics of the callback in C<$cb>
please look in the description of the C<submit_form> method below.

=cut

sub send_unregistration_request {
   my ($self, $cb) = @_;

   my $con = $self->{connection};

   $self->{delivery}->send (new_iq (set => create => {
      defns => 'register',
      node => { name => 'query', childs => [ { name => 'remove' } ] }
   }, cb => sub {
      my ($node, $error) = @_;

      if ($node) {
         $cb->($self, 1)
      } else {
         $self->_error_or_form_cb ($error, $cb);
      }
   }));
}

=item send_password_change_request ($username, $password, $cb->($reg, $ok, $error, $form))

This method sends a password change request for the user C<$username>
with the new password C<$password>.

For description of the semantics of the callback in C<$cb>
please look in the description of the C<submit_form> method below.

=cut

sub send_password_change_request {
   my ($self, $username, $password, $cb) = @_;

   my $con = $self->{connection};

   $con->send_iq (set => {
      defns => 'register',
      node => { ns => 'register', name => 'query', childs => [
         { ns => 'register', name => 'username', childs => [ $username ] },
         { ns => 'register', name => 'password', childs => [ $password ] },
      ]}
   }, sub {
      my ($node, $error) = @_;

      if ($node) {
         $cb->($self, 1, undef, undef)

      } else {
         $self->_error_or_form_cb ($error, $cb);
      }
   });
}

=item submit_form ($form, $cb->($reg, $ok, $error, $form))

This method submits the C<$form> which should be of
type L<AnyEvent::XMPP::Ext::RegisterForm> and should be an answer
form.

C<$cb> is the callback that will be called once the form has been submitted and
either an error or success was received.

The first argument to the callback
will be the L<AnyEvent::XMPP::Ext::Registration> object, the second will be a
boolean value that is true when the form was successfully transmitted and
everything is fine.  If the second argument is false then the third argument is
a L<AnyEvent::XMPP::Error::Register> object.  If the error contained a data form
which is required to successfully make the request then the fourth argument
will be a L<AnyEvent::XMPP::Ext::RegisterForm> which you should fill out and send
again with C<submit_form>.

For the semantics of such an error form see also XEP-0077.

=cut

sub submit_form {
   my ($self, $form, $cb) = @_;

   $self->{delivery}->send (new_iq (set => create => {
      defns => 'register',
      node => { ns => 'register', name => 'query', childs => [
         $form->answer_form_to_simxml
      ]}
   }, cb => sub {
      my ($node, $error) = @_;

      if ($node) {
         $cb->($self, 1, undef, undef)

      } else {
         $self->_error_or_form_cb ($error, $cb);
      }
   }));
}

=back

=head1 AnyEvent::XMPP::Error::Register;

This is an error class for in-band registration errors,
it's derived from L<AnyEvent::XMPP::Error::IQ>.

=cut

package AnyEvent::XMPP::Error::Register;
use AnyEvent::XMPP::Error;
use strict;
use base qw/AnyEvent::XMPP::Error::IQ/;

=head1 METHODS

=over 4

=item register_state ()

Returns the state of registration, one of:

   register
   unregister
   submit

=cut

sub register_state {
   my ($self) = @_;
   $self->{register_state}
}

sub string {
   my ($self) = @_;

   sprintf "ibb registration error (in %s): %s",
      $self->register_state,
      $self->SUPER::string
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP::Ext::Registration
