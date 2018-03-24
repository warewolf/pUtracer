This is pUTracer, a perl based CLI for Ronald Dekker's uTracer3; a PIC16F based vacuum tube curve tracer.  Read more about it at http://dos4ever.com/uTracer3/uTracer3.html

Design goal in mind: automation.  I have a bunch of vacuum tubes that I need to test, and ultimately sell to folks who need them.

 * ` tracer.pl ` is the brains that talks to the uTracer3 over a serial port.
 * ` run_test.sh ` three tests, a test for producing a transconductance test, a plate resistance test, and a quick test at a default bias point.

For graphing:

 * ` common.gnu ` is a common script used by the following gnuplot scripts
 * ` plate_resistance.gnu ` does smoothed graphs of the plate current, and plate resistance.
 * ` transconductance.gnu ` does smoothed graphs of the plate current, and transconductance.

Generate graphs with gnuplot (default output format is SVG, Scalable Vector Graphic): ` gnuplot -c plate_resistance.gnu tube-rp.csv ` or ` gnuplot -c transconductance.gnu tube-gm.csv `

This software is under active development, and currently is lacking documentation and usage instructions.  Check back later for progress.

Cheers,
Richard Harman
