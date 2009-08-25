package AnyEvent::XMPP::Ext::Disco::Provider;

use strict;
use warnings;
use base qw( AnyEvent::XMPP::Ext::CB );

sub handle_iq_get {
   my ($self, $conn, $node, $proto) = @_;
   
   if ($proto eq 'http://jabber.org/protocol/disco#info') {
      my (@ids, %features);
      
      $conn->event('build_disco_info', \@ids, \%features);
      
      
   }
   elsif ($proto eq 'http://jabber.org/protocol/disco#items') {
      
   }
   
   return;
}

sub ext_added {
   my ($self, $conn) = @_;

   $self->{cb_id} = $conn->reg_cb('iq_get_request_xml', sub { $self->handle_iq_get(@_) });
   return;
}

sub ext_removed {
   my ($self, $conn) = @_;

   $conn->unreg_cb(delete $self->{cb_id});
   return;
}


1;