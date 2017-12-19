#!/bin/sh
# Build uBlocks on the Raspberry Pi
# Prerequisits:
#   Build and install: wiringPi (http://wiringpi.com) v2.44 or later

gcc -I ../vm raspberryPi.c ../vm/*.c -l wiringPi -o uBlocksPi
