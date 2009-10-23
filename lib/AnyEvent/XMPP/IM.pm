package AnyEvent::XMPP::IM;
use strict;
no warnings;
use Carp qw/croak/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::Util qw/node_jid stringprep_jid is_bare_jid new_message/;
use base qw/AnyEvent::XMPP::CM/;

our $VERSION = '0.1';

=head1 NAME

AnyEvent::XMPP::IM - An XMPP instant messaging client

=head1 SYNOPSIS

=head2 DESCRIPTION

This class acts as highlevel XMPP client. It derives connection management from
L<AnyEvent::XMPP::CM> and adds some extensions and default behaviour for you.

This module will load some extensions for you as stated in the next section
(L<Extensions>). You can always customize the extensions by getting them via
the C<get_ext> method (see also L<AnyEvent::XMPP::Extendable>).

If you need a lot of customizations you should think about building your own
class and maybe use L<AnyEvent::XMPP::CM> yourself. This module is just a small
helper to give people some bare set of usable defaults.

=head2 Extensions

Following extensions are loaded:

=over 4

=item AnyEvent::XMPP::Ext::Disco

=item AnyEvent::XMPP::Ext::Version

=item AnyEvent::XMPP::Ext::Presence

NOTE: It will send an initial available presence.

=item AnyEvent::XMPP::Ext::Roster

NOTE: The roster will be fetched automatically when you connect
to a server.

=item AnyEvent::XMPP::Ext::Delay

=item AnyEvent::XMPP::Ext::LangExtract

=item AnyEvent::XMPP::Ext::MsgTracker

=item AnyEvent::XMPP::Ext::MUC

=back

=head2 METHODS

=over 4

=item my $im = AnyEvent::XMPP::IM->new (%args)

This class takes the same arguments as the L<AnyEvent::XMPP::CM>
class, as it is derived from it. And additionally you
can provide these:

=over 4

=item client_name => $name

This option is the name of the client (usually for Disco and Version
replies).
The default is 'AnyEvent::XMPP::IM';

=item client_version => $version

This option is the version of the client (usually for Version replies).
Default is the version of this module.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (
      client_name    => 'AnyEvent::XMPP::IM',
      client_version => $VERSION,
      @_
   );

   $self->{disco}   = $self->add_ext ('Disco');
   $self->{version} = $self->add_ext ('Version');
   $self->{pres}    = $self->add_ext ('Presence');
   $self->{rost}    = $self->add_ext ('Roster');
   $self->{delay}   = $self->add_ext ('Delay');
   $self->{lang}    = $self->add_ext ('LangExtract');
   $self->{track}   = $self->add_ext ('MsgTracker');
   $self->{muc}     = $self->add_ext ('MUC');

   $self->init_exts;

   return $self
}

sub init_exts {
   my ($self) = @_;

   $self->{disco}->set_identity ('client', 'console', $self->{client_name});

   $self->{version}->set_name ($self->{client_name});
   $self->{version}->set_version ($self->{client_version});
   $self->{version}->set_os (`uname -s -r -m -o`);

   $self->{pres}->set_default (available => undef, 10);

   $self->{rost}->auto_fetch;

   $self->{delay}->enable_unix_timestamp;
}

=item $im->send_message ($from_jid, $to_jid, $msg)

This method will send a text message C<$msg> from your account C<$from_jid> to
the JID C<$to_jid>.

It will be checked whether there exists a connected connection for
C<$from_jid>, and if not, an exception is thrown.

This method will also do the 'right thing' in case C<$to_jid> is
the JID of a MUC room you are joined.

In case C<$to_jid> is a bare JID it will also do the 'right thing' in case you
have a conversation with it. (The messages will be sent using the
L<AnyEvent::XMPP::Ext::MsgTracker> extension).

=cut

sub send_message {
   my ($self, $fromjid, $tojid, $msg) = @_;

   my $con = $self->get_connection ($fromjid)
      or croak "$fromjid not connected, you can only send "
               . "messages to connected connections";

   my $resjid = $con->jid;

   if ($self->{muc}->joined_room ($resjid, $tojid)
       && is_bare_jid ($tojid)) {

      $self->{im}->send (
         new_message (groupchat => $msg, src => $resjid, to => $tojid));
      return;
   }

   $self->{track}->send (
      new_message (chat => $msg, src => $resjid, to => $tojid));
}

=item my $nick = $im->nickname_for_jid ($accountjid, $jid)

This method will give you a nickname for the C<$jid> for the account
C<$accountjid>.  The nickname you set in the roster will be checked, and if
none is set some other default will be used (for instance the node part of the
JID).

=cut

sub nickname_for_jid {
   my ($self, $resjid, $jid) = @_;

   my $item = $self->{rost}->get ($resjid, $jid)
      or return node_jid ($jid);

   $item->{name} ne ''
      ? $item->{name}
      : node_jid ($jid)
}

=head1 EVENTS

These events are emitted by this object via the L<Object::Event> API:

=over 4

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
