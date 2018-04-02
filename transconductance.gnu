# common to all graphs
load "common.gnu"

# smooth out Ia and Is by means of a sampled acspline
set table $datablock
plot ARG1 index 0 using "Vg":"Ia" smooth acsplines, \
       '' index 0 using "Vg":"Is" smooth acsplines
unset table


if (strlen(ARG2) > 0) {
  load ARG2.".gnu"
  GM_TITLE_CURRENT = MAKE." ".MODEL." # ".SERIAL."\n"."Average Characteristics, Va = ".GM_TEST_VA
  GM_TITLE_GM = MAKE." ".MODEL." # ".SERIAL."\n"."Transconductance, Va = ".GM_TEST_VA
}

set xrange [GM_CURRENT_GRID_MIN:0] # grid voltage -6 to 0
set yrange [0:GM_CURRENT_PLATE_MA_MAX] # plate current, 0 to 5

set datafile separator whitespace
set xlabel 'Grid Voltage V'
set ylabel 'Plate Current mA'
set output ARG1."-current.".EXTENSION
set title GM_TITLE_CURRENT

plot \
  $datablock index 0 using 1:2 with lines title "Ia", \
  $datablock index 1 using 1:2 with lines title "Is"

unset xrange
unset yrange

set xrange [0:GM_PLATE_MA_MAX]
set yrange [0:GM_TRANSCONDUCTANCE_MAX]


set xlabel 'Plate Current mA'
set ylabel 'Gm mA/V'
set title GM_TITLE_GM
set output ARG1."-gm.".EXTENSION

plot $datablock \
          index 0 using 2:( Vg=column(1), Ia = column(2), Gma = transconductance(delta_Ia(Ia),delta_Vg(Vg)), Gma) with lines title "Gma", \
       '' index 1 using 2:( Vg=column(1), Is = column(2), Gma = transconductance(delta_Is(Is),delta_Vg(Vg)), Gma) with lines title "Gms"
