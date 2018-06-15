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

# take only the executable name, removing everything up to the last slash
# also works if there are no slashes at all in $exepath
executable=${exepath##*/}

destdir=$2
if [ -z "$destdir" ]; then destdir=".."; fi

version=$3
if [ -z "$version" ]; then version="0-unknown"; fi

arch=$4
if [ -z "$arch" ]; then arch="all"; fi

mkdir -p deb/ublocks/usr/local/bin
mkdir -p deb/ublocks/DEBIAN

cat control | sed -E "s/@AppVersion/$version/" | sed -E "s/@Arch/$arch/" > deb/ublocks/DEBIAN/control
cp $exepath deb/ublocks/usr/local/bin/
cat ublocks | sed -E "s/@Executable/$executable/" > deb/ublocks/usr/local/bin/ublocks
fakeroot chmod 755 deb/ublocks/usr/local/bin/ublocks

cd deb
fakeroot dpkg-deb --build ublocks
cd ..
mv deb/ublocks.deb $destdir/ublocks-$arch.deb

rm -rf deb
