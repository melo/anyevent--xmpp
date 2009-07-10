#!perl
no warnings;
use strict;

use AnyEvent::XMPP::Util qw/resourceprep nodeprep/;
use Encode;
use Net::LibIDN ':all';

unless (@ARGV) {
   print "1..0\n";
   exit;
}

for (my $i = 0x0000; $i < 0xE0FFF; $i++) {
   my $c = chr ($i);

   my ($res, $res2);

   if ($ARGV[0] eq 'node') {
      $res  = idn_prep_node (encode ('utf-8', $c), 'utf-8');
      $res  = decode ('utf-8', $res) if defined $res;
      $res2 = nodeprep ($c);
   } elsif ($ARGV[0] eq 'resource') {
      $res  = idn_prep_resource (encode ('utf-8', $c), 'utf-8');
      $res  = decode ('utf-8', $res) if defined $res;
      $res2 = resourceprep ($c);
   }

   if (not defined $res) {
      unless (not defined $res2) {
         warn sprintf "error at char %x: not undef: %s (%x)\n",
                      $i, $res2, ord ($res2);
      }
   } else {
      unless ($res eq $res2) {
         warn sprintf
            "error at char %x: not equal: %s (%x) != %s (%x)\n",
            $i, $res, ord ($res), $res2, ord ($res2);
      }
   }

   if ($i % 10000 == 0) { print "$i\n" }
}
