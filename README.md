# README #

Microblocks (uBlocks) is a virtual machine for blocks
languages designed to run on 32-bit embedded processors with
as little as 8k of RAM. It is intended to be simple and
easily ported and extended, yet high performance. It
includes a garbage collected memory to allow working with
dynamic data structures and low-latency task scheduler
that can work at timescales down to 10-20 microseconds.

uBlocks supports incremental, "live" code development when
a board is tethered but allows the program to run autonomously
whent he board is disconnected from the host computer.

Built-in data types will include integers, single-precision
floating point numbers, booleans, strings, object arrays,
and byte arrays.

### How do I compile the VM? ###

The uBlocks virtual machine is written in C and C++.
The Arduino platform is preferred, but it can also
be built using the mbed platform and it should be
portable to other platforms with minimal effort.

The uBlocks virtual machine can be compiled and loaded onto
a board using the Arduino IDE (version 1.8 or later)
with the appropriate board installed and selected.
Boards that have been tested so far include the
Arduino Due and Primo and the BBC micro:bit.

### To Do List

#### Current Issues and Tasks ####

  * code persistence
  * test/make work on the Calliope

#### Virtual Machine ####

  * persistence (store code chunks in Flash, restore on startup)
  * incorporate immediate floats
  * mixed-mode int/float arithmetic
  * support for function parameters and local variables
  * garbage collector

#### Blocks ####

  * finish function support
  * additional I/O blocks (e.g. I2C, accelerometer, etc.)
  * improved support for arrays
  * allow arrays to be returned (serialized) to the IDE
  * string concatenation and manipulation blocks?

#### Snap IDE ####

  * compiler support for condition hats, wait until, "and" and "or", and new primitives
  * watchers

#### GP IDE ####

  * re-work top-level screen layout
  * stack highlighting
  * stop/go button support
  * talk bubble for returned values
  * finish support for user-defined functions
  * watchers
  * option to use helper app (needs websocket client support) to allow running in browser

### Who is working on this? ###

This project is a collaboration between Bernat Romagosa, Jens Moenig,
and John Maloney.
