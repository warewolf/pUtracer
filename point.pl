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

# Resistors in voltage dividers, 400V version
use constant {
  AnodeR1 => 5_230,   # R32
  AnodeR2 => 470_000, # R33
  AnodeRs => 17.8,    # R45 ... actually 18 ohm, but we cheat w/ 17.8 for correction http://dos4ever.com/uTracerlog/tubetester2.html#examples
  #
  ScreenR1 => 5_230,   # R18
  ScreenR2 => 470_000, # R19
  ScreenRs => 17.8,    # R20 ... actually 18 ohm, but we cheat w/ 17.8 for correction http://dos4ever.com/uTracerlog/tubetester2.html#examples
  #
  VsupR1 => 1_800, # R44
  VsupR2 => 6_800, # R43
  #
  VminR1 => 2_000, # R3 (-15v supply)
  VminR2 => 47_000 # R4 (-15v supply)
};

# XXX factor these aliases out?
use constant {
  AnodeDivR1 => AnodeR1,
  AnodeDivR2 => AnodeR2,
  ScreenDivR1 => ScreenR1,
  ScreenDivR2 => ScreenR2,
};

# calculations to go to/fro stuff
use constant { # {{{

  SCALE_VSU    => ( 5 / 1024 ) * (VsupR1+VsupR2)/VsupR1, # needs calibration scale
  # 
  SCALE_IA     => ( 5 / 1024 ) * 1000 / AnodeRs, # needs calibration scale
  SCALE_IA_PGA => ( 5 / 1024 ) * 1000 / AnodeRs, # needs calibration scale
  #
  SCALE_IS     => ( 5 / 1024 ) * 1000 / ScreenRs, # needs calibration scale
  SCALE_IS_PGA => ( 5 / 1024 ) * 1000 / ScreenRs, # needs calibration scale
  #
  SCALE_VA     => ( 5 / 1024 ) * ((AnodeDivR1 + AnodeDivR2) / AnodeDivR1), # subtract supply voltage, needs calibration
  SCALE_VS     => ( 5 / 1024 ) * ((ScreenDivR1 + ScreenDivR2) / ScreenDivR1), # subtract supply voltage, needs calibration
  #
  #SCALE_VN     =>  # I have no fucking clue how to do this, I don't think I can do the way I want to.
  
}; # }}}

my $tubes = { # {{{
  "12AU7" => { # {{{
    "vg" => -8.5, # grid volts
    "va" => 250,  # plate volts
    "vs" => 250,  # plate volts
    "rp" => 7700, # plate resistance, in ohms
    "ia" => 10.5, # plate current, in mA
    "gm" => 2.2,  # transconductance, in mA/V
    "mu" => 17,   # amplification factor
    "vf" => 12.6, # filament voltage (in series, not using center tap)
  },   # }}}
  "12AX7" => { # {{{
    "vg" => -2,
    "va" => 250,
    "vs" => 250,
    "rp" => 6250,
    "ia" => 1.2,
    "gm" => 1.6,
    "mu" => 100,
    "vf" => 12.6,
  },   # }}}
  "5751" => { # {{{
    "vg" => -3,
    "va" => 250,
    "vs" => 250,
    "rp" => 5800,
    "ia" => 1.0,
    "gm" => 1.6,
    "mu" => 70,
    "vf" => 12.6,
  },   # }}}
}; # }}}

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

GetOptions($opts,"hot","device=s","tube=s","vg=f","va=i","vs=i","rp=f","ia=f","gm=f","mu=f","vf=f","name=s") || pod2usage(2);
delete $opts->{tube};

# my calibration values (YMMV)
my $CalVar1  = 1018/1000; # Va Gain
my $CalVar2  = 1008/1000; # Vs Gain
my $CalVar3  =  990/1000; # Ia Gain
my $CalVar4  =  985/1000; # Is Gain
my $CalVar5  = 1011/1000; # VsupSystem
my $CalVar6  = 1014/1000; # Vgrid(40V)
my $CalVar7  = 1000/1000; # VglowA
my $CalVar8  = 1018/1000; # Vgrid(4V)
my $CalVar9  =  996/1000; # Vgrid(sat)
my $CalVar10 = 1000/1000; # VglowB, unused?

# my PSU voltage (YMMV)
my $VsupSystem=824*SCALE_VSU*$CalVar5;
print "vsup = $VsupSystem\n";

my ($Ia,$IaComp) = (0,0); # Ia is anode current, IaComp is anode current before PGA
my ($Is,$IsComp) = (0,0); # Is is screen current, IsComp is screen current before PGA

sub getVa {
  my ($voltage) = @_;
  return (1024 / 5) * (AnodeR1 / (AnodeR1 + AnodeR2)) * ($voltage + $VsupSystem) * $CalVar1;
}

sub getVs {
  my ($voltage) = @_;
  return ((1024 / 5) * (ScreenR1 / (ScreenR1 + ScreenR2)) * ($voltage + $VsupSystem) * $CalVar2);
}

sub getVg {
  my ($voltage) = @_;
  my $cal ;
  if (abs($voltage) > 4) {
    print STDERR "Using 40v calibration value\n";
    $cal = $CalVar6;
  } else {
    print STDERR "Using 4v calibration value\n";
    $cal = $CalVar8;
  }
  return ((-1023 * $voltage  * $cal) / 50) + 0.00001
}

sub getVf {
  my ($voltage) = @_;
  return 1024 * ( $voltage * $voltage) / ($VsupSystem * $VsupSystem) * $CalVar5;
}


printf("Va at %d = %04x\n",$opts->{va},getVa($opts->{va}));
printf("Vs at %d = %04x\n",$opts->{vs},getVs($opts->{vs}));
printf("Vg at %d = %04x\n",$opts->{vg},getVg($opts->{vg}));
printf("Vf at %2.1f = %04x\n",$opts->{vf},getVf($opts->{vf}));


sub decode_measurement{
  my ($string) = @_;
  my $data = {};
  @{$data}{qw(
	status_byte
	anode_current_pga
	anode_current_raw
	screen_current_pga
	screen_current_raw
	anode_voltage
	screen_volage
	psu_voltage
	negative_voltage
	anode_pga_gain
	screen_pga_gain
  )} = map {hex($_) } unpack("A2 A4 A4 A4 A4 A4 A4 A4 A4 A2 A2",$string);
  
}

__END__

=head1 NAME

puTracer - command line quick test

=head1 SYNOPSIS

putracer.pl --tube 12AU7
