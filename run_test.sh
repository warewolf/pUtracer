#!/bin/bash

TYPE=$1
NAME=$2

# do RP and GM curves
perl tracer.pl --verbose --preset ${TYPE}-rp --name "${NAME}" --log "${TYPE}-${NAME}-rp.csv" --warm 
perl tracer.pl --verbose --preset ${TYPE}-gm --name "${NAME}" --log "${TYPE}-${NAME}-gm.csv" --hot --warm --settle 0 

# do quicktest
perl tracer.pl --verbose --quicktest --preset ${TYPE} --name "${NAME}" --log "${TYPE}-${NAME}-quicktest.csv" --hot --settle 0 

tail -19  "${TYPE}-${NAME}-quicktest.csv"
