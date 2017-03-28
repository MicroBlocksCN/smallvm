# README #

SmallVM is an "bytecoded" virtual machine designed to run on 32-bit embedded processors with as little as 32k of RAM.
It is intended to be simple and easily ported and extended, yet high performance. It includes a garbage collected memory
to allow working with dynamic data structures such as strings and lists. Builtin data types include integers,
single-precision floating point numbers, booleans, and strings.

### How do I get set up? ###

The quickest way to compile the VM is to use mbed's online compiler. You'll need to create an mbed account. It's free, but it may require some sort of registration key. I set up my mbed account years ago, so things may have changed.

In any case, the mbed online compiler is super easy to use. Just create a new project, discard the main.cpp it gives you, and drag-drop all the .h and .c files onto it. Then hit the compile switch. This will download a .bin file to your computer. (It may also show some compiler warnings that you can ignore.) Plug in your mbed board and drag the .bin file onto the USB drive that appears. This will install the program. Press the reset button and the program will run. Easy!

I wanted some additional options, such as the ability to output assembly code listings, so I have been developing on Mac OS X (10.11.8) using the GCC ARM compiler and an mbed LPC1768 board.

I installed the ARM tools using:


```
#!shell script

brew cask install gcc-arm-embedded
```

The build the VM with this tool, just type make in the smallvm directory.

### Who do I talk to? ###

This project is a collaboration between Bernat Romagosa (Arduino), Jens Moenig (SAP), and John Maloney (YCR-HARC).