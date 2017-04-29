// microBlocksPrims.c - Microblocks primitives
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Helper Functions

#ifndef ARDUINO
// On non-Arduino, implement millisecs() using the microsecond clock.
// Note: mbed doesn't have a millisecond clock and not all mbed boards
// have a realtime clock, so gettimeofday() doesn't work, either.

static uint32 msecsSinceStart = 0;
static uint32 lastTicks = 0;
static uint32 extraTicks = 0;

uint32 millisecs() {
	uint32 now = TICKS();
	extraTicks += (now - lastTicks);
	while (extraTicks >= 1000) {
		extraTicks -= 1000;
		msecsSinceStart += 1;
	}
	lastTicks = now;
	return msecsSinceStart;
}
#endif // not ARDUINO

OBJ sizeFailure() { return failure("Size must be a positive integer"); }
OBJ arrayClassFailure() { return failure("Must must be an Array"); }
OBJ indexClassFailure() { return failure("Index must be an integer"); }
OBJ outOfRangeFailure() { return failure("Index out of range"); }

// Platform Agnostic Primitives

OBJ primPeek(OBJ *args) {
	if (!isInt(args[0])) return int2obj(0);
	int *addr = (int *) obj2int(args[0]);
	return int2obj(*addr);
}

OBJ primPoke(OBJ *args) {
	if (!isInt(args[0])) return nilObj;
	int *addr = (int *) obj2int(args[0]);
	*addr = obj2int(args[1]);
	return nilObj;
}

OBJ primNewArray(OBJ args[]) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return sizeFailure();
// hack for primes benchmark: use byte array to simulate array of booleans
	OBJ result = newObj(ArrayClass, (obj2int(n) + 3) / 4, nilObj); // bytes
	return result;
}

OBJ primArrayFill(OBJ args[]) {
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	OBJ value = args[1];

	value = (OBJ) ((value == trueObj) ? 0x01010101 : 0); // hack to encode flag array as bytes

	int end = objWords(array) + HEADER_WORDS;
	for (int i = HEADER_WORDS; i < end; i++) ((OBJ *) array)[i] = value;
	return nilObj;
}

OBJ primArrayAt(OBJ args[]) {
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	OBJ index = args[1];
	if (!isInt(index)) return indexClassFailure();

	int i = obj2int(index);
	if ((i < 1) || (i > (objWords(array) * 4))) { return outOfRangeFailure(); }
// hack for primes benchmark: use byte array to simulate array of booleans
	char *bytes = (char *) array;
	return (bytes[(4 * HEADER_WORDS) + (i - 1)]) ? trueObj : falseObj;
}

OBJ primArrayAtPut(OBJ args[]) {
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	OBJ index = args[1];
	if (!isInt(index)) return indexClassFailure();
	OBJ value = args[2];

	int i = obj2int(index);
	if ((i < 1) || (i > (objWords(array) * 4))) return outOfRangeFailure();

// hack for primes benchmark: use byte array to simulate array of booleans
	char *bytes = (char *) array;
	bytes[(4 * HEADER_WORDS) + (i - 1)] = (value == trueObj);
	return nilObj;
}

// Platform specific primitives

#ifdef ARDUINO
#include "arduino.h"

static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > 5)) return int2obj(0);
	int pin = analogPin[pinNum];
	pinMode(pin, INPUT);
	return int2obj(analogRead(pin));
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = obj2int(args[1]);
	if ((pinNum < 0) || (pinNum > 5)) return nilObj;
	int pin = analogPin[pinNum];
	pinMode(pin, OUTPUT);
	analogWrite(pin, value);
	return nilObj;
}

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > 15)) return falseObj;
	pinMode(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	if ((pinNum < 0) || (pinNum > 15)) return nilObj;
	pinMode(pinNum, OUTPUT);
	digitalWrite(pinNum, value);
	return nilObj;
}

#else

// stubs for testing on laptop

int readBytes(uint8 *buf, int count) { return 0; }
void writeBytes(uint8 *buf, int count) {}

OBJ primAnalogRead(OBJ *args) { return int2obj(0); }
OBJ primAnalogWrite(OBJ *args) { return nilObj; }
OBJ primDigitalRead(OBJ *args) { return falseObj; }
OBJ primDigitalWrite(OBJ *args) { return nilObj; }

#endif
