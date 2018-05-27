#!/bin/bash

TYPE=$1
NAME=$2

# do RP and GM curves
perl tracer.pl --preset ${TYPE}-rp --name "${NAME}" --log "${TYPE}-${NAME}-rp.csv" --warm 
perl tracer.pl --preset ${TYPE}-gm --name "${NAME}" --log "${TYPE}-${NAME}-gm.csv" --hot --warm --settle 0 

# do quicktest
perl tracer.pl --quicktest-pentode --store --preset ${TYPE} --name "${NAME}" --log "${TYPE}-${NAME}-quicktest.csv" --hot --settle 0 

./graph.sh
./make_pdf.sh "${TYPE}-${NAME}"
mv *.pdf *.csv pentodes
rm *.png


