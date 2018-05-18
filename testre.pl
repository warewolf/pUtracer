#!/bin/perl
my @inputs =  (

    '10:30:100',
    '120',
    
);

my $re = qr{
            \d+?:   # start
            \d+?:   # rate
            (\d+?$) # full
         }xms;

foreach my $input (@inputs) {
    print "input = '$input'\n";
    if ( $input =~ $re ) {
        print "REGEX Matched\n";
        print "1='$1'\n";
        print "2='$2'\n";
    }
    else {
        print "NO MATCH\n";
    }
}


