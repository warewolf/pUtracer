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

use constant {
  AnodeR1 => 5230,
  AnodeR2 => 470000,
  AnodeRs => 17.8,
  #
  ScreenR1 => 5230,
  ScreenR2 => 470000,
  ScreenRs => 17.8,
};

# XXX factor these aliases out?
use constant {
  AnodeDivR1 => AnodeR1,
  AnodeDivR2 => AnodeR2,
  ScreenDivR1 => ScreenR1,
  ScreenDivR2 => ScreenR2,
};

use constant { # {{{
  SCALE_VSU  => (5/1023)*(1800+6800)/1800,
  SCALE_IA => 5*1024,
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
my $CalVar1  = 1018/1000; #  Va Gain
my $CalVar2  = 1008/1000; # Vs Gain
my $CalVar3  =  990/1000; # Ia Gain
my $CalVar4  =  985/1000; # Is Gain
my $CalVar5  = 1011/1000; # VsupSystem
my $CalVar6  = 1014/1000; # Vgrid(40V)
my $CalVar7  = 1000/1000; # VglowA
my $CalVar8  = 1018/1000; # Vgrid(4V)
my $CalVar9  =  996/1000; # Vgrid(sat)
my $CalVar10 = 1000/1000; # VglowB

# my PSU voltage (YMMV)
my $VsupSystem=824*SCALE_VSU*$CalVar5;
print "vsup = $VsupSystem\n";


my ($VsupR1,$VSupR2) = (1800,6800);
my ($ScreenDivR1,$ScreenDivR2)= (5230,470000); # XXX THESE ARE THE SAME AS ScreenR1 ScreenR2
my ($AnodeDivR1,$AnodeDivR2)= (5230,470000); # XXX THESE ARE THE SAME AS AnodeR1 AnodeR2
my ($VminR1, $VminR2) = (2000,47000); # negative supply

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
  return ((-1024 * $voltage  * $CalVar6) / 50) + 0.00001
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
