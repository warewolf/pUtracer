# common to all graphs
reset

# variables
old_Va = NaN
old_Vs = NaN
old_Vg = NaN
old_Ia = NaN
old_Is = NaN
#
dVa = NaN
dVs = NaN
dVg = NaN
dIa = NaN
dIs = NaN

# functions
delta_Va(x) = ( dVa = x - old_Va, old_Va = x, dVa)
delta_Vs(x) = ( dVs = x - old_Vs, old_Vs = x, dVs)
delta_Vg(x) = ( dVg = x - old_Vg, old_Vg = x, dVg)
delta_Ia(x) = ( dIa = x - old_Ia, old_Ia = x, dIa)
delta_Is(x) = ( dIs = x - old_Is, old_Is = x, dIs)

# plate resistance = dVa / dIa
plate_resistance(rp_Va, rp_Ia) = ( rp_Va / rp_Ia  )

# gm = Ia / Vg
transconductance(gm_Ia,gm_Vg) = ( gm_Ia / gm_Vg  )

set datafile separator "\t"

set title 'Plate Resistance'
set xlabel 'Plate Current mA'
set ylabel 'Resistance kOhm'

set key autotitle columnhead

set multiplot

set xtics
set ytics
set mxtics 10
set mytics 10
set grid x y xtics ytics mxtics mytics

set xrange [0:30]
set yrange [0:20]

plot ARG1 using "Ia":( Va=column("Va"), Ia = column("Ia"), plate_resistance(delta_Va(Va),delta_Ia(Ia))) with linespoints, \
          '' using "Is":( Vs=column("Vs"), Is = column("Is"), plate_resistance(delta_Vs(Vs),delta_Is(Is))) with linespoints
pause -1
