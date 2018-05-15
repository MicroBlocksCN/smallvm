#!/bin/sh
# Build uBlocks for generic GNU/Linux
# No I/O pins or devices, but useful for testing
# Connect to it via pseudo terminal
#
# -D GNUBLOCKS enables persistence by saving code into a file
#
# Prereq for 64-bit Linux systems: libc6-dev-i386

gcc -m32 -std=c99 -Wall -O3 \
	-D GNUBLOCKS -I ../vm linux.c ../vm/*.c \
	-o GnuBlocks
