#!/bin/sh
# Build uBlocks for generic GNU/Linux
# Connect to it via pseudo terminal
#
# Prereqs for 64-bit Linux systems:
#	libc6-dev-i386 gcc-multilib g++-multilib libsdl2-dev:i386 libsdl2-ttf-dev:i386
# May also need:
#	libgl1-mesa-glx:i386 libasound2:i386

gcc -m32 -std=c99 -Wall -Wno-unused-variable -Wno-unused-result -O3 \
	-D GNUBLOCKS \
	-I/usr/local/include/SDL2 \
	-I ../vm \
	linux.c ../vm/*.c \
	linuxFilePrims.c linuxFont.c linuxIOPrims.c linuxNetPrims.c \
	linuxOutputPrims.c linuxSensorPrims.c linuxTftPrims.c \
	/usr/local/lib/libSDL2.a \
	/usr/local/lib/libSDL2_ttf.a \
	/usr/local/lib/libfreetype.a \
	/usr/lib/i386-linux-gnu/libpng.a \
	/usr/lib/i386-linux-gnu/libz.a \
	-ldl -lm -lpthread \
	-o GnuBlocks

# For static linking replace -lSDL2 with /usr/local/lib/libSDL2.a \

# -lsndio

#	`pkg-config --cflags pangocairo` \
#	`pkg-config --libs pangocairo` \
# libpango1.0-dev
