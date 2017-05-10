// microbitMain.c - Test interpreter.
// John Maloney, May 2017

#include <stdio.h>
#include <stdlib.h>
#include "mem.h"
#include "interp.h"

int main(int argc, char *argv[]) {
	printf("Starting Micro Bit...\r\n");

	hardwareInit();
	memInit(2500);

	while (true) {
		processMessage();
		stepTasks();
	}
	return 0;
}
