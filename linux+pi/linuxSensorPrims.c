/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.c - Microblocks adaptation of sensor primitives for Linux.
// Most are just stubs. Others can be implemented for the Raspberry Pi.
// Microphone could be implemented for regular Linux.
// Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "mem.h"
#include "interp.h"

#ifdef ARDUINO_RASPBERRY_PI
	#include <wiringPi.h>
	#include <wiringPiI2C.h>
	#include <wiringPiSPI.h>
#endif

// I2C and SPI Prims

#ifdef ARDUINO_RASPBERRY_PI

OBJ primI2cGet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);

	int fd = wiringPiI2CSetup(deviceID);
	int result = wiringPiI2CReadReg8(fd, registerID);
	close(fd);
	return int2obj(result);
}

OBJ primI2cSet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	int value = obj2int(args[2]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);
	if ((value < 0) || (value > 255)) return fail(i2cValueOutOfRange);

	int fd = wiringPiI2CSetup(deviceID);
	wiringPiI2CWriteReg8(fd, registerID, value);
	close(fd);
	return falseObj;
}

#define SPI_CHANNEL 0 // use GPIO 8 (CE0) for chip enable
#define DEFAULT_SPI_CLOCK_SPEED 1000000 // 1 MHz default

static int spiDevice = -1;

OBJ primSPISend(OBJ *args) {
	if (!isInt(args[0])) return fail(needsIntegerError);
	unsigned char data = obj2int(args[0]);
	if (data > 255) return fail(i2cValueOutOfRange);

	if (spiDevice < 0) {
		spiDevice = wiringPiSPISetup(SPI_CHANNEL, DEFAULT_SPI_CLOCK_SPEED);
		if (spiDevice < 0) return zeroObj; // initialization failed
	}
	wiringPiSPIDataRW(SPI_CHANNEL, &data, 1); // send data byte
	return falseObj;
}

OBJ primSPIRecv(OBJ *args) {
	if (spiDevice < 0) {
		spiDevice = wiringPiSPISetup(SPI_CHANNEL, DEFAULT_SPI_CLOCK_SPEED);
		if (spiDevice < 0) return zeroObj; // initialization failed
	}
	unsigned char data = 0;
	wiringPiSPIDataRW(SPI_CHANNEL, &data, 1); // send zero, get result byte
	return int2obj(data);
}

OBJ primSPIExchange(int argCount, OBJ *args) {
	if ((argCount < 1) || (objType(args[0]) != ByteArrayType)) return falseObj;

	if (spiDevice < 0) {
		spiDevice = wiringPiSPISetup(SPI_CHANNEL, DEFAULT_SPI_CLOCK_SPEED);
		if (spiDevice < 0) return zeroObj; // initialization failed
	}
	unsigned char *data = (unsigned char *) &FIELD(args[0], 0);
	int byteCount = BYTES(args[0]);
	wiringPiSPIDataRW(SPI_CHANNEL, data, byteCount);
	return trueObj;
}

OBJ primSPISetup(int argCount, OBJ *args) {
	// Set SPI speed, mode, and channel (i.e. chip enable pin).
	// Both channels use the same SPI pins (GPIO 9-11) but channel 0 uses CE0 (GPIO8)
	// as the chip enable line while channel 1 uses CE1 (GPIO7).

	if ((argCount < 1) || !isInt(args[0])) { return trueObj; }
	int speed = obj2int(args[0]);
	int mode = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 0;
	if ((mode < 0) || (mode > 3)) mode = 0; // use mode 0 if out of range
	int spiChannel = ((argCount > 2) && isInt(args[2])) ? obj2int(args[2]) : 0;
	if ((spiChannel < 0) || (spiChannel > 1)) spiChannel = 0; // use channel 0 if out of range

	if (spiDevice < 0) close(spiDevice);
	spiDevice = wiringPiSPISetupMode(spiChannel, speed, mode);
	return (spiDevice >= 0) ? trueObj : falseObj;
}

#else // not Raspberry PI; use stubs

OBJ primI2cGet(OBJ *args) { return int2obj(0); }
OBJ primI2cSet(OBJ *args) { return int2obj(0); }
OBJ primSPISend(OBJ *args) { return int2obj(0); }
OBJ primSPIRecv(OBJ *args) { return int2obj(0); }
OBJ primSPIExchange(int argCount, OBJ *args) { return falseObj; }
OBJ primSPISetup(int argCount, OBJ *args) { return falseObj; }

#endif

// Touch Read (use key scancodes)

extern int KEY_SCANCODE[];

static OBJ primTouchRead(int argCount, OBJ *args) {
	// instead of pins, we use key scancodes
	int code = obj2int(args[0]);
	return int2obj(KEY_SCANCODE[code] ? 0 : 255);
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
	addPrimitiveSet("sensors", sizeof(entries) / sizeof(PrimEntry), entries);
}
