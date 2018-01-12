#!/bin/bash

mkdir -p deb/ublocks/usr/local
mkdir -p deb/ublocks/etc/xdg/autostart
mkdir -p deb/ublocks/etc/profile.d

unzip -o ../build/ublocks-linux.zip -d deb/ublocks/usr/local/
cp ublocksd deb/ublocks/usr/local/ublocks
cp ublocks.desktop deb/ublocks/etc/xdg/autostart
cd deb
dpkg-deb --build ublocks
mv ublocks.deb ..

rm -rf ublocks/usr
rm -rf ublocks/etc

cd ..
