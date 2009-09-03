package AnyEvent::XMPP::Ext::IBB;

use strict;
use warnings;
use base qw/AnyEvent::XMPP::Ext/;

use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util

# I like shortcuts
sub e { return $_[0]->{extendable} }
sub s { return shift->{extendable}->send(@_) }

sub disco_feature { ( xmpp_ns('ibb') ) }

sub init {
  my ($self) = @_;

  $self->e->reg_cb(
    ext_before_recv_iq => sub {
      my ($e, $node) = @_;
      
      return unless $node->attr('type') eq 'set';

      my $ft = $node->find('ibb', 'query');
      return unless $ft;
      
      $self->process_incoming_request($ft, $node);
      $e->stop_event;
    }
  );
}


sub process_incoming_request {
  my ($self, $ft, $node) = @_;
  
  my $sid = $ft->attr('sid');
  my $size = $ft->attr('block-size');
  my $type = $ft->attr('stanza') || 'iq';
  return $self->s(new_iq_error_reply($node, 'bad-request') unless $sid && $size;
  
  ### FIXME: for now auto-accept stuff - need should_accept callback here
  my $reply = ;
  $self->e->send(new_reply($node, type => 'result'));
}

1;


<iq from='romeo@montague.net/orchard'
    id='jn3h8g65'
    to='juliet@capulet.com/balcony'
    type='set'>
  <open xmlns='http://jabber.org/protocol/ibb'
        block-size='4096'
        sid='i781hf64'
        stanza='iq'/>
</iq>

