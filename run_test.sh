#!/bin/bash

TYPE=$1
NAME=$2

# do RP and GM curves
for TEST in rp gm; do 
  perl tracer.pl --preset ${TYPE}-rp --name "${NAME}" --log "${TYPE}-${NAME}-${TEST}.csv"
done

# do quicktest
perl tracer.pl --quicktest --preset ${TYPE} --name "${NAME}" --log "${TYPE}-${NAME}-quicktest.csv"
