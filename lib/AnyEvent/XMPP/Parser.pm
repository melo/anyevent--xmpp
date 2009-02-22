package AnyEvent::XMPP::Parser;
no warnings;
use strict;
use AnyEvent::XMPP::Node;
use AnyEvent::XMPP::Stanza;
# OMFG!!!111 THANK YOU FOR THIS MODULE TO HANDLE THE XMPP INSANITY:
use XML::Parser::Expat;

use base qw/Object::Event::Methods/;

=head1 NAME

AnyEvent::XMPP::Parser - Parser for XML streams (helper for AnyEvent::XMPP)

=head1 SYNOPSIS

   use AnyEvent::XMPP::Parser;
   ...

=head1 DESCRIPTION

This is a XMPP XML parser helper class, which helps me to cope with the XMPP XML.

See also L<AnyEvent::XMPP::Writer> for a discussion of the issues with XML in XMPP.

=head1 METHODS

=over 4

=item B<new ($stream_ns)>

This creates a new AnyEvent::XMPP::Parser and calls C<init>.

C<$stream_ns> is the namespace of the stream.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = $class->SUPER::new (stream_ns => (shift));
   bless $self, $class;
   $self->init;
   $self
}

=item B<init>

This methods (re)initializes the parser.

=cut

sub cb_start_tag {
   my ($self, $p, $el, %attrs) = @_;

   my $node = AnyEvent::XMPP::Node->new ($p->namespace ($el), $el, \%attrs, $self);
   $node->append_raw ($p->recognized_string);

   if (not @{$self->{nodestack}}) {
      $self->received_stanza_xml ($node);
      $self->stream_start ($node);
   }

   push @{$self->{nodestack}}, $node;
}

sub cb_char_data {
   my ($self, $p, $str) = @_;

   unless (@{$self->{nodestack}}) {
      warn "characters outside of tag: [$str]!\n";
      return;
   }

   my $node = $self->{nodestack}->[-1];
   $node->add_text ($str);
   $node->append_raw ($p->recognized_string);
}

sub cb_end_tag {
   my ($self, $p, $el) = @_;

   unless (@{$self->{nodestack}}) {
      warn "end tag </$el> read without any starting tag!\n";
      return;
   }

   if (!$p->eq_name ($self->{nodestack}->[-1]->name, $el)) {
      warn "end tag </$el> doesn't match start tags ($self->{tags}->[-1]->[0])!\n";
      return;
   }

   my $node = pop @{$self->{nodestack}};
   $node->append_raw ($p->recognized_string);

   # > 1 because we don't want the stream tag to save all our children...
   if (@{$self->{nodestack}} > 1) {
      $self->{nodestack}->[-1]->add_node ($node);
   }

   if (@{$self->{nodestack}} == 1) {
      $self->received_stanza_xml ($node);

      $self->received_stanza (
         AnyEvent::XMPP::Stanza::analyze ($node, $self->{stream_ns})
      );

   } elsif (@{$self->{nodestack}} == 0) {
      $self->received_stanza_xml ($node);
      $self->stream_end ($node);
   }
}

sub cb_default {
   my ($self, $p, $str) = @_;

   $self->{nodestack}->[-1]->append_raw ($str)
      if @{$self->{nodestack}};
}

sub init {
   my ($self) = @_;

   if ($self->{parser}) {
      $self->{parser}->finish;
      $self->{parser}->release;
      delete $self->{parser};
   }

   $self->{parser} = XML::Parser::ExpatNB->new (
      Namespaces => 1,
      ProtocolEncoding => 'UTF-8'
   );

   $self->{parser}->setHandlers (
      Start   => sub { $self->cb_start_tag (@_) },
      End     => sub { $self->cb_end_tag   (@_) },
      Char    => sub { $self->cb_char_data (@_) },
      Default => sub { $self->cb_default   (@_) },
   );

   $self->{nso}       = {};
   $self->{nodestack} = [];
}

=item B<cleanup>

This methods removes all handlers. Use it to avoid circular references.

=cut

sub cleanup {
   my ($self) = @_;

   $self->{parser}->release;

   for (qw(stanza_cb parser nso nodestack)) {
      delete $self->{$_};
   }

   return;
}

=item B<nseq ($namespace, $tagname, $cmptag)>

This method checks whether the C<$cmptag> matches the C<$tagname>
in the C<$namespace>.

C<$cmptag> needs to come from the XML::Parser::Expat as it has
some magic attached that stores the namespace.

=cut

sub nseq {
   my ($self, $ns, $name, $tag) = @_;

   unless (exists $self->{nso}->{$ns}->{$name}) {
      $self->{nso}->{$ns}->{$name} =
         $self->{parser}->generate_ns_name ($name, $ns);
   }

   return $self->{parser}->eq_name ($self->{nso}->{$ns}->{$name}, $tag);
}

=item B<feed ($data)>

This method feeds a chunk of unparsed data to the parser.

=cut

sub feed {
   my ($self, $data) = @_;

   eval {
      $self->{parser}->parse_more ($data);
   };

   $self->parse_error ($@, $data) if $@;
}

sub stream_start {
   my ($self, $node) = @_;
}

sub stream_end {
   my ($self, $node) = @_;
}

sub received_stanza_xml {
   my ($self, $node) = @_;
   # subclass/event callback responsibility
}

sub received_stanza {
   my ($self, $stanza) = @_;
   # subclass/event callback responsibility
}

sub parse_error {
   my ($self, $error) = @_;
   # subclass/event callback responsibility
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP
