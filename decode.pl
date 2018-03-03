#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

my $str = "100000000000000000002C002B033802870000";
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
)}=map {hex($_) } unpack("A2A4A4A4A4A4A4A4A4A2A2",$str);

# these magic scale constants came from another project, uTmax.
use constant { # {{{
  SCALE_IA => 1000.0*5.0/1023.0/18.0,
  SCALE_IA_RAW => 1000.0*5.0/1023.0/18.0,
  SCALE_IS => 1000.0*5.0/1023.0/18.0,
  SCALE_IS_RAW => 1000.0*5.0/1023.0/18.0,
  #
  SCALE_IA_400 => 1000.0*5.0/1023.0/9.0,
  SCALE_IA_400_RAW => 1000.0*5.0/1023.0/9.0,
  SCALE_IS_400 => 1000.0*5.0/1023.0/9.0,
  SCALE_IS_400_RAW => 1000.0*5.0/1023.0/9.0,
  #
  SCALE_VA => (470.0+5.23)/5.230, # oh, son of a bitch this is wrong. 6.8k is 300V version.  Should be 5.23
  SCALE_VS => (470.0+5.230)/5.230, # oh, son of a bitch this is wrong. 6.8k is 300V version.  Should be 5.23
  SCALE_VSU => 5.0/1023.0*(1.8+6.8)/1.8,
  SCALE_VN=> 49.0/2.0,
  SCALE_GAIN_A=>1,
  SCALE_GAIN_S => 1,
}; # }}}

use constant {
  HEAT_CNT_MAX => 20,
};

print "Scale VSU = ",SCALE_VSU,"\n";

print "Before scale:\n";
print Data::Dumper->Dump([$data],[qw($data)]);
$data->{psu_voltage} *= SCALE_VSU;
$data->{psu_voltage} *= 1.011; # calibration value
print "\nAfter scale:\n";  
print Data::Dumper->Dump([$data],[qw($data)]);
