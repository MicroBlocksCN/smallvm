// mbedMain.c - Test interpreter.
// John Maloney, April 2017

#include <stdio.h>
#include <stdlib.h>
#include "mem.h"
#include "interp.h"

#include <gpio_api.h>
#include <us_ticker_api.h>
#define TICKS() (us_ticker_read())

void interpTests1(void);
void taskTest(void);

gpio_t myPin;

void pinTest(char *name, int p) {
	gpio_init(&myPin, p);

	printf("%s: pin %x mask %lx dir %x set %x clr %x in %x\r\n",
		name, myPin.pin, myPin.mask,
		(uint32) myPin.reg_dir, (uint32) myPin.reg_set,
		(uint32) myPin.reg_clr, (uint32) myPin.reg_in);
}

gpio_t ledPin1;
gpio_t ledPin2;
gpio_t ledPin3;
gpio_t ledPin4;

void turnOnLEDs(int led1, int led2, int led3, int led4) {
	gpio_init(&ledPin1, LED1);
	gpio_init(&ledPin2, LED2);
	gpio_init(&ledPin3, LED3);
	gpio_init(&ledPin4, LED4);

	gpio_dir(&ledPin1, PIN_OUTPUT);
	gpio_dir(&ledPin2, PIN_OUTPUT);
	gpio_dir(&ledPin3, PIN_OUTPUT);
	gpio_dir(&ledPin4, PIN_OUTPUT);

	gpio_write(&ledPin1, led1);
	gpio_write(&ledPin2, led2);
	gpio_write(&ledPin3, led3);
	gpio_write(&ledPin4, led4);
}

void waitMillisecs(int msecs) {
	unsigned int wakeTime = TICKS() + (1000 * msecs);
	while ((TICKS() - wakeTime) > 100000) {
		// busy wait
	}
}

void showStackAndHeap() {
	int dummy;
	char *stackPointer = (char *) &dummy; // approximated as the address of the stack variable "dummy"
	char *tmp = (char *) malloc(4);
	char *heapStart = tmp; // record the start of heap
	free(tmp);
	printf("Bottom of stack: %x, Start of heap: %x, Difference: %d bytes\r\n",
		(int) stackPointer, (int) heapStart, stackPointer - heapStart);
}

int maxHeapChunk() {
	// Return the size of the largest piece of memory we can malloc()
	void *buf;
	int size = 32768;
	while ((buf = (void *) malloc(--size)) == NULL) { /* noop */ }
	free(buf);
	return size;
}

void scanMemory(unsigned int startAddr) {
	// Scan RAM or Flash memory (stops when it runs off the the end)
	int emptyCount = 0; // number of times we've read -1, which indicates an erased page
    unsigned int *mem = (unsigned int *) startAddr;
    while (1) {
		if (0xFFFFFFFF == *mem) emptyCount++;
		else emptyCount = 0;
        printf("%x: %x \r\n", (int) mem, *mem);
        mem += 512;
        if (emptyCount > 10) return;
 	}
}

int main(int argc, char *argv[]) {
//	hardwareInit();
	memInit(5000);
	printStartMessage("Welcome to uBlocks for mbed!");
	vmLoop();
	return 0;

	printf("Starting...\r\n");
	showStackAndHeap();
    printf("Max malloc allocation: %d bytes\r\n", maxHeapChunk());
	scanMemory(0); // scan Flash

// pinTest("D8", D8);
// pinTest("D9", D9);
// pinTest("D2", D2);
// pinTest("D3", D3);
// pinTest("A1", A1);
// pinTest("A2", A2);
// pinTest("A4", A4);
// pinTest("A5", A5);
//
// int delay = 100;
// while (1) {
// 	turnOnLEDs(0, 0, 0, 0);
// 	waitMillisecs(delay);
// 	turnOnLEDs(1, 0, 0, 0);
// 	waitMillisecs(delay);
// 	turnOnLEDs(1, 1, 0, 0);
// 	waitMillisecs(delay);
// 	turnOnLEDs(0, 1, 1, 0);
// 	waitMillisecs(delay);
// 	turnOnLEDs(0, 0, 1, 1);
// 	waitMillisecs(delay);
// 	turnOnLEDs(0, 0, 0, 1);
// 	waitMillisecs(delay);
// }
}
