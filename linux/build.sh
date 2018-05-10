#!/bin/sh
# Build uBlocks for generic GNU/Linux
# No I/O pins or devices, but useful for testing
# Connect to it via pseudo terminal

# Prereqs: libc6-dev-i386

gcc -m32 -O3 -Wall -Wno-implicit-function-declaration -I ../vm linux.c ../vm/*.c -o ublocks-generic
