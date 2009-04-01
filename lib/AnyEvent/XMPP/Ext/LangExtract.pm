package AnyEvent::XMPP::Ext::LangExtract;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/stringprep_jid new_iq new_reply extract_lang_element/;
use Scalar::Util qw/weaken/;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::LangExtract - Extract language based fields from stanzas

=head1 SYNOPSIS

   $con->add_ext ('LangExtract');

   $con->reg_cb (
      recv_message => sub {
         my ($con, $node) = @_;

         return if $node->meta->{error};

         my $body_of_default_lang = $node->meta->{body};
         my $body_of_lang_en      = $node->meta->{all_body}->{en};
      }
   );

=head1 DESCRIPTION

This extension will automatically call C<extract_lang_element> from
L<AnyEvent::XMPP::Util> for incoming message and presence stanzas.

Elements that are extracted are:

For C<presence> stanzas:

   status

For C<message> stanzas:

   subject
   body

For every element a two meta (see also L<AnyEvent::XMPP::Meta>) entries will be
generated, with the same keys C<extract_lang_element> would add to the
argument.

=head1 METHODS

=over 4

=cut

sub disco_feature { }

sub init {
   my ($self) = @_;

   $self->{iq_guard} = $self->{extendable}->reg_cb (
      ext_before_recv_presence => sub {
         my ($ext, $node) = @_;
         extract_lang_element ($node, 'status', $node->meta);
      },
      ext_before_recv_message => sub {
         my ($ext, $node) = @_;

         extract_lang_element ($node, 'subject', $node->meta);
         extract_lang_element ($node, 'body', $node->meta);
      },
   );
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
