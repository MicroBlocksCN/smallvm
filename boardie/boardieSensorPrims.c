/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.c - Microblocks adaptation of sensor primitives for Boardie.
// Most are just stubs. Microphone could be implemented. Tilt and acceleration
// could be implemented for mobile devices.
// Bernat Romagosa, November 2022

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "mem.h"
#include "interp.h"

#include <emscripten.h>

// Comm (stubs)
OBJ primI2cGet(OBJ *args) { return int2obj(0); }
OBJ primI2cSet(OBJ *args) { return int2obj(0); }
OBJ primSPISend(OBJ *args) { return int2obj(0); }
OBJ primSPIRecv(OBJ *args) { return int2obj(0); }
OBJ primSPIExchange(int argCount, OBJ *args) { return falseObj; }
OBJ primSPISetup(int argCount, OBJ *args) { return falseObj; }

// Touch Read (use keycodes)

static OBJ primTouchRead(int argCount, OBJ *args) {
	// instead of pins, we use keycodes
 	int code = obj2int(args[0]);
	return int2obj(EM_ASM_INT({ return window.keys.get($0); }, code) ? 0 : 255);
}

// Stubs

static OBJ primAcceleration(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTemp(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltX(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltY(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltZ(int argCount, OBJ *args) { return int2obj(0); }
static OBJ primI2cRead(int argCount, OBJ *args) { return int2obj(0); }
static OBJ primI2cWrite(int argCount, OBJ *args) { return int2obj(0); }
static OBJ primReadDHT(int argCount, OBJ *args) { return int2obj(0); }
static OBJ primMicrophone(int argCount, OBJ *args) { return int2obj(0); }

static PrimEntry entries[] = {
	{"acceleration", primAcceleration},
	{"temperature", primMBTemp},
	{"tiltX", primMBTiltX},
	{"tiltY", primMBTiltY},
	{"tiltZ", primMBTiltZ},
	{"touchRead", primTouchRead},
	{"i2cRead", primI2cRead},
	{"i2cWrite", primI2cWrite},
	{"spiExchange", primSPIExchange},
	{"spiSetup", primSPISetup},
	{"readDHT", primReadDHT},
	{"microphone", primMicrophone},
};

void addSensorPrims() {
	addPrimitiveSet(SensorPrims, "sensors", sizeof(entries) / sizeof(PrimEntry), entries);
}
