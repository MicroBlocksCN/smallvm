#!/bin/bash

# Pass the directory where the IDE files are as a parameter
idedir=$1
if [ -z "$idedir" ]; then
    echo "Please provide a directory where I can find the IDE files"
    echo "Example:"
    echo
    echo "./make-installer.sh ~/Microblocks-v14"
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

unset DISPLAY
mkdir build
cp $idedir/* -r build
cp microBlocks.ico build
cp install-config.iss build
cd build
wine "$isccpath" install-config.iss
mv microBlocks\ setup.exe ..
cd ..
rm -rf build
