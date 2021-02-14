#!/bin/sh
# Build uBlocks for generic GNU/Linux
# No I/O pins or devices, but useful for testing
# Connect to it via pseudo terminal
#
# -D GNUBLOCKS enables persistence by saving code into a file
#
# Prereq for 64-bit Linux systems: libc6-dev-i386 gcc-multilib g++-multilib libsdl2-dev:i386 libsdl2-ttf-dev:i386

gcc -m32 -std=c99 -Wall -Wno-unused-variable -Wno-unused-result -O3 \
	-D GNUBLOCKS \
	-I/usr/local/include/SDL2 \
	-I ../vm \
	linux.c ../vm/*.c \
	linuxFilePrims.c linuxIOPrims.c linuxNetPrims.c linuxOutputPrims.c linuxTftPrims.c \
	-lSDL2 -lSDL2_ttf \
	-ldl -lm -lpthread -lsndio -lz -lpng \
	-o GnuBlocks

# For static linking:
#	/usr/local/lib/libSDL2.a /usr/local/lib/libSDL2_ttf.a /usr/local/lib/libfreetype.a \
