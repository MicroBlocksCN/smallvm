#!/bin/sh
# Build uBlocks on the Raspberry Pi
#
# Prerequisites:
#   Build and install: wiringPi (http://wiringpi.com) v2.44 or later

gcc -std=c99 -O3 -Wall -I ../vm raspberryPi.c ../vm/*.c -l wiringPi -o uBlocks-pi
