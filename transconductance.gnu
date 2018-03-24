# common to all graphs
reset
load "common.gnu"

# smooth out Ia and Is by means of a sampled acspline
set table $datablock
plot ARG1 using "Vg":"Ia" smooth acsplines, \
       '' using "Vg":"Is" smooth acsplines
unset table

#set xrange [0:]
#set yrange [0:]

set datafile separator whitespace
set title 'Transfer Characteristics'
set xlabel 'Grid Voltage V'
set ylabel 'Plate Current mA'
set output ARG1."-current.svg"

plot \
  $datablock index 0 using 1:2 with lines title "Ia", \
  $datablock index 1 using 1:2 with lines title "Is"

#pause -1

set title 'Transconductance'
set xlabel 'Plate Current mA'
set ylabel 'Gm mA/V'
set output ARG1."-gm.svg"
plot $datablock \
          index 0 using 2:( Vg=column(1), Ia = column(2), Gma = transconductance(delta_Ia(Ia),delta_Vg(Vg)), Gma) with lines title "Gma", \
       '' index 1 using 2:( Vg=column(1), Is = column(2), Gma = transconductance(delta_Is(Is),delta_Vg(Vg)), Gma) with lines title "Gms"

#pause -1
