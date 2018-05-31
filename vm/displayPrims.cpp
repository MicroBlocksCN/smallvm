/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// displayPrims.c - Microblocks display primitives
// John Maloney, May 2018

#include <Arduino.h>
#include <stdio.h>

#include "mem.h"
#include "interp.h"

// LED Matrix Pins on BBC micro:bit and Calliope

#if defined(ARDUINO_BBC_MICROBIT)

#define ROW1 3
#define ROW2 4
#define ROW3 6
#define ROW4 7
#define ROW5 9
#define ROW6 10
#define ROW7 23
#define ROW8 24
#define ROW9 25

#define COL1 26
#define COL2 27
#define COL3 28

#elif defined(ARDUINO_CALLIOPE)

#define ROW1 4
#define ROW2 5
#define ROW3 12
#define ROW4 11
#define ROW5 10
#define ROW6 6
#define ROW7 7
#define ROW8 8
#define ROW9 9

#define COL1 13
#define COL2 14
#define COL3 15

#endif

static int microBitDisplayBits = 0;

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE)

static void turnDisplayOn() {
	char pins[] = {COL1, COL2, COL3, ROW1, ROW2, ROW3, ROW4, ROW5, ROW6, ROW7, ROW8, ROW9};

	for (int i = 0; i < 12; i++) setPinMode(pins[i], OUTPUT);
}

static void turnDisplayOff() {
	char pins[] = {COL1, COL2, COL3, ROW1, ROW2, ROW3, ROW4, ROW5, ROW6, ROW7, ROW8, ROW9};

	for (int i = 0; i < 12; i++) setPinMode(pins[i], INPUT);
}

static int displaySnapshot = 0;
static int displayCycle = 0;

#define DISPLAY_BIT(n) (((displaySnapshot >> (n - 1)) & 1) ? LOW : HIGH)

void updateMicrobitDisplay() {
	// Update the display by cycling through the three columns, turning on the rows
	// for each column. To minimize display artifacts, the display bits are snapshot
	// at the start of each cycle and the snapshot is not changed during the cycle.

	if (!microBitDisplayBits && !displaySnapshot) return; // display is off

	if (0 == displayCycle) { // starting a new cycle
		if (!displaySnapshot && microBitDisplayBits) turnDisplayOn(); // display just became on
		if (displaySnapshot && !microBitDisplayBits) { // display just became off
			displaySnapshot = 0;
			turnDisplayOff();
			return;
		}
		// take a snapshot of the display bits for the next cycle
		displaySnapshot = microBitDisplayBits;
	}

	// turn off all columns
	digitalWrite(COL1, LOW);
	digitalWrite(COL2, LOW);
	digitalWrite(COL3, LOW);

	switch (displayCycle) {
	case 0:
		digitalWrite(ROW1, DISPLAY_BIT(1));
		digitalWrite(ROW2, DISPLAY_BIT(3));
		digitalWrite(ROW6, DISPLAY_BIT(5));
		digitalWrite(ROW3, DISPLAY_BIT(12));
		digitalWrite(ROW4, DISPLAY_BIT(16));
		digitalWrite(ROW5, DISPLAY_BIT(17));
		digitalWrite(ROW9, DISPLAY_BIT(18));
		digitalWrite(ROW8, DISPLAY_BIT(19));
		digitalWrite(ROW7, DISPLAY_BIT(20));
		digitalWrite(COL1, HIGH);
		break;
	case 1:
		digitalWrite(ROW7, DISPLAY_BIT(2));
		digitalWrite(ROW8, DISPLAY_BIT(4));
		digitalWrite(ROW2, DISPLAY_BIT(11));
		digitalWrite(ROW6, DISPLAY_BIT(13));
		digitalWrite(ROW1, DISPLAY_BIT(15));
		digitalWrite(ROW5, DISPLAY_BIT(22));
		digitalWrite(ROW9, DISPLAY_BIT(24));
		digitalWrite(ROW3, HIGH); // unused
		digitalWrite(ROW4, HIGH); // unused
		digitalWrite(COL2, HIGH);
		break;
	case 2:
		digitalWrite(ROW7, DISPLAY_BIT(6));
		digitalWrite(ROW8, DISPLAY_BIT(7));
		digitalWrite(ROW9, DISPLAY_BIT(8));
		digitalWrite(ROW5, DISPLAY_BIT(9));
		digitalWrite(ROW4, DISPLAY_BIT(10));
		digitalWrite(ROW3, DISPLAY_BIT(14));
		digitalWrite(ROW6, DISPLAY_BIT(21));
		digitalWrite(ROW1, DISPLAY_BIT(23));
		digitalWrite(ROW2, DISPLAY_BIT(25));
		digitalWrite(COL3, HIGH);
		break;
	}
	displayCycle = (displayCycle + 1) % 3;
}

#else // stubs for boards without 5x5 LED displays

void updateMicrobitDisplay() { }
// xxx delete:
// static int microbitAccel(int reg) { return 0; }
// static int microbitTemp(int registerID) { return 0; }
// static OBJ microbitButton(int buttonID) { return falseObj; }

#endif // micro:bit/Calliope display support

// NeoPixel Support

#define DELAY_CYCLES(n) { \
	__asm__ __volatile__ ( \
		".rept " #n " \n\t" \
		"nop \n\t" \
		".endr \n\t" \
	); \
}

inline uint32 saveIRQState(void) {
	uint32 pmask = 0;
	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
		__asm__ volatile ("rsil %0, #2" : "=a" (pmask));
	#else
		pmask = __get_PRIMASK() & 1;
		__set_PRIMASK(1);
	#endif
	return pmask;
}

inline void restoreIRQState(uint32 pmask) {
	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
		 __asm__ volatile ("wsr %0, ps; rsync" :: "a" (pmask));
	#else
		__set_PRIMASK(pmask);
	#endif
}

#if defined(ARDUINO_CALLIOPE)

#define pinBit 0x40004 // pin 18 (Calliope)
volatile int *pinSetDir = (int *) 0x50000518;
volatile int *pinSet = (int *) 0x50000508;
volatile int *pinClr = (int *) 0x5000050C;

void sendNeoPixelByte(int val) { // Calliope (16 MHz)
	*pinSetDir = pinBit;
	for (int i = 0; i < 8; i++) {
		if (val & 0x80) { // one bit: goal > 600 nqnosecs
			*pinSet = pinBit;
			DELAY_CYCLES(8);
			*pinClr = pinBit;
		} else { // zero bit: goal < 350 nqnosecs
			uint32 oldIRQ = saveIRQState();
			*pinSet = pinBit;
			*pinClr = pinBit;
			restoreIRQState(oldIRQ);
		}
		val <<= 1;
	}
}

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)

#define pinBit 0x800000 // pin PB23 (CircuitPlayground)
volatile int *pinSetDir = (int *) 0x41004488;
volatile int *pinSet = (int *) 0x41004498;
volatile int *pinClr = (int *) 0x41004494;

void sendNeoPixelByte(int val) { // Circuit Playground (48 MHz)
	*pinSetDir = pinBit;
	for (int i = 0; i < 8; i++) {
		if (val & 0x80) { // one bit: goal > 600 nqnosecs
			*pinSet = pinBit;
			DELAY_CYCLES(15);
			*pinClr = pinBit;
		} else { // zero bit: goal < 350 nqnosecs
			uint32 oldIRQ = saveIRQState();
			*pinSet = pinBit;
			*pinClr = pinBit;
			restoreIRQState(oldIRQ);
		}
		DELAY_CYCLES(5);
		val <<= 1;
	}
}

#else // stub for boards without NeoPixels

void sendNeoPixelByte(int val) { }

#endif // NeoPixel Support

// Display Primitives for micro:bit/Calliope (noops on other boards)

void primMBDisplay(OBJ *args) {
	OBJ arg = args[0];
	if (isInt(arg)) microBitDisplayBits = evalInt(arg);
}

void primMBDisplayOff(OBJ *args) {
	OBJ off = falseObj;
	primSetUserLED(&off);
	microBitDisplayBits = 0;
}

void primMBPlot(OBJ *args) {
	int x = evalInt(args[0]);
	int y = evalInt(args[1]);
	if ((1 <= x) && (x <= 5) && (1 <= y) && (y <= 5)) {
		int shift = (5 * (y - 1)) + (x - 1);
		microBitDisplayBits |= (1 << shift);
	}
}

void primMBUnplot(OBJ *args) {
	int x = evalInt(args[0]);
	int y = evalInt(args[1]);
	if ((1 <= x) && (x <= 5) && (1 <= y) && (y <= 5)) {
		int shift = (5 * (y - 1)) + (x - 1);
		microBitDisplayBits &= ~(1 << shift);
	}
}

// NeoPixel Primitive

void primNeoPixelSend(OBJ *args) {
	int r = evalInt(args[0]);
	int g = evalInt(args[1]);
	int b = evalInt(args[2]);
	if (r < 0) r = 0; if (r > 255) r = 255;
	if (g < 0) g = 0; if (g > 255) g = 255;
	if (b < 0) b = 0; if (b > 255) b = 255;
	sendNeoPixelByte(g);
	sendNeoPixelByte(r);
	sendNeoPixelByte(b);
}
