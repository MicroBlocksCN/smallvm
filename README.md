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
to allow working with dynamic data structures (within
the limits of the available RAM, of course).

MicroBlocks supports incremental, "live" code development when
a board is tethered but allows the program to run autonomously
when the board is disconnected from the host computer.
This allows the user to see the results of a program changes
immediately, without the overhead of compiling and downloading,
while allowing programs to continue to run when the board
is untethered. Since the board retains the user's program
in persistent Flash memory, MicroBlocks will eventually
allow the program on the board to be read back into a
MicroBlocks development environment for inspection and
further development.

Built-in data types include integers, booleans, strings, object
arrays, and byte arrays.

## How do I compile the VM? ##

First of all, you may not need to. If you have a BBC micro:bit,
Calliope mini, or an AdaFruit board such as the Circuit Playground
Express that supports loading .uf2 files by drag-and-drop, you can
just drop the appropriate .hex or .uf2 file onto the virtual
disk for your board to install it.

If you have an ARM-based Arduino or other board with
Arduino IDE support, or if you just want to build
the virtual machine yourself, read on.

The MicroBlocks virtual machine is written in C and C++.
The Arduino platform is preferred, but it has also
been built using the mbed platform (not supported).
It can also be built for Linux-based environments such
as the Raspberry Pi, and it should be portable to other
platforms that have a C compiler with minimal effort.

The MicroBlocks virtual machine can be compiled and loaded
onto a board using the Arduino IDE (version 1.8 or later)
with the appropriate board installed and selected.
Open the file "vm.ino", select your board from the
board manager, and click the upload button.

See the MicroBlocks website for a list of currently supported boards.

## Website ##

<http://microblocks.fun>

## License ##

MicroBlocks is licensed under the Mozilla Public License 2.0 (MPL 2.0).

## Status ##

MicroBlocks is not yet released. It is currently "pre-alpha".

## Contributing ##

Since MicroBlocks is not yet finished, we are not currently
soliciting or accepting contributions or pull requests.

However, we welcome your feedback, comments, feature requests, and bug reports.

## Who created MicroBlocks? ##

This project is a collaboration between John Maloney, Bernat Romagosa,
and Jens Moenig.
