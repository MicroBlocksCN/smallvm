#!/bin/bash

# Pass the directory where the IDE files are as a parameter
exepath=$1
if [ -z "$exepath" ]; then
    echo "Please provide a path to the win32 IDE executable"
    echo "Example:"
    echo
    echo "./build-installer.sh ~/ublocks-win.exe [destination] [version-number]"
    exit 1
fi;

# Look for InnoSetup in the wine folder, otherwise try to install it
isccpath=`find ~/.wine/drive_c | grep ISCC.exe`
if [ -z "$isccpath" ]; then
    echo "Could not find an InnoSetup installation"
    echo "Will try to install it now"
    if command -v wine; then
        mkdir innosetup  
        cd innosetup  
        wget http://files.jrsoftware.org/ispack/ispack-5.2.3.exe  
        wine ./ispack-5.2.3.exe
        cd ..
        rm -rf innosetup
        isccpath=`find ~/.wine/drive_c | grep ISCC.exe`
        if [ -z "$isccpath" ]; then
            echo "Inno Setup installation seems to have failed."
            exit 1
        else
            echo "Inno Setup installed successfully."
        fi
    else
        echo "Wine is not installed in this system."
        echo "Wine is a prerequisite for installing Inno Setup. Please get it from your distro package manager, or head to https://www.winehq.org/download"
        exit 1
    fi
fi;

# Run InnoSetup and generate the installer
destdir=$2
if [ -z "$destdir" ]; then destdir=".."; fi

version=$3
if [ -z "$version" ]; then version="missing-version"; fi

unset DISPLAY
mkdir build
cp $exepath -r build
cp microBlocks.ico build
cat install-config.iss | sed -E "s/@AppVersion/$version/" > build/install-config.iss
cd build
wine "$isccpath" install-config.iss
cd ..
mv build/microBlocks\ setup.exe $destdir
rm -rf build
