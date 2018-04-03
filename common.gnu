# common to all graphs
#set terminal svg size 800,600 fname 'Verdana' fsize 12
set termoption dash
set terminal png size 800,600
EXTENSION="png"

set samples 25
set isosamples 25
set key inside top left autotitle columnhead

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

set xtics
set ytics
set mxtics 10
set mytics 10
set grid x y xtics ytics mxtics mytics

set for [i=1:5] linetype i dt i

set linetype 1 dt 1 linecolor rgb "red"     linewidth 2
set linetype 2 dt 2 linecolor rgb "green"   linewidth 2
