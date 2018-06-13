#!/bin/bash
# Build the GP IDE for all platforms.

mkdir -p ../apps

systemName=`uname -s`

if [ "$systemName" == "Darwin" ]; then
    ./gp-mac runtime/lib/* loadIDE.gp buildApps.gp
elif [ "$systemName" == "Linux" ]; then
    ./gp-linux64bit runtime/lib/* loadIDE.gp buildApps.gp
else
    echo "Platform $systemName is not (yet?) supported by this build script."
    echo "Try to find the gp executable for your platform in this folder and run:"
    echo "[command-to-run-GP] runtime/lib/* loadIDE.gp buildApps.gp"
    echo "Good luck!"
fi
