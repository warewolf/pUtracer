#!/bin/bash

for foo in $*; do montage -rotate 90 -geometry '-0-0' *$foo*-{gm-current,gm-gm,rp-current,rp-resistance}.png -mode concatenate -border 2x2 -title "uTracer3 Test Results" -tile 2x2 -units pixelsperinch -density 72 -page letter $foo.pdf;done
