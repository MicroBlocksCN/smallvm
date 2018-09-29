#!/bin/bash

# Pass the directory where the IDE files are as a parameter
exepath=$1
if [ -z "$exepath" ]; then
    echo "Please provide a path to the linux IDE executable"
    echo "Example:"
    echo
    echo "./build-deb.sh ~/ublocks-linux64bit [destination] [version-number] [arch]"
    exit 1
fi;

destdir=$2
if [ -z "$destdir" ]; then destdir=".."; fi

version=$3
if [ -z "$version" ]; then version="0-unknown"; fi

arch=$4
if [ -z "$arch" ]; then arch="all"; fi

mkdir -p deb/ublocks/usr/local/bin
mkdir -p deb/ublocks/usr/share/icons
mkdir -p deb/ublocks/usr/share/applications
mkdir -p deb/ublocks/usr/share/menu
mkdir -p deb/ublocks/DEBIAN
mkdir -p deb/ublocks/usr/share/doc/ublocks
chmod 0755 deb/ublocks/usr -R

cp $exepath deb/ublocks/usr/local/bin/ublocks
cp MicroBlocks.png deb/ublocks/usr/share/icons
cp MicroBlocks.desktop deb/ublocks/usr/share/applications
cp copyright deb/ublocks/usr/share/doc/ublocks
cp microBlocks.menu deb/ublocks/usr/share/menu

size=`du deb/ublocks | tail -n1 | cut -f1`
cat control | sed -E "s/@AppVersion/$version/" | sed -E "s/@Arch/$arch/" | sed -E "s/@InstalledSize/$size/"> deb/ublocks/DEBIAN/control
cp prerm postinst deb/ublocks/DEBIAN/

cd deb
fakeroot dpkg-deb --build ublocks
cd ..
mv deb/ublocks.deb $destdir/ublocks-$arch.deb

rm -rf deb
