package AnyEvent::XMPP::Ext::Delay;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/xmpp_datetime_as_timestamp/;
use Scalar::Util qw/weaken/;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::Delay - XEP-0203 & XEP-0091: Extract delay information

=head1 SYNOPSIS

   my $delay = $con->add_ext ('Delay');

   $con->reg_cb (
      recv_message => sub {
         my ($con, $node) = @_;

         return if $node->meta->{error};

         my $delay = $node->meta->{delay};

         if ($delay) { # delayed
            print "message delayed $delay->{timestamp}"
                 ." ($delay->{from}, $delay->{reason})\n";

         } else { # either not delayed or the Delay extesion isn't loaded :)
            # ...
         }
      }
   );

   $delay->enable_unix_timestamp; # for enabling automatic xmpp_datetime_as_timestamp

=head1 DESCRIPTION

This extension will automatically extract delay elements according to
XEP-0203 and XEP-0091 from C<message> and C<presence> stanzas.

When a delay has been found it will put the following structure into the
C<delay> meta attribute of the L<AnyEvent::XMPP::Node> that represents that
stanza:

   {
      from   => <from JID>,                # often not present
      reason => <reason string for delay>, # often not present
      timestamp => $timestamp_string
   }

C<$timestamp_string> will be the timestamp delay string. It may be of the old
style legacy format (C<"CCYYMMDDThh:mm:ss">) or it can be in the new style
XEP-0082 timestamp format. You can use the C<from_xmpp_datetime> function of
L<AnyEvent::XMPP::Util> to extract further information from these timestamps.

In case you enable automatic unix timestamp extraction with the
C<enable_unix_timestamp> method there will be an additional key in the C<delay>
hash: C<unix_timestamp> which will contain the result of the
C<xmpp_datetime_as_timestamp> function of L<AnyEvent::XMPP::Util> (which
requires the L<POSIX> module).

=head1 METHODS

=over 4

=cut

sub disco_feature { }

sub init {
   my ($self) = @_;

   weaken $self;

   $self->{iq_guard} = $self->{extendable}->reg_cb (
      ext_before_recv_presence => sub { $self->analyze_delay ($_[1]) },
      ext_before_recv_message  => sub { $self->analyze_delay ($_[1]) },
   );
}

sub analyze_delay {
   my ($self, $node) = @_;

   my ($delay)    = $node->find (x_delay => 'x');
   my ($newdelay) = $node->find (delay   => 'delay');

   $delay = $newdelay if $newdelay;

   my $meta = $node->meta;

   if ($delay) {
      $meta->{delay}->{timestamp} = $delay->attr ('stamp');
      $meta->{delay}->{from}      = $delay->attr ('from');
      $meta->{delay}->{reason}    = $delay->text;

      if ($self->{unix_timestamp}) {
         $meta->{delay}->{unix_timestamp} =
            xmpp_datetime_as_timestamp ($meta->{delay}->{timestamp});
      }

   } else {
      delete $meta->{delay}
   }
}

=item $delay->enable_unix_timestamp

Enables automatic extraction of the unix timestamp (see also
C<xmpp_datetime_as_timestamp> function of L<AnyEvent::XMPP::Util>) and storage
in the delay key C<unix_timestamp>.

=cut

sub enable_unix_timestamp {
   my ($self) = @_;
   $self->{unix_timestamp} = 1;
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
