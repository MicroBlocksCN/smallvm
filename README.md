# README #

SmallVM is an "bytecoded" virtual machine designed to run on 32-bit embedded processors with as little as 4k of RAM.
It is intended to be simple and easily ported and extended, yet high performance. It includes a garbage collected memory
to allow working with dynamic data structures. Built-in data types include integers, single-precision floating point numbers, booleans, strings, object arrays, and byte arrays.

### How do I get set up? ###

The quickest way to compile the VM is to use mbed's online compiler. You'll need to create a free mbed account, but you don't need to download or install any software.

The mbed online compiler is super easy to use. Just select your board, create a new project, discard the main.cpp it gives you, and drag-and-drop the appropriate .h, .c, and .cpp files onto it. Use microbit.c for the BBC Micro Bit board and adapt mbedMain.c for generic mbed boards, and omit the other main and test .c files. Then hit the compile button. This will download a .bin file to your computer. (It may also show some compiler warnings that you can usually ignore.) Plug in your board and drag the .bin file onto the USB drive that appears. (For the Micro Bit, it will be a .hex file instead.) This will install the program. Press the reset button and the VM will start. Easy!

You can also use the Arduino IDE 1.8.2 or later. Select your ARM-based Arduino board and create a new sketch. This will make a folder in your Arduino folder (which is in the Documents folder on Mac OS). Delete the .ino file in the sketch folder and replace it with the appropriate .h, .c, and .cpp files (i.e. all but the ones with "main" or "test" in their names). Also include SmallVM.ino. Quit the Arduinio IDE and double-click on SmallVM.ino to restart the IDE. You should see the .ino file and all the .c and .cpp files as tabs in the sketch. Hit the download button to compile the sketch and install it on your board.

I needed some additional options, such as the ability to output assembly code listings, so I have been developing on Mac OS X (10.11.8) using the GCC ARM compiler and an mbed LPC1768 board.

I installed the necessary tools with following commands:


```
brew update
brew install srecord
brew cask install gcc-arm-embedded
```

The build the mbed VM with this tool, just type make in the smallvm directory.

Finally, you can build and run the VM on a laptop using your favorite C compiler. (Tested only on Mac OS with XCode, but should work on other platforms.) The ARM hardware operations will be stubbed out, of course, but basic VM tests can be run. This path is be used to debug the VM and object memory logic. Many bugs can be found and fixed before testing on actual hardware. The files interpTests1.c and taskTest.c were used, with suitable modifications of mbedMain.c. To compile the VM to run your local computer just invoke the compiler like this:

```
gcc -m32 macMain.c interp.c mem.c runtime.c primitives.cpp interpTests1.c taskTest.c -o vmTest
```

If it succeeds, you can run the VM like this:


```
./vmTest
```

### To Do List

#### Current Issues ####

  * debug lost messages
  * Snap: keep track of stack ID's
  * make Calliope work

#### Virtual Machine ####

  * persistence (store chunks in Flash, restore on startup)
  * incorporate immediate floats
  * mixed-mode int/float arithmetic
  * garbage collector

#### Blocks ####

  * additional math blocks
  * finish function support
  * additional Arduino and Micro Bit I/O blocks
  * string blocks?

#### Host-VM Communication Design ####

  * update protocol spec
  * finish and test protocol implementation
  * implement client side in GP and Snap

#### Blocks IDEs in Snap and GP ####

  * top-level screen layout
  * design the work flow
  * implement compiler
  * implement Host-VM communication
  * feedback for running stacks
  * support for user-defined functions
  * visualizing Arduino state

### Who is working on this? ###

This project is a collaboration between Bernat Romagosa (Arduino), Jens Moenig (SAP),
and John Maloney (YCR-HARC).
