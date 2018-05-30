#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

my @results = (
    { va => 1,
      vs => 2,
      vg => 3,
    },
    { va => 4,
      vs => 5,
      vg => 6,
    },
    { va => 7,
      vs => 8,
      vg => 9,
    }
);

sub dumplist {
   use Data::Dumper;
   print Dumper \@_;
   return @_;
}
 

#print Dumper @results;
my ($vg) = 
    map { $_[0]->{vg} }
    #dumplist 
        grep { $_->{va} == 4 } 
            @results;

print "===========\n";
print Dumper $vg;
#print "VG='" . $vg[0]->{vg} ."'\n";

