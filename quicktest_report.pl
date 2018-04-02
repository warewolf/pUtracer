#!/usr/bin/perl

use strict;
use warnings;

my $tube_ref;
  printf("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",qw(
    Type Serial
    Ia Is
    Ra Rs
    GmA GmS
    MuA MuS
  ));
while (my $file = shift @ARGV) {
  my ($name) = ($file =~ m/\/?([^\/]+)$/);
  @{$tube_ref}{qw(type serial)} = split(m/-/,$name,3);
  open (my $fh, "<",$file) or die "Couldn't open $file for reading! ($!)";
  while (my $line = <$fh>) {
    chomp $line;
    next unless $line =~ m/Test Results/;
    if ($line =~ m/Ia:/) {
      ($tube_ref->{ia}) = ($line =~ m/Ia:? ([\d\.]+) mA/);
      ($tube_ref->{ra}) = ($line =~ m/Ra:? ([\d\.]+) kOhm/);
      ($tube_ref->{gma}) = ($line =~ m/Gm:? ([\d\.]+) mA\/V/);
      ($tube_ref->{mua}) = ($line =~ m/Mu:? ([\d\.]+)/);
    } elsif ($line =~ m/Is:/) {
      ($tube_ref->{is}) = ($line =~ m/Is:? ([\d\.]+) mA/);
      ($tube_ref->{rs}) = ($line =~ m/Rs:? ([\d\.]+) kOhm/);
      ($tube_ref->{gms}) = ($line =~ m/Gm:? ([\d\.]+) mA\/V/);
      ($tube_ref->{mus}) = ($line =~ m/Mu:? ([\d\.]+)/);
    }
  }
} continue {
  printf("%s\t%s\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%d\t%d\n",@{$tube_ref}{qw(
    type serial
    ia is
    ra rs
    gma gms
    mua mus
  )});
}
