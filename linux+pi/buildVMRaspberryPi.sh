#!/bin/sh
# Build uBlocks on the Raspberry Pi
#
# Prereqs for raspbian systems:
#	libsdl2-dev libsdl2-ttf-dev
# John did not need to install these (on newly installed Raspberrian "Buster"):
#	wiringpi libc6-dev gcc g++

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

# For static linking replace -lSDL2 -lSDL2_ttf with:
#	/usr/local/lib/libSDL2.a /usr/local/lib/libSDL2_ttf.a /usr/local/lib/libfreetype.a \
