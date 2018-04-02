#!/usr/bin/perl

use strict;
use warnings;
use List::Util qw(all);
use Data::Dumper;

my $opts = {
  ia => 1.0,
  rp => 58,
  gm => 1.2,
  mu => 70,
  percent => 10,
};

my $min = {
  ia => $opts->{ia} * ($opts->{percent}/100), 
  is => $opts->{ia} * ($opts->{percent}/100), 
  ra => $opts->{rp} * ($opts->{percent}/100), 
  rs => $opts->{rp} * ($opts->{percent}/100), 
  gma => $opts->{gm} * ($opts->{percent}/100), 
  gms => $opts->{gm} * ($opts->{percent}/100), 
  mua => $opts->{mu} * ($opts->{percent}/100), 
  mus => $opts->{mu} * ($opts->{percent}/100), 
};

my $max = {
  ia => $opts->{ia} * 1+($opts->{percent}/100), 
  is => $opts->{ia} * 1+($opts->{percent}/100), 
  ra => $opts->{rp} * 1+($opts->{percent}/100), 
  rs => $opts->{rp} * 1+($opts->{percent}/100), 
  gma => $opts->{gm} * 1+($opts->{percent}/100), 
  gms => $opts->{gm} * 1+($opts->{percent}/100), 
  mua => $opts->{mu} * 1+($opts->{percent}/100), 
  mus => $opts->{mu} * 1+($opts->{percent}/100), 
};

print Data::Dumper->Dump([$opts],[qw($opts)]);
print Data::Dumper->Dump([$min],[qw($min)]);
print Data::Dumper->Dump([$max],[qw($max)]);
while (my $line = <>) {
  chomp $line;
  next if ($line =~ m/^Type/);
  my $tube;
  @{$tube}{qw(type serial ia is ra rs gma gms mua mus)} = split(m/\t/,$line);
  if (all {
     #printf("tube %s %f >= %f\n",$_, $tube->{$_},$min->{$_});
     #printf("tube %s %f <= %f\n",$_, $tube->{$_},$max->{$_});
     $tube->{$_} >= $min->{$_} &&
     $tube->{$_} <= $max->{$_}  } qw(ra rs gma gms))  {
    print "$line\n" 
  }
}
