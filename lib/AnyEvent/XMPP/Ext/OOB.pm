package AnyEvent::XMPP::Ext::OOB;
use AnyEvent::XMPP;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/new_iq new_reply new_error/;
use AnyEvent::XMPP::Node qw/simxml/;
use Scalar::Util qw/weaken/;
use strict;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::OOB - XEP-0066 Out of Band Data

=head1 SYNOPSIS

   my $ext = $con->add_ext ('OOB');

   # Example for receiving OOB data via AnyEvent::HTTP:

   use AnyEvent::HTTP;
   $ext->reg_cb (
      oob_recv => sub {
         my ($ext, $node, $oob_data) = @_;

         if (defined $node->attr ('from')) {
            http_get $oob_data->{url}, sub {
               my ($data) = @_;
               unless (defined $data) {
                  $ext->reply_failure ($node, 'not-found');
                  return;
               }

               # ... write $data out to disk

               $ext->reply_success ($node);
            };
         } else {
            $ext->reply_failure ($node, 'reject');
         }
      }
   );

   # Example for sending OOB data:

   $ext->send_url (
      $src_jid,  # the source JID (the full JID of your own connected resource)
      $dest_jid, # destination JID
      'http://www.ta-sa.org/data/imgs/laughing_man_big_2.png',
      'Some pic I made',
      sub {
         my ($error) = @_;

         if ($error) { # then error
            # ...
         } else { # everything fine
            # ...
         }
      }
   );

=head1 DESCRIPTION

This module provides a helper abstraction for handling out of band
data as specified in XEP-0066.

There is are also some utility function defined to get for example the
oob info from an XML element:

=head1 FUNCTIONS

=over 4

=item B<url_from_node ($node)>

This function extracts the URL and optionally a description
field from the XML element in C<$node> (which must be a
L<AnyEvent::XMPP::Node>).

C<$node> must be the XML node which contains the C<url> and optionally C<desc>
element (which is eg. a <x xmlns='jabber:x:oob'> element)!

(This method searches both, the jabber:x:oob and jabber:iq:oob namespaces for
the C<url> and C<desc> elements).

It returns a hash reference which should have following structure:

   {
      url  => "http://someurl.org/mycoolparty.jpg",
      desc => "That was a party!",
   }

If nothing was found this method returns nothing (undef).

=cut

sub url_from_node {
   my ($node) = @_;

   my ($url)   = $node->find_all ([qw/x_oob url/]);
   my ($desc)  = $node->find_all ([qw/x_oob desc/]);
   my ($url2)  = $node->find_all ([qw/iq_oob url/]);
   my ($desc2) = $node->find_all ([qw/iq_oob desc/]);
   $url  ||= $url2;
   $desc ||= $desc2;

   defined $url
      ?  { url => $url->text, desc => ($desc ? $desc->text : undef) }
      : ()
}

=back

=head1 METHODS

=over 4

=cut

sub disco_feature { (xmpp_ns ('x_oob'), xmpp_ns ('iq_oob')) }

sub init {
   my ($self) = @_;

   $self->{extendable}->reg_cb (
      ext_before_recv_iq => sub {
         my ($extdbl, $node) = @_;

         for ($node->find_all ([qw/iq_oob query/])) {
            $self->event (oob_recv => $node, url_from_node ($_));
            $extdbl->stop_event
         }
      }
   );
}

=item B<reply_success ($node)>

This method replies to the sender of the oob that the URL
was retrieved successfully.

C<$node> is the C<$node> argument of the C<oob_recv> event you want to reply
to.

=cut

sub reply_success {
   my ($self, $node) = @_;

   $self->{extendable}->send (new_reply ($node));
}

=item B<reply_failure ($node, $type)>

This method replies to the sender that either the transfer was rejected
or it was not fount.

If the transfer was rejects you have to set C<$type> to 'reject',
otherwise C<$type> must be 'not-found'.

C<$node> is the C<$node> argument of the C<oob_recv> event you want to reply
to.

=cut

sub reply_failure {
   my ($self, $node, $type) = @_;

   $self->{extendable}->send (
      new_reply ($node, create => [
         $node->nodes,
         new_error ($node,
            $type eq 'reject'
               ? ('cancel', 'item-not-found')
               : ('modify', 'not-acceptable'))
      ], type => 'error'));
}

=item B<send_url ($src, $jid, $url, $desc, $cb)>

This method sends a out of band file transfer request to C<$jid> from
your resource C<$src>.
C<$url> is the URL that the other one has to download. C<$desc> is an optional
description string (human readable) for the file pointed at by the url and
can be undef when you don't want to transmit any description.

C<$cb> is a callback that will be called once the transfer is successful.

The first argument to the callback will either be undef in case of success
or 'reject' when the other side rejected the file or 'not-found' if the other
side was unable to download the file.

=cut

sub send_url {
   my ($self, $src, $jid, $url, $desc, $cb) = @_;

   $self->{extendable}->send (new_iq (
      set =>
         src => $src,
         to  => $jid,
      create => { node => {
         dns => iq_oob => name => 'query', childs => [
            { name => 'url', childs => [ $url ] },
            { name => 'desc', (defined $desc ? (childs => [ $desc ]) : ()) }
         ]
      } },
      cb => sub {
         my ($n, $e) = @_;

         $cb->($e
               ? ($e->condition eq 'item-not-found' ? 'not-found' : 'reject')
               : ()) if $cb;
      }
   ));
}

=back

=head1 EVENTS

These events can be registered to whith C<reg_cb>:

=over 4

=item oob_recv => $node, $url

This event is generated whenever someone wants to send you a out of band data file.
C<$url> is a hash reference like it's returned by C<url_from_node>.

C<$node> is the L<AnyEvent::XMPP::Node> of the IQ request, you can get the senders
JID from the 'from' attribute of it.

If you fetched the file successfully you have to call C<reply_success>.
If you want to reject the file or couldn't get it call C<reply_failure>.

=back

=cut

1
