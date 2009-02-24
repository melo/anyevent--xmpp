package AnyEvent::XMPP::Node;
use strict;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns_maybe/;
use AnyEvent::XMPP::Util qw/xml_escape/;

use constant {
   NS     => 0,
   NAME   => 1,
   ATTRS  => 2,
   NODES  => 3,
   META   => 4,
};

use constant {
   NNODE   => 0,
   NTEXT   => 1,
   NPARS   => 2,
   NRAW    => 3,
};

=head1 NAME

AnyEvent::XMPP::Node - XML node tree helper for the parser.

=head1 SYNOPSIS

   use AnyEvent::XMPP::Node;
   ...

=head1 DESCRIPTION

This class represens a XML node. L<AnyEvent::XMPP> should usually not
require messing with the parse tree, but sometimes it is neccessary.

If you experience any need for messing with these and feel L<AnyEvent::XMPP> should
rather take care of it drop me a mail, feature request or most preferably a patch!

Every L<AnyEvent::XMPP::Node> has a namespace, attributes, text and child nodes.

You can access these with the following methods:

=head1 METHODS

=over 4

=item B<new ($ns, $el, $attrs)>

Creates a new AnyEvent::XMPP::Node object with the node tag name C<$el> in the
namespace URI C<$ns> and the attributes C<$attrs>.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = [];
   $self->[NS]    = shift;
   $self->[NAME]  = shift;
   $self->[NODES] = [];
   $self->[RAW] = '';

   my @a;
   if (ref $_[0] eq 'ARRAY') {
      @a = @{$_[0]};
   } elsif (ref $_[0] eq 'HASH') {
      @a = %{$_[0]};
   } else {
      @a = @_;
   }

   my $map = $self->[ATTRS] = { };
   while (@a) {
      my ($name, $value) = (shift @a, shift @a);
      if (ref $name) {
         $name = join "|", @$name
      } else {
         unless ($name =~ /\|/) {
            $name = $self->[NS] . "|" . $name
         }
      }
      $map->{$name} = $value;
   }

   bless $self, $class;
   return $self
}

=item B<name>

The tag name of this node.

=cut

sub name {
   $_[0]->[NAME]
}

=item B<namespace>

Returns the namespace URI of this node.

=cut

sub namespace {
   $_[0]->[NS]
}

=item B<meta ($meta)>

=cut

sub meta {
   defined $_[1]
      ? $_[0]->[META] = $_[1]
      : $_[0]->[META]
}

=item B<eq ($namespace_or_alias, $name) or eq ($node)>

Returns true whether the current element matches the tag name C<$name>
in the namespaces pointed at by C<$namespace_or_alias>.

You can either pass an alias that was defined in L<AnyEvent::XMPP::Namespaces>
or pass an namespace URI in C<$namespace_or_alias>. If no alias with the name
C<$namespace_or_alias> was found in L<AnyEvent::XMPP::Namespaces> it will be
interpreted as namespace URI.

The first argument to eq can also be another L<AnyEvent::XMPP::Node> instance.

=cut

sub eq {
   my ($self, $n, $name) = @_;
   if (ref $n) {
      return
         ($n->namespace eq $self->namespace)
         && $n->name eq $self->name;
   } else {
      return
         (xmpp_ns_maybe ($n) eq $self->namespace)
         && ($name eq $self->name);
   }
}

=item B<eq_ns ($namespace_or_alias) or eq_ns ($node)>

This method return true if the namespace of this instance of L<AnyEvent::XMPP::Node>
matches the namespace described by C<$namespace_or_alias> or the
namespace of the C<$node> which has to be another L<AnyEvent::XMPP::Node> instance.

See C<eq> for the meaning of C<$namespace_or_alias>.

=cut

sub eq_ns {
   my ($self, $n) = @_;
   if (ref $n) {
      return ($n->namespace eq $self->namespace);
   } else {
      return xmpp_ns_maybe ($n) eq $self->namespace;
   }
}

=item B<attr ($name, $value)>

Returns the contents of the C<$name> attribute in the namespace of the element.
C<$value> is optional, and if not undef it will replace the attribute value.

=cut

sub attr {
   defined $_[2]
      ? $_[0]->[ATTRS]->{$_[0]->[NS] . "|" . $_[1]} = $_[2]
      : $_[0]->[ATTRS]->{$_[0]->[NS] . "|" . $_[1]}
}

=item B<attrs>

Returns a hash reference of attributes of this node.  The keys of the hash
reference have the namespace of the attribute and the name of the attribute
concationated with a '|' within, like this:

    {
       "$namespace|$name" => $value,
       ...
    }

=cut

sub attrs { $_[0]->[ATTRS] }

=item B<add ($node)>

=item B<add ($ns, $el, $attrs)>

=item B<add ($text)>

=item B<add (\$unescaped)>

Adds a sub-node to the current node.

=cut

sub add {
   my ($self, $node, @args) = @_;

   my $n;
   if (ref ($node) eq 'AnyEvent::XMPP::Node') {
      push @{$self->[NODES]}, [NNODE, $n = $node];
   } elsif (ref ($node) eq 'REF') {
      push @{$self->[NODES]}, [NRAW,  $n = $node];
   } elsif (@args > 0) {
      push @{$self->[NODES]}, [NNODE, $n = AnyEvent::XMPP::Node->new ($node, @args)];
   } else {
      push @{$self->[NODES]}, [NTEXT, $n = $node]
   }
   $n
}

=item B<nodes>

Returns a list of sub nodes.

=cut

sub nodes {
   map { $_->[1] }
      grep { $_->[0] == NNODE }
         @{$_[0]->[NODES]};
}

=item B<text>

Returns the text for this node.

=cut

sub text {
   join '', map $_->[1], grep { $_->[0] == NTEXT } @{$_[0]->[NODES]}
}

=item B<find_all (@path)>

This method does a recursive descent through the sub-nodes and
fetches all nodes that match the last element of C<@path>.

The elements of C<@path> consist of a array reference to an array with
two elements: the namespace key known by the C<$parser> and the tagname
we search for.

=cut

sub find_all {
   my ($self, @path) = @_;
   my $cur = shift @path;
   my @ret;
   for my $n ($self->nodes) {
      if ($n->eq (@$cur)) {
         if (@path) {
            push @ret, $n->find_all (@path);
         } else {
            push @ret, $n;
         }
      }
   }
   @ret
}

=item B<write_on ($writer)>

This writes the current node out to the L<AnyEvent::XMPP::Writer> object in C<$writer>.

=cut

sub write_on {
   my ($self, $w) = @_;
   $w->raw ($self->as_string);
}

=item B<raw_string ()>

This method returns the original character representation of this XML element
(and it's children nodes). Please note that the string is a unicode string,
meaning: to get octets use:

   my $octets = encode ('UTF-8', $node->raw_string);

Now you can roll stunts like this:

   my $libxml = XML::LibXML->new;
   my $doc    = $libxml->parse_string (encode ('UTF-8', $node->raw_string ()));

(You can use your favorite XML parser :)

=cut

sub raw_string {
   my ($self) = @_;
   join '',
      map { $_->[0] == NPARS ? $_->[1] : $_->[1]->as_string }
         grep { $_->[0] != NTEXT }
            @{$self->[NODES]};
}

=item B<as_string ($default_namespace, $indent)>

This function will serialize this node to an unicode XML string,
ready for being UTF-8 encoded and written to the socket.
C<$default_namespace> is the default namespace this element is in.

=cut

# Welcome to XML nightmare!!!!!!
sub as_string {
   my ($self, $nsdecls, $indent, $idcnt) = @_;

   my $name = $self->[NAME];
   my $ns = $self->[NS];

   my %subdecls = %{$nsdecls || {}};
   my @attrs;

   my $only_start;
   if (ref ($idcnt)) {
      for (@$idcnt) {
         if (ref ($_)) {
            my $decls = $_;
            push @attrs, [$decls->{$_}, $_, 'xmlns'] for keys %$decls;
         } elsif ($_ eq 'start') {
            $only_start = 1;
         }
      }
      $idcnt = 0;
   } else {
      unless (defined ($subdecls{$ns}) && $subdecls{$ns} eq '') {
         delete $subdecls{$_} for grep { $subdecls{$_} eq '' } keys %subdecls;
         $subdecls{$ns} = '';
         unshift @attrs, ['', $ns, 'xmlns'];
      }
   }

   for my $ak (sort keys %{$self->[ATTRS] || {}}) {
      my ($ns, $name) = split /\|/, $ak;
      my $pref;

      if (defined ($subdecls{$ns})) {
         $pref = $subdecls{$ns};
      } else {
         $pref = $subdecls{$ns} = 'ns' . ++$idcnt;
         unshift @attrs, [$pref, $ns, 'xmlns']
      }

      push @attrs, [$name, $self->[ATTRS]->{$ak}, $pref]
   }

   my $pad = "  " x $indent;
   
   my $child_data =
      join '', map {
         my $str;
         if ($_->[0] == NNODE) {
            $str = $_->[1]->as_string (\%subdecls, ($indent ? ($indent + 1) : 0), $idcnt)
         } elsif ($_->[0] == NTEXT) {
            $str = xml_escape ($indent ? map { $pad . $_ } split /\n/, $_->[1] : $_->[1])
         } elsif ($_->[0] == NRAW) {
            $str = ${$_->[1]};
         }
         $str
      } @{$self->[NODES]};

   my $elem_name = $subdecls{$ns} eq '' ? $name : "$subdecls{$ns}:$name";

   my $start = 
      $pad . "<$elem_name "
      . (join ' ', map {
           my ($name, $value, $pref) = @$_;
           (substr ($name, 0, 4) eq 'xml:')
               ? "$name=\"" . xml_escape ($value) ."\""
               : (
           $pref eq ''
              ? "$name=\"" . xml_escape ($value) ."\""
              : "$pref" . ($name ne '' ? "\:$name" : '')
                 . '="' . xml_escape ($value) . "\""
           )
        } @attrs);

   return $start . '>' if $only_start;

   $start
   . ($child_data ne ''
        ? '>'
          . ($indent ? "\n" : '')
          . $child_data
          . ($indent ? "\n$pad" : '')
          . "</$elem_name>"
        : '/>')
}

=item B<append_parsed ($string)>

This method is called by the parser to store original strings of this element.

=cut

sub append_parsed {
   my ($self, $str) = @_;
   push @{$self->[NODES]}, [NPARS, $str];
}

=item B<to_sax_events ($handler)>

This method takes anything that can receive SAX events.
See also L<XML::GDOME::SAX::Builder> or L<XML::Handler::BuildDOM>
or L<XML::LibXML::SAX::Builder>.

With this you can convert this node to any DOM level 2 structure you want:

   my $builder = XML::LibXML::SAX::Builder->new;
   $node->to_sax_events ($builder);
   my $dom = $builder->result;
   print "Canonized: " . $dom->toStringC14N . "\n";

=cut

sub to_sax_events {
   my ($self, $handler) = @_;
   my $doc = { Parent => undef };
   $handler->start_document ($doc);
   $self->_to_sax_events ($handler);
   $handler->end_document ($doc);
}

sub _to_sax_events {
   my ($self, $handler) = @_;
   $handler->start_element ({
      NamespaceURI => $self->namespace,
      Name         => $self->name,
      Attributes   => {
         map {
            ($_ => { Name => $_, Value => $self->[ATTRS]->{$_} })
         } keys %{$self->[ATTRS]}
      }
   });
   for (@{$self->[NODES]}) {
      if ($_->[0] == NTEXT) {
         $handler->characters ($_->[1]);
      } elsif ($_->[0] == NNODE) {
         $_->[1]->_to_sax_events ($handler);
      }
   }
   $handler->end_element ({
      NamespaceURI => $self->namespace,
      Name         => $self->name,
   });
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
