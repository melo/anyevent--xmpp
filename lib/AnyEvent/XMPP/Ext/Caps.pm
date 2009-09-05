package AnyEvent::XMPP::Ext::Caps;

use warnings;
use strict;
use base qw/AnyEvent::XMPP::Ext/;

use AnyEvent::XMPP::Namespaces qw/ set_xmpp_ns_alias /;
use AnyEvent::XMPP::Util qw/ split_jid prep_join_jid resourceprep /;
use MIME::Base64 qw( encode_base64 );
use Digest::SHA1 qw( sha1 );

set_xmpp_ns_alias(caps => 'http://jabber.org/protocol/caps');



############################
# The verification algorithm

sub _ver_gen {
  my ($disco_info, $hash) = @_;
  ### FIXME: add support for XEP-0128

  my ($ids, $features) = _extract_idents_and_features($disco_info);
  map {$_ = "$_->{category}/$_->{type}/$_->{lang}/$_->{name}"} @$ids;
  my $S = join('<', sort @$ids, sort @$features) . '<';
  utf8::encode($S); ### Turns UTF-8 string into byte sequence

  if ($hash eq 'sha-1') {
    $S = sha1($S);
  }
  else {
    croak(qq{Invalid hash '$hash' in call to _ver_gen});
  }
  
  return encode_base64($S, '');
}

sub _extract_idents_and_features {
  my $di = shift;

  my (@ids, @feats);
  foreach my $node ($di->nodes) {
    if ($node->eq('disco_info', 'identity')) {
      push @ids,
        {
        category => $node->attr('category') || '',
        name     => $node->attr('name')     || '',
        type     => $node->attr('type')     || '',
        lang => $node->attr_ns('xml', 'lang') || '',
        };
    }
    elsif ($node->eq('disco_info', 'feature')) {
      push @feats, $node->attr('var');
    }
  }

  return (\@ids, \@feats);
}

1;
