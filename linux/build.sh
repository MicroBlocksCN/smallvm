#!/bin/sh
# Build uBlocks for GNU/Linux

# Prereqs: libc6-dev-i386

gcc -m32 -O3 -Wall -I ../vm linux.c ../vm/*.c -o GnuBlocks
