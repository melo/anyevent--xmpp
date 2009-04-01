package AnyEvent::XMPP::Util;
use strict;
no warnings;
use Encode;
use Net::LibIDN qw/idn_prep_name idn_prep_resource idn_prep_node/;
use AnyEvent::Socket;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns_maybe xmpp_ns/;
use AnyEvent::XMPP::Error::Stanza;
require Exporter;
our @EXPORT_OK = qw/resourceprep nodeprep prep_join_jid join_jid
                    split_jid stringprep_jid prep_bare_jid bare_jid
                    is_bare_jid dump_twig_xml install_default_debug_dump
                    cmp_jid cmp_bare_jid
                    node_jid domain_jid res_jid
                    prep_node_jid prep_domain_jid prep_res_jid
                    from_xmpp_datetime to_xmpp_datetime to_xmpp_time
                    xmpp_datetime_as_timestamp
                    filter_xml_chars filter_xml_attr_hash_chars xml_escape
                    new_iq new_reply new_error new_presence new_message
                    xml_unescape extract_lang_element
                    /;
our @ISA = qw/Exporter/;

=head1 NAME

AnyEvent::XMPP::Util - Utility functions for AnyEvent::XMPP

=head1 SYNOPSIS

   use AnyEvent::XMPP::Util qw/split_jid/;
   ...

=head1 FUNCTIONS

These functions can be exported if you want:

=over 4

=item B<resourceprep ($string)>

This function applies the stringprep profile for resources to C<$string>
and returns the result.

=cut

sub resourceprep {
   my ($str) = @_;
   decode_utf8 (idn_prep_resource (encode_utf8 ($str), 'UTF-8'))
}

=item B<nodeprep ($string)>

This function applies the stringprep profile for nodes to C<$string>
and returns the result.

=cut

sub nodeprep {
   my ($str) = @_;
   decode_utf8 (idn_prep_node (encode_utf8 ($str), 'UTF-8'))
}

=item B<prep_join_jid ($node, $domain, $resource)>

This function joins the parts C<$node>, C<$domain> and C<$resource>
to a full jid and applies stringprep profiles. If the profiles couldn't
be applied undef will be returned.

=cut

sub prep_join_jid {
   my ($node, $domain, $resource) = @_;
   my $jid = "";

   if ($node ne '') {
      $node = nodeprep ($node);
      return undef unless defined $node;
      $jid .= "$node\@";
   }

   $domain = $domain; # TODO: apply IDNA!
   $jid .= $domain;

   if ($resource ne '') {
      $resource = resourceprep ($resource);
      return undef unless defined $resource;
      $jid .= "/$resource";
   }

   $jid
}

=item B<join_jid ($user, $domain, $resource)>

This is a plain concatenation of C<$user>, C<$domain> and C<$resource>
without stringprep.

See also L<prep_join_jid>

=cut

sub join_jid {
   my ($node, $domain, $resource) = @_;
   my $jid = "";
   $jid .= "$node\@" if $node ne '';
   $jid .= $domain;
   $jid .= "/$resource" if $resource ne '';
   $jid
}

=item B<split_jid ($jid)>

This function splits up the C<$jid> into user/node, domain and resource
part and will return them as list.

   my ($user, $host, $res) = split_jid ($jid);

=cut

sub split_jid {
   my ($jid) = @_;
   if ($jid =~ /^(?:([^@]*)@)?([^\/]+)(?:\/(.*))?$/) {
      return ($1 eq '' ? undef : $1, $2, $3 eq '' ? undef : $3);
   } else {
      return (undef, undef, undef);
   }
}

=item B<node_jid ($jid)>

See C<prep_res_jid> below.

=item B<domain_jid ($jid)>

See C<prep_res_jid> below.

=item B<res_jid ($jid)>

See C<prep_res_jid> below.

=item B<prep_node_jid ($jid)>

See C<prep_res_jid> below.

=item B<prep_domain_jid ($jid)>

See C<prep_res_jid> below.

=item B<prep_res_jid ($jid)>

These functions return the corresponding parts of a JID.
The C<prep_> prefixed JIDs return the stringprep'ed versions.

=cut

sub node_jid   { (split_jid ($_[0]))[0] }
sub domain_jid { (split_jid ($_[0]))[1] }
sub res_jid    { (split_jid ($_[0]))[2] }

sub prep_node_jid {
   my $node = node_jid ($_[0]); defined $node ? nodeprep ($node) : undef
}
sub prep_domain_jid { domain_jid ($_[0]) }
sub prep_res_jid    {
   my $res = res_jid ($_[0]); defined $res ? resourceprep ($res) : undef
}

=item B<stringprep_jid ($jid)>

This applies stringprep to all parts of the jid according to the RFC 3920.
Use this if you want to compare two jids like this:

   stringprep_jid ($jid_a) eq stringprep_jid ($jid_b)

This function returns undef if the C<$jid> couldn't successfully be parsed
and the preparations done.

=cut

sub stringprep_jid {
   my ($jid) = @_;
   my ($user, $host, $res) = split_jid ($jid);
   return undef unless defined ($user) || defined ($host) || defined ($res);
   return prep_join_jid ($user, $host, $res);
}

=item B<cmp_jid ($jid1, $jid2)>

This function compares two jids C<$jid1> and C<$jid2>
whether they are equal.

=cut

sub cmp_jid {
   my ($jid1, $jid2) = @_;
   stringprep_jid ($jid1) eq stringprep_jid ($jid2)
}

=item B<cmp_bare_jid ($jid1, $jid2)>

This function compares two jids C<$jid1> and C<$jid2> whether their
bare part is equal.

=cut

sub cmp_bare_jid {
   my ($jid1, $jid2) = @_;
   cmp_jid (bare_jid ($jid1), bare_jid ($jid2))
}

=item B<prep_bare_jid ($jid)>

This function makes the jid C<$jid> a bare jid, meaning:
it will strip off the resource part. With stringprep.

=cut

sub prep_bare_jid {
   my ($jid) = @_;
   my ($user, $host, $res) = split_jid ($jid);
   prep_join_jid ($user, $host)
}

=item B<bare_jid ($jid)>

This function makes the jid C<$jid> a bare jid, meaning:
it will strip off the resource part. But without stringprep.

=cut

sub bare_jid {
   my ($jid) = @_;
   my ($user, $host, $res) = split_jid ($jid);
   join_jid ($user, $host)
}

=item B<is_bare_jid ($jid)>

This method returns a boolean which indicates whether C<$jid> is a 
bare JID.

=cut

sub is_bare_jid {
   my ($jid) = @_;
   my ($user, $host, $res) = split_jid ($jid);
   not defined $res
}

=item B<filter_xml_chars ($string)>

This function removes all characters from C<$string> which
are not allowed in XML and returns the new string.

=cut

sub filter_xml_chars($) {
   my ($string) = @_;
   $string =~ s/[^\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFFFF}]+//g;
   $string
}

=item B<filter_xml_attr_hash_chars ($hashref)>

This runs all values of the C<$hashref> through C<filter_xml_chars> (see above)
and changes them in-place!

=cut

sub filter_xml_attr_hash_chars {
   my ($hash) = @_;
   $hash->{$_} = filter_xml_chars $hash->{$_} for keys %$hash
}

=item B<to_xmpp_time ($sec, $min, $hour, $tz, $secfrac)>

This function transforms a time to the XMPP date time format.
The meanings and value ranges of C<$sec>, ..., C<$hour> are explained
in the perldoc of Perl's builtin C<localtime>.

C<$tz> has to be either C<"Z"> (for UTC) or of the form C<[+-]hh:mm>, it can be undefined
and wont occur in the time string then.

C<$secfrac> are optional and can be the fractions of the second.

See also XEP-0082.

=cut

sub to_xmpp_time {
   my ($sec, $min, $hour, $tz, $secfrac) = @_;
   my $frac = sprintf "%.3f", $secfrac;
   substr $frac, 0, 1, '';
   sprintf "%02d:%02d:%02d%s%s",
      $hour, $min, $sec,
      (defined $secfrac ? $frac : ""),
      (defined $tz ? $tz : "Z")
}

=item B<to_xmpp_datetime ($sec,$min,$hour,$mday,$mon,$year,$tz,$secfrac)>

This function transforms a time to the XMPP date time format.
The meanings of C<$sec>, ..., C<$year> are explained in the perldoc
of Perl's C<localtime> builtin and have the same value ranges.

C<$tz> has to be either C<"Z"> (for UTC) or of the form C<[+-]hh:mm> (offset
from UTC), if it is undefined "Z" will be used.

C<$secfrac> are optional and can be the fractions of the second.

See also XEP-0082.

=cut

sub to_xmpp_datetime {
   my ($sec, $min, $hour, $mday, $mon, $year, $tz, $secfrac) = @_;
   my $time = to_xmpp_time ($sec, $min, $hour, (defined $tz ? $tz : 'Z'), $secfrac);
   sprintf "%04d-%02d-%02dT%s", $year + 1900, $mon + 1, $mday, $time;
}

=item B<from_xmpp_datetime ($string)>

This function transforms the C<$string> which is either a time or datetime in XMPP
format. If the string was not in the right format an empty list is returned.
Otherwise this is returned:

   my ($sec, $min, $hour, $mday, $mon, $year, $tz, $secfrac)
      = from_xmpp_datetime ($string);

For the value ranges and semantics of C<$sec>, ..., C<$srcfrac> please look at the
documentation for C<to_xmpp_datetime>.

C<$tz> and C<$secfrac> might be undefined.

If C<$tz> is undefined the timezone is to be assumed to be UTC.

If C<$string> contained just a time C<$mday>, C<$mon> and C<$year> will be undefined.

See also XEP-0082.

=cut

sub from_xmpp_datetime {
   my ($string) = @_;

   if ($string !~
      /^(?:(\d{4})-?(\d{2})-?(\d{2})T)?(\d{2}):(\d{2}):(\d{2})(\.\d{3})?(Z|[+-]\d{2}:\d{2})?/)
   {
      return ()
   }

   ($6, $5, $4,
      ($3 ne '' ? $3        : undef),
      ($2 ne '' ? $2 - 1    : undef),
      ($1 ne '' ? $1 - 1900 : undef),
      ($8 ne '' ? $8        : undef),
      ($7 ne '' ? $7        : undef))
}

=item B<xmpp_datetime_as_timestamp ($string)>

This function takes the same arguments as C<from_xmpp_datetime>, but returns a
unix timestamp, like C<time ()> would.

This function requires the L<POSIX> module.

=cut

sub xmpp_datetime_as_timestamp {
   my ($string) = @_;
   require POSIX;
   my ($s, $m, $h, $md, $mon, $year, $tz) = from_xmpp_datetime ($string);
   return 0 unless defined $h;

   my $otz = $ENV{TZ};
   $ENV{TZ} = ($tz =~ /^([+-])(\d{2}):(\d{2})$/ ? "UTC$tz" : "UTC+0:00");
   POSIX::tzset ();

   my $ts = POSIX::mktime ($s, $m, $h, $md, $mon, $year);

   if (defined $otz) {
      $ENV{TZ} = $otz;
   } else {
      delete $ENV{TZ};
   }

   POSIX::tzset ();

   $ts
}

sub dump_twig_xml {
   my $data = shift;
   require XML::Twig;
   my $t = XML::Twig->new;
   if ($t->safe_parse ("<deb>$data</deb>")) {
      $t->set_pretty_print ('indented');
      return ($t->sprint . "\n");
   } else {
      return "$data\n";
   }
}

=item $xml_escaped = xml_escape ($string)

Your regular XML escape procedure. Escaping <, >, & and " characters.  It will
also run the output through filter_xml_chars, just for convenience.

=cut

our %UNESC_MAP = (
   lt => '<',
   gt => '>',
   amp => '&',
   quot => '"',
   apos => "'",
);

our %ESC_MAP = map { $UNESC_MAP{$_} => $_ } keys %UNESC_MAP;

sub xml_escape {
   my $str = shift;
   $str =~ s/([<>&"'])/&$ESC_MAP{$1};/go;
   filter_xml_chars $str
}

=item $text = xml_unescape ($xmltext)

Replaces predefined XML entities from C<$xmltext>. The inverse function of C<xml_escape>.

=cut

sub xml_unescape {
   my $str = shift;
   $str =~ s/
      &
      (
           (\#[0-9]+)
         | (\#x[0-9a-fA-F]+)
         | ([a-zA-Z]+)
      )
      ;
   /
      substr ($1, 0, 2) eq '#x'
         ? chr (hex (substr ($1, 2)))
         : (
            substr ($1, 0, 1) eq '#'
              ? chr ($1)
              : $UNESC_MAP{$1}
         )
   /gexo;
   filter_xml_chars $str
}

=item $node = new_iq ($type, %attrs)

This function generates a new L<AnyEvent::XMPP::Node> object for you,
representing an XMPP IQ stanza.

C<$type> may be one of these 4 values:

   set
   get
   result
   error

The destination and source of the stanza should be given by the C<to> and
C<from> attributes in C<%args>. C<%args> may also contain additional XML attributes
or these keys:

=over 4

=item create => $creation

This is the most important parameter for any XMPP stanza, it
allows you to create (custom) content of the stanza.

The value in C<$creation> will be added directly to the generated
L<AnyEvent::XMPP::Node> via the C<add> method. So C<$creation> may anything
that the C<add> method of L<AnyEvent::XMPP::Node> accepts.

=item sent_cb => $callback

The code reference in C<$callback> will be invoked when the serialized bytes
of the generated L<AnyEvent::XMPP::Node> is completely written out to the operating
system.

=item src => $src_jid

=item dest => $dest_jid

These two keys will set the C<src> and C<dest> keys in the meta information
of the generated L<AnyEvent::XMPP::Node> object. See L<AnyEvent::XMPP::Meta>
about the meaning of them.

=item cb => $callback

If you expect a reply to this IQ stanza you have to set a C<$callback>.
That callback will be called when either a response stanza was received
or the timeout triggered.

If the result was successful then the first argument of the callback
will be the result stanza.

If the result was an error or a timeout the first argument will be undef
and the second will contain an L<AnyEvent::XMPP::Error::IQ> object,
describing the error.

=item timeout => $seconds

This sets the timeout for this IQ stanza. It's entirely optional and
will be set to a default IQ timeout (see also L<AnyEvent::XMPP::Connection>
and L<AnyEvent::XMPP::IQTracker> for more details).

If you set the timeout to 0 no timeout will be generated.

=back

=cut

sub new_iq {
   my ($type, %args) = @_;

   my $node = AnyEvent::XMPP::Node->new (xmpp_ns ('stanza') => 'iq');
   $node->attr ('type', $type);

   if (my $int = delete $args{create}) {
      $node->add ($int);
   }

   my @reply_info;
   if (my $cb = delete $args{cb}) {
      (@reply_info) = ($cb, delete $args{timeout});
   }

   my $sent_cb = delete $args{sent_cb};
   my $src     = delete $args{src};
   my $dest    = delete $args{dest};

   $node->attr ($_ => $args{$_}) for keys %args;

   my $meta = $node->meta;
   $meta->{src}  = stringprep_jid $src if defined $src;
   $meta->{dest} = stringprep_jid $dest if defined $dest;
   $meta->set_reply_cb (@reply_info);
   $meta->add_sent_cb ($sent_cb) if defined $sent_cb;

   $node
}

=item $node = new_message ($type, $body, %args)

# TODO: document this!

=cut

sub _add_language_element {
   my ($node, $elementname, $arg) = @_;

   if (ref ($arg)) {
      $arg = { @$arg }
      if ref ($arg) eq 'ARRAY';
   } else {
      $arg = { '' => $arg };
   }

   for my $lang (keys %$arg) {
      next unless $arg->{$lang} ne '';

      $node->add ({ defns => 'stanza', node => {
         name => $elementname,
         ($lang ne '' ? (attrs => [ [xml => 'lang'] => $lang ]) : ()),
         childs => [ $arg->{$lang} ]
      }});
   }
}

sub new_message {
   my ($type, $body, %args) = @_;

   my $node = AnyEvent::XMPP::Node->new (xmpp_ns ('stanza') => 'message');
   $node->attr ('type', $type || 'chat');

   if (defined $body) {
      _add_language_element ($node, 'body', $body);
   }

   if (my $subject = delete $args{subject}) {
      _add_language_element ($node, 'subject', $subject);
   }

   if (my $thread = delete $args{thread}) {
      my @attrs;
      if (ref $thread) {
         push @attrs, (parent => $thread->[0]);
         $thread = $thread->[1];
      }

      $node->add ({ defns => 'stanza', node => {
         name => 'thread', attrs => \@attrs, childs => [ $body ] }
      });
   }

   if (my $int = delete $args{create}) {
      $node->add ($int);
   }

   my $sent_cb = delete $args{sent_cb};
   my $src     = delete $args{src};
   my $dest    = delete $args{dest};

   $node->attr ($_ => $args{$_}) for keys %args;

   my $meta = $node->meta;

   $meta->{src}  = stringprep_jid $src if defined $src;
   $meta->{dest} = stringprep_jid $dest if defined $dest;
   $meta->add_sent_cb ($sent_cb) if defined $sent_cb;

   $node
}

=item $node = new_presence ($type, $show, $status, $priority, %args)

This function generates an XMPP presence stanza of type C<$type> and returns it
as L<AnyEvent::XMPP::Node> structure.

C<$type> can be one of these values:

   undef           (stands for being 'available')
   'unavailable'
   'subscribe'
   'unsubscribe'
   'subscribed'
   'unsubscribed'

C<$show> will be the presence status, which has to be one of these:

   'available'
   'chat'
   'away'
   'xa'
   'dnd'

If C<$show> is undefined it has the same meaning as being 'available'.

C<$status> contains the human readable presence status. It can either be a
simple string or a hash reference. If it is a hash reference the keys define
the language tag and the values the human readable text for the status in that
language.

C<$priority> is the priority of the presence. C<$priority> should be either
a number or undef.

C<%args> can contain further attributes for the presence XML element or one
of these special keys:

=over 4

=item create => $creation

=item sent_cb => $coderef

=item src => $src_jid

=item dest => $dest_jid

See C<new_iq> documentation about these keys.

=back

All other keys found in C<%args> are appended as they are
as XML element attributes.

=cut

sub new_presence {
   my ($type, $show, $status, $prio, %args) = @_;

   $type = undef if $type eq 'available';

   my $node = AnyEvent::XMPP::Node->new (xmpp_ns ('stanza') => 'presence');
   $node->attr ('type', $type) if defined $type;

   if (my $int = delete $args{create}) {
      $node->add ($int);
   }

   if (defined $status) {
      _add_language_element ($node, 'status', $status);
   }

   if (defined $show) {
      $node->add ({ defns => 'stanza', node => { name => 'show', childs => [ $show ] } });
   }

   if (defined $prio) {
      $node->add ({ defns => 'stanza', node => { name => 'priority', childs => [ $prio ] } });
   }

   my $sent_cb = delete $args{sent_cb};
   my $src     = delete $args{src};
   my $dest    = delete $args{dest};

   $node->attr ($_ => $args{$_}) for keys %args;

   my $meta = $node->meta;

   $meta->{src}  = stringprep_jid $src if defined $src;
   $meta->{dest} = stringprep_jid $dest if defined $dest;
   $meta->add_sent_cb ($sent_cb) if defined $sent_cb;

   $node
}

=item $node = new_reply ($request_node, $create, %attrs)

# TODO: document this!

=cut

sub new_reply {
   my ($node, $child, %attrs) = @_;
   my $nnode = AnyEvent::XMPP::Node->new ($node->namespace, $node->name, \%attrs);

   $nnode->meta->{src}  = $node->meta->{dest} if defined $node->meta->{dest};
   $nnode->meta->{dest} = $node->meta->{src}  if defined $node->meta->{src};

   $nnode->attr (id => $node->attr ('id')) if defined $node->attr ('id');
   $nnode->attr (to => $node->attr ('from')) if defined $node->attr ('from');
   $nnode->attr (from => $node->attr ('to')) if defined $node->attr ('to');

   if ($node->name eq 'iq') {
      $nnode->attr (type => 'result')
         unless defined $nnode->attr ('type');
   }

   $nnode->add ($child);
   $nnode
}

=item $node = new_error ($error_node, $error, $type)

# TODO: document this!

=cut

sub new_error {
   my ($errstanza, $error, $type) = @_;

   my @add;

   unless (defined ($type)
           && defined $AnyEvent::XMPP::Error::Stanza::STANZA_ERRORS{$error}) {
      $type = $AnyEvent::XMPP::Error::Stanza::STANZA_ERRORS{$error}->[0];
   }

   push @add, (type => $type) if defined $type;
   push @add, (code => $AnyEvent::XMPP::Error::Stanza::STANZA_ERRORS{$error}->[1]);

   AnyEvent::XMPP::Node::simxml (
      defns => $errstanza->namespace,
      node => {
         name => 'error', attrs => \@add,
         childs => [
            { dns => 'stanzas', name => $error }
         ]
      }
   )
}

=item extract_lang_element ($node, $elementname, $struct)

=cut

sub extract_lang_element {
   my ($node, $elname, $struct) = @_;

   my (@element) = $node->find (stanza => $elname);

   my $def_element;

   for my $s (@element) {
      if (defined (my $lang = $s->attr_ns (xml => 'lang'))) {
         if ($lang eq $node->meta->{lang}) {
            $def_element = $s->text;
         }

         $struct->{'all_' . $elname}->{$lang} = $s->text;
      } else {
         $struct->{'all_' . $elname}->{''} = $s->text;
      }
   }

   $def_element = $struct->{'all_' . $elname}->{''} unless defined $def_element;
   $def_element = $element[-1]->text if ((not defined $def_element) && @element);

   $struct->{$elname} = $def_element if defined $def_element;
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
