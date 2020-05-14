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
    echo "usage: ./build.sh [OPTIONS]"
    echo
    echo "--help                        Print this message."
    echo "--system=[SYSTEM]             Only generate executables for this system. Possible"
    echo "                              values are linux64bit, linux32bit, raspberryPi, win"
    echo "                              and mac. If not set, it will generate executables for"
    echo "                              all systems."
    echo "--pack                        Create packages and installers. If --system parameter"
    echo "                              is present, it will only create it for the specified"
    echo "                              platform."
    echo "--version=[VERSION-NUMBER]    Specify a version number, i.e. 0.1.16rc3. If not set,"
    echo "                              it will try to parse it from the GP source files."
    echo "--esptool                     Download esptool in order to embed it into the IDE so"
    echo "                              it can install the VM into espressif boards."
    echo "--vm                          Build VMs for all officially supported boards. These"
    echo "                              will be embedded into the IDE."
    echo "--tools                       Automatically try to install missing tools needed"
    echo "                              by the build process."
    echo "--upload=[USER]@[URL]:[PATH]  Try to upload the VMs to a remote server."
    echo "--locale=[LANGUAGE-NAME]      Update locales for the specified language. To print"
    echo "                              all currently available languages, run it without"
    echo "                              an argument. If language does not exist, a new"
    echo "                              locale file will be created for it. If it does, a"
    echo "                              backup copy of the current locale file will be"
    echo "                              created in your OS temporary files directory."
    echo "--dev                         Build for the current system, and launch in dev mode"
    echo "                              with a REPL console. Press Control+C on the console"
    echo "                              to pause the Morphic loop and gain access to the"
    echo "                              REPL. Then issue the 'go' command to give control"
    echo "                              back to the Morphic loop."
    echo
    exit 0
fi

systems=("linux64bit" "linux32bit" "raspberryPi" "win" "mac")

currentOS=`uname -s`
if [ "$currentOS" == "Darwin" ]; then
    gp="gp-mac"
elif [ "$currentOS" == "Linux" ]; then
    gp="gp-linux64bit"
else
    echo "Platform $currentOS is not (yet?) supported by this build script."
    echo "Try to find the gp executable for your platform in this folder and run:"
    echo "cd gp; [command-to-run-GP] runtime/lib/* loadIDE.gp buildApps.gp"
    echo "Good luck!"
    exit 1
fi

if test -n "$locale"; then
    if [ $locale == '--locale' ]; then
        echo "Currently available locales:"
        echo
        for lang in `ls translations`; do
            echo $lang | cut -f1 -d.
        done
        echo
    else
        echo "Updating locale file for $locale..."
        (cd gp; ./$gp runtime/lib/* loadIDE.gp updateLocale.gp -- $locale)
        echo "Done."
        echo "Please edit the updated locale file at translations/$locale.txt"
        missing=`grep "^--MISSING--" translations/$locale.txt | wc -l`
        echo "A total of $missing missing strings have been marked with the \"--MISSING--\" tag."
    fi
    exit 0
fi

if test -n "$vm"; then
    (cd precompiled; ./updatePrecompiled.sh)
fi

if [ -z $version ]; then
    version=`cat ide/MicroBlocksRuntime.gp | sed -n -E "s/^method ideVersion.*'(.*)'.*/\1/p"`
fi

if test -n "$upload"; then
    if [ $upload == '--upload' ]; then
        echo "usage: --upload=[user]@[url]:[path]"
        exit 0
    else
        mkdir /tmp/$version
        cp precompiled/vm.* /tmp/$version
        scp -r /tmp/$version $upload
        rm -r /tmp/$version
    fi
fi

if test -n "$tools"; then
    # set the tools flag so packager scripts know we want them to auto-install missing tools
    export tools=1
fi

if test -n "$esptool"; then
    # get esptool for the requested systems
    if [ -z $system ] || [ $system == 'win' ]; then
        wget https://microblocks.fun/util/esptool.exe
        mkdir -p gp/packagers/win32/esptool
        mv esptool.exe gp/packagers/win32/esptool
    fi
    if [ -z $system ] || [ $system == 'linux64bit' ] || [ $system == 'linux32bit' ] || [ $system == 'raspberryPi' ]; then
        wget https://raw.githubusercontent.com/espressif/esptool/master/esptool.py
        mkdir -p gp/packagers/linux/esptool
        # change python to python3 in the shebang
        sed 's:#!/usr/bin/env python:&3:g' esptool.py > gp/packagers/linux/esptool/esptool.py
        rm esptool.py
    fi
    if [ -z $system ] || [ $system == 'mac' ]; then
        wget https://dl.espressif.com/dl/esptool-2.6.1-macos.tar.gz
        tar -xf esptool-2.6.1-macos.tar.gz
        rm esptool-2.6.1-macos.tar.gz
        mkdir -p gp/packagers/darwin/esptool
        mv esptool/esptool gp/packagers/darwin/esptool
        rm -r esptool
    fi
    exit 0
fi

# build the IDE by using the corresponding executable for our host system
mkdir -p apps

if test -n "$dev"; then
	# If launching in dev mode, build for current system
	if [ "$currentOS" == "Darwin" ]; then
		system="mac"
	elif [ "$currentOS" == "Linux" ]; then
		system="linux64bit"
	fi
fi

if [ -z $system ]; then
    # build for all systems
    for sys in ${systems[@]}; do
        (cd gp; ./$gp runtime/lib/* loadIDE.gp buildApps.gp -- $sys)
    done
else
    (cd gp; ./$gp runtime/lib/* loadIDE.gp buildApps.gp -- $system)
fi

# update date of MicroBlocks.app
touch apps/MicroBlocks.app

# app packaging
# also zips standalone executables
if test -n "$pack"; then
    echo "Packaging microBlocks version $version..."
    mkdir -p apps/packages
    mkdir -p apps/standalone
    # build Win32 installer
    if [ -z $system ] || [ $system == 'win' ]; then
        (cd apps; zip ublocks-win.zip ublocks-win.exe; mv ublocks-win.zip standalone)
        (cd gp/packagers/win32/; ./build-installer.sh ../../../apps/ublocks-win.exe ../../../apps/packages $version)
    fi
    # build .deb packages for amd64, i386 and armhf (Raspberry Pi)
    if [ -z $system ] || [ $system == 'linux64bit' ]; then
        (cd apps; zip ublocks-linux64bit.zip ublocks-linux64bit; mv ublocks-linux64bit.zip standalone)
        (cd gp/packagers/linux/; ./build-deb.sh ../../../apps/ublocks-linux64bit ../../../apps/packages $version amd64)
    fi
    if [ -z $system ] || [ $system == 'linux32bit' ]; then
        (cd apps; zip ublocks-linux32bit.zip ublocks-linux32bit; mv ublocks-linux32bit.zip standalone)
        (cd gp/packagers/linux/; ./build-deb.sh ../../../apps/ublocks-linux32bit ../../../apps/packages $version i386)
    fi
    if [ -z $system ] || [ $system == 'raspberryPi' ]; then
        (cd apps; zip ublocks-raspberryPi.zip ublocks-raspberryPi; mv ublocks-raspberryPi.zip standalone)
        (cd gp/packagers/linux/; ./build-deb.sh ../../../apps/ublocks-raspberryPi ../../../apps/packages $version armhf)
    fi
    # build zip package for Mac
    if [ -z $system ] || [ $system == 'mac' ]; then
        (cd gp/packagers/darwin/; ./build-zip.sh ../../../apps/MicroBlocks.app ../../../apps/packages $version)
    fi
fi

echo
echo "Done building $version"

if test -n "$dev"; then
	# Launch MicroBlocks in a REPL console
	if [[ `command -v rlwrap` ]]; then
		launcher='rlwrap ../apps/ublocks-'$system
	else
		echo "rlwrap not found. Consider installing it to get command history and keyboard"
		echo "navigation in the MicroBlocks REPL."
		launcher='../apps/ublocks-'$system
	fi
    (cd gp; $launcher runtime/lib/* loadIDE.gp - --allowMorphMenu)
fi
