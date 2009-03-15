package AnyEvent::XMPP::Node;
use strict;
no warnings;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns_maybe/;
use AnyEvent::XMPP::Util qw/xml_escape/;
use AnyEvent::XMPP::Meta;
require Exporter;
our @EXPORT_OK = qw/simxml/;
our @ISA = qw/Exporter/;

use constant {
   NS      => 0,
   NAME    => 1,
   ATTRS   => 2,
   NODES   => 3,
   META    => 4,
   NSDECLS => 5,
   FLAGS   => 6
};

use constant {
   NNODE   => 0,
   NTEXT   => 1,
   NPARS   => 2,
   NRAW    => 3,
};

use constant {
   ONLY_START => 1,
   ONLY_END   => 2,
};

=head1 NAME

AnyEvent::XMPP::Node - XML node tree helper for the parser.

=head1 SYNOPSIS

   use AnyEvent::XMPP::Node;
   ...

=head1 DESCRIPTION

This class represents a XML node. L<AnyEvent::XMPP> should usually not
require messing with the parse tree, but sometimes it is necessary.

If you experience any need for messing with these and feel L<AnyEvent::XMPP> should
rather take care of it drop me a mail, feature request or most preferably a patch!

Every L<AnyEvent::XMPP::Node> has a namespace, attributes, text and child nodes.

You can access these with the following methods:

=head1 FUNCTIONS

=over 4

=item B<simxml (%xmlstruct)>

C<%xmlstruct> key value pairs:

   simxml ($w,
      defns => '<xmlnamespace>',
      node  => <node>,
   );

Where node is:

   <node> := {
                ns     => '<xmlnamespace>',
                name   => 'tagname',
                attrs  => [ 'name', 'value', 'name2', 'value2', ... ],
                childs => [ <node>, ... ]
             }
           | {
                dns    => '<xmlnamespace>', # this will set that namespace to
                                            # the default namespace before using it.
                name   => 'tagname',
                attrs  => [ 'name', 'value', 'name2', 'value2', ... ],
                childs => [ <node>, ... ]
             }
           | [ sub { ... }, ... ]
           | sub { ... }
           | \(my $rawxml = "raw XML unicode text")
           | "textnode"

Please note: C<childs> stands for C<child sequence> :-)

Also note that if you omit the C<ns> key for nodes there is a fall back
to the namespace of the parent element or the last default namespace.
This makes it easier to write things like this:

   {
      defns => 'muc_owner',
      node => { name => 'query' }
   }

(Without having to include C<ns> in the node.)

This is a bigger example:

   ...

   $msg->node->add (
      simxml($w,
         defns => 'muc_user', # sets the default namepsace for all following elements
         node  => {
            name => 'x',      # element 'x' in namespace 'muc_user'
            childs => [
               {
                  'name' => 'invite',           # element 'invite' in namespace 'muc_user'
                  'attrs' => [ 'to', $to_jid ], # to="$to_jid" attribute for 'invite'
                  'childs' => [
                     { # the <reason>$reason</reason> element in the invite element
                       'name' => 'reason',
                       childs => [ $reason ]
                     }
                  ],
               }
            ]
         }
      );
   );

=cut

sub simxml {
   my (%desc) = @_;

   $desc{fb_ns} = $desc{defns}
      unless exists $desc{fb_ns};

   my $node = $desc{node};

   if (not defined $node) {
      return;

   } elsif (ref ($node) eq 'CODE') {
      return $node->();

   } elsif (ref ($node) eq 'ARRAY') {
      my @o;
      push @o, $_->() for @$node;
      return @o;

   } elsif (ref ($node) eq 'HASH') {
      my $ns = $node->{dns} ? $node->{dns} : $node->{ns};
      $ns    = $ns          ? $ns          : $desc{fb_ns};
      $ns    = xmpp_ns_maybe ($ns);

      my $nnode = AnyEvent::XMPP::Node->new ($ns, $node->{name}, $node->{attrs} || []);
      
      my $fb_ns = $desc{fb_ns};

      if (defined ($node->{dns}) && xmpp_ns_maybe ($node->{dns}) eq $ns) {
         $nnode->add_decl_prefix ($ns => '');
         $fb_ns = $ns;
      }

      for (@{$node->{childs}}) {
         next unless defined $_;
         my @nodes = simxml (node => $_, fb_ns => $fb_ns);
         $nnode->add ($_) for @nodes;
      }

      return $nnode;
   } else {
      return $node;
   }
}

=back

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

sub shallow_clone {
   my ($self) = @_;
   $self->new ($self->[NS], $self->[NAME], $self->[ATTRS]);
}

=item B<name>

The tag name of this node.

=cut

sub name {
   $_[0]->[NAME]
}

=item B<namespace ($ns)>

Returns or sets (if C<$ns> is defined) the namespace URI of this node.

=cut

sub namespace {
   my ($self, $ns) = @_;

   $ns = xmpp_ns_maybe ($ns);

   if (defined $ns) {
      for my $k (keys %{$self->[ATTRS]}) {
         if ($k =~ /^\Q$self->[NS]\E\|(.*)$/) {
            $self->[ATTRS]->{$ns . '|' . $1} =
               delete $self->[ATTRS]->{$k};
         }
      }

      return $self->[NS] = $ns;
   } else {
      return $self->[NS]
   }
}

=item B<meta>

This method will return or set (if C<$meta> is defined) the meta information of
this node. The meta information should be an L<AnyEvent::XMPP::Meta> object,
containing annotations about the content of the node.

B<NOTE>: The meta information object will be auto-generated when this method
is called for the first time. So make sure you built up the essential
parts of your stanza before you request the meta information.

=cut

sub meta {
   defined $_[1]
      ? $_[0]->[META] = $_[1]
      : (
         $_[0]->[META]
           ? $_[0]->[META]
           : ($_[0]->[META] = AnyEvent::XMPP::Meta->new ($_[0], $_[0]->[NS]))
      )
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
   @_ > 2
      ? (
           defined $_[2]
              ? $_[0]->[ATTRS]->{$_[0]->[NS] . "|" . $_[1]} = $_[2]
              : delete $_[0]->[ATTRS]->{$_[0]->[NS] . "|" . $_[1]}
        )
      : $_[0]->[ATTRS]->{$_[0]->[NS] . "|" . $_[1]}
}

=item B<attr_ns ($ns, $name, $value)>

Returns the contents of the C<$name> attribute in the namespace C<$ns>.
C<$value> is optional, and if not undef it will replace the attribute value.

=cut

sub attr_ns {
   @_ > 3
      ? (
           defined $_[2]
              ? $_[0]->[ATTRS]->{$_[1] . "|" . $_[2]} = $_[3]
              : delete $_[0]->[ATTRS]->{$_[1] . "|" . $_[2]}
        )
      : $_[0]->[ATTRS]->{$_[1] . "|" . $_[2]}
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

=item B<add ($simxml_args = { ... })>

=item B<add (\$unescaped)>

=item B<add ($nodes = [$node1, $node2, ...])>

Adds a sub-node to the current node.

=cut

sub add {
   my ($self, $node, @args) = @_;

   my $n;
   if (ref ($node) eq 'AnyEvent::XMPP::Node') {
      push @{$self->[NODES]}, [NNODE, $n = $node];
   } elsif (ref ($node) eq 'SCALAR') {
      push @{$self->[NODES]}, [NRAW,  $n = $node];
   } elsif (ref ($node) eq 'HASH') {
      push @{$self->[NODES]}, [NNODE, $n = simxml (%$node)];
   } elsif (ref ($node) eq 'ARRAY') {
      push @{$self->[NODES]}, [NNODE, $n = $_] for @$node;
   } elsif (@args > 0) {
      push @{$self->[NODES]}, [NNODE, $n = AnyEvent::XMPP::Node->new ($node, @args)];
   } else {
      my $found = 0;
      for (my $i = @{$self->[NODES]} - 1; $i >= 0; $i--) {
         next if $self->[NODES]->[$i]->[0] == NPARS;
         if ($self->[NODES]->[$i]->[0] == NTEXT) {
            $self->[NODES]->[$i]->[1] .= $node;
            $found = 1;
         }
      }
      unless ($found) {
         push @{$self->[NODES]}, [NTEXT, $n = $node]
      }
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

=item B<add_decl_prefix ($namespace_or_abbrev, $prefix)>

This will append a prefix declaration directly to the node.

=cut

sub add_decl_prefix {
   my ($self, $nsdecl, $prefix) = @_;
   push @{$self->[NSDECLS]}, [xmpp_ns_maybe ($nsdecl), $prefix];
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
      map { $_->[0] == NPARS ? $_->[1] : $_->[1]->raw_string }
         grep { $_->[0] != NTEXT }
            @{$self->[NODES]};
}

=item B<as_string ($indent)>

This function will serialize this node to an unicode XML string,
ready for being UTF-8 encoded and written to the socket.

=cut

# Welcome to XML nightmare!!!!!!
sub as_string {
   my ($self, $indent, $subdecls, $idcnt) = @_;

   my $name      = $self->[NAME];
   my $ns        = $self->[NS];
   my $elem_name = $name;

   $subdecls = { %{$subdecls || {}} };
   my @attrs;

   for (sort { $a->[1] cmp $b->[1] } @{$self->[NSDECLS] || []}) {
      if (not (exists $subdecls->{$_->[1]})
          || $subdecls->{$_->[1]} ne $_->[0]) {

         push @attrs, [$_->[1], $_->[0], 'xmlns'];
         $subdecls->{$_->[0]} = $_->[1];
      }
   }

   if (defined ($ns)) {
      unless (exists $subdecls->{$ns}) {
         my $pref = $subdecls->{$ns} = 'ns' . ++$idcnt;
         unshift @attrs, [$pref, $ns, 'xmlns']
      }
      $elem_name = $subdecls->{$ns} eq '' ? $name : "$subdecls->{$ns}:$name";
   }

   for my $ak (sort keys %{$self->[ATTRS] || {}}) {
      my ($ans, $name) = split /\|/, $ak;
      my $pref;

      if ($ans ne $ns) { # optimisation: attributes without prefix have
                         # the namespace of the lement they are in
         if (exists $subdecls->{$ans}) {
            $pref = $subdecls->{$ans};

         } else { 
            $pref = $subdecls->{$ans} = 'ns' . ++$idcnt;
            unshift @attrs, [$pref, $ans, 'xmlns']
         }
      }

      push @attrs, [$name, $self->[ATTRS]->{$ak}, $pref]
   }

   if ($self->[FLAGS] & ONLY_END) {
      return "</$elem_name>";
   }

   my $start = 
      "<$elem_name"
      . (join '', map { ' ' . $_ } map {
           my ($name, $value, $pref) = @$_;
           (substr ($name, 0, 4) eq 'xml:')
               ? "$name=\"" . xml_escape ($value) ."\""
               : (
           $pref eq ''
              ? "$name=\"" . xml_escape ($value) ."\""
              : "$pref" . ($name ne '' ? "\:$name" : '')
                 . '="' . xml_escape ($value) . "\""
           )
        } grep { defined $_->[1] } @attrs);

   if ($self->[FLAGS] & ONLY_START) {
      return $start . ">";
   }

   my $child_data =
      join '', map {
         my $str;

         if ($_->[0] == NNODE) {
            $str = $_->[1]->as_string ($indent, $subdecls, $idcnt)

         } elsif ($_->[0] == NTEXT) {
            $str = xml_escape ($_->[1])

         } elsif ($_->[0] == NRAW) {
            $str = ${$_->[1]};
         }

         $str ne '' ?  $str . ($indent ? "\n" : "") : ''
      } @{$self->[NODES]};

   if ($indent) {
      return $start 
         . ($child_data ne ''
              ? ">\n" . (join "\n", map { "  " . $_ } split /\n/, $child_data)
                 . "\n</$elem_name>"
              : "/>")
   } else {
      return $start . ($child_data ne '' ? ">" . $child_data . "</$elem_name>" : "/>")
   }
}

=item B<append_parsed ($string)>

This method is called by the parser to store original strings of this element.

=cut

sub append_parsed {
   my ($self, $str) = @_;
   my ($np) = grep { $_->[0] == NPARS } @{$self->[NODES]};
   if ($np) {
      $np->[1] .= $str;
   } else {
      push @{$self->[NODES]}, [NPARS, $str];
   }
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


=item $node->set_only_start ()

This will set a flag that will prevent the element from having
an end tag.

=item $node->set_only_end ()

This will set a flag that will prevent the element from having
a start tag and contents.

=cut

sub set_only_start { $_[0]->[FLAGS] |= ONLY_START }
sub set_only_end   { $_[0]->[FLAGS] |= ONLY_END   }

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007, 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::XMPP
