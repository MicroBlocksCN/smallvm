#!/bin/sh
# Build uBlocks on the Raspberry Pi
#
# Prereqs for Raspbian ("Buster") system:
#	libsdl2-dev libsdl2-ttf-dev

gcc -std=c99 -O3 -Wall -Wno-unused-variable -Wno-unused-result \
	-D GNUBLOCKS \
	-D ARDUINO_RASPBERRY_PI \
	-I/usr/local/include/SDL2 \
	-I ../vm \
	linux.c ../vm/*.c \
	linuxSensorPrims.c linuxFilePrims.c linuxIOPrims.c linuxNetPrims.c \
	linuxOutputPrims.c linuxTftPrims.c \
	-lSDL2 -lSDL2_ttf \
	-l wiringPi \
	-ldl -lm -lpthread -lsndio -lz \
	-o vm.linux.rpi
