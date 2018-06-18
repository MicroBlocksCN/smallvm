#!/bin/bash

# Pass the directory where the IDE files are as a parameter
exepath=$1
if [ -z "$exepath" ]; then
    echo "Please provide a path to the MacOS .app dir"
    echo "Example:"
    echo
    echo "./build-deb.sh ~/ublocks-mac.app [destination] [version-number]"
    exit 1
fi;

destdir=$2
if [ -z "$destdir" ]; then destdir=".."; fi

version=$3
if [ -z "$version" ]; then version="unknown"; fi

systemName=`uname -s`

if [ "$systemName" == "Darwin" ]; then
    # untested! I don't have a Mac.
    ./dmgbuild -s settings.py -D app=$exepath "MicroBlocks" $destdir/MicroBlocks.dmg
elif [ "$systemName" == "Linux" ]; then
    if test -z `which mkfs.hfsplus`; then
        echo "I will now try to install hfstools for you."
        echo "Please provide your sudo password when asked."
        ./hfstools-install
        if test $? != 0; then
            # errors occurred when installing hfstools. We cannot proceed.
            echo "I tried to install hfstools into your system but failed."
            echo "Please install them manually and try again."
            echo "Here's the list of commands I ran for you:"
            echo
            cat hfstools-install
            exit 1
        fi
    fi

    size=du -B1048576 $exepath | tail -n1 | cut -f1
    ./makedmg "MicroBlocks.dmg" "MicroBlocks" $size $exepath
    mv MicroBlocks.dmg $destdir

else
    echo "Platform $systemName is not (yet?) supported by this build script."
    echo "Try to find the gp executable for your platform in this folder and run:"
    echo "[command-to-run-GP] runtime/lib/* loadIDE.gp buildApps.gp"
    echo "Good luck!"
    exit 1
fi

