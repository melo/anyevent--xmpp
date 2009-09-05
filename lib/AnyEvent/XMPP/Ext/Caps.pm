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



############################
# The verification algorithm

sub _ver_gen {
  my ($disco_info, $hash) = @_;

  my ($ids, $features, $forms) = _extract_ids_features_and_forms($disco_info);

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

1;
