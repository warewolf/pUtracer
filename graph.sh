#!/bin/bash

for foo in *-gm.csv; do
  TYPE=`echo $foo | cut -f1 -d-`
  SERIAL=`echo $foo | cut -f2 -d-`
  gnuplot -e "SERIAL='${SERIAL}'" -c transconductance.gnu $foo $TYPE
done

for foo in *-rp.csv; do
  TYPE=`echo $foo | cut -f1 -d-`
  SERIAL=`echo $foo | cut -f2 -d-`
  gnuplot -e "SERIAL='${SERIAL}'" -c plate_resistance.gnu $foo $TYPE
done

