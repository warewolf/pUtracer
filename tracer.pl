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
  CMD_START        => 0x00,
  CMD_MEASURE      => 0x10,
  CMD_MEASURE_HOLD => 0x20,    # for magic eye?
  CMD_END          => 0x30,
  CMD_FILAMENT     => 0x40,
  CMD_PING         => 0x50
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
  DECODE_SCALE_IA  => 1000 / AnodeRs,
  DECODE_SCALE_IS  => 1000 / ScreenRs,
  # 
  DECODE_TRACER => 5/1024, # decode values from the tracer
  DECODE_SCALE_VA => (AnodeR1 + AnodeR2) / AnodeR1,
  DECODE_SCALE_VS => (ScreenR1 + ScreenR2) / ScreenR1,

  ENCODE_TRACER => 1024/5, # encode values to the tracer
  ENCODE_SCALE_VA => AnodeR1 / (AnodeR1 + AnodeR2),
  ENCODE_SCALE_VS => ScreenR1 / (ScreenR1 + ScreenR2),
  ENCODE_SCALE_VG => -1023/50,

  SCALE_VSU => (VsupR1+VsupR2)/VsupR1, # needs calibration scale

}; # }}}

my $averaging_to_tracer = { # {{{
  auto => 0x40,
    32 => 0x20,
    16 => 0x10,
     8 => 0x08,
     4 => 0x04,
     2 => 0x02,
     1 => 0x01,
}; # }}}

# decode gain from uTracer to a human readable value
my $gain_from_tracer = { # {{{
  0x08 => "auto",
  0x07 => 200,
  0x06 => 100,
  0x05 => 50,
  0x04 => 20,
  0x03 => 10,
  0x02 => 5,
  0x01 => 2,
  0x00 => 1,
}; # }}}

my $gain_to_tracer = {};
@{$gain_to_tracer}{values %$gain_from_tracer} = keys %$gain_from_tracer;

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

my $compliance_to_tracer = { # {{{
  200 => 0x8F,
  175 => 0x8C,
  150 => 0xAD,
  125 => 0xAB,
  100 => 0x84,
  75 => 0x81,
  50 => 0xA4,
  25 => 0xA2,
  0 =>  0x00,
}; # }}}

my $tubes = { # {{{
  "resistor" => { # {{{
    "vg" => -1, # grid volts
    "va" => "2-200/2",  # plate volts
    "vs" => "2-200/2",  # plate volts
    "rp" => 7700, # plate resistance, in ohms
    "ia" => 10.5, # plate current, in mA
    "gm" => 2.2,  # transconductance, in mA/V
    "mu" => 17,   # amplification factor
    "vf" => 0, # filament voltage (in series, not using center tap)
  },   # }}}
  "12au7-quick" => { # {{{
    "vg" => -8.5, # grid volts
    "va" => 250,  # plate volts
    "vs" => 250,  # plate volts
    "rp" => 7700, # plate resistance, in ohms
    "ia" => 10.5, # plate current, in mA
    "gm" => 2.2,  # transconductance, in mA/V
    "mu" => 17,   # amplification factor
    "vf" => 12.6, # filament voltage (in series, not using center tap)
  },   # }}}
  "12ax7-quick" => { # {{{
    "vg" => -2,
    "va" => 250,
    "vs" => 250,
    "rp" => 6250,
    "ia" => 1.2,
    "gm" => 1.6,
    "mu" => 100,
    "vf" => 12.6,
  },   # }}}
  "12ax7-dangerous-this-will-destroy-your-tube" => { # {{{
    "vg" => "-5-0/5",
    "va" => "50-300/5",
    "vs" => "50-300/5",
    "rp" => 6250,
    "ia" => 1.2,
    "gm" => 1.6,
    "mu" => 100,
    "vf" => 12.6,
  },   # }}}
  "5751-quick" => { # {{{
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

my $opts; $opts = {  # {{{
  device => "/dev/ttyUSB0",
  debug => 0,
  verbose => 1,
  correction => 0,
  steps => 0,
  compliance => 200,
  gain => "auto",
  averaging => "auto",
  preset => sub { # {{{
    $_[1] = lc $_[1];
    $opts->{preset_name} = $_[1];
    $_[1] = "$_[1]-quick" if (! exists $tubes->{$_[1]});
    if (exists $tubes->{$_[1]}) {
      map { $opts->{$_} = $tubes->{$_[1]}->{$_} } keys %{ $tubes->{$_[1]} }; 
      $opts->{steps} = $tubes->{$_[1]}->{steps} if $tubes->{$_[1]}->{steps};
    } else {
      die "Don't know tube type $_[1]";
    }
  }, # }}}
}; # }}}

GetOptions($opts,"hot", # leave filiments on or not
  "debug",
  "verbose",
  "device=s", # serial device
  "preset=s", # preset trace settings
  "name=s",   # name to put in log
  "tube=s",   # tube type
  # 
  "vg=s","va=s","vs=s","rp=f","ia=f","gm=f","mu=f","vf=s", # value override
  "compliance=i", # miliamps 
  "averaging=i", # averaging 
  "gain=i", # gain 
  "correction", # low voltage correction
  "log=s",
) || pod2usage(2);
delete $opts->{tube};

$opts->{tube} ||= $opts->{preset_name};

# connect to uTracer
#open(my $tracer,"+<",$opts->{device}) or die "Couldn't open uTracer device $opts->{device}!: ($!)";
my $tracer = Device::SerialPort->new($opts->{device});
$tracer->baudrate(9600);
# n
$tracer->databits(8);
$tracer->stopbits(1);
$tracer->read_const_time(10000);

open(my $log,">>",$opts->{log});

# turn args into measurement steps
foreach my $arg (qw(vg va vs vf)) { # {{{
  my ($range,$steps) = split(m/\//,$opts->{$arg},2);
  
  # steps may not exist, default to 0
  $steps = defined($steps) ? $steps: 0;
  
  my ($range_start,$range_end) = ($range =~ m/(-?[\d\.]+)(?:-(-?[\d\.]+))?/);

  # range end may not exist, default to range start.
  $range_end = defined($range_end) ? $range_end : $range_start;
  
  my $sweep_width = $range_end - $range_start;
  my $step_size = $steps == 0 ? 0 : $sweep_width / $steps;
  
  # overwrite argument in $opts
  $opts->{$arg} = [];
  # add our stuff in.
  push @{ $opts->{$arg} },$range_start+$step_size*$_ for (0..$steps);
  printf("Arg: %s, start: %s, end: %s, step size: %s, steps %s\n",$arg,$range_start,$range_end,$step_size, $steps);
}  # }}}

# rough guess as to what the system supply is supposed to be
my $VsupSystem = 19.5;

sub getVa { # {{{ # getVa is done
  my ($voltage) = @_;

  die "Voltage above 400v is not supported" if ($voltage > 400);
  die "Voltage below 2v is not supported" if ($voltage < 2);
  # voltage is in reference to supply voltage, adjust
  $voltage += $VsupSystem;
  my $ret = $voltage * ENCODE_TRACER * ENCODE_SCALE_VA * CalVar1;
  if ($ret > 1023) {
    warn "Va voltage too high, clamping";
    $ret = 1023;
  }
  return $ret;
  
} # }}}

sub getVs { # {{{ # getVs is done
  my ($voltage) = @_;

  die "Voltage above 400v is not supported" if ($voltage > 400);
  die "Voltage below 2v is not supported" if ($voltage < 2);

  # voltage is in reference to supply voltage, adjust
  $voltage+= $VsupSystem;
  my $ret = $voltage * ENCODE_TRACER * ENCODE_SCALE_VS * CalVar2;
  if ($ret > 1023) {
    warn "Vs voltage too high, clamping";
    $ret = 1023;
  }
  return $ret;
} # }}}

# also PWM, mapping a 0 - 5V to 0 - -50V, referenced from the system supply
sub getVg { # {{{ # getVg is done
  my ($voltage) = @_;
  my $cal;

  if (abs($voltage) == $voltage) {
    die "Positive grid voltages, from the grid terminal are not supported.  Cheat with screen/anode terminal.";
  }

  if (abs($voltage) > 4) { # {{{
    $cal = CalVar6;
  } else {
    $cal = CalVar8;
  } # }}}
  
  my $ret = ENCODE_SCALE_VG * $voltage * $cal;

  if ($ret > 1023) {
    warn "Grid voltage too high, clamping to max";
    $ret = 1023;
  }

  if ($ret < 0) {
    warn  "Grid voltage too low, clamping to min";
    $ret = 0;
  }

  return $ret;
} # }}}

sub getVf { # {{{ # getVf is done
  my ($voltage) = @_;
  my $ret = 1024 * ( $voltage ** 2) / ($VsupSystem **2) * CalVar5;
  if ($ret > 1023) {
    warn sprintf("Requested filament voltage %f > 100%% PWM duty cycle, clamping to 100%%, %f.",$voltage,$VsupSystem);
    $ret = 1023;
  } elsif ( $ret < 0) {
    warn sprintf("Requested filament voltage %f < 0%% PWM duty cycle, clamping to 0%%.",$voltage);
    $ret = 0;
  }
  return $ret;
} # }}}

#printf("Va at %d = %04x\n",$opts->{va},getVa($opts->{va}));
#printf("Vs at %d = %04x\n",$opts->{vs},getVs($opts->{vs}));
#printf("Vg at %d = %04x\n",$opts->{vg},getVg($opts->{vg}));
#printf("Vf at %2.1f = %04x\n",$opts->{vf},getVf($opts->{vf}));

do_curve();

sub do_curve {
  # 00 - all zeros turn everything off 
  send_settings(compliance => 0, averaging => 0, gain_is => 0, gain_ia => 0);

  # 50 - read out AD
  my $data = ping();

  # set filament
  # 40 - set fil voltage (repeated 10x) +=10% of voltage, once a second
  if ($opts->{hot}) {
    # "hot" mode - just set it to max
	  set_filament($opts->{vf}->[-1]);
  } else {
    # cold mode - ramp it up slowly
	foreach my $mult (1..10) {
	  set_filament($mult* ( $opts->{vf}->[-1]/10));
	  sleep 1;
	}
  }

  #   00 - set settings
  send_settings(compliance => 200, averaging => "auto", gain_is => "auto", gain_ia => "auto");
  #   10 - do measurement
  foreach my $vg_step (0 .. $#{$opts->{vg}}) {
    foreach my $step (0 ..  $#{$opts->{va}}) {
	  printf("Measuring Vg: %d\tVa: %d\tVs: %d\tVf: %f\n",
		$opts->{vg}->[$vg_step],
		$opts->{va}->[$step],
		$opts->{vs}->[$step],
		$opts->{vf}->[$step] || $opts->{vf}->[0]) if ($opts->{verbose});
      my $measurement = do_measurement(
		vg => $opts->{vg}->[$vg_step],
		va => $opts->{va}->[$step],
		vs => $opts->{vs}->[$step],
		vf => $opts->{vf}->[$step] || $opts->{vf}->[0],
      );
      # name tube Vpsu Vmin Vg Va Va_meas Ia Vs Vs_meas Is Vf
      $log->printf("%s\t%s\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\n",
        $opts->{name},
        $opts->{tube},
        $measurement->{Vpsu},
        $measurement->{Vmin},
		$opts->{vg}->[$vg_step],
		$opts->{va}->[$step],
		$measurement->{Va},
		$measurement->{Ia},
		$opts->{vs}->[$step],
		$measurement->{Vs},
		$measurement->{Is},
		$opts->{vf}->[$step] || $opts->{vf}->[0],
      );
    }
  }
  # 30 -- end measurement
  # 00 - all zeros turn everything off 
}

sub end_measurement { # {{{
  my (%args) = @_;
  my $string = sprintf("%02X00000000%02X%02X%02X%02X",
    CMD_END, 0,0,0,0
  );
  print "> $string\n" if ($opts->{debug});;
  $tracer->write($string);
  my ($bytes,$response) = $tracer->read(18);
  print "< $response\n" if ($opts->{debug});
  if ($response ne $string) { warn "uTracer returned $response, when I expected $string"; }
} # }}}
sub set_filament { # {{{

  my ($voltage) =@_;
  my $string = sprintf("%02X00000000%02X%02X%02X%02X",
	CMD_FILAMENT,
	0,0,0,$voltage
  );
  print "> $string\n" if ($opts->{debug});;
  $tracer->write($string);
  my ($bytes,$response) = $tracer->read(18);
  print "< $response\n" if ($opts->{debug});
  if ($response ne $string) { warn "uTracer returned $response, when I expected $string"; }
} # }}}

sub ping { # {{{
  my $string = sprintf("%02X00000000%02X%02X%02X%02X",
    CMD_PING,
    0,0,0,0
  );
  print "> $string\n" if ($opts->{debug});;
  $tracer->write($string);
  my ($bytes,$response) = $tracer->read(18);
  print "< $response\n" if ($opts->{debug});
  if ($response ne $string) { warn "uTracer returned $response, when I expected $string"; }
  ($bytes,$response) = $tracer->read(38);
  print "< $response\n" if ($opts->{debug});
  my $data = decode_measurement($response);
  return $data;
} # }}}

sub send_settings { # {{{
  my (%args) = @_;
  my $string = sprintf("%02X00000000%02X%02X%02X%02X",
    CMD_START,
    $compliance_to_tracer->{$args{compliance}},
    $averaging_to_tracer->{$args{averaging}} || 0,
    $gain_to_tracer->{$args{gain_is}} || 0,
    $gain_to_tracer->{$args{gain_ia}} || 0,
  );
  print "> $string\n" if ($opts->{debug});;
  $tracer->write($string);
  my ($bytes,$response) = $tracer->read(18);
  print "< $response\n" if ($opts->{debug});
  if ($response ne $string) { warn "uTracer returned $response, when I expected $string"; }
} # }}}

sub do_measurement { # {{{
  my (%args) = @_;
  my $string = sprintf("%02X%04X%04X%04X%04X",
    CMD_MEASURE,
    getVa($args{va}),
    getVs($args{vs}),
    getVg($args{vg}),
    getVf($args{vf}),
  );
  print "> $string\n" if ($opts->{debug});;
  $tracer->write($string);
  my ($bytes,$response) = $tracer->read(18);
  print "< $response\n" if ($opts->{debug});
  if ($response ne $string) { warn "uTracer returned $response, when I expected $string"; }
  ($bytes,$response) = $tracer->read(38);
  print "< $response\n" if ($opts->{debug});
  my $data = decode_measurement($response);
  return $data;
} # }}}

#my $data = decode_measurement("10 077A 0000 0724 0001 0034 0033 0338 0288 0707"); # from utracer
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

  # update PSU voltage global
  $VsupSystem = $data->{Vpsu};

  $data->{Va} *= DECODE_TRACER * DECODE_SCALE_VA * CalVar1;
  # VA is in reference to PSU, adjust
  $data->{Va} -= $data->{Vpsu};


  #$data->{Vs} = $data->{Vs} * (5/1024) * ((ScreenR1 + ScreenR2) / (ScreenR1 * CalVar2)) - $data->{Vpsu};
  $data->{Vs} *= DECODE_TRACER * DECODE_SCALE_VS * CalVar2;
  # VA is in reference to PSU, adjust
  $data->{Vs} -= $data->{Vpsu};

  $data->{Ia} *= DECODE_TRACER * DECODE_SCALE_IA * CalVar3;

  $data->{Is} *= DECODE_TRACER * DECODE_SCALE_IS * CalVar4;

  $data->{Ia_Raw} *= DECODE_TRACER * DECODE_SCALE_IA * CalVar3;

  $data->{Is_Raw} *= DECODE_TRACER * DECODE_SCALE_IS * CalVar4;

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
    
    $data->{Va} = $data->{Va} - (($data->{Ia}) / 1000) * AnodeRs - (0.6 * CalVar7);
    $data->{Vs} = $data->{Vs} - (($data->{Is}) / 1000) * ScreenRs - (0.6 * CalVar7);
  }

  if ($opts->{verbose}) {
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
