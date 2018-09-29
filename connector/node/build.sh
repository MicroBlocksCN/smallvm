#!/bin/bash
# I build bundled binaries for the three major desktop OSes by using pkg

# First, make sure pkg is installed

if ! test `which pkg`; then
    echo "Please provide your superuser password so I can install pkg for you"
    sudo npm install pkg -g
fi

if ls build 2> /dev/null > /dev/null; then
    echo "Removing old binaries..."
    rm -rf build
fi

echo "Building binaries..."
pkg . --debug > /tmp/pkg.log

echo "Packaging binaries for all three OSes..."
mkdir -p build/linux
mkdir -p build/macos
mkdir -p build/win
mv ublocks-linux build/linux
mv ublocks-macos build/macos
mv ublocks-win.exe build/win

echo "Copying additional files..."
cp -r icons build/linux
cp -r icons build/macos
cp -r win32-extras/icons build/win

echo "Downloading serialport pre-built binaries..."
curl -OL https://github.com/node-serialport/node-serialport/releases/download/v6.0.4/serialport-v6.0.4-node-v57-linux-x64.tar.gz
curl -OL https://github.com/node-serialport/node-serialport/releases/download/v6.0.4/serialport-v6.0.4-node-v57-darwin-x64.tar.gz
curl -OL https://github.com/node-serialport/node-serialport/releases/download/v6.0.4/serialport-v6.0.4-node-v57-win32-x64.tar.gz

echo "Unpacking serialport lib pre-built binaries..."
tar -xf serialport-v6.0.4-node-v57-linux-x64.tar.gz
mv build/Release/serialport.node build/linux

tar -xf serialport-v6.0.4-node-v57-darwin-x64.tar.gz
mv build/Release/serialport.node build/macos

tar -xf serialport-v6.0.4-node-v57-win32-x64.tar.gz
mv build/Release/serialport.node build/win

rm -rf build/Release

rm serialport-v6.0.4-node-v57-linux-x64.tar.gz
rm serialport-v6.0.4-node-v57-darwin-x64.tar.gz
rm serialport-v6.0.4-node-v57-win32-x64.tar.gz

echo "Packing archives..."
cd build
mv linux ublocks
zip -r ublocks-linux.zip ublocks
rm -r ublocks

mv macos ublocks
zip -r ublocks-macos.zip ublocks
rm -r ublocks

mv win ublocks
zip -r ublocks-win.zip ublocks
rm -r ublocks

cd ..

echo "All done!"
