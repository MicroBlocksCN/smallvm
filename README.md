# README #

MicroBlocks is a free, live, blocks programming system
for educators, learners, and makers. It runs on the BBC
micro:bit, the NodeMCU, ARM-based Arudino boards, and
other tiny computers such as the Raspberry Pi.

The MicroBlock virtual machine runs on 32-bit embedded processors
with as little as 8k of RAM. It is intended to be simple and
easily ported and extended, yet high performance.
It includes a low-latency task scheduler that works
at timescales down to about 20 microseconds.
It will eventually include a garbage collected memory
to allow working with dynamic data structures, within
the limits of the available RAM.

MicroBlocks supports incremental, "live" code development when
a board is tethered but allows the program to run autonomously
when the board is disconnected from the host computer.
This allows the user to try program changes immediately,
without the overhead of compiling and downloading, while
still creating programs to continue to run when the board
is untethered. Since the board retains the program
in persistent Flash memory, MicroBlocks will eventually
allow the program on the board to be read back into the
MicroBlocks development environment for inspection or
further development.

Built-in data types include integers, booleans, strings, object
arrays, and byte arrays.

### How do I compile the VM? ###

First of all, you may not need to. If you have a BBC micro:bit,
Calliope mini, or an AdaFruit board such as the Circuit Playground
Express that supports loading .uf2 files by drag-and-drop, you can
just drop the appropriate .hex or .uf2 file onto the virtual
disk for your board to install it.

If you have and ARM-based Arduino or another board with
Arduino IDE support, read on.

The MicroBlocks virtual machine is written in C and C++.
The Arduino platform is preferred, but it can also
be built using the mbed platform (not supported).
It can be built for Linux-based environments such
as the Raspberry Pi. It should be portable to other
platforms with minimal effort.

The MicroBlocks virtual machine can be compiled and loaded
onto a board using the Arduino IDE (version 1.8 or later)
with the appropriate board installed and selected.
Boards that have been tested so far include the
Arduino Due and Primo and the BBC micro:bit.

### Status ###

MicroBlocks is not yet released. It is currently "pre-alpha".

### License ###

MicroBlocks is licensed under the Mozilla Public License 2.0 (MPL 2.0).

### Contributing ###

Since MicroBlocks is not yet finished, we are not currently
soliciting or accepting contributions or pull requests.

We welcome your feedback, comments, feature requests, and bug reports.

### Who is working on this? ###

This project is a collaboration between Bernat Romagosa, Jens Moenig,
and John Maloney.
