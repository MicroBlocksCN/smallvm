// primitives_stubs.cpp - Microblocks primitive stubs for testing on Mac or Linux
// John Maloney, September 2017

#include <stdio.h>
#include <sys/time.h>
#include <time.h>

#include "mem.h"
#include "interp.h"

uint32 microsecs() {
	struct timeval now;
	gettimeofday(&now, NULL);
	return ((1000000L * now.tv_sec) + now.tv_usec) & 0xFFFFFFFF;
}

uint32 millisecs() {
	// Approximate milliseconds as (usecs / 1024) using a bitshift, since divide is very slow.
	// This avoids the need for a second hardware timer for milliseconds, but the millisecond
	// clock is effectively only 22 bits, and (like the microseconds clock) it wraps around
	// every 72 minutes.

	return microsecs() >> 10;
}

// stubs for compiling/testing on laptop

int canReadByte() { return false; }
int readBytes(uint8 *buf, int count) { return 0; }
int canSendByte() { return true; }
void sendByte(char aByte) { }

void hardwareInit() {}
void systemReset() {}

OBJ primAnalogRead(OBJ *args) { return int2obj(0); }
OBJ primAnalogWrite(OBJ *args) { return nilObj; }
OBJ primDigitalRead(OBJ *args) { return falseObj; }
OBJ primDigitalWrite(OBJ *args) { return nilObj; }
OBJ primSetLED(OBJ *args) { return nilObj; }
