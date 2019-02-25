#!/bin/sh
# Run MicroBlocks IDE on Mac.
# If an argument is supplied, run the server rather than the IDE.

if [ "$#" -gt 0 ]; then
	./gp-mac runtime/lib/* loadServer.gp -
else
	./gp-mac runtime/lib/* loadIDE.gp -
fi
