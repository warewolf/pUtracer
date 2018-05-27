#!/bin/bash
sqlite3 -header -csv tubes.sq3 "select * from pentodes;" > pentodes.csv
