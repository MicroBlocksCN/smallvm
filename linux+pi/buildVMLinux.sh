#!/bin/sh
# Build uBlocks for generic GNU/Linux
# Connect to it via pseudo terminal
#
# Prereqs for 64-bit Linux systems:
#	libc6-dev-i386 gcc-multilib g++-multilib libpng-dev:i386 zlib1g-dev:i386
# Might also need (need to check on clean Ubuntu):
#	libgl1-mesa-glx:i386 libasound2:i386

gcc -m32 -std=c99 -Wall -Wno-unused-variable -Wno-unused-result -O3 \
	-D GNUBLOCKS \
	-I/usr/local/include/SDL2 \
	-I ../vm \
	linux.c ../vm/*.c \
	linuxFilePrims.c linuxIOPrims.c linuxNetPrims.c \
	linuxOutputPrims.c linuxSensorPrims.c linuxTftPrims.c \
	libs/libSDL2.a \
	libs/libSDL2_ttf.a \
	libs/libfreetype.a \
	/usr/lib/i386-linux-gnu/libpng.a \
	/usr/lib/i386-linux-gnu/libz.a \
	-ldl -lm -lpthread \
	-o GnuBlocks
