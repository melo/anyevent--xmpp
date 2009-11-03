package AnyEvent::XMPP::Ext::Caps;

use warnings;
use strict;
use base qw/AnyEvent::XMPP::Ext/;

use AnyEvent::XMPP::Namespaces qw/ set_xmpp_ns_alias /;
use AnyEvent::XMPP::Util qw/ split_jid prep_join_jid resourceprep /;
use AnyEvent::XMPP::Ext::DataForm;
use MIME::Base64 qw( encode_base64 );
use Digest::SHA1 qw( sha1 );

set_xmpp_ns_alias(caps => 'http://jabber.org/protocol/caps');


##########
# Caps API

sub caps_for {
  my ($self, $jid, $cb) = @_;

  my $caps = $self->_fetch_caps_for($jid);
  if (exists $caps->{current}) {
    $cb->($caps->{current});
    return;
  }

  $self->_calc_caps_for($jid, $cb);
  return;
}


####################
# Initialize our Ext

sub init {
  my ($self) = @_;

  $self->{guard} = $self->{extendable}->reg_cb(
    ## 250, after ext_'s, before normal reg's
    recv_presence => 250 => sub {
      my ($e, $node) = @_;
      $self->_check_presence($node);
    }
  );
}


#####################
# The sausage factory

## <presence> handler
sub _check_presence {
  my ($self, $node) = @_;

  my $type = $node->attr('type') || '';
  return if $type =~ /subscribe/;

  if ($type eq 'unavailable') {
    $self->_remove_caps_for($node->attr('from'));
    return;
  }

  my $c = $self->_extract_caps($node);
  my $f = $node->attr('from');
  if ($c) {
    $self->_store_caps_for($f, $c);
  }
  else {
    $self->_remove_caps_for($f, $c);
  }
}

sub _store_caps_for {
  my ($self, $from, $c) = @_;
  my ($bare, $res) = _split_from($from);

  return $self->{caps}{$bare}{$res} = $c;
}

sub _remove_caps_for {
  my ($self, $from) = @_;
  my ($bare, $res)  = _split_from($from);

  return delete $self->{caps}{$bare}{$res};
}

sub _extract_caps {
  my ($self, $node) = @_;

  my ($c, $wtf) = $node->find('caps', 'c');
  ### FIXME: what to do if more than one caps element is present?
  # if ($wtf) {
  #   ...
  # }
  #
  return unless $c;

  return {
    hash => $c->attr('hash'),
    node => $c->attr('node'),
    ver  => $c->attr('ver'),
    ext  => $c->attr('ext'),
  };
}

sub _split_from {
  my ($l, $d, $r) = split_jid($_[0]);

  return (prep_join_jid($l, $d), resourceprep($r));
}

############################
# The verification algorithm

sub _ver_gen {
  my ($disco_info, $hash) = @_;

  my ($ids, $features, $forms) = _extract_ids_features_and_forms($disco_info);
  
  ### Section 5.4, bullets 3.4, 3.5
  return if _has_dups($ids);
  return if _has_dups($features);

  my $S = join('', sort @$ids, sort @$features, sort @$forms);
  utf8::encode($S);    ### Turns UTF-8 string into byte sequence

  if ($hash eq 'sha-1') {
    $S = sha1($S);
  }
  else {
    croak(qq{Invalid hash '$hash' in call to _ver_gen});
  }

  return encode_base64($S, '');
}

sub _extract_ids_features_and_forms {
  my $di = shift;

  my (@ids, @feats, @forms);
  foreach my $node ($di->nodes) {
    if ($node->eq('disco_info', 'identity')) {
      push @ids,
        join(
        '/',
        map { $_ || '' } (
          $node->attr('category'), $node->attr('type'),
          $node->attr_ns('xml', 'lang'), $node->attr('name')
        ),
        ) . '<';
    }
    elsif ($node->eq('disco_info', 'feature')) {
      push @feats, $node->attr('var') . '<';
    }
    elsif ($node->eq('data_form', 'x')) {
      my $df = AnyEvent::XMPP::Ext::DataForm->new;
      $df->from_node($node);
      push @forms, $df->as_verification_string;
    }
  }

  return (\@ids, \@feats, \@forms);
}

sub _has_dups {
  my $list = $_[0];
  
  my %dc = map { $_ => 1 } @$list;
  return 0 if @$list == keys(%dc);
  return 1;
}

1;
