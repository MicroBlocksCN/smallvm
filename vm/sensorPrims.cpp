/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.cpp - Microblocks I2C, SPI, tilt, and temperature primitives
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
	// xxx Should this releasing the i2c bus (on ESP32) when we're about to request data?
	// Need to revisit how i2c works...
#ifdef ARDUINO_ARCH_ESP32
	int error = Wire.endTransmission();
#else
	int error = Wire.endTransmission(false);
#endif
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

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_SINOBIT)

#define ACCEL_ID 29

static int accelerometerOn = false;

static int readAcceleration(int registerID) {
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

	val = (val < 128) ? val : -(256 - val); // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = -((val * 100) / 127); // invert sign and scale to range 0-100
	return val;
}

static int readTemperature() {
	volatile int *startReg = (int *) 0x4000C000;
	volatile int *readyReg = (int *) 0x4000C100;
	volatile int *tempReg = (int *) 0x4000C508;

	*startReg = 1;
	while (!(*readyReg)) { /* busy wait */ }
	return (*tempReg / 4) - 6; // callibrated at 26 degrees C using average of 3 micro:bits
}

#elif defined(ARDUINO_CALLIOPE)

static int readAcceleration(int registerID) {
	// adjust register offsets for Calliope
	int reg = registerID;
	if (1 == registerID) reg = 5; // x-axis
	else if (3 == registerID) reg = 3; // y-axis
	else if (5 == registerID) reg = 7; // z axis

	if (!wireStarted) startWire();

	Wire.beginTransmission(ACCEL_ID);
	Wire.write(reg);
	int error = Wire.endTransmission(false);
	if (error) return 0; // error; return 0

	Wire.requestFrom(ACCEL_ID, 1);
	while (!Wire.available());
	int val = Wire.read();

	val = (val < 128) ? val : -(256 - val); // value is a signed byte
	if (8 == registerID) return val; // temperature sensor

	if (val < -127) val = -127; // keep in range -127 to 127
	val = -((val * 100) / 127); // invert sign and scale to range 0-100
	if (5 == registerID) val = -val; // invert z-axis
	return val;
}

static int readTemperature() {
	int fudgeFactor = 2;
	return (readAcceleration(8) / 2) + 23 - fudgeFactor;
}

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)

#define ACCEL_ID 25

int accelStarted = false;

static int readAcceleration(int registerID) {
	if (!accelStarted) {
		Wire1.begin(); // use internal I2C bus
		// turn on the accelerometer
		if (!wireStarted) startWire();
		Wire1.beginTransmission(ACCEL_ID);
		Wire1.write(32);
		Wire1.write(127);
		Wire1.endTransmission();
		accelStarted = true;
	}
	Wire1.beginTransmission(ACCEL_ID);
	Wire1.write(40 + registerID);
	int error = Wire1.endTransmission(false);
	if (error) return 0; // error; return 0

	Wire1.requestFrom(ACCEL_ID, 1);
	while (!Wire1.available());
	int val = Wire1.read();

	val = (val < 128) ? val : -(256 - val); // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = ((val * 100) / 127); // scale to range 0-100
	if (1 == registerID) val = -val; // invert sign for x axis
	return val;
}

static int readTemperature() {
	// Return the temperature in Celcius

	setPinMode(A9, INPUT);
	int adc = analogRead(A9);

	return ((int) (0.116 * adc)) - 37; // linear approximation

	// The following unused code does not seem as accurate as the linear approximation
	// above (based on comparing the thermistor to a household digital thermometer).
	// See https://learn.adafruit.com/thermistor/using-a-thermistor
	// The following constants come from the NCP15XH103F03RC thermister data sheet:
	#define SERIES_RESISTOR 10000
	#define RESISTANCE_AT_25C 10000
	#define B_CONSTANT 3380

	if (adc < 1) adc = 1; // avoid divide by zero (although adc should never be zero)
	float r = ((1023 * SERIES_RESISTOR) / adc) - SERIES_RESISTOR;

	float steinhart = log(r / RESISTANCE_AT_25C) / B_CONSTANT;
	steinhart += 1.0 / (25 + 273.15); // add 1/T0 (T0 is 25C in Kelvin)
	float result = (1.0 / steinhart) - 273.15; // steinhart is 1/T; invert and convert to C

	return (int) round(result);
}

#else // stubs for non-micro:bit boards

static int readAcceleration(int reg) { return 0; }
static int readTemperature() { return 0; }

#endif // micro:bit primitve support

OBJ primMBTiltX(OBJ *args) { return int2obj(readAcceleration(1)); }
OBJ primMBTiltY(OBJ *args) { return int2obj(readAcceleration(3)); }
OBJ primMBTiltZ(OBJ *args) { return int2obj(readAcceleration(5)); }
OBJ primMBTemp(OBJ *args) { return int2obj(readTemperature()); }
