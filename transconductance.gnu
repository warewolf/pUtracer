# common to all graphs
reset
load "common.gnu"

set title 'Transconductance'
set xlabel 'Plate Current mA'
set ylabel 'Gm in mA/V'

set key autotitle columnhead

set xtics
set ytics
set mxtics 10
set mytics 10
set grid x y xtics ytics mxtics mytics

set xrange [0:30]
set yrange [0:4]

plot ARG1 using "Ia":( Vg=column("Vg"), Ia = column("Ia"), transconductance(delta_Ia(Ia),delta_Vg(Vg))) with linespoints, \
       '' using "Is":( Vg=column("Vg"), Is = column("Is"), transconductance(delta_Is(Is),delta_Vg(Vg))) with linespoints
