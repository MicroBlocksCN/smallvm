// ioPrims.cpp - Microblocks IO primitives and hardware dependent functions
// John Maloney, April 2017

#include "Arduino.h"
#include <stdio.h>

#include "mem.h"
#include "interp.h"

// Timing Functions

#if defined(NRF51)

static char *clock_base = (char *) 0x40008000;

void initClock_NRF51() {
	*((int *) (clock_base + 0x010)) = 1; // shutdown & clear
	*((int *) (clock_base + 0x504)) = 0; // timer mode
	*((int *) (clock_base + 0x508)) = 3; // 32-bit
	*((int *) (clock_base + 0x510)) = 4; // prescale - divides 16MHz by 2^N
	*((int *) (clock_base + 0x0)) = 1; // start
}

uint32 microsecs() {
	*((int *) (clock_base + 0x40)) = 1; // capture into cc1
	return *((uint32 *) (clock_base + 0x540)); // return contents of cc1
}

uint32 millisecs() {
	// Approximate milliseconds as (usecs / 1024) using a bitshift, since divide is very slow.
	// This avoids the need for a second hardware timer for milliseconds, but the millisecond
	// clock is effectively only 22 bits, and (like the microseconds clock) it wraps around
	// every 72 minutes.

	return microsecs() >> 10;
}

void hardwareInit() { initClock_NRF51(); }

#else

uint32 microsecs() { return (uint32) micros(); }
uint32 millisecs() { return (uint32) millis(); }

void hardwareInit() { }

#endif

// Communciation/System Functions

void putSerial(char *s) { Serial.print(s); } // callable from C; used to simulate printf for debugging

int readBytes(uint8 *buf, int count) {
	int bytesRead = Serial.available();
	for (int i = 0; i < bytesRead; i++) {
		buf[i] = Serial.read();
	}
	return bytesRead;
}

int canReadByte() { return Serial.available(); }
int canSendByte() { return true; } // Serial.availableForWrite not implemented for Primo
void sendByte(char aByte) { Serial.write(aByte); }

void systemReset() { NVIC_SystemReset(); }

// General Purpose I/O Pins

// See variant.cpp in variants/BBCMicrobit folder for a detailed pin map.
// Pins 0-20 are for micro:bit pads and edge connector.
// Pins 21-22: RX, TX (for USB Serial?)
// Pins 23-28: COL4, COL5, COL6, ROW1, ROW2, ROW3

// Analog pins (micro:bit pin numbers 0, 1, 2, 3, 4, 10)
// Note: The micro:bit does not have dedicated analog input pins, so these
// pins are the same as the digital pins with the same numbers.

static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

// Macro used to set pin input/output mode; current mode kept in an array
// to avoid calling pinMode() unless mode has changed.

#define MAX_PINS 29
static char currentMode[MAX_PINS];

#define SET_MODE(pin, newMode) { \
	if ((newMode) != currentMode[pin]) { \
		pinMode((pin), newMode); \
		currentMode[pin] = newMode; \
	} \
}

OBJ primAnalogRead(OBJ *args) {
char buf[100];
sprintf(buf, "29 -> %d, 30 -> %d, 31 -> %d, 32 -> %d",
	g_ADigitalPinMap[29],
	g_ADigitalPinMap[30],
	g_ADigitalPinMap[31],
	g_ADigitalPinMap[32]);
outputString(buf);

	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > 5)) return int2obj(0);
	int pin = analogPin[pinNum];
	SET_MODE(pin, INPUT);
	return int2obj(analogRead(pin));
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = obj2int(args[1]);
	if ((pinNum < 0) || (pinNum >= MAX_PINS)) return nilObj;
	SET_MODE(pinNum, OUTPUT);
	analogWrite(pinNum, value);
	return nilObj;
}

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum >= MAX_PINS)) return nilObj;
	SET_MODE(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	if ((pinNum < 0) || (pinNum >= MAX_PINS)) return nilObj;
	SET_MODE(pinNum, OUTPUT);
	digitalWrite(pinNum, value);
	return nilObj;
}

OBJ primSetLED(OBJ *args) {
	const int col2 = 4;
	const int row1 = 26;
	SET_MODE(col2, OUTPUT);
	SET_MODE(row1, OUTPUT);
	if (trueObj == args[0]) {
		digitalWrite(col2, LOW);
		digitalWrite(row1, HIGH);
	} else {
		digitalWrite(col2, HIGH);
		digitalWrite(row1, LOW);
	}
	return nilObj;
}
