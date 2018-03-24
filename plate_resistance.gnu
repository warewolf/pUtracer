# common to all graphs
reset
load 'common.gnu'

# smooth out Ia and Is by means of a sampled acspline
set table $datablock
set samples 20
set datafile separator "\t"
plot ARG1 index 0 using "Va":"Ia" with lines, \
       '' index 0 using "Vs":"Is" with lines
unset table

set xrange [0:]
set yrange [0:]

set datafile separator whitespace
set xlabel 'Plate Voltage V'
set ylabel 'Plate Current mA'
set output ARG1."-current.svg"
plot \
  $datablock index 0 using 1:2 with lines title "Ia", \
  $datablock index 1 using 1:2 with lines title "Is", \

set xlabel 'Plate Current mA'
set ylabel 'Plate Resistance kOhm'
set output ARG1."-resistance.svg"
plot \
  $datablock index 0 using 2:( Va=column(1), Ia = column(2), Rpa = plate_resistance(delta_Ia(Va),delta_Vg(Ia)), Rpa) with lines title "Rpa", \
  $datablock index 1 using 2:( Vs=column(1), Is = column(2), Rps = plate_resistance(delta_Is(Vs),delta_Vg(Is)), Rps) with lines title "Rps"
