package AnyEvent::XMPP::Writer;
use strict;
use XML::Writer;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/simxml filter_xml_chars filter_xml_attr_hash_chars/;
use Encode;
use Carp qw/cluck/;

=head1 NAME

AnyEvent::XMPP::Writer - "XML" writer for XMPP

=head1 SYNOPSIS

   use AnyEvent::XMPP::Writer;
   ...

=head1 DESCRIPTION

This module contains some helper functions for writing XMPP "XML", which is not
real XML at all ;-( I use L<XML::Writer> and tune it until it creates "XML"
that is accepted by most servers propably (all of the XMPP servers I tested
should work (jabberd14, jabberd2, ejabberd, googletalk).

I hope the semantics of L<XML::Writer> don't change much in the future, but if
they do and you run into problems, please report them!

The whole "XML" concept of XMPP is fundamentally broken anyway. It's supposed
to be an subset of XML. But a subset of XML productions is not XML. Strictly
speaking you need a special XMPP "XML" parser and writer to be 100% conformant.

On top of that XMPP B<requires> you to parse these partial "XML" documents.
But a partial XML document is not well-formed, heck, it's not even a XML
document!  And a parser should bail out with an error. But XMPP doesn't care,
it just relies on implementation dependend behaviour of chunked parsing modes
for SAX parsing.  This functionality isn't even specified by the XML
recommendation in any way.  The recommendation even says that it's undefined
what happens if you process not-well-formed XML documents.

But I try to be as XMPP "XML" conformant as possible (it should be around
99-100%).  But it's hard to say what XML is conformant, as the specifications
of XMPP "XML" and XML are contradicting. For example XMPP also says you only
have to generated and accept UTF-8 encodings of XML, but the XML recommendation
says that each parser has to accept UTF-8 B<and> UTF-16. So, what do you do? Do
you use a XML conformant parser or do you write your own?

I'm using XML::Parser::Expat because expat knows how to parse broken (aka
'partial') "XML" documents, as XMPP requires. Another argument is that if you
capture a XMPP conversation to the end, and even if a '</stream:stream>' tag
was captured, you wont have a valid XML document. The problem is that you have
to resent a <stream> tag after TLS and SASL authentication each! Awww... I'm
repeating myself.

But well... AnyEvent::XMPP does it's best with expat to cope with the
fundamental brokeness of "XML" in XMPP.

Back to the issue with "XML" generation: I've discoverd that many XMPP servers
(eg.  jabberd14 and ejabberd) have problems with XML namespaces. Thats the
reason why I'm assigning the namespace prefixes manually: The servers just
don't accept validly namespaced XML. The draft 3921bis does even state that a
client SHOULD generate a 'stream' prefix for the <stream> tag.

I advice you to explicitly set the namespaces too if you generate "XML" for
XMPP yourself, at least until all or most of the XMPP servers have been fixed.
Which might take some years :-) And maybe will happen never.

And another note: As XMPP requires all predefined entity characters to be
escaped in character data you need a "XML" writer that will escape everything:

   RFC 3920 - 11.1.  Restrictions:

     character data or attribute values containing unescaped characters
     that map to the predefined entities (Section 4.6 therein);
     such characters MUST be escaped

This means:
You have to escape '>' in the character data. I don't know whether XML::Writer
does that. And I honestly don't care much about this. XMPP is broken by design and
I have barely time to writer my own XML parsers and writers to suit their sick taste
of "XML". (Do I repeat myself?)

I would be happy if they finally say (in RFC3920): "XMPP is NOT XML. It's just
XML-like, and some XML utilities allow you to process this kind of XML.".

=head1 METHODS

=over 4

=item B<new (%args)>

Basic constructor, which calls C<init>.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = { @_ };
   bless $self, $class;
   $self->init;
   return $self;
}

=item B<init>

(Re)initializes the writer.

=cut

sub init {
   my ($self) = @_;
   $self->{ns} = xmpp_ns ($self->{stream_ns});
   $self->{write_buf} = '';

   $self->{writer} =
      XML::Writer->new (
         OUTPUT => \$self->{write_buf},
         NAMESPACES => 1,
         UNSAFE => 1
      );
}

sub ns { (shift)->{ns} }

=item B<flush ()>

This method flushes the internal write buffer and will invoke the C<write_cb>
callback. (see also C<new ()> above)

=cut

sub flush {
   my ($self) = @_;
   substr $self->{write_buf}, 0, (length $self->{write_buf}), ''
}

=item B<init_stream ($language, $version, %attrs)>

This method will generate a XMPP stream header. The namespace of the stream
has to be given in the arguments to C<new> (see above).

C<$langauge> is the stream language, default is 'en'. C<$version>
is the stream version, default is '1.0'.

C<%attrs> should contain further attributes for the stream header.
Most popular is 'to', for the domain name.

The return value is the unicode character string of the generated header.

=cut

sub init_stream {
   my ($self, $language, $vers, %attrs) = @_;

   my $w = $self->{writer};
   $w->xmlDecl ();
   $w->addPrefix (xmpp_ns ('stream'), 'stream');
   $w->addPrefix ($self->ns, '');
   $w->forceNSDecl ($self->ns);
   $w->startTag (
      [xmpp_ns ('stream'), 'stream'],
      %attrs,
      version => $vers || '1.0',
      [xmpp_ns ('xml'), 'lang'] => $language || 'en'
   );

   $self->flush
}

=item B<whitespace_ping>

This method generates a single space for the server and returns it.

=cut

sub whitespace_ping {
   my ($self) = @_;
   $self->{writer}->raw (' ');
   $self->flush
}

=item B<end_of_stream>

Generates a end of the stream.

=cut

sub end_of_stream {
   my ($self) = @_;
   my $w = $self->{writer};
   $w->endTag ([xmpp_ns ('stream'), 'stream']);
   $self->flush
}

sub call_writer {
   my ($self, $cb) = @_;

   $cb->($self, $self->{writer});
   $self->flush
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
