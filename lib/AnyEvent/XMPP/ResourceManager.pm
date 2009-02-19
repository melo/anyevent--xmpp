package AnyEvent::XMPP::ResourceManager;
use strict;
no warnings;
use AnyEvent::XMPP::Util qw/stringprep_jid/;
use AnyEvent::XMPP::Stanza;

=head1 NAME

AnyEvent::XMPP::ResourceManager - An XMPP stream resource manager

=head1 SYNOPSIS

=head2 DESCRIPTION

=head2 METHODS

=over 4

=item B<new (%args)>

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub add {
   my ($self, $jid) = @_;

   $self->{resources}->{stringprep_jid $jid} = 1;
}

sub any_jid {
   my ($self) = @_;
   return unless %{$self->{resources} || {}};

   my ($k) = keys %{$self->{resources}};
   $k
}

sub bind {
   my ($self, $resource, $cb) = @_;

   my $con = $self->{connection};

   my @req_res;
   if (defined $resource) {
      (@req_res) = (
         childs => [ { name => 'resource', childs => [ $resource ] } ]
      )
   }

   $con->send (new_iq (set => create => {
      defns => 'bind', node => { name => 'bind', @req_res }
   }, cb => sub {
      my ($stanza, $error) = @_;

      if ($error) {
         $cb->(undef, $error);

         ## TODO: make bind error into a seperate error class?
         #if ($error->stanza) {
         #   my ($res) = $error->stanza->node->find_all ([qw/bind bind/], [qw/bind resource/]);
         #   $self->event (bind_error => $error, ($res ? $res : $self->{resource}));
         #} else {
         #   $self->event (bind_error => $error);
         #}

      } else {
         my @jid = $stanza->node->find_all ([qw/bind bind/], [qw/bind jid/]);
         my $jid = $jid[0]->text;

         # TODO: unless ($jid) { die "Got empty JID tag from server!\n" }

         $cb->($jid);
      }
   }));
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

