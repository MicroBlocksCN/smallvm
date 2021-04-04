#!/bin/sh
# Build uBlocks for generic GNU/Linux
# Connect to it via pseudo terminal
#
# Prerequisites to run on 64-bit Linux (tested on Ubuntu 20.04):
#	sudo apt install gcc-multilib libgl1-mesa-glx:i386
#
# Might be needed: libasound2:i386
#
# Additional prerequisites to build GnuBlocks on a 64-bit Linux system:
#	sudo apt install libsdl2-dev:i386 libsdl2-ttf-dev:i386 libpng-dev:i386
#
# Not needed in John's test:
#	libc6-dev-i386 g++-multilib zlib1g-dev:i386

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
	-ldl -lm -lpthread -lasound \
	-o GnuBlocks
