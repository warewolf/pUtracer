#!/bin/bash

perl quicktest_report.pl $* | perl load.pl
sqlite3 -header -csv tubes.sq3 < matchmaker.sql | tee matches.txt
