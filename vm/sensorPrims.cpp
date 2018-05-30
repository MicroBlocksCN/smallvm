/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.cpp - Microblocks I2C, SPI, accelerometer, and temperature sensor primitives
// John Maloney, May 2018

#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <stdio.h>

#include "mem.h"
#include "interp.h"

static int wireStarted = false;

static void startWire() {
	Wire.begin();
	wireStarted = true;
}

OBJ primI2cGet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);

	if (!wireStarted) startWire();
	Wire.beginTransmission(deviceID);
	Wire.write(registerID);
	int error = Wire.endTransmission(false);
	if (error) return int2obj(0 - error); // error; bad device ID?

	Wire.requestFrom(deviceID, 1);
	while (!Wire.available());
	return int2obj(Wire.read());
}

OBJ primI2cSet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	int value = obj2int(args[2]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);
	if ((value < 0) || (value > 255)) return fail(i2cValueOutOfRange);

	if (!wireStarted) startWire();
	Wire.beginTransmission(deviceID);
	Wire.write(registerID);
	Wire.write(value);
	Wire.endTransmission();
	return falseObj;
}

static void initSPI() {
	setPinMode(13, OUTPUT);
	setPinMode(14, OUTPUT);
	setPinMode(15, INPUT);
	SPI.begin();
	SPI.setClockDivider(SPI_CLOCK_DIV16);
}

OBJ primSPISend(OBJ *args) {
	if (!isInt(args[0])) return fail(needsIntegerError);
	unsigned data = obj2int(args[0]);
	if (data > 255) return fail(i2cValueOutOfRange);
	initSPI();
	SPI.transfer(data); // send data byte to the slave
	return falseObj;
}

OBJ primSPIRecv(OBJ *args) {
	initSPI();
	int result = SPI.transfer(0); // send a zero byte while receiving a data byte from slave
	return int2obj(result);
}

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE)

	#if defined(ARDUINO_BBC_MICROBIT)
		#define ACCEL_ID 29
		#define MAG_ID 14
	#endif

static int accelerometerOn = false;
static int magnetometerOn = false;

static int microbitAccel(int registerID) {
	if (!accelerometerOn) {
		// turn on the accelerometer
		if (!wireStarted) startWire();
		Wire.beginTransmission(ACCEL_ID);
		Wire.write(0x2A);
		Wire.write(1);
		Wire.endTransmission();
		accelerometerOn = true;
	}

	Wire.beginTransmission(ACCEL_ID);
	Wire.write(registerID);
	int error = Wire.endTransmission(false);
	if (error) return 0; // error; return 0

	Wire.requestFrom(ACCEL_ID, 1);
	while (!Wire.available());
	int val = Wire.read();
	return (val < 128) ? val : -(256 - val); // value is a signed byte
}

static int microbitTemp(int registerID) {
	// Get the temp from magnetometer chip (faster response than CPU temp sensor)

	if (!magnetometerOn) {
		// configure and turn on magnetometer
		if (!wireStarted) startWire();
		Wire.beginTransmission(MAG_ID);
		Wire.write(0x10);
		Wire.write(0x29); // 20 Hz with 16x oversample (see spec sheet)
		Wire.endTransmission();
		magnetometerOn = true;
	}

	// read a byte from register 1 to force an update
	Wire.beginTransmission(MAG_ID);
	Wire.write(1); // register 1
	int error = Wire.endTransmission(false);
	if (error) return 0;
	Wire.requestFrom(MAG_ID, 1);
	while (!Wire.available());
	Wire.read();

	// read temp from register 15
	Wire.beginTransmission(MAG_ID);
	Wire.write(15); // register 15
	error = Wire.endTransmission(false);
	if (error) return 0;
	Wire.requestFrom(MAG_ID, 1);
	while (!Wire.available());
	int degrees = Wire.read();
	degrees = (degrees < 128) ? degrees : -(256 - degrees); // temp is a signed byte

	int adjustment = 5; // based on John's micro:bit, Jan 2018
	return degrees + adjustment;
}

static int microbitMag(int registerID) {

	if (!magnetometerOn) {
		// configure and turn on magnetometer
		if (!wireStarted) startWire();
		Wire.beginTransmission(MAG_ID);
		Wire.write(0x10);
		Wire.write(0x29); // 20 Hz with 16x oversample (see spec sheet)
		Wire.endTransmission();
		magnetometerOn = true;
	}

	Wire.beginTransmission(MAG_ID);
	Wire.write(1); // read from register 1
	int error = Wire.endTransmission(false);
	if (error) {
		Serial.print("Error: "); Serial.println(error);
	}

	// always read x, y, and z at 16-bit resolution
	// even when reading temp, this is needed to force an update
	Wire.requestFrom(MAG_ID, 6);
	while (Wire.available() < 6);
	int x = Wire.read() << 8;
	x |= Wire.read();
	if (x > 32767) x += -65536;
	int y = Wire.read() << 8;
	y |= Wire.read();
	if (y > 32767) y += -65536;
	int z = Wire.read() << 8;
	z |= Wire.read();
	if (z > 32767) z += -65536;

	if (1 == registerID) return x;
	if (3 == registerID) return y;
	if (5 == registerID) return z;
	if (15 == registerID) { // read temperature
		Wire.beginTransmission(MAG_ID);
		Wire.write(15);
		int error = Wire.endTransmission(false);
		if (error) return 0; // error; return 0

		Wire.requestFrom(MAG_ID, 1);
		while (!Wire.available());
		int val = Wire.read();
		return (val < 128) ? val : -(256 - val); // temp is a signed byte
	}
	return 0;
}

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)

#define ACCEL_ID 33

int accelStarted = false;

static int circuitPlayAccel(int registerID) {
	// xxx not yet finished
	if (!accelStarted) {
		Wire1.begin(); // use internal I2C bus
		// turn on the accelerometer
		if (!wireStarted) startWire();
		Wire1.beginTransmission(ACCEL_ID);
		Wire1.write(0x2A);
		Wire1.write(1);
		Wire1.endTransmission();
		accelStarted = true;
	}

	Wire1.beginTransmission(ACCEL_ID);
	Wire1.write(registerID);
	int error = Wire1.endTransmission(false);
	if (error) return 0; // error; return 0

	Wire1.requestFrom(ACCEL_ID, 1);
	while (!Wire1.available());
	int val = Wire1.read();
	return (val < 128) ? val : -(256 - val); // value is a signed byte
}

static int microbitAccel(int reg) { return 0; }
static int microbitTemp(int registerID) { return 0; }

#else // stubs for non-micro:bit boards

static int microbitAccel(int reg) { return 0; }
static int microbitTemp(int registerID) { return 0; }

#endif // micro:bit primitve support

OBJ primMBTiltX(OBJ *args) { return int2obj(microbitAccel(1)); }
OBJ primMBTiltY(OBJ *args) { return int2obj(microbitAccel(3)); }
OBJ primMBTiltZ(OBJ *args) { return int2obj(-microbitAccel(5)); } // invert sign of Z
OBJ primMBTemp(OBJ *args) { return int2obj(microbitTemp(15)); }
