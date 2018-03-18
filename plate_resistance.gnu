
# common to all graphs
reset
load 'common.gnu'
set output ARG1.".svg"

set title 'Plate Resistance'
set xlabel 'Plate Current in mA'
set ylabel 'Resistance in kOhm'

set key autotitle columnhead

set xtics
set ytics
set mxtics 10
set mytics 10
set grid x y xtics ytics mxtics mytics

set xrange [0:30]
set yrange [0:20]

plot ARG1 \
     using "Ia":( Va=column("Va"), Ia = column("Ia"), plate_resistance(delta_Va(Va),delta_Ia(Ia))) with linespoints, \
  '' using "Is":( Vs=column("Vs"), Is = column("Is"), plate_resistance(delta_Vs(Vs),delta_Is(Is))) with linespoints

