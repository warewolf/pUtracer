# common to all graphs
load 'common.gnu'

# smooth out Ia and Is by means of a sampled acspline
set table $datablock
plot ARG1 index 0 using "Va":"Ia" smooth acsplines, \
       '' index 0 using "Vs":"Is" smooth acsplines
unset table

set datafile separator whitespace
set xlabel 'Plate Voltage V'
set ylabel 'Plate Current mA'
set output ARG1."-current.".EXTENSION

if (strlen(ARG2) > 0) {
  load ARG2.".gnu"
  RP_TITLE_CURRENT = MAKE." ".MODEL." # ".SERIAL."\n"."Average Characteristics, Vg = ".RP_TEST_VG
  RP_TITLE_RP = MAKE." ".MODEL." # ".SERIAL."\n"."Resistance, Vg = ".RP_TEST_VG
}

set xrange [0:RP_VA_MAX] # plate voltage 0 - 400
set yrange [0:RP_CURRENT_PLATE_MA_MAX] # plate current 0 - 6

set title RP_TITLE_CURRENT
plot \
  $datablock index 0 using 1:2 with lines title "Ia", \
  $datablock index 1 using 1:2 with lines title "Is", \

unset label
unset xrange
unset yrange
set xrange [0:RP_PLATE_MA_MAX]
set yrange [0:RP_RESISTANCE_KOHM_MAX] # kOhm


set title RP_TITLE_RP
set xlabel 'Plate Current mA'
set ylabel 'Plate Resistance kOhm'
set output ARG1."-resistance.".EXTENSION
plot \
  $datablock index 0 using 2:( Va=column(1), Ia = column(2), Rpa = plate_resistance(delta_Ia(Va),delta_Vg(Ia)), Rpa) with lines title "Rpa", \
  $datablock index 1 using 2:( Vs=column(1), Is = column(2), Rps = plate_resistance(delta_Is(Vs),delta_Vg(Is)), Rps) with lines title "Rps"
