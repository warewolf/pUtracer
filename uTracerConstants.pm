package uTracerConstants;

use strict;
use warnings;

use Exporter qw( import );
use Const::Fast;
use Config::General;
use File::Slurp;

our @EXPORT    = qw( 
    $CMD_START $CMD_MEASURE $CMD_MEASURE_HOLD $CMD_END $CMD_FILAMENT $CMD_PING 
    $AnodeR1 $AnodeR2 $AnodeRs $ScreenR1 $ScreenR2 $ScreenRs $VsupR1 $VsupR2 $VminR1 $VminR2 
    $DECODE_SCALE_IA $DECODE_SCALE_IS $DECODE_TRACER $DECODE_SCALE_VA $DECODE_SCALE_VS 
    $ENCODE_TRACER $ENCODE_SCALE_VA $ENCODE_SCALE_VS $ENCODE_SCALE_VG  $SCALE_VSU 
    %averaging_to_tracer %gain_from_tracer %gain_to_tracer %gain_to_average @measurement_fields %compliance_to_tracer
    $cal
  );
  
# commands http://dos4ever.com/uTracerlog/tubetester2.html#protocol

const our $CMD_START        => 0x00;
const our $CMD_MEASURE      => 0x10;
const our $CMD_MEASURE_HOLD => 0x20;    # for magic eye?  ... Yes.
                                        # This holds voltage on terminals until the next command.  Kinda dangerous.
const our $CMD_END          => 0x30;
const our $CMD_FILAMENT     => 0x40;
const our $CMD_PING         => 0x50;

# Resistors in voltage dividers, 400V version.  These are not correct for other versions.
# values mostly taken from VB code provided by Ronald:
#   http://www.dos4ever.com/uTracer3/code_blocks1.txt
#   http://www.dos4ever.com/uTracer3/code_blocks2.txt

const our $AnodeR1 => 5_230;      # R32
const our $AnodeR2 => 470_000;    # R33
const our $AnodeRs => 17.8;       # R45 ... actually 18 ohm, but we cheat w/ 17.8 for correction
                                  # http://dos4ever.com/uTracerlog/tubetester2.html#examples

const our $ScreenR1 => 5_230;      # R18
const our $ScreenR2 => 470_000;    # R19
const our $ScreenRs => 17.8;       # R20 ... actually 18 ohm, but we cheat w/ 17.8 for correction
                                   # http://dos4ever.com/uTracerlog/tubetester2.html#examples
const our $VsupR1   => 1_800;      # R44
const our $VsupR2   => 6_800;      # R43
                                   #
const our $VminR1   => 2_000;      # R3 (-15v supply)
const our $VminR2   => 47_000;     # R4 (-15v supply)

const our $cal => get_cal();# Read the cal data from the app.cal file and preset to tracer as a const hash

# scale constants, 400V version
#  ... so these are basically refactored versions of Ronald's formulas in his VB code
#  ... once I got my head wrapped around what was being done, and why.
#  ... this makes it easier in my head to take a response value and multiply it by a couple modifiers.
const our $DECODE_SCALE_IA => 1000 / $AnodeRs;
const our $DECODE_SCALE_IS => 1000 / $ScreenRs;

# Read the config to get the CalVars
my $cfg = Config::General->new("app.ini");
my %config  = $cfg->getall();

# decode values from the tracer
const our $DECODE_TRACER   => 5 / 1024;
const our $DECODE_SCALE_VA => ( $AnodeR1 + $AnodeR2 ) / ( $AnodeR1 * $cal->{CalVar1} );
const our $DECODE_SCALE_VS => ( $ScreenR1 + $ScreenR2 ) / ( $ScreenR1 * $cal->{CalVar2} );
#
# encode values to the tracer
const our $ENCODE_TRACER   => 1024 / 5;
const our $ENCODE_SCALE_VA => $AnodeR1 / ( $AnodeR1 + $AnodeR2 );
const our $ENCODE_SCALE_VS => $ScreenR1 / ( $ScreenR1 + $ScreenR2 );
const our $ENCODE_SCALE_VG => 1023 / 50;
#
const our $SCALE_VSU => ( $VsupR1 + $VsupR2 ) / $VsupR1;    # needs calibration scale

# convert human averaging values to the values for the uTracer
const our %averaging_to_tracer => (
    auto => 0x40,
    32   => 0x20,
    16   => 0x10,
    8    => 0x08,
    4    => 0x04,
    2    => 0x02,
    1    => 0x01
);

# decode gain from uTracer to a human readable value
const our %gain_from_tracer => (
    0x08 => "auto",
    0x07 => 200,
    0x06 => 100,
    0x05 => 50,
    0x04 => 20,
    0x03 => 10,
    0x02 => 5,
    0x01 => 2,
    0x00 => 1
);

# Strike that, reverse it.  youtu.be/ZWJo2EZW8yU
const our %gain_to_tracer => (
    "auto" => 0x08,
    200 => 0x07,
    100 => 0x06,
    50 => 0x05,
    20 => 0x04,
    10 => 0x03,
    5 => 0x02,
    2 => 0x01,
    1 => 0x00
);

# measured current is divided by this, based on gain by default.
const our %gain_to_average => (
    200 => 8,
    100 => 4,
    50  => 2,
    20  => 2,
    10  => 1,
    5   => 1,
    2   => 1,
    1   => 1
);

# measurement response fields http://dos4ever.com/uTracerlog/tubetester2.html#protocol
const our @measurement_fields => qw(
  Status

  Ia
  Ia_Raw

  Is
  Is_Raw

  Va_Meas
  Vs_Meas
  Vpsu
  Vmin

  Gain_Ia
  Gain_Is
);

# mA measurement limits, aka compliance.  Values from code blocks.
const our %compliance_to_tracer => (
    200 => 0x8F,
    175 => 0x8C,
    150 => 0xAD,
    125 => 0xAB,
    100 => 0x84,
    75  => 0x81,
    50  => 0xA4,
    25  => 0xA2,
    0   => 0x00
);

# Get the calibration data from the uTracer cal file (app.cal)
sub get_cal {
    my %cal;
    my @lines = read_file('app.cal');
    my $count = 0;
    foreach my $line (@lines) {
        $count++;
        my $idx = "CalVar" . $count;
        $line =~ s/\s+//;
        ( $cal{$idx}, my $dud ) = split( /\s+/, $line );
        $cal{$idx} = $cal{$idx} / 1000;
        if ( $count >= 10 ) { last; }
    }
    return \%cal;
}


__PACKAGE__;
__END__
