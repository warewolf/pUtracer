# common to all graphs
reset
load "common.gnu"
set output ARG1.".svg"

set title 'Transconductance'
set xlabel 'Plate Current mA'
set ylabel 'Gm in mA/V'

set key autotitle columnhead

set xtics
set ytics
set mxtics 10
set mytics 10
set grid x y xtics ytics mxtics mytics


# smooth out Ia and Is by means of a sampled acspline
set table ARG1.'_fitted_ia.dat'
set samples 100
plot ARG1 using "Vg":"Ia" smooth acsplines, \
       '' using "Vg":"Is" smooth acsplines, \
       '' using "Vg":"Ia" with linespoints title "Ia", \
       '' using "Vg":"Is" with linespoints title "Is"
unset table

# read in fitted data, and graph it.
set datafile separator whitespace

set xrange [0<*:0<*]
set yrange [0<*:0<*]

plot ARG1.'_fitted_ia.dat' \
          index 0 using 1:( Vg=column(1), Ia = column(2), Gma = transconductance(delta_Ia(Ia),delta_Vg(Vg)), Gma) with lines title "Ia", \
       '' index 1 using 1:( Vg=column(1), Is = column(2), Gma = transconductance(delta_Is(Is),delta_Vg(Vg)), Gma) with lines title "Is"
