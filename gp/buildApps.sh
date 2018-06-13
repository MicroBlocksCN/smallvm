#!/bin/sh
# Build the GP IDE for all platforms.

mkdir -p ../apps
./gp-mac runtime/lib/* loadIDE.gp buildApps.gp
