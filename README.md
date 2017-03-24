# README #

SmallVM is an "bytecoded" virtual machine designed to run on 32-bit embedded processors with as little as 32k of RAM.
It is intended to be simple and easily ported and extended, yet high performance. It includes a garbage collected memory
to allow working with dynamic data structures such as strings and lists. Builtin data types include integers,
single-precision floating point numbers, booleans, and strings.

### How do I get set up? ###

I have been developing on Mac OS using the GCC ARM compiler and an mbed LPC1768 board.

I installed the ARM tools using:


```
#!shell script

brew tap PX4/homebrew-px4
brew update
brew install gcc-arm-none-eabi
```

This might also work:


```
#!shell script

brew cask install gcc-arm-embedded
```

It is also possible to develop using mbed's online compiler. In fact, this project started out
that way, then was exported to the GCC ARM toolchain. The mbed online compiler is very easy to use and probably sufficient for most people.

It should be possible to develop for some ARM-based Arduinos using the Arduino library
and toolchain, although that has not yet been explored.

### Who do I talk to? ###

This project is a collaboration between Bernat Romagosa (Arduino), Jens Moenig (SAP), and John Maloney (YCR-HARC).