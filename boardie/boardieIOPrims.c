/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieIOPrims.c - IO primitives for Boardie
// John Maloney, October 2022

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <emscripten.h>
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

OBJ primButtonA(OBJ *args) {
	// simulate button A with the left arrow key or A key
	// simulate A+B with T key (ASCII 84)
	return EM_ASM_INT({
		return window.keys.get(37) || window.keys.get(65) || window.keys.get(84);
	}) ? trueObj : falseObj;
}

OBJ primButtonB(OBJ *args) {
	// simulate button B with the right arrow key or B key
	// simulate A+B with T key (ASCII 84)
	return EM_ASM_INT({
		return window.keys.get(39) || window.keys.get(66) || window.keys.get(84);
	}) ? trueObj : falseObj;
}

// Tone

void stopTone() {
	EM_ASM_({
		if (window.oscillator.playing) {
			window.oscillator.disconnect();
			window.oscillator.playing = false;
			window.dispatchEvent(new Event('soundstop'));
		}
	});
}

OBJ primHasTone(int argCount, OBJ *args) { return trueObj; }
OBJ primPlayTone(int argCount, OBJ *args) {
	if ((argCount < 2) || !isInt(args[1])) return falseObj;
	int frequency = obj2int(args[1]);

	if ((frequency > 16) && (frequency < 11025)) {
		EM_ASM_({
			window.oscillator.frequency.value = $0;
			window.oscillator.playing = true;
			window.dispatchEvent(new Event('soundstart'));
			window.oscillator.connect(window.gainNode);
		}, frequency);
	} else {
		stopTone();
	}

	return falseObj;
}

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
	addPrimitiveSet(IOPrims, "io", sizeof(entries) / sizeof(PrimEntry), entries);
}
