/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.c - Microblocks adaptation of sensor primitives for Linux. Most
// of them will just be always studs. Others can be implemented for the Raspberry
// pi. Microphone can be implemented for regular Linux.
// Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "mem.h"
#include "interp.h"

extern int KEY_SCANCODE[];

OBJ primAcceleration(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTemp(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltX(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltY(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltZ(int argCount, OBJ *args) { return int2obj(0); }

OBJ primTouchRead(int argCount, OBJ *args) {
	// instead of pins, we use key scancodes
	int code = obj2int(args[0]);
	return int2obj(KEY_SCANCODE[code] ? 0 : 255);
}

OBJ primI2cGet(OBJ *args) { return int2obj(0); }
OBJ primI2cSet(OBJ *args) { return int2obj(0); }
OBJ primSPISend(OBJ *args) { return int2obj(0); }
OBJ primSPIRecv(OBJ *args) { return int2obj(0); }
OBJ primI2cRead(OBJ *args) { return int2obj(0); }
OBJ primI2cWrite(OBJ *args) { return int2obj(0); }
OBJ primReadDHT(OBJ *args) { return int2obj(0); }
OBJ primMicrophone(OBJ *args) { return int2obj(0); }

static PrimEntry entries[] = {
	{"acceleration", primAcceleration},
	{"temperature", primMBTemp},
	{"tiltX", primMBTiltX},
	{"tiltY", primMBTiltY},
	{"tiltZ", primMBTiltZ},
	{"touchRead", primTouchRead},
	{"i2cRead", primI2cRead},
	{"i2cWrite", primI2cWrite},
	{"readDHT", primReadDHT},
	{"microphone", primMicrophone},
};

void addSensorPrims() {
	addPrimitiveSet("sensors", sizeof(entries) / sizeof(PrimEntry), entries);
}
