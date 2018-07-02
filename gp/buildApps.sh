#!/bin/bash
# Build the GP IDE for all platforms.

# parse parameters
while echo $1 | grep ^- > /dev/null; do eval $( echo $1 | sed 's/-//g' | sed 's/=.*//g' | tr -d '\012')=$( echo $1 | sed 's/.*=//g' | tr -d '\012'); shift; done

if test -n "$help"; then
    echo "The microBlocks desktop IDE builder and packager generates executables for"
    echo "Windows, MacOS and GNU/Linux (including RaspberryPi)."
    echo "It can also generate installers for Windows and MacOS, and .deb packages for"
    echo "GNU/Linux."
    echo
    echo "usage: ./buildApps.sh [OPTIONS]"
    echo
    echo "--help                        Print this message."
    echo "--pack                        Create packages and installers for all systems."
    echo "--version=VERSION-NUMBER      Specify a version number, i.e. 0.1.16rc3."
    echo "--tools                       Automatically try to install missing tools needed"
    echo "                              by the build process."
    echo
    exit 0
fi

if [ -n $tools ]; then export tools=1; fi

# build the IDE by using the corresponding executable for our host system
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
    exit 1
fi

if [ -z $version ]; then
    version=`cat ../ide/MicroBlocksRuntime.gp | sed -n -E "s/^method ideVersion.*'(.*)'.*/\1/p"`
fi

# app packaging
if test -n "$pack"; then
    echo "Packaging microBlocks version $version..."
    mkdir -p ../apps/packages
    # build Win32 installer
    (cd packagers/win32/; ./build-installer.sh ../../../apps/ublocks-win.exe ../../../apps/packages $version)
    # build .deb packages for amd64, i386 and armhf (Raspberry Pi)
    (cd packagers/linux/; ./build-deb.sh ../../../apps/ublocks-linux64bit ../../../apps/packages $version amd64)
    (cd packagers/linux/; ./build-deb.sh ../../../apps/ublocks-linux32bit ../../../apps/packages $version i386)
    (cd packagers/linux/; ./build-deb.sh ../../../apps/ublocks-raspberryPi ../../../apps/packages $version armhf)
    # build zip package for Mac
    (cd packagers/darwin/; ./build-zip.sh ../../../apps/MicroBlocks.app ../../../apps/packages $version)
fi

echo
echo "Done building $version"
