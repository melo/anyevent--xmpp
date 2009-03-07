package AnyEvent::XMPP::Parser;
no warnings;
use strict;
use AnyEvent::XMPP::Node;
# OMFG!!!111 THANK YOU FOR THIS MODULE TO HANDLE THE XMPP INSANITY:
use XML::Parser;

use base qw/Object::Event/;

=head1 NAME

AnyEvent::XMPP::Parser - Parser for XML streams (helper for AnyEvent::XMPP)

=head1 SYNOPSIS

   use AnyEvent::XMPP::Parser;
   ...

=head1 DESCRIPTION

This is a XMPP "XML" parser helper class, which helps me to cope with the XMPP "XML".

TODO: Insert old rant about XML from AnyEvent::XMPP::Writer here.

=head1 METHODS

=over 4

=item B<new>

This creates a new AnyEvent::XMPP::Parser and calls C<init>.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = $class->SUPER::new (enable_methods => 1);
   bless $self, $class;

   $self->{parser} = XML::Parser->new (
      Namespaces => 1,
      ProtocolEncoding => 'UTF-8'
   );

   $self->{parser}->setHandlers (
      Start   => sub { $self->cb_start_tag (@_) },
      End     => sub { $self->cb_end_tag   (@_) },
      Char    => sub { $self->cb_char_data (@_) },
      Default => sub { $self->cb_default   (@_) },
   );

   $self->init;
   $self
}

=item B<init>

This methods (re)initializes the parser.

=cut

sub cb_start_tag {
   my ($self, $p, $el, @attrs) = @_;

   my %attrs;
   while (@attrs) {
      my ($k, $v) = (shift @attrs, shift @attrs);
      my $ns = $p->namespace ($k);
      $ns = $p->namespace ($el) unless defined $ns;
      $attrs{"$ns\|$k"} = $v;
   }
   my $node = AnyEvent::XMPP::Node->new ($p->namespace ($el), $el, \%attrs);
   $node->append_parsed ($p->recognized_string);

   if (not @{$self->{nodestack}}) {
      $node->set_only_start;
      $self->stream_start ($node);
      $node = AnyEvent::XMPP::Node->new ($p->namespace ($el), $el, \%attrs);
      $node->set_only_end;
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
   $node->add ($str);
   $node->append_parsed ($p->recognized_string);
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
   $node->append_parsed ($p->recognized_string);

   # > 1 because we don't want the stream tag to save all our children...
   if (@{$self->{nodestack}} > 1) {
      $self->{nodestack}->[-1]->add ($node);
   }

   if (@{$self->{nodestack}} == 1) {
      $self->recv ($node);

   } elsif (@{$self->{nodestack}} == 0) {
      $self->stream_end ($node);
   }
}

sub cb_default {
   my ($self, $p, $str) = @_;

   $self->{nodestack}->[-1]->append_parsed ($str)
      if @{$self->{nodestack}};
}

sub init {
   my ($self) = @_;

   if ($self->{nbparser}) {
      eval { $self->{nbparser}->parse_done };
   }

   $self->{nbparser} = $self->{parser}->parse_start;
   $self->{nodestack} = [];
}

=item B<cleanup>

This methods removes all handlers. Use it to avoid circular references.

=cut

sub cleanup {
   my ($self) = @_;

   eval { $self->{nbparser}->parse_done };

   for (qw(parser nbparser nodestack)) {
      delete $self->{$_};
   }

   return;
}

=item B<feed ($data)>

This method feeds a chunk of unparsed data to the parser.

=cut

sub feed {
   my ($self, $data) = @_;

   eval {
      $self->{nbparser}->parse_more ($data);
   };

   if ($@) {
      $self->event (parse_error => $@, $data) if $@;
      $self->init;
   }
}

=back

=head1 EVENTS

=over 4

=item recv => $node

This event is generated whenever a complete stanza has been received.  It will
B<NOT> be emitted for the start and end tag of a stream. C<$node> will be an
L<AnyEvent::XMPP::Node> object.

=cut

sub recv { }

=item stream_start => $node

This event is emitted when the start stream tag has been parsed.
C<$node> is the L<AnyEvent::XMPP::Node> object containing the start tag,
along with the stream elements attributes.

=cut

sub stream_start { }

=item stream_end => $node

This event is emitted when the end tag of the stream has been parsed.
C<$node> is the L<AnyEvent::XMPP::Node> object containing the end tag,
along with the attributes of the stream element.

=cut

sub stream_end { }

=item parse_error => $error, $data

This event is emitted when a parse error has been detected. After receiving a
C<parse_error> you must not pass further data to the parser. You may reuse
the parser for new XMPP streams by calling the C<init> method.

=cut

sub parse_error { }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP
