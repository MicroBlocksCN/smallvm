// linux.c - Microblocks for Linux
// An adaptation of raspberryPi.c by John Maloney to
// work on a GNU/Linux TTY as a serial device

// John Maloney, December 2017
// Bernat Romagosa, February 2018

#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Timing Functions

uint32 microsecs() {
    return millisecs() * 100; // just testing, give me a break! :)
}
uint32 millisecs() {
    return (uint32) 5;
}

// Communication/System Functions

static int serialPort;

void putSerial(char *s) { puts(s); }

int readBytes(uint8 *buf, int count) {
	int readCount = 0;
        char currentChar;
	while (readCount < count) {
            currentChar = getchar();
            if (currentChar ) return readCount;
            buf[readCount++] = currentChar;
	}
	return readCount;
}

int canReadByte() { return true; }
int canSendByte() { return true; }
void sendByte(char aByte) { printf("%c", aByte); }

// System Functions

const char * boardType() { return "Linux Computer"; }
void systemReset() { } // noop on Linux

// General Purpose I/O Pins

#define DIGITAL_PINS 0
#define ANALOG_PINS 0
#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
#define PIN_LED 0

// Pin Modes

// To speed up pin I/O, the current pin input/output mode is recorded in the currentMode[]
// array to avoid calling pinMode() unless the pin mode has actually changed.

static char currentMode[TOTAL_PINS];

#define MODE_NOT_SET (-1)

#define SET_MODE(pin, newMode) { \
	if ((newMode) != currentMode[pin]) { \
		pinMode((pin), newMode); \
		currentMode[pin] = newMode; \
	} \
}

static void initPins(void) {
	// Initialize currentMode to MODE_NOT_SET (neigher INPUT nor OUTPUT)
	// to force the pin's mode to be set on first use.

	for (int i; i < TOTAL_PINS; i++) currentMode[i] = MODE_NOT_SET;
}

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }
OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(OBJ *args) { return int2obj(0); } // no analog inputs
OBJ primAnalogWrite(OBJ *args) { return nilObj; } // analog output not supported

OBJ primDigitalRead(OBJ *args) {
	return nilObj;
}

OBJ primDigitalWrite(OBJ *args) {
	return nilObj;
}

OBJ primSetLED(OBJ *args) {
	return nilObj;
}

OBJ primI2cGet(OBJ *args) {
        return nilObj;
}

OBJ primI2cSet(OBJ *args) {
	return nilObj;
}

// Bogus micro:bit primitives
OBJ primMBDisplay(OBJ *args) {
        return nilObj;
}

OBJ primMBDisplayOff(OBJ *args) {
        return nilObj;
}

OBJ primMBPlot(OBJ *args) {
        return nilObj;
}

OBJ primMBUnplot(OBJ *args) {
        return nilObj;
}

OBJ primMBTiltX(OBJ *args) {
        return nilObj;
}

OBJ primMBTiltY(OBJ *args) {
        return nilObj;
}

OBJ primMBTiltZ(OBJ *args) {
        return nilObj;
}

OBJ primMBTemp(OBJ *args) {
        return nilObj;
}

OBJ primMBButtonA(OBJ *args) {
        return nilObj;
}

OBJ primMBButtonB(OBJ *args) {
        return nilObj;
}


// Linux Main

int main() {
    memInit(5000); // 5k words = 20k bytes
    restoreScripts();
    startAll();
    printf("MicroBlocks is running...\n");
    outputString("Welcome to uBlocks for Linux!");
    vmLoop();
}
