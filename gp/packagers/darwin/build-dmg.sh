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

dmgbuild -s settings.py -D app=$exepath "MicroBlocks" $destdir/MicroBlocks.dmg
