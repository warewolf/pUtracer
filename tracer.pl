#!/usr/bin/perl
# vim: foldmethod=marker ts=4 sw=2 commentstring=\ #\ %s

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Pod::Usage;
use Device::SerialPort;
use List::Util qw(max);

use constant {
       CMD_START => "00",
     CMD_MEASURE => "10",
CMD_MEASURE_HOLD => "20", # for magic eye?
         CMD_END => "30",
    CMD_FILAMENT => "40",
        CMD_PING => "50"
};

# Resistors in voltage dividers, 400V version
use constant {   # {{{
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
}; # }}}

# calibration
use constant { # {{{
  CalVar1  => 1018/1000, # Va Gain
  CalVar2  => 1008/1000, # Vs Gain
  CalVar3  =>  990/1000, # Ia Gain
  CalVar4  =>  985/1000, # Is Gain
  CalVar5  => 1011/1000, # VsupSystem
  CalVar6  => 1014/1000, # Vgrid(40V)
  CalVar7  => 1000/1000, # VglowA, unused?
  CalVar8  => 1018/1000, # Vgrid(4V)
  CalVar9  =>  996/1000, # Vgrid(sat)
  CalVar10 => 1000/1000, # VglowB, unused?
}; # }}}

# scale constants
use constant { # {{{
  SCALE_IA  => 1000 / AnodeRs,
  SCALE_IS  => 1000 / ScreenRs,
  #
  SCALE_VA => (AnodeR1 + AnodeR2) / AnodeR1,
  SCALE_VS => (ScreenR1 + ScreenR2) / ScreenR1,

  SCALE_VSU => (VsupR1+VsupR2)/VsupR1, # needs calibration scale

  ENCODE_TRACER => 1024/5, # encode values to the tracer
  DECODE_TRACER => 5/1024, # decode values from the tracer
}; # }}}

# decode gain from uTracer to a human readable value
my $gain_from_tracer = { # {{{
  0x07 => 200,
  0x06 => 100,
  0x05 => 50,
  0x04 => 20,
  0x03 => 10,
  0x02 => 5,
  0x01 => 2,
  0x00 => 1,
}; # }}}

# measured current is divided by this, based on gain
my $gain_to_average = { # {{{
  200 => 8,
  100 => 4,
   50 => 2,
   20 => 2,
   10 => 1,
    5 => 1,
    2 => 1,
    1 => 1,
}; # }}}

my @measurement_fields = qw(
  Status

  Ia
  Ia_Raw

  Is
  Is_Raw

  Va
  Vs
  Vpsu
  Vmin

  Gain_Ia
  Gain_Is
);

my $compliance_to_hex = { # {{{
  200 => "8F",
  175 => "8C",
  150 => "AD",
  125 => "AB",
  100 => "84",
  75 => "81",
  50 => "A4",
  25 => "A2",
  0 =>  "00",
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
  correction => 0,
  compliance => 200,
  tube => sub { # {{{
    $_[1] = uc $_[1];
    if (exists $tubes->{$_[1]}) {
      map { $opts->{$_} = $tubes->{$_[1]}->{$_} } keys %{ $tubes->{$_[1]} }; 
    } else {
      die "Don't know tube type $_[1]";
    }
  }, # }}}
};

GetOptions($opts,"hot", # leave filiments on or not
  "debug",
  "device=s", # serial device
  "tube=s",   # tube shortcut
  "vg=f","va=i","vs=i","rp=f","ia=f","gm=f","mu=f","vf=f", # value override
  "name=s",   # name to put in log
  "compliance=i", # miliamps 
  "range_ia=i", # graph range, Ia
  "range_is=i", # graph range, Is
  "average=i", # averaging 
  "correction", # low voltage correction
) || pod2usage(2);
delete $opts->{tube};

my $VsupSystem = 19.5;

sub getVa { # {{{
  my ($voltage) = @_;
  return ENCODE_TRACER * (AnodeR1 / (AnodeR1 + AnodeR2)) * ($voltage + $VsupSystem) * CalVar1;
} # }}}

sub getVs { # {{{
  my ($voltage) = @_;
  return (ENCODE_TRACER * (ScreenR1 / (ScreenR1 + ScreenR2)) * ($voltage + $VsupSystem) * CalVar2);
} # }}}

# also PWM, mapping a 0 - 5V to 0 - -50V, referenced from the system supply
sub getVg { # {{{
  my ($voltage) = @_;
  my $cal ;
  if (abs($voltage) > 4) {
    print STDERR "Using 40v calibration value\n";
    $cal = CalVar6;
  } else {
    print STDERR "Using 4v calibration value\n";
    $cal = CalVar8;
  }
  return ((-1023 * $voltage  * $cal) / 50) + 0.00001
} # }}}

sub getVf { # {{{
  my ($voltage) = @_;
  my $ret = 1024 * ( $voltage ** 2) / ($VsupSystem **2) * CalVar5;
  if ($ret > 1023) {
    warn sprintf("Requested filament voltage %f > 100%% PWM duty cycle, clamping to 100%%, %f.",$voltage,$VsupSystem);
    $ret = 1023;
  }
  return $ret;
} # }}}


printf("Va at %d = %04x\n",$opts->{va},getVa($opts->{va}));
printf("Vs at %d = %04x\n",$opts->{vs},getVs($opts->{vs}));
printf("Vg at %d = %04x\n",$opts->{vg},getVg($opts->{vg}));
printf("Vf at %2.1f = %04x\n",$opts->{vf},getVf($opts->{vf}));


sub do_curve {
  # 00 - all zeros turn everything off 
  # 50 - read out AD
  # 40 - set fil voltage (repeated 10x) +=10% of voltage, once a second
  # $a=0; printf("%2.2f\n",$a+=12.6/10) for (0..9)
  #   00 - set settings
  #   10 - do measurement
  # 30 -- end measurement
  # 00 - all zeros turn everything off 
}

sub do_measurement {
  # strCommandString = strCommand + strA + strS + strG + strF
  #                            10   0047   0047   0016   006B
}


my $data = decode_measurement("10 077A 0000 0724 0001 0034 0033 0338 0288 0707"); # from utracer
#my $data = decode_measurement("10 02B0 0043 02B4 0044 01DB 01DA 033A 0287 0303"); # from utracer

# decode_measurement is feature-complete.
sub decode_measurement { # {{{
  my ($str) = @_;
  $str =~ s/ //g;
  my $data = {};
  @{$data}{@measurement_fields} = map {hex($_) } unpack("A2 A4 A4 A4 A4 A4 A4 A4 A4 A2 A2",$str);

  # status byte = 10 - all good.
  # status byte = 11 - compliance error
  # $compliance_error = $status_byte & 0x1 == 1;

  $data->{Vpsu} *= DECODE_TRACER * SCALE_VSU * CalVar5;

  $data->{Va} = $data->{Va} * (5/1024) * ((AnodeR1 + AnodeR2) / (AnodeR1 * CalVar1)) - $data->{Vpsu};
  $data->{Vs} = $data->{Vs} * (5/1024) * ((ScreenR1 + ScreenR2) / (ScreenR1 * CalVar2)) - $data->{Vpsu};

  $data->{Ia} *= DECODE_TRACER * SCALE_IA * CalVar3;

  $data->{Is} *= DECODE_TRACER * SCALE_IS * CalVar4;

  $data->{Ia_Raw} *= DECODE_TRACER * SCALE_IA * CalVar3;

  $data->{Is_Raw} *= DECODE_TRACER * SCALE_IS * CalVar4;

  $data->{Vmin} = 5 * ((VminR1 + VminR2) / VminR1) * (( $data->{Vmin} / 1024) - 1);
  $data->{Vmin} += 5;

  # decode gain
  @{$data}{qw(Gain_Ia Gain_Is)} = map { $gain_from_tracer->{$_} } @{$data}{qw(Gain_Ia Gain_Is)};

  # find max gain
  my $gain = max @{$data}{qw(Gain_Ia Gain_Is)};

  # fix measured current by dividing it by the number of samples (averaging)
  $data->{Ia} /= $gain_to_average->{$gain};
  $data->{Is} /= $gain_to_average->{$gain};

  # correction - this appears to be backwards?
  if ($opts->{correction}) {
    #$data->{Va} -= (($data->{Ia}) / 1000) * AnodeRs - (0.6 * CalVar7);
    #$data->{Vs} -= (($data->{Is}) / 1000) * ScreenRs - (0.6 * CalVar7);
    
    $data->{Va} = $data->{Va} - (($data->{Ia}) / 1000) * AnodeRs - (0.6 * CalVar7);
    $data->{Vs} = $data->{Vs} - (($data->{Is}) / 1000) * ScreenRs - (0.6 * CalVar7);
  }

  if ($opts->{debug}) {
    printf "stat ____ia iacmp ____is _is_comp ____va ____vs _vPSU _vneg ia_gain is_gain\n";
    printf "% 4x % 6.1f % 5.1f % 6.1f % 8.1f % 6.1f % 6.1f % 2.1f % 2.1f % 7d % 7d\n", @{$data}{@measurement_fields};
  }

  return $data;
} # }}}

__END__

=head1 NAME

puTracer - command line quick test

=head1 SYNOPSIS

putracer.pl --tube 12AU7
