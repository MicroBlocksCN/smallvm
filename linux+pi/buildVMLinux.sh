#!/bin/sh
# Build uBlocks for generic GNU/Linux
# Connect to it via pseudo terminal
#
# Prereqs for 64-bit Linux systems:
#	libc6-dev-i386 gcc-multilib g++-multilib libsdl2-dev:i386 libsdl2-ttf-dev:i386

gcc -m32 -std=c99 -Wall -Wno-unused-variable -Wno-unused-result -O3 \
	-D GNUBLOCKS \
	-I/usr/local/include/SDL2 \
	`pkg-config --cflags pangocairo` \
	-I ../vm \
	linux.c ../vm/*.c \
	linuxSensorPrims.c linuxFilePrims.c linuxIOPrims.c linuxNetPrims.c \
	linuxOutputPrims.c linuxTftPrims.c \
	-lSDL2 \
	`pkg-config --libs pangocairo` \
	-ldl -lm -lpthread -lasound -lz \
	-o GnuBlocks

# For static linking replace -lSDL2 with /usr/local/lib/libSDL2.a \
# -lsndio
