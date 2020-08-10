#!/bin/bash

# Pass the directory where the IDE files are as a parameter
exepath=$1
if [ -z "$exepath" ]; then
    echo "Please provide a path to the MacOS .app dir"
    echo "Example:"
    echo
    echo "./build-zip.sh ~/ublocks-mac.app [destination] [version-number]"
    exit 1
fi;

destdir=$2
if [ -z "$destdir" ]; then destdir=".."; fi

version=$3
if [ -z "$version" ]; then version="unknown"; fi

echo "Packaging MacOS version..."
cp -r $exepath .
zip -r MicroBlocksUnsigned.app.zip MicroBlocks.app
rm -R MicroBlocks.app

mv MicroBlocksUnsigned.app.zip $destdir
