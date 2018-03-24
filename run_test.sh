#!/bin/bash

TYPE=$1
NAME=$2

# do RP and GM curves
for TEST in rp gm; do 
done

perl tracer.pl --preset ${TYPE}-rp --name "${NAME}" --log "${TYPE}-${NAME}-rp.csv" --warm 
perl tracer.pl --preset ${TYPE}-gm --name "${NAME}" --log "${TYPE}-${NAME}-gm.csv" --hot --warm --settle 0
# do quicktest
perl tracer.pl --quicktest --preset ${TYPE} --name "${NAME}" --log "${TYPE}-${NAME}-quicktest.csv" --hot --settle 0
