#!/usr/bin/perl
# vim: foldmethod=marker ts=4 sw=2 commentstring=\ #\ %s

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Pod::Usage;
use Device::SerialPort;
use constant {
  CMD_START => "00",
  CMD_MEASURE => "10",
  CMD_HOLD => "20", # for magic eye?
  CMD_END => "30",
  CMD_FILAMENT => "40",
  CMD_PING => "50"
};

my $tubes = {
  "12AU7" => {
    "vg" => -8.5, # grid volts
    "va" => 250,  # plate volts
    "rp" => 7700, # plate resistance, in ohms
    "ia" => 10.5, # plate current, in mA
    "gm" => 2.2,  # transconductance, in mA/V
    "mu" => 17,   # amplification factor
    "vf" => 12.6, # filament voltage (in series, not using center tap)
  },  
  "12AX7" => { # {{{
    "vg" => -2,
    "va" => 250,
    "rp" => 6250,
    "ia" => 1.2,
    "gm" => 1.6,
    "mu" => 100,
    "vf" => 12.6,
  },   # }}}
  "5751" => { # {{{
    "vg" => -3,
    "va" => 250,
    "rp" => 5800,
    "ia" => 1.0,
    "gm" => 1.6,
    "mu" => 70,
    "vf" => 12.6,
  },   # }}}
};

my $opts; $opts = { 
  tube => sub { # {{{
    $_[1] = uc $_[1];
    if (exists $tubes->{$_[1]}) {
      map { $opts->{$_} = $tubes->{$_[1]}->{$_} } keys %{ $tubes->{$_[1]} }; 
    } else {
      die "Don't know tube type $_[1]";
    }
  }, # }}}
};

GetOptions($opts,"hot","device=s","tube=s","vg=f","va=f","rp=f","ia=f","gm=f","mu=f","hv=f","name=s") || pod2usage(2);
delete $opts->{tube};

#dblCalVar1  = Va Gain
my $CalVar1=1018/1000;
#dblCalVar2  = Vs Gain
#dblCalVar3  = Ia Gain
#dblCalVar4  = Is Gain
#dblCalVar5  = Vsupp
#dblCalVar6  = Vgrid(40V)
#dblCalVar7  = VglowA
#dblCalVar8  = Vgrid(4V)
#dblCalVar9  = Vgrid(sat)
#dblCalVar10 = VglowB

my $VsupSystem=824;

# 400v version
my ($AnodeR1,$AnodeR2,$AnodeRs) = (5230,470000,17.8);

sub getVa {
  my ($voltage) = @_;
  return (1024 / 5) * ($AnodeR1 / ($AnodeR1 + $AnodeR2)) * ($voltage + $VsupSystem) * $CalVar1;
}
my ($ScreenR1,$ScreenR2,$ScreenRs) = (5230,470000,17.8);

printf("VA at %d = %d\n",200,getVa(200));

__END__

=head1 NAME

puTracer - command line quick test

=head1 SYNOPSIS

putracer.pl --tube 12AU7
