#!/usr/bin/perl
# vim: foldmethod=marker ts=4 sw=2 commentstring=\ #\ %s

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;

my $opts = {
  steps => 5,
  vg=> "-5",
  va=> "50-300",
  vs=> "50-300",
};

GetOptions($opts,"steps=i","vg=s","va=s","vs=s");


foreach my $arg (qw(vg va vs)) {
  my $steps = $opts->{steps};
  #my ($range,$steps) = split(m/\//,$opts->{$arg},2);
  my $range = $opts->{$arg};

  # steps may not exist, default to 0
  $steps = defined($steps) ? $steps: 0;

  my ($range_start,$range_end) = ($range =~ m/(-?\d+)(?:-(-?\d+))?/);

  # range end may not exist, default to range start.
  $range_end = defined($range_end) ? $range_end : $range_start;

  my $sweep_width = $range_end - $range_start;
  my $step_size = $steps == 0 ? 0 : $sweep_width / $steps;

  # overwrite argument in $opts
  $opts->{$arg} = [];
  # add our stuff in.
  push @{ $opts->{$arg} },$range_start+$step_size*$_ for (0..$steps);
  printf("Arg: %s, start: %s, end: %s, step size: %s, steps %s\n",$arg,$range_start,$range_end,$step_size, $steps);
}
printf "steps %d\n",$#{$opts->{va}};
print Data::Dumper->Dump([$opts],[qw($opts)]);
