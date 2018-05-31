#!/bin/sh

unset DISPLAY

mkdir build
cd build
unzip ../../build/ublocks-win.zip
mv ublocks/* .
cp ../daemon.vbs .
cp ../install-config.iss .
wine "`find ~/.wine/drive_c | grep ISCC.exe`" install-config.iss
mv microBlocks\ setup.exe ..
cd ..
rm -rf build
