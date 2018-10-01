# README #

This repository contains the source for the MicroBlocks
virtual machine.

[MicroBlocks](http://microblocks.fun) is a free, live, blocks programming system
for educators, learners, and makers. It runs on the BBC
micro:bit, the NodeMCU, ARM-based Arudino boards, and
other tiny computers such as the Raspberry Pi.

The MicroBlock virtual machine runs on 32-bit embedded processors
with as little as 8k of RAM. It is intended to be simple,
easily ported and extended, and offer decent performance.
It includes a low-latency task scheduler that works
at timescales down to about 20 microseconds.
It will eventually include a garbage collected memory
to allow working with dynamic data structures -- within
the limits of the available RAM, of course!

MicroBlocks supports both *live* development and autonomous operation.
Live development allows the user to see the results of program changes
immediately, without the overhead of compiling and downloading.
Autonomous operation means that programs continue to run when the board
is untethered from the host computer. Since the board retains the user's program
in persistent Flash memory, MicroBlocks will eventually
allow the user's program stored on the board to be read back into a
MicroBlocks development environment for inspection and
further development.

Built-in data types include integers, booleans, strings, and lists.

## How do I build the VM? ##

First of all, you may not need to. If you have a BBC micro:bit,
Calliope mini, or an AdaFruit board such as the Circuit Playground
Express that supports loading programs by drag-and-drop, you can
just drop the appropriate .hex or .uf2 file onto the virtual
disk for your board to install it.

If you have an ARM-based Arduino or other board with
Arduino IDE support, or if you just want to build
the virtual machine yourself, read on.

The MicroBlocks virtual machine is written in C and C++.
The Arduino platform is preferred, but it has also
been built using the mbed platform (no longer supported).
It can also be built for Linux-based environments such
as the Raspberry Pi, and it should be portable to other
platforms that have a C compiler with minimal effort.

The MicroBlocks virtual machine can be compiled and loaded
onto a board using the Arduino IDE (version 1.8 or later)
with the appropriate board installed and selected.
Open the file "vm.ino", select your board from the
board manager, and click the upload button.

See <a href="https://bitbucket.org/john_maloney/smallvm/wiki/Devices">supported devices</a> for a list of currently supported boards.

## Building for Raspberry Pi ##

To build the VM on the Raspberry Pi, run "./build" in the raspberryPi folder.
The Raspberry Pi version of MicroBlocks can control the digital I/O
pins of the Raspberry Pi.

On the Raspberry Pi, MicroBlocks can be run in two ways:

Desktop: If you run ublocks-pi with the "-p" switch,
it will create a pseudoterminal, and you can connect to that pseudoterminal
from the MicroBlocks IDE running in a window on the same Raspberry Pi.

Headless: If you configure your RaspberryPi Zero(W) to behave like a slave USB-serial
device, then it can be plugged into a laptop as if it were an Arduino or micro:bit.
The MicroBlocks VM can be started on a headless Pi either by connecting
to the Pi via SSH and running ublocks-pi from the command line
or by configuring Linux to start the VM at boot time.

## Building for generic Linux ##

To build the VM to run on a generic Linux computer, run "./build" in the linux folder.
Running the resulting executable creates a pseudoterminal that you can connect
to from the MicroBlocks IDE running on the same computer.

The generic Linux version of the VM can't control pins or other microcontroller I/O devices
(there aren't any!), but it can be used to study the virtual machine.
It's also handy for debugging, since the Linux VM can print debugging information
to stdout without interfering with the VM-IDE communications (which goes over
the pseudoterminal connection).

## MicroBlocks Website ##

<http://microblocks.fun>

## Status ##

MicroBlocks is released as alpha. The released version is stable and has been used by hundreds of people, many of them complete beginners. The "alpha" status is because MicroBlocks is still evolving. If you are writing documentation, plan to update it to track changes to the blocks, libraries, and UI.

## Contributing ##

We welcome your feedback, comments, feature requests, and
[bug reports](https://bitbucket.org/john_maloney/smallvm/issues?status=new&status=open).

Since MicroBlocks is still under active development by the core team, we are not currently
soliciting code contributions or pull requests. However, if you are creating tutorials or other materials for MicroBlocks, please let us know so we can link to your website.

## Team ##

This project is a collaboration between John Maloney, Bernat Romagosa,
and Jens Moenig.

## License ##

MicroBlocks is licensed under the Mozilla Public License 2.0 (MPL 2.0).
