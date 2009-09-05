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

  my ($ids, $features, $forms) = _extract_idents_and_features($disco_info);
  map { $_ = "$_->{category}/$_->{type}/$_->{lang}/$_->{name}" } @$ids;
  _serialize_forms($forms);

  my $S = join('<', sort @$ids, sort @$features, sort @$forms) . '<';
  utf8::encode($S);    ### Turns UTF-8 string into byte sequence

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

  my (@ids, @feats, @forms);
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
    elsif ($node->eq('data_form', 'x')) {
      push @forms, $node;
    }
  }

  return (\@ids, \@feats, \@forms);
}

sub _serialize_forms {
  my $forms = shift;

  for my $form (@$forms) {
    my @S;
    my $type;
    my @fields =
      sort { $a->attr('var') cmp $b->attr('var') }
      $form->find(qw/data_form field/);
      
    for my $field (@fields) {
      my $var = $field->attr('var');
      my @values =
        sort map { $_->text } $field->find(qw/data_form value/);

      if ($var eq 'FORM_TYPE') {
        $type = $values[0];
      }
      else {
        push @S, join('<', $var, @values);
      }
    }

    $form = join('<', $type,@S);
  }
  
  return;
}

1;
