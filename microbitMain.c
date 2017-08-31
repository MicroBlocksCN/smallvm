// microbitMain.c - Test interpreter.
// John Maloney, May 2017

#include <stdio.h>
#include <stdlib.h>
#include "mem.h"
#include "interp.h"

int main(int argc, char *argv[]) {
	hardwareInit();
	memInit(2500);
	printStartMessage("Welcome to uBlocks for BBC micro:bit!");
	vmLoop();
}
