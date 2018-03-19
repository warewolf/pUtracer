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


# smooth out Ia and Is by means of a sampled acspline
set table ARG1.'_fitted_ia.dat'
set samples 100
plot ARG1 using "Va":"Ia" smooth acsplines title "Smooth Ia", \
       '' using "Vs":"Is" smooth acsplines title "Smooth Is", \
       '' using "Va":"Ia" with linespoints title "Ia", \
       '' using "Vs":"Is" with linespoints title "Is"
unset table

plot ARG1 using "Va":"Ia" smooth acsplines title "Smooth Ia", \
       '' using "Vs":"Is" smooth acsplines title "Smooth Is", \
       '' using "Va":"Ia" with linespoints title "Ia", \
       '' using "Vs":"Is" with linespoints title "Is"

pause -1
# read in fitted data, and graph it.
set datafile separator whitespace

set xrange [0<*:0<*]
set yrange [0<*:0<*]

plot ARG1.'_fitted_ia.dat' \
          index 0 using 2:( Va=column(1), Ia = column(2), Rpa = plate_resistance(delta_Ia(Va),delta_Vg(Ia)), Rpa) with lines title "Ia", \
       '' index 1 using 2:( Vs=column(1), Is = column(2), Rps = plate_resistance(delta_Is(Vs),delta_Vg(Is)), Rps) with lines title "Is"
pause -1
