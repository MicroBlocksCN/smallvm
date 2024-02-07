/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieSerialPrims.cpp - Microblocks Serial primitives based on WebMIDI
// Bernat Romagosa, February 2023

#include <stdio.h>
#include <stdlib.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"

// Serial stubs, for now

static OBJ primSerialOpen(int argCount, OBJ *args) { return falseObj; }
static OBJ primSerialClose(int argCount, OBJ *args) { return falseObj; }
static OBJ primSerialRead(int argCount, OBJ *args) { return falseObj; }
static OBJ primSerialReadInto(int argCount, OBJ *args) { return falseObj; }
static OBJ primSerialWrite(int argCount, OBJ *args) { return falseObj; }
static OBJ primSetPins(int argCount, OBJ *args) { return falseObj; }
static OBJ primSerialWriteBytes(int argCount, OBJ *args) { return falseObj; }

// WebMIDI

static OBJ primMIDISend(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	EM_ASM_({
			if (typeof window.midiOutput === 'undefined') {
				// try to open output
				if (typeof navigator.requestMIDIAccess !== 'undefined') {
					navigator.requestMIDIAccess().then(
						function (midiAccess) {
							window.midiOutput = Array.from(midiAccess.outputs)[0][1];
						}
					);
				}
			}
			if (typeof window.midiOutput === 'undefined') return; // no midi output

			// Yes, really. If someone knows of a *fast* and *elegant*
			// way to get emscripten params by their index, I'll gladly
			// turn this ugly switch statement into a for loop...
			switch ($0) {
				case 1:
					window.midiOutput.send([$1]);
					break;
				case 2:
					window.midiOutput.send([$1, $2]);
					break;
				case 3:
					window.midiOutput.send([$1, $2, $3]);
					break;
			}
		},
		argCount, // byteCount
		obj2int(args[0]), // byte 1
		obj2int(args[1]), // byte 2 (optional)
		obj2int(args[2]) // byte 3 (optional)
	);
	return trueObj;
}

static OBJ primMIDIRecv(int argCount, OBJ *args) { return falseObj; }
static OBJ primMIDIConnect(int argCount, OBJ *args) { return falseObj; } // deprecated; will be removed

// Primitives

static PrimEntry entries[] = {
	{"open", primSerialOpen},
	{"close", primSerialClose},
	{"read", primSerialRead},
	{"readInto", primSerialReadInto},
	{"write", primSerialWrite},
	{"setPins", primSetPins},
	{"writeBytes", primSerialWriteBytes},
	{"midiSend", primMIDISend},
	{"midiRecv", primMIDIRecv},
	{"midiConnect", primMIDIConnect}, // deprecated; will be removed
};

void addSerialPrims() {
	addPrimitiveSet("serial", sizeof(entries) / sizeof(PrimEntry), entries);
}
