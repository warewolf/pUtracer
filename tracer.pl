#!/usr/bin/perl
# vim: foldmethod=marker ts=4 sw=2 commentstring=\ #\ %s
$|++;
use strict;
use v5.10;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Pod::Usage;
use Device::SerialPort;
use List::Util qw(max first);
use POSIX qw(strftime);
my $VERSION = "0.0.1";
use Carp::Always;
use Config::General;
use File::Slurp;
use File::Basename;
use lib dirname(__FILE__);
use uTracerConstants;
use TubeDatabase;

my $cfg    = Config::General->new("app.ini");
my %config = $cfg->getall();

my $opts  = $config{options};
my $tubes = $config{tubes};
initdb();

$opts->{preset} = sub {
    $_[1]                = lc $_[1];
    $opts->{preset_name} = $_[1];
    $_[1]                = "$_[1]-quick" if ( !exists $tubes->{ $_[1] } );
    if ( exists $tubes->{ $_[1] } ) {
        map { $opts->{$_} ||= $tubes->{ $_[1] }->{$_} } keys %{ $tubes->{ $_[1] } };
    } else {
        die "Don't know tube type $_[1].  Specify vf, vg, va, vs on the command line.";
    }
};

$Getopt::Long::autoabbrev = 1;
$Getopt::Long::bundling   = 1;
GetOptions(
    $opts,
    "hot!",        # expect filiments to be hot already
    "warm!",       # leave filiments on or not
    "debug",       # protocol-level debugging
    "verbose",     # print measurement requests, and responses.
    "device=s",    # serial device
    "preset=s",    # preset trace settings
    "name=s",      # name to put in log
    "tube=s",      # tube type
    "interactive!",# prompt to store current quicktest entry in the database
    "store",       # automatically store the current quicktest in the database
                   #
    "vg=s", "va=s", "vs=s", "rp=f", "ia=f", "gm=f", "mu=f", "vf=s",    # measurement value override
    "compliance=i",                      # miliamps
    "settle=i",                          # settle delay after slow heating tube
    "averaging=i",                       # averaging
    "gain=i",                            # gain
    "correction!",                       # low voltage correction
    "log=s",
    "quicktest|quicktest-triode|qtt",    # do quicktest of triodes to a log file, rather than a sweep.
    "quicktest-pentode|qtp",             # do quicktest of pentodes to a log file, rather than a sweep.
    "offset=i",                          # quicktest offset percentage
    "calm=i",                            # delay this long before the next command after a "end measurement"
) || pod2usage(2);

# Copy in tube name from preset, if not specified on the command line.
$opts->{tube} ||= $opts->{preset_name};

# connect to uTracer
my $comport = $opts->{device};
say "Connecting to dev:'$comport'";
my $tracer = Device::SerialPort->new($comport) || die "Can't open $comport: $!\n";
$tracer->baudrate(9600);
$tracer->parity("none");
$tracer->databits(8);
$tracer->stopbits(1);

# wait this long for reads to timeout.  This is in miliseconds.
# this is stupid high so that I can simulate the uTracer with another terminal by hand.
$tracer->read_const_time(10_000);

# append log, no overwrite
open( my $log, ">>", $opts->{log} );

# turn args into measurement steps.
# This takes start-end/steps(logarithm) and makes it a list of values for each.
# ... Yes it supports fil voltage.
foreach my $arg (qw(vg va vs vf)) {    # {{{
    my ( $range, $steps ) = split( m/\//, $opts->{$arg}, 2 );
    my ($log_mode) = 0;

    # steps may not exist, default to 0
    $steps = defined($steps) ? $steps : 0;

    if ( rindex( $steps, "l" ) + 1 == length($steps) ) {
        $log_mode++;
        chop $steps;
    }

    my ( $range_start, $range_end ) = ( $range =~ m/(-?[\d\.]+)(?:-(-??[\d\.]+))?/ );

    # range end may not exist, default to range start.
    $range_end = defined($range_end) ? $range_end : $range_start;

    my $sweep_width = $range_end - $range_start;
    my $step_size = $steps == 0 ? 0 : $sweep_width / $steps;

    # overwrite argument in $opts
    $opts->{$arg} = [];

    # add our stuff in.
    if ( !$log_mode ) {
        push @{ $opts->{$arg} }, $range_start + $step_size * $_ for ( 0 .. $steps );
    } else {
        push @{ $opts->{$arg} }, $range_start;
        push @{ $opts->{$arg} }, ( $sweep_width**( $_ * ( 1 / $steps ) ) ) + $range_start for ( 0 .. $steps );
    }
}    # }}}

# rough guess as to what the system supply is supposed to be
my $VsupSystem = 19.5;

# "main"
if ( !( $opts->{quicktest} || $opts->{"quicktest-pentode"} ) ) {
    do_curve();
} elsif ( $opts->{quicktest} ) {
    quicktest_triode();
} elsif ( $opts->{"quicktest-pentode"} ) {
    quicktest_pentode();
} else {
    die "lolwat";
}

$log->close();
##END MAIN

#===========
# Begin Subs
#===========
sub getVa {    # {{{ # getVa is done
    my ($voltage) = @_;

    die "Voltage above 400v is not supported" if ( $voltage > 400 );
    die "Voltage below 2v is not supported"   if ( $voltage < 2 );

    # voltage is in reference to supply voltage, adjust
    $voltage += $VsupSystem;

    my $ret = $voltage * $ENCODE_TRACER * $ENCODE_SCALE_VA * $cal->{CalVar1};

    if ( $ret > 1023 ) {
        warn "Va voltage too high, clamping";
        $ret = 1023;
    }
    return $ret;

}    # }}}

sub getVs {    # {{{ # getVs is done
    my ($voltage) = @_;

    die "Voltage above 400v is not supported" if ( $voltage > 400 );
    die "Voltage below 2v is not supported"   if ( $voltage < 2 );

    # voltage is in reference to supply voltage, adjust
    $voltage += $VsupSystem;
    my $ret = $voltage * $ENCODE_TRACER * $ENCODE_SCALE_VS * $cal->{CalVar2};
    if ( $ret > 1023 ) {
        warn "Vs voltage too high, clamping";
        $ret = 1023;
    }
    return $ret;
}    # }}}

# also PWM, mapping a 0 - 5V to 0 - -50V, referenced from the system supply
sub getVg {    # {{{ # getVg is done
    my ($voltage) = @_;

    my $Vsat = 2 * ( $cal->{CalVar9} - 1 );
    my ( $X1, $Y1, $X2, $Y2 );
    if ( abs($voltage) <= 4 ) {
        $X1 = $Vsat;
        $Y1 = 0;
        $X2 = 4;
        $Y2 = $ENCODE_SCALE_VG * $cal->{CalVar8} * $cal->{CalVar6} * 4;
    } else {
        $X1 = 4;
        $Y1 = $ENCODE_SCALE_VG * $cal->{CalVar8} * $cal->{CalVar6} * 4;
        $X2 = 40;
        $Y2 = $ENCODE_SCALE_VG * $cal->{CalVar6} * 40;
    }

    my $AA  = ( $Y2 - $Y1 ) / ( $X2 - $X1 );
    my $BB  = $Y1 - $AA * $X1;
    my $ret = $AA * abs($voltage) + $BB;

    if ( $voltage > 0 ) {
        die "Positive grid voltages, from the grid terminal are not supported.  Cheat with screen/anode terminal.";
    }

    if ( $ret > 1023 ) {
        warn "Grid voltage too high, clamping to max";
        $ret = 1023;
    }

    if ( $ret < 0 ) {
        warn "Grid voltage too low, clamping to min";
        $ret = 0;
    }

    return $ret;
}    # }}}

sub getVf {    # {{{ # getVf is done
    my ($voltage) = @_;
    my $ret = 1024 * ( $voltage**2 ) / ( $VsupSystem**2 ) * $cal->{CalVar5};
    if ( $ret > 1023 ) {
        warn sprintf( "Requested filament voltage %f > 100%% PWM duty cycle, clamping to 100%%, %f.", $voltage, $VsupSystem );
        $ret = 1023;
    } elsif ( $ret < 0 ) {
        warn sprintf( "Requested filament voltage %f < 0%% PWM duty cycle, clamping to 0%%.", $voltage );
        $ret = 0;
    }
    return $ret;
}    # }}}


sub warmup_tube {
    if ( $opts->{hot} ) {    # {{{
                             # "hot" mode - just set it to max
        set_filament( getVf( $opts->{vf}->[-1] ) );
    } else {

        # cold mode - ramp it up slowly
        printf STDERR "Tube heating..\n";
        foreach my $mult ( 1 .. 10 ) {
            my $voltage = $mult * ( $opts->{vf}->[-1] / 10 );
            printf STDERR "Setting fil voltage to %2.1f\n", $voltage if ( $opts->{verbose} );
            set_filament( getVf($voltage) );
            sleep 1;
        }
    }    # }}}

    if ( !$opts->{hot} ) {    # {{{
        printf "Sleeping for %d seconds for tube settle ...\n", $opts->{settle} if ( $opts->{verbose} );
        sleep $opts->{settle};
    }    # }}}
    printf STDERR "Tube heated.\n";
}

sub init_voltage_ranges {
    
    my ( @va, @vs, @vg );

    # bracket Va
    push @va, $opts->{va}[0] - ( $opts->{va}[0] * ( $opts->{offset} / 100 ) );
    push @va, $opts->{va}[0] + ( $opts->{va}[0] * ( $opts->{offset} / 100 ) );
    

    # bracket Vs
    push @vs, $opts->{vs}[0] - ( $opts->{vs}[0] * ( $opts->{offset} / 100 ) );
    push @vs, $opts->{vs}[0] + ( $opts->{vs}[0] * ( $opts->{offset} / 100 ) );

    # bracket Vg
    push @vg, $opts->{vg}[0] - ( $opts->{vg}[0] * ( $opts->{offset} / 100 ) );
    push @vg, $opts->{vg}[0] + ( $opts->{vg}[0] * ( $opts->{offset} / 100 ) );

    # high
    if ( first { $_ > 400 } @va ) {
        die "Va voltages > 400v is not allowed.  Try reducing voltage, or offset percentage";
    }
    
    if ( first { $_ > 400 } @vs ) {
        die "Vs voltages > 400v is not allowed.  Try reducing voltage, or offset percentage";
    }
    # low
    if ( first { $_ < 2 } @va ) {
        die "Va voltages < 2v is not allowed.  Try increasing voltage, or decreasing offset percentage";
    }

    if ( first { $_ < 2 } @vs ) {
        die "Vs voltages < 2v is not allowed.  Try increasing voltage, or decreasing offset percentage";
    }

    # grid
    if ( first { $_ > 0 } @vg ) {
        die "Vg voltages > 0v is not allowed.";
    }
    if ( first { $_ < -40 } @vg ) {
        die "Vg voltages < -40v is not allowed.  Try increasing voltage, or decreasing offset percentage";
    }
    
    return \@va, \@vs, \@vg;
}

sub quicktest_triode {    # {{{
    printf STDERR "Running quicktest...\n";

    # print log header
    $log->printf( "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
        qw(Name Tube Point Vpsu Vmin Vg Va Va_Meas Ia Ia_Raw Ia_Gain Vs Vs_Meas Is Is_Raw Is_Gain Vf) );

    # 00 - send settings w/ compliance, etc.
    send_settings(
        compliance => $opts->{compliance},
        averaging  => $opts->{averaging},
        gain_is    => $opts->{gain},
        gain_ia    => $opts->{gain}
    );

    # 50 - read out AD
    my $data = ping();

    # set filament
    # 40 - set fil voltage (repeated 10x) +=10% of voltage, once a second
    warmup_tube();

    # do the five measurements for a triode http://dos4ever.com/uTracerlog/tubetester2.html#quicktest
    # theory explained here https://wtfamps.wordpress.com/mugmrp/
    #
    # Basically, we do four measurements offset around the suggested bias point of a tube.  The suggested bias point is the 5th.
    # Think of the pattern of dots of the 5th side of a six sided die, to visualize.

    my ($va, $vs, $vg) = init_voltage_ranges(); # make sure the requeted voltage ranges are within the capabilities of the uTracer
    my ( @todo );


    # four corner dots
    @todo = map { { va => @$va[ $_->[0] ], vs => @$vs[ $_->[0] ], vg => @$vg[ $_->[1] ] } } ( [ 0, 0 ], [ 0, 1 ], [ 1, 0 ], [ 1, 1 ] );

    # and that last center dot, to calculate current draw at the bias point center.
    push @todo, { va => $opts->{va}[0], vs => $opts->{vs}[0], vg => $opts->{vg}[0] };

    my $results = get_results_matrix(\@todo);

    # extract center point, for current draw at the bias point.
    my $center = pop @$results;

    # calculate gm
    # gm = dIa / dVg, consistent Va, changing Vg
    my ( $GmA, $GmS );

    my ($min_va) = map { $_->{Va} } sort { $a->{Va} > $b->{Va} } @$results;
    my ($max_va) = map { $_->{Va} } sort { $a->{Va} < $b->{Va} } @$results;

    # go through the two Va values
    foreach my $Va ( $min_va, $max_va ) {    # {{{
                                             # find the two Vg values
        my ($min_vg) = map { $_->{Vg} } sort { $a->{Vg} > $b->{Vg} } grep { $_->{Va} == $Va } @$results;
        my ($max_vg) = map { $_->{Vg} } sort { $a->{Vg} < $b->{Vg} } grep { $_->{Va} == $Va } @$results;
        my $delta_vg = $max_vg - $min_vg;

        # grab currents
        my ($max_ia) = map { $_->{Ia} } sort { $a->{Ia} > $b->{Ia} } grep { $_->{Va} == $Va && $_->{Vg} == $max_vg } @$results;
        my ($min_ia) = map { $_->{Ia} } sort { $a->{Ia} < $b->{Ia} } grep { $_->{Va} == $Va && $_->{Vg} == $min_vg } @$results;
        my $delta_ia = $max_ia - $min_ia;
        $GmA += $delta_ia / $delta_vg;
    }    # }}}

    # average the two Va voltage Gm measurements together
    $GmA /= 2;

    my ($min_vs) = map { $_->{Vs} } sort { $a->{Vs} > $b->{Vs} } @$results;
    my ($max_vs) = map { $_->{Vs} } sort { $a->{Vs} < $b->{Vs} } @$results;

    # go through the two Va values
    foreach my $Vs ( $min_vs, $max_vs ) {    # {{{
                                             # find the two Vg values
        my ($min_vg) = map { $_->{Vg} } sort { $a->{Vg} > $b->{Vg} } grep { $_->{Vs} == $Vs } @$results;
        my ($max_vg) = map { $_->{Vg} } sort { $a->{Vg} < $b->{Vg} } grep { $_->{Vs} == $Vs } @$results;
        my $delta_vg = $max_vg - $min_vg;

        # grab currents
        my ($max_is) = map { $_->{Is} } sort { $a->{Is} > $b->{Is} } grep { $_->{Vs} == $Vs && $_->{Vg} == $max_vg } @$results;
        my ($min_is) = map { $_->{Is} } sort { $a->{Is} < $b->{Is} } grep { $_->{Vs} == $Vs && $_->{Vg} == $min_vg } @$results;
        my $delta_is = $max_is - $min_is;
        $GmS += $delta_is / $delta_vg;
    }    # }}}

    # average the two Vs voltage Gm measurements together
    $GmS /= 2;

    # calculate rp
    # rp = dVa / dIa, consistent Vg, changing Va
    my ( $RpA, $RpS );

    my ($min_vg) = map { $_->{Vg} } sort { $a->{Vg} > $b->{Vg} } @$results;
    my ($max_vg) = map { $_->{Vg} } sort { $a->{Vg} < $b->{Vg} } @$results;

    # go through the two Vg values
    foreach my $Vg ( $min_vg, $max_vg ) {    # {{{
                                             # find the two Va values
        my ($min_va) = map { $_->{Va} } sort { $a->{Va} > $b->{Va} } grep { $_->{Vg} == $Vg } @$results;
        my ($max_va) = map { $_->{Va} } sort { $a->{Va} < $b->{Va} } grep { $_->{Vg} == $Vg } @$results;
        my $delta_va = $max_va - $min_va;

        # grab currents
        my ($max_ia) = map { $_->{Ia} } sort { $a->{Ia} > $b->{Ia} } grep { $_->{Vg} == $Vg && $_->{Va} == $max_va } @$results;
        my ($min_ia) = map { $_->{Ia} } sort { $a->{Ia} < $b->{Ia} } grep { $_->{Vg} == $Vg && $_->{Va} == $min_va } @$results;
        my $delta_ia = $max_ia - $min_ia;
        $RpA += $delta_va / $delta_ia;
    }    # }}}
    $RpA /= 2;

    foreach my $Vg ( $min_vg, $max_vg ) {    # {{{
                                             # find the two Va values
        my ($min_vs) = map { $_->{Vs} } sort { $a->{Vs} > $b->{Vs} } grep { $_->{Vg} == $Vg } @$results;
        my ($max_vs) = map { $_->{Vs} } sort { $a->{Vs} < $b->{Vs} } grep { $_->{Vg} == $Vg } @$results;
        my $delta_vs = $max_vs - $min_vs;

        # grab currents
        my ($max_is) = map { $_->{Is} } sort { $a->{Is} > $b->{Is} } grep { $_->{Vg} == $Vg && $_->{Vs} == $max_vs } @$results;
        my ($min_is) = map { $_->{Is} } sort { $a->{Is} < $b->{Is} } grep { $_->{Vg} == $Vg && $_->{Vs} == $min_vs } @$results;
        my $delta_is = $max_is - $min_is;
        $RpS += $delta_vs / $delta_is;
    }    # }}}
         # average the two Vg voltage Rp measurements together
    $RpS /= 2;

    # mu = gm * rp
    my ( $MuA, $MuS );
    $MuA = $GmA * $RpA;
    $MuS = $GmS * $RpS;

    $log->printf( "\n# %s  pUTracer3 400V CLI, V%s Triode Quick Test\n#\n",
        strftime( "%m/%d/%Y %I:%m:%S %p", localtime() ), $VERSION );
    $log->printf( "# %s %s\n#\n", $opts->{tube}, $opts->{name} );
    $log->printf("# SECTION ANODE\n#\n");
    $log->printf(
        "# Test Conditions: Va: %dv @ %d %%, Vg: %1.1fv @ %d %%\n#\n",
        $opts->{va}->[0],
        $opts->{offset}, $opts->{vg}->[0],
        $opts->{offset}
    );
    $log->printf(
        "# Test Results: Ia: %2.2f mA (%d%%), Ra: %2.2f kOhm (%d%%), Gm: %2.2f mA/V (%d%%), Mu: %d (%d%%)\n#\n",
        $center->{Ia}, ( $center->{Ia} / $opts->{ia} ) * 100,
        $RpA, ( $RpA / $opts->{rp} ) * 100,
        $GmA, ( $GmA / $opts->{gm} ) * 100,
        $MuA, ( $MuA / $opts->{mu} ) * 100,
    );
    $log->printf("# SECTION SCREEN\n#\n");
    $log->printf(
        "# Test Conditions: Vs: %dv @ %d %%, Vg: %1.1fv @ %d %%\n#\n",
        $opts->{vs}->[0],
        $opts->{offset}, $opts->{vg}->[0],
        $opts->{offset}
    );

    $log->printf(
        "# Test Results: Is: %2.2f mA (%d%%), Rs: %2.2f kOhm (%d%%), Gm: %2.2f mA/V (%d%%), Mu: %d (%d%%)\n#\n",
        $center->{Is}, ( $center->{Is} / $opts->{ia} ) * 100,
        $RpS, ( $RpS / $opts->{rp} ) * 100,
        $GmS, ( $GmS / $opts->{gm} ) * 100,
        $MuS, ( $MuS / $opts->{mu} ) * 100,
    );
 
}    # }}}

sub get_results_matrix {
    
    my $todo = shift;
    my @results;
    my $count = 1;
    foreach my $point (@$todo) {
        printf( "\nMeasuring Vg: %f\tVa: %f\tVs: %f\tVf: %f\n", $point->{vg}, $point->{va}, $point->{vs}, $opts->{vf}->[0] )
          if ( $opts->{verbose} );
        my $measurement = do_measurement(
            vg => $point->{vg},
            va => $point->{va},
            vs => $point->{vs},
            vf => $opts->{vf}->[0],
        );
        $measurement->{Vg} = $point->{vg};
        push @results, $measurement;
        $log->printf(
            "%s\t%s\t%d\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\n",  # {{{
            $opts->{name},
            $opts->{tube},
            $count++,
            $measurement->{Vpsu},
            $measurement->{Vmin},
            $point->{vg},
            $point->{va},
            $measurement->{Va_Meas},
            $measurement->{Ia},
            $measurement->{Ia_Raw},
            $measurement->{Gain_Ia},
            $point->{vs},
            $measurement->{Vs_Meas},
            $measurement->{Is},
            $measurement->{Is_Raw},
            $measurement->{Gain_Is},
            $opts->{vf}->[0],
        );    # }}}
    }

    end_measurement();

    printf "Sleeping for $opts->{calm} seconds for uTracer\n";
    sleep $opts->{calm};

    # 00 - all zeros turn everything off
    # 40 turn off fil
    set_filament(0) if ( !$opts->{warm} );
    
    return \@results;
}

sub print_dual {
    my $outstring = shift;
    $log->printf($outstring);
    print STDOUT ($outstring);
}

sub quicktest_pentode {    # {{{
    printf STDERR "Running quicktest...\n";

    # print log header
    $log->printf( "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
        qw(Name Tube Point Vpsu Vmin Vg Va Va_Meas Ia Ia_Raw Ia_Gain Vs Vs_Meas Is Is_Raw Is_Gain Vf) );

    # 00 - send settings w/ compliance, etc.
    send_settings(
        compliance => $opts->{compliance},
        averaging  => $opts->{averaging},
        gain_is    => $opts->{gain},
        gain_ia    => $opts->{gain}
    );

    # read out AD
    my $data = ping();

    # set filament
    # set fil voltage (repeated 10x) +=10% of voltage, once a second
    warmup_tube();

    # do the seven measurements for a pentode -> http://dos4ever.com/uTracerlog/tubetester2.html#quicktest
    #
    # There are six derivativs we need to measure:
    # Ia(Vg,Va,Vs) => dIa/dVa, dIa/dVs, dIa/dVg
    # Is(Vg,Va,Vs) => dIs/dVa, dIs/dVs, dIs/dVg
    #
    # This can be calculated from six mesurements + a seventh at the bias point.
    #
    # The measurements we need are as follows:
    #     Va              VsMax,VsMin           Vg
    #     Va                  Vs            VgMax,VgMin
    # VaMax,VaMin             Vs                Vg
    #

    my ($va, $vs, $vg) = init_voltage_ranges(); # make sure the requeted voltage ranges are within the capabilities of the uTracer

    my @todo;
    
    # Vary Vs while holding Va & Vg at bias conditions
    @todo = map { { va => $opts->{va}[0], vs => @$vs[$_], vg => $opts->{vg}[0] } } ( 0, 1 );

    # Vary Vg while holding Va & Vs at bias conditions
    push @todo, map { { va => $opts->{va}[0], vs => $opts->{vs}[0], vg => @$vg[$_] } } ( 0, 1 );

    # Vary Va while holding Vs & Vg at bias conditions
    push @todo, map { { va => @$va[$_], vs => $opts->{vs}[0], vg => $opts->{vg}[0] } } ( 0, 1 );

    # and that last center dot, to calculate current draw at the bias point center.
    push @todo, { va => $opts->{va}[0], vs => $opts->{vs}[0], vg => $opts->{vg}[0] };

    if ($opts->{debug}) {dump_csv( 'todo.csv', \@todo );}

    my $results = get_results_matrix(\@todo);

    ### Do the calculations now that we have the results
    if ($opts->{debug}) {dump_csv( 'results.csv', $results )};

    # extract center point, for current draw at the bias point.
    my $center = pop @$results;

    # calculate the partial derivaties
    # dVa
    my ($min_va) = map { $_->{Va_Meas} } sort { $a->{Va_Meas} > $b->{Va_Meas} } @$results;
    my ($max_va) = map { $_->{Va_Meas} } sort { $a->{Va_Meas} < $b->{Va_Meas} } @$results;
    my $dVa = $max_va - $min_va;

    # dVs
    my ($min_vs) = map { $_->{Vs_Meas} } sort { $a->{Vs_Meas} > $b->{Vs_Meas} } @$results;
    my ($max_vs) = map { $_->{Vs_Meas} } sort { $a->{Vs_Meas} < $b->{Vs_Meas} } @$results;
    my $dVs      = $max_vs - $min_vs;

    # dVg
    my ($min_vg) = map { $_->{Vg} } sort { $a->{Vg} > $b->{Vg} } @$results;
    my ($max_vg) = map { $_->{Vg} } sort { $a->{Vg} < $b->{Vg} } @$results;
    my $dVg      = $max_vg - $min_vg;

    # Calculate RpA & dIs/dVa where Va = min, max
    # go through the two Va values
    # find the two Ia values
    my ($min_ia) = map { $_->{Ia} } grep { $_->{Va_Meas} == $min_va } @$results;
    my ($min_is) = map { $_->{Is} } grep { $_->{Va_Meas} == $min_va } @$results;
    my ($max_ia) = map { $_->{Ia} } grep { $_->{Va_Meas} == $max_va } @$results;
    my ($max_is) = map { $_->{Is} } grep { $_->{Va_Meas} == $max_va } @$results;
    my $RpA = $dVa/($max_ia - $min_ia) ;
    my $dIs_dVa = ($max_is - $min_is)/$dVa;

    # Calculate GmA where Vg = min, max
    # go through the two Vg values
    # find the two Ia values
    ($min_ia) = map { $_->{Ia} } grep { $_->{Vg} == $min_vg } @$results;
    ($max_ia) = map { $_->{Ia} } grep { $_->{Vg} == $max_vg } @$results;
    my $GmA =  ($max_ia - $min_ia) / $dVg ;

    # Calculate RpS & dIa/dVs where Vs = min, max
    # go through the two Vs values
    # find the two Is values
    ($min_is) = map { $_->{Is} } grep { $_->{Vs_Meas} == $min_vs } @$results;
    ($min_ia) = map { $_->{Ia} } grep { $_->{Vs_Meas} == $min_vs } @$results;
    ($max_is) = map { $_->{Is} } grep { $_->{Vs_Meas} == $max_vs } @$results;
    ($max_ia) = map { $_->{Ia} } grep { $_->{Vs_Meas} == $max_vs } @$results;
    my $RpS =  $dVs / ($max_is - $min_is) ;
    my $dIa_dVs = ($max_ia - $min_ia) / $dVs; 

    # Calculate GmS where Vg = min, max
    # go through the two Vg values
    # find the two Is values
    ($min_is) = map { $_->{Is} } grep { $_->{Vs_Meas} == $min_vs } @$results;
    ($max_is) = map { $_->{Is} } grep { $_->{Vs_Meas} == $max_vs } @$results;
    my $GmS =  ($max_is - $min_is) / $dVg ;

    my $MuA = $RpA * $GmA;    # Mu of the anode
    my $MuS = $RpS * $GmS;

    ### Output
    
    print_dual( sprintf( "\n# %s  pUTracer3 400V CLI, V%s Triode Quick Test\n#\n",
        strftime( "%m/%d/%Y %I:%m:%S %p", localtime() ), $VERSION )
    );
    print_dual( sprintf( "# %s %s\n#\n", $opts->{tube}, $opts->{name} ) );

    print_dual( sprintf(
        "# Test Conditions: Va: %dv @ %d %%, Vs: %dv @ %d %%, Vg: %1.1fv @ %d %%\n#\n",
        $opts->{va}->[0],
        $opts->{offset}, $opts->{vs}->[0],
        $opts->{offset}, $opts->{vg}->[0],
        $opts->{offset}
    ) );
    print_dual( sprintf(
"# Anode Results: Ia: %2.2f mA (%d%%), Ra: %2.2f kOhm (%d%%), GmA: %2.2f mA/V (%d%%), Mu1: %d (%d%%), dIa/dVs: %5.4f (uA/V) \n#\n",
        $center->{Ia},
        ( $center->{Ia} / $opts->{ia} ) * 100,
        $RpA,
        ( $RpA / $opts->{rp} ) * 100,
        $GmA,
        ( $GmA / $opts->{gm} ) * 100,
        $MuA,
        ( $MuA / $opts->{mu} ) * 100,
        $dIa_dVs * 1000,
    ));

    print_dual( sprintf(
        "# Screen Results: Is: %2.2f mA (%d%%), Rs: %2.2f kOhm , GmS: %2.2f mA/V , Mu2: %d , dIs/dVa %5.4f (uA/V) \n#\n",
        $center->{Is}, ( $center->{Is} / $opts->{is} ) * 100,
        $RpS, $GmS, $MuS, $dIs_dVa * 1000
    ));

    print_dual(sprintf( "# Deltas: dVa %2.2f V, dVs %2.2f V, dVg %2.2f V \n#\n",$dVa, $dVs, $dVg ));

    print_dual("\n\n");
    
    #@pentode_fields = qw( type serial ia is ra rs gma gms mua mus dIa_dVs dIs_dVa );
    
    if ($opts->{store}) {
        print STDOUT "Updating tube:" . $opts->{tube} . ':' . $opts->{name} . " pentodes table in tubes.sq3\n";
        my %db_data; 
        @db_data{@pentode_fields} = (
            $opts->{tube},
            $opts->{name},
            $center->{Ia},
            $center->{Is},
            $RpA,
            $RpS,
            $GmA,
            $GmS,
            $MuA,
            $MuS,
            $dIa_dVs,
            $dIs_dVa
        );
        
        insert_pentode( \%db_data ); 
    }
}    # }}}

sub dump_csv {

    my $fname       = shift;
    my $results_ref = shift;
    my @results     = @$results_ref;

    my @names = sort keys %{ $results[0] };

    use Text::CSV;

    my $csv = Text::CSV->new( { binary => 1 } )    # should set binary attribute.
      or die "Cannot use CSV: " . Text::CSV->error_diag();

    $csv->eol("\n");

    #$csv->column_names(\@names);
    my $fh;
    open $fh, ">:encoding(utf8)", $fname or die "$fname: $!";
    $csv->print( $fh, \@names );

    #print Dumper @results;
    foreach my $result (@results) {
        my @row;
        foreach my $name ( sort @names ) {
            push @row, $result->{$name};
        }
        #print Dumper @row;

        $csv->print( $fh, \@row );
    }
    close $fh or die "$fname: $!";
}

sub do_curve {    # {{{
                  # print log header
    $log->printf(
        "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%2.2f\n",
        qw(Name Tube Point Vpsu Vmin Vg Va Va_Meas Ia Ia_Raw Ia_Gain Vs Vs_Meas Is Is_Raw Is_Gain Vf)
    );
    printf STDERR "Preparing to run curve...\n";

    # 00 - send settings w/ compliance, etc.
    send_settings(    # {{{
        compliance => $opts->{compliance},
        averaging  => $opts->{averaging},
        gain_is    => $opts->{gain},
        gain_ia    => $opts->{gain}
    );                # }}}

    # 50 - read out AD
    my $data = ping();

    # set filament
    # 40 - set fil voltage (repeated 10x) +=10% of voltage, once a second
    warmup_tube();

    #   00 - set settings again
    send_settings(
        compliance => $opts->{compliance},
        averaging  => $opts->{averaging},
        gain_is    => $opts->{gain},
        gain_ia    => $opts->{gain}
    );

    #   10 - do measurement
    my $point = 1;
    printf STDERR "Running curve measurements...";
    foreach my $vg_step ( 0 .. $#{ $opts->{vg} } ) {    # {{{
        foreach my $step ( 0 .. $#{ $opts->{va} } ) {    # {{{

            printf(
                "\nMeasuring Vg: %f\tVa: %f\tVs: %f\tVf: %f\n",
                $opts->{vg}->[$vg_step],
                $opts->{va}->[$step],
                $opts->{vs}->[$step],
                $opts->{vf}->[$step] || $opts->{vf}->[0]
            ) if ( $opts->{verbose} );
            my $measurement = do_measurement(
                vg => $opts->{vg}->[$vg_step],
                va => $opts->{va}->[$step],
                vs => $opts->{vs}->[$step],
                vf => $opts->{vf}->[$step] || $opts->{vf}->[0],
            );

            # name tube Vpsu Vmin Vg Va Va_meas Ia Ia_Raw Ia_Gain Vs Vs_meas Is Is_Raw Is_Gain Vf
            $log->printf(
                "%s\t%s\t%d\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\t%2.2f\n",
                $opts->{name},
                $opts->{tube},
                $point++,
                $measurement->{Vpsu},
                $measurement->{Vmin},
                $measurement->{Vg},
                $measurement->{Va},
                $measurement->{Va_Meas},
                $measurement->{Ia},
                $measurement->{Ia_Raw},
                $measurement->{Gain_Ia},
                $measurement->{Vs},
                $measurement->{Vs_Meas},
                $measurement->{Is},
                $measurement->{Is_Raw},
                $measurement->{Gain_Is},
                $measurement->{Vf}
            );
        }    # }}}
    }    # }}}
         # 30 -- end measurement
    printf STDERR "...done\n";
    end_measurement();

    #reset_tracer();

    # Apparently, the uTracer needs a delay after a measurement cycle
    $log->printf("\n\n");
    $log->close();
    printf "Sleeping for $opts->{calm} seconds for uTracer\n";
    sleep $opts->{calm};

    # 00 - all zeros turn everything off
    # 40 turn off fil
    set_filament(0) if ( !$opts->{warm} );

    #send_settings(
    #	  compliance => $opts->{compliance},
    #	  averaging  => $opts->{averaging},
    #	  gain_is    => $opts->{gain},
    #	  gain_ia    => $opts->{gain}
    #  );
}    # }}}

#reset_tracer();

sub end_measurement {    # {{{
    my (%args) = @_;
    my $string = sprintf( "%02X00000000%02X%02X%02X%02X", $CMD_END, 0, 0, 0, 0 );
    print "> $string\n" if ( $opts->{debug} );
    $tracer->write($string);
    my ( $bytes, $response ) = $tracer->read(18);
    print "< $response\n" if ( $opts->{debug} );
    if ( $response ne $string ) { warn "uTracer returned $response, when I expected $string"; }
}    # }}}

sub set_filament {    # {{{

    my ($voltage) = @_;
    my $string = sprintf( "%02X000000000000%04X", $CMD_FILAMENT, $voltage );
    print "> $string\n" if ( $opts->{debug} );
    $tracer->write($string);
    my ( $bytes, $response ) = $tracer->read(18);
    print "< $response\n" if ( $opts->{debug} );
    if ( $response ne $string ) { warn "uTracer returned $response, when I expected $string"; }
}    # }}}

sub ping {    # {{{
    my $string = sprintf( "%02X00000000%02X%02X%02X%02X", $CMD_PING, 0, 0, 0, 0 );
    print "> $string\n" if ( $opts->{debug} );
    $tracer->write($string);
    my ( $bytes, $response ) = $tracer->read(18);
    print "< $response\n" if ( $opts->{debug} );
    if ( $response ne $string ) { warn "uTracer returned $response, when I expected $string"; }
    ( $bytes, $response ) = $tracer->read(38);
    print "< $response\n" if ( $opts->{debug} );
    my $data = decode_measurement($response);
    @{$data}{qw(Va Vs Vg Vf)} = ( 0, 0, 0, 0 );
    return $data;
}    # }}}

sub send_settings {    # {{{
    my (%args) = @_;
    my $string = sprintf(
        "%02X00000000%02X%02X%02X%02X",
        $CMD_START,
        $compliance_to_tracer{ $args{compliance} },
        $averaging_to_tracer{ $args{averaging} } || 0,
        $gain_to_tracer{ $args{gain_is} }        || 0,
        $gain_to_tracer{ $args{gain_ia} }        || 0,
    );
    print "> $string\n" if ( $opts->{debug} );
    $tracer->write($string);
    my ( $bytes, $response ) = $tracer->read(18);
    print "< $response\n" if ( $opts->{debug} );
    if ( $response ne $string ) { warn "uTracer returned $response, when I expected $string"; }
}    # }}}

sub do_measurement {    # {{{
    my (%args) = @_;
    my $string = sprintf(
        "%02X%04X%04X%04X%04X",
        $CMD_MEASURE,
        getVa( $args{va} ),
        getVs( $args{vs} ),
        getVg( $args{vg} ),
        getVf( $args{vf} ),
    );
    print "> $string\n" if ( $opts->{debug} );
    $tracer->write($string);
    my ( $bytes, $response ) = $tracer->read(18);
    print "< $response\n" if ( $opts->{debug} );
    if ( $response ne $string ) { warn "uTracer returned $response, when I expected $string"; }
    ( $bytes, $response ) = $tracer->read(38);
    print "< $response\n" if ( $opts->{debug} );
    my $data = decode_measurement($response);
    @{$data}{qw(Va Vs Vg Vf)} = @args{qw(va vs vg vf)};
    return $data;
}    # }}}

# send an escape character, to reset the input buffer of the uTracer.
# This unfortunately, does not actually *reset* the uTracer.
sub reset_tracer {
    $tracer->write("\x1b");
}

sub abort {
    print "Aborting!\n";

    #reset_tracer();
    end_measurement();
    set_filament(0);
    die "uTracer reports compliance error, current draw is too high.  Test aborted";
}

sub decode_measurement {    # {{{
    my ($str) = @_;
    $str =~ s/ //g;
    my $data = {};
    @{$data}{@measurement_fields} = map { hex($_) } unpack( "A2 A4 A4 A4 A4 A4 A4 A4 A4 A2 A2", $str );

    # status byte = 10 - all good.
    # status byte = 11 - compliance error
    if ( $data->{Status} == 0x11 ) {
        warn "uTracer reports overcurrent!";
        abort();
    }

    $data->{Vpsu} *= $DECODE_TRACER * $SCALE_VSU * $cal->{CalVar5};

    # update PSU voltage global
    $VsupSystem = $data->{Vpsu};

    $data->{Va_Meas} *= $DECODE_TRACER * $DECODE_SCALE_VA;    # * CalVar1;
                                                              # Va is in reference to PSU, adjust
    $data->{Va_Meas} -= $data->{Vpsu};

    $data->{Vs_Meas} *= $DECODE_TRACER * $DECODE_SCALE_VS;    # * CalVar2;
                                                              # Vs is in reference to PSU, adjust
    $data->{Vs_Meas} -= $data->{Vpsu};

    $data->{Ia} *= $DECODE_TRACER * $DECODE_SCALE_IA * $cal->{CalVar3};
    $data->{Is} *= $DECODE_TRACER * $DECODE_SCALE_IS * $cal->{CalVar4};

    $data->{Ia_Raw} *= $DECODE_TRACER * $DECODE_SCALE_IA * $cal->{CalVar3};
    $data->{Is_Raw} *= $DECODE_TRACER * $DECODE_SCALE_IS * $cal->{CalVar4};

    $data->{Vmin} = 5 * ( ( $VminR1 + $VminR2 ) / $VminR1 ) * ( ( $data->{Vmin} / 1024 ) - 1 );
    $data->{Vmin} += 5;

    # decode gain
    @{$data}{qw(Gain_Ia Gain_Is)} = map { $gain_from_tracer{$_} } @{$data}{qw(Gain_Ia Gain_Is)};

    # undo gain amplification
    # XXX NOTE: the uTracer can and will use different PGA gains for Ia and Is!
    $data->{Ia} = $data->{Ia} / $data->{Gain_Ia};
    $data->{Is} = $data->{Is} / $data->{Gain_Is};

    # average
    # XXX NOTE: the uTracer can and will use different PGA gains for Ia and Is!  Averaging is global though.
    my $averaging =
        $gain_to_average{ $data->{Gain_Ia} } > $gain_to_average{ $data->{Gain_Is} }
      ? $gain_to_average{ $data->{Gain_Ia} }
      : $gain_to_average{ $data->{Gain_Is} };
    $data->{Ia} /= $averaging;
    $data->{Is} /= $averaging;

    if ( $opts->{correction} ) {
        $data->{Va_Meas} = $data->{Va_Meas} - ( ( $data->{Ia} ) / 1000 ) * $AnodeRs -  ( 0.6 * $cal->{CalVar7} );
        $data->{Vs_Meas} = $data->{Vs_Meas} - ( ( $data->{Is} ) / 1000 ) * $ScreenRs - ( 0.6 * $cal->{CalVar7} );
    }

    if ( $opts->{verbose} ) {
        printf "\nstat ____ia iacmp ____is _is_comp ____va ____vs _vPSU _vneg ia_gain is_gain\n";
        printf "% 4x % 6.1f % 5.1f % 6.1f % 8.1f % 6.1f % 6.1f % 2.1f % 2.1f % 7d % 7d\n", @{$data}{@measurement_fields};
    }

    return $data;
}    # }}}


__END__

=head1 NAME

puTracer - command line quick test

=head1 SYNOPSIS

tracer.pl [options] --tube 12AU7

    Options:
        --hot                             # expect filiments to be hot already
        --warm                            # leave filiments on or not
        --debug                           # protocol-level debugging
        --interactive                     # prompt to store current quicktest in the database
        --store                           # automatically store the current quicktest in the database  
        --verbose                         # print measurement requests, and responses.
        --device=s                        # serial device
        --preset=s                        # preset trace settings
        --name=s                          # name to put in log
        --tube=s                          # tube type
        --vg=sva=svs=srp=fia=fgm=fmu=fvf=s # measurement value override
        --compliance=i                    # miliamps 
        --settle=i                        # settle delay after slow heating tube 
        --averaging=i                     # averaging 
        --gain=i                          # gain 
        --correction!                     # low voltage correction
        --log=s                           # path to the logfile
        --quicktest|quicktest-triode|qtt  # do quicktest of triodes to a log file, rather than a sweep.
        --quicktest-pentode|qtp           # do quicktest of pentodes to a log file, rather than a sweep.
        --offset=i                        # quicktest offset percentage
        --calm=i                          # delay this long before the next command after a end measurement

