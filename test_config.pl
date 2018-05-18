#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use Config::General;
use Data::Dumper;
use File::Slurp;

#my $cfg = Config::General->new( "app.ini" );
#my %config = $cfg->getall();
#my %caltags = %{$config{caltags}};
#
#my $calcfg = Config::General->new( "app.cal" );
#my %cals = reverse $calcfg->getall();
#
##my %cals = reverse %tmpcals;
##print Dumper %cals;
#
#my %calset;
#foreach my $item (keys %caltags) {
#     $calset{$item} = $cals{$caltags{$item}} /1000;
#     if ($calset{$item} == 0) { $calset{$item} = 1; }
#}
#
#foreach my $item (sort keys %calset) {
#    
#    printf("%10s\t%6.3f\n",$item, $calset{$item});
#}
my %cal;
my @lines = read_file('app.cal');
my $count = 0;
foreach my $line (@lines) {
    $count++;
    my $idx = "CalVar" . $count;
    $line =~ s/\s+//;
    ($cal{$idx}, my $dud) = split( /\s+/, $line );
    if ($count >= 10) {last;}
}

foreach my $var (sort keys %cal) {
    printf("%10s\t%6.3f\n",$var, $cal{$var});
}    




