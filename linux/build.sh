#!/bin/sh
# Build uBlocks for GNU/Linux

# Prereqs: libc6-dev-i386

gcc -I ../vm linux.c ../vm/*.c -o GnuBlocks -m32
