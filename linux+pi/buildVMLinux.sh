#!/bin/sh
# Build uBlocks for generic GNU/Linux
# Connect to it via pseudo terminal
#
# Prerequisites to run on 64-bit Linux (tested on Ubuntu 20.04):
#	sudo apt install gcc-multilib libgl1-mesa-glx:i386
#
# Additional prerequisites to build GnuBlocks on a 64-bit Linux system:
#	sudo apt install libsdl2-dev:i386 libsdl2-ttf-dev:i386 libpng-dev:i386
#
# Libraries built on Ubutu 16.04 (32-bit):
#	Prerequisite: libsndio-dev (without this installed, sndio won't be included)
#	SDL2-2.0.12 (./configure --disable-video-vulkan --disable-video-opengles --enable-sndio)
#	SDL2-ttf-2.0.15 (default configuration)
#	freetype-2.10.4 (default configuration)

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
	-o vm.linux.i386
