#!perl
use Net::LibIDN ':all';
use Unicode::Stringprep;
use Encode;

my $nodeprof =
   Unicode::Stringprep->new (
      3.2,
      [
         \@Unicode::Stringprep::Mapping::B1,
         \@Unicode::Stringprep::Mapping::B2
      ],
      'KC',
      [
         [0x22, 0x22],
         [0x26, 0x27],
         [0x2F, 0x2F],
         [0x3A, 0x3A],
         [0x3C, 0x3C],
         [0x3E, 0x3E],
         [0x40, 0x40],
         \@Unicode::Stringprep::Prohibited::C11,
         \@Unicode::Stringprep::Prohibited::C12,
         \@Unicode::Stringprep::Prohibited::C21,
         \@Unicode::Stringprep::Prohibited::C22,
         \@Unicode::Stringprep::Prohibited::C3,
         \@Unicode::Stringprep::Prohibited::C4,
         \@Unicode::Stringprep::Prohibited::C5,
         \@Unicode::Stringprep::Prohibited::C6,
         \@Unicode::Stringprep::Prohibited::C7,
         \@Unicode::Stringprep::Prohibited::C8,
         \@Unicode::Stringprep::Prohibited::C9,
      ],
      0
   );

for (my $i = 0x0000; $i < 0xE0FFF; $i++) {
   my $c = chr ($i);
   my $res  = idn_prep_node (encode ('utf-8', $c), 'utf-8');
   $res = decode ('utf-8', $res) if defined $res;
   my $res2 = eval { $nodeprof->($c) };
   if ($@) { $res2 = undef }

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
