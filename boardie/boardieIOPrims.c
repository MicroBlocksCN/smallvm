/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieIOPrims.c - IO primitives for Boardie
// John Maloney, October 2022

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "mem.h"
#include "interp.h"

// Stubs for Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(0); }
OBJ primDigitalPins(OBJ *args) { return int2obj(0); }
OBJ primAnalogRead(int argCount, OBJ *args) { return int2obj(0); }
void primAnalogWrite(OBJ *args) { }
OBJ primDigitalRead(int argCount, OBJ *args) { return int2obj(0); }
void primDigitalWrite(OBJ *args) { }
void primDigitalSet(int pinNum, int flag) { };


// Stubs for other functions not used by Boardie

void resetServos() {}
void stopPWM() {}
void systemReset() {}
void turnOffPins() {}
void stopServos() { }

// Button simulation (use keyboard)

static int KEY_SCANCODE[255];

OBJ primButtonA(OBJ *args) {
	// simulate button A with the left arrow key
	return KEY_SCANCODE[80] ? trueObj : falseObj;
}

OBJ primButtonB(OBJ *args) {
	// simulate button B with the right arrow key
	return KEY_SCANCODE[79] ? trueObj : falseObj;
}

// static OBJ primTouchRead(int argCount, OBJ *args) {
// 	// instead of pins, we use key scancodes
// 	int code = obj2int(args[0]);
// 	return int2obj(KEY_SCANCODE[code] ? 0 : 255);
// }

// Tone (stubs for now)

void stopTone() { }

OBJ primHasTone(int argCount, OBJ *args) { return falseObj; }
OBJ primPlayTone(int argCount, OBJ *args) { return falseObj; }

// Other primitives (stubs)

OBJ primHasServo(int argCount, OBJ *args) { return falseObj; }
OBJ primSetServo(int argCount, OBJ *args) { return falseObj; }
OBJ primDACInit(int argCount, OBJ *args) { return falseObj; }
OBJ primDACWrite(int argCount, OBJ *args) { return falseObj; }

void primSetUserLED(OBJ *args) {
	tftSetHugePixel(3, 1, (trueObj == args[0]));
}

static PrimEntry entries[] = {
	{"hasTone", primHasTone},
	{"playTone", primPlayTone},
	{"hasServo", primHasServo},
	{"setServo", primSetServo},
	{"dacInit", primDACInit},
	{"dacWrite", primDACWrite},
};

void addIOPrims() {
	addPrimitiveSet("io", sizeof(entries) / sizeof(PrimEntry), entries);
}
