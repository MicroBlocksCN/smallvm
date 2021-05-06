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
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

// i2c helper functions

static int wireStarted = false;

static void startWire() {
	Wire.begin();
	Wire.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)
	wireStarted = true;
}

static int readI2CReg(int deviceID, int reg) {
	if (!wireStarted) startWire();
	Wire.beginTransmission(deviceID);
	Wire.write(reg);
	#if defined(ARDUINO_ARCH_ESP32)
		int error = Wire.endTransmission();
	#else
		int error = Wire.endTransmission((bool) false);
	#endif
	if (error) return -error; // error; bad device ID?

	#if defined(NRF51)
		noInterrupts();
		Wire.requestFrom(deviceID, 1);
		interrupts();
	#else
		Wire.requestFrom(deviceID, 1);
	#endif

	return Wire.available() ? Wire.read() : 0;
}

static void writeI2CReg(int deviceID, int reg, int value) {
	if (!wireStarted) startWire();
	Wire.beginTransmission(deviceID);
	Wire.write(reg);
	Wire.write(value);
	Wire.endTransmission();
}

// i2c prims

OBJ primI2cGet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);

	return int2obj(readI2CReg(deviceID, registerID));
}

OBJ primI2cSet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	int value = obj2int(args[2]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);
	if ((value < 0) || (value > 255)) return fail(i2cValueOutOfRange);

	writeI2CReg(deviceID, registerID, value);
	return falseObj;
}

static OBJ primI2cRead(int argCount, OBJ *args) {
	// Read multiple bytes from the given I2C device into the given list and return the
	// number of bytes read. The list size determines the number of bytes to read (up to a
	// max of 32). This operation is usually preceded by an I2C write to request some data.

	if ((argCount < 2) || !isInt(args[0])) return int2obj(0);
	int deviceID = obj2int(args[0]);
	OBJ obj = args[1];
	if (!IS_TYPE(obj, ListType)) return int2obj(0);

	int count = obj2int(FIELD(obj, 0));
	if (count > 32) count = 32; // the Arduino Wire library limits reads to a max of 32 bytes

	if (!wireStarted) startWire();
	#if defined(NRF51)
		noInterrupts();
		Wire.requestFrom(deviceID, count);
		interrupts();
	#else
		Wire.requestFrom(deviceID, count);
	#endif

	for (int i = 0; i < count; i++) {
		if (!Wire.available()) return int2obj(i); /* no more data */;
		int byte = Wire.read();
		FIELD(obj, i + 1) = int2obj(byte);
	}
	return int2obj(count);
}

static OBJ primI2cWrite(int argCount, OBJ *args) {
	// Write one or multiple bytes to the given I2C device. If the second argument is an
	// integer, write it as a single byte. If it is a list of bytes, write those bytes.
	// The list should contain integers in the range 0..255; anything else will be skipped.

	if ((argCount < 2) || !isInt(args[0])) return int2obj(0);
	int deviceID = obj2int(args[0]);
	OBJ data = args[1];

	if (!wireStarted) startWire();
	Wire.beginTransmission(deviceID);
	if (isInt(data)) {
		Wire.write(obj2int(data) & 255);
	} else if (IS_TYPE(data, ListType)) {
		int count = obj2int(FIELD(data, 0));
		for (int i = 0; i < count; i++) {
			OBJ item = FIELD(data, i + 1);
			if (isInt(item)) {
				Wire.write(obj2int(item) & 255);
			}
		}
	}
	int error = Wire.endTransmission();
	if (error) fail(i2cTransferFailed);
	return falseObj;
}

// SPI prims

static void initSPI() {
	setPinMode(13, OUTPUT);
	setPinMode(14, OUTPUT);
	setPinMode(15, INPUT);
	SPI.begin();
	#ifndef ARDUINO_RASPBERRY_PI_PICO
		SPI.setClockDivider(SPI_CLOCK_DIV16);
	#endif
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

// Accelerometer and Temperature

int accelStarted = false;

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_SINOBIT)

typedef enum {
	accel_unknown = -1,
	accel_none = 0,
	accel_MMA8653 = 1,
	accel_LSM303 = 2,
	accel_FXOS8700 = 3,
} AccelerometerType_t;

static AccelerometerType_t accelType = accel_unknown;

#define MMA8653_ID 29
#define LSM303_ID 25
#define FXOS8700_ID 30

static void startAccelerometer() {
	if (0x5A == readI2CReg(MMA8653_ID, 0x0D)) {
		accelType = accel_MMA8653;
		writeI2CReg(MMA8653_ID, 0x2A, 1);
	} else if (0x33 == readI2CReg(LSM303_ID, 0x0F)) {
		accelType = accel_LSM303;
		writeI2CReg(LSM303_ID, 0x20, 0x8F); // 1620 Hz sample rate, low power, all axes
	} else if (0xC7 == readI2CReg(FXOS8700_ID, 0x0D)) {
		accelType = accel_FXOS8700;
		writeI2CReg(FXOS8700_ID, 0x2A, 0); // turn off chip before configuring
		writeI2CReg(FXOS8700_ID, 0x2A, 0x1B); // 100 Hz sample rate, fast read, turn on
	} else {
		accelType = accel_none;
	}
	accelStarted = true;
}

static int readAcceleration(int registerID) {
	if (!accelStarted) startAccelerometer();
	int sign = -1;
	int val = 0;
	switch (accelType) {
	case accel_MMA8653:
		val = readI2CReg(MMA8653_ID, registerID);
		break;
	case accel_LSM303:
		if (1 == registerID) { val = readI2CReg(LSM303_ID, 0x29); sign = 1; } // x-axis
		if (3 == registerID) val = readI2CReg(LSM303_ID, 0x2B); // y-axis
		if (5 == registerID) val = readI2CReg(LSM303_ID, 0x2D); // z-axis
		break;
	case accel_FXOS8700:
		val = readI2CReg(FXOS8700_ID, registerID);
		break;
	default:
		val = 0;
		break;
	}
	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = sign * ((val * 200) / 127); // scale to range 0-200 and multiply by sign
	return val;
}

static int setAccelRange(int range) {
	// xxx work in progress...
	writeI2CReg(LSM303_ID, 0x23, 0x30); // +/- 16G
}

static int readTemperature() {
	volatile int *startReg = (int *) 0x4000C000;
	volatile int *readyReg = (int *) 0x4000C100;
	volatile int *tempReg = (int *) 0x4000C508;

	*startReg = 1;
	while (!(*readyReg)) { /* busy wait */ }
	return (*tempReg / 4) - 6; // callibrated at 26 degrees C using average of 3 micro:bits
}

#elif defined(ARDUINO_BBC_MICROBIT_V2)

static int internalWireStarted = false;

static void startInternalWire() {
	Wire1.begin();
	Wire1.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)
	internalWireStarted = true;
}

static int readInternalI2CReg(int deviceID, int reg) {
	if (!internalWireStarted) startInternalWire();
	Wire1.beginTransmission(deviceID);
	Wire1.write(reg);
	#if defined(ARDUINO_ARCH_ESP32)
		int error = Wire1.endTransmission();
	#else
		int error = Wire1.endTransmission();
	#endif
	if (error) return -error; // error; bad device ID?

	#if defined(NRF51)
		noInterrupts();
		Wire1.requestFrom(deviceID, 1);
		interrupts();
	#else
		Wire1.requestFrom(deviceID, 1);
	#endif

	return Wire1.available() ? Wire1.read() : 0;
}

static void writeInternalI2CReg(int deviceID, int reg, int value) {
	if (!internalWireStarted) startInternalWire();
	Wire1.beginTransmission(deviceID);
	Wire1.write(reg);
	Wire1.write(value);
	Wire1.endTransmission();
}

typedef enum {
	accel_unknown = -1,
	accel_none = 0,
	accel_MMA8653 = 1,
	accel_LSM303 = 2,
	accel_FXOS8700 = 3,
} AccelerometerType_t;

static AccelerometerType_t accelType = accel_unknown;

#define MMA8653_ID 29
#define LSM303_ID 25
#define FXOS8700_ID 30

static void startAccelerometer() {
	if (0x5A == readInternalI2CReg(MMA8653_ID, 0x0D)) {
		accelType = accel_MMA8653;
		writeInternalI2CReg(MMA8653_ID, 0x2A, 1);
	} else if (0x33 == readInternalI2CReg(LSM303_ID, 0x0F)) {
		accelType = accel_LSM303;
		writeInternalI2CReg(LSM303_ID, 0x20, 0x8F); // 1620 Hz sample rate, low power, all axes
	} else if (0xC7 == readInternalI2CReg(FXOS8700_ID, 0x0D)) {
		accelType = accel_FXOS8700;
		writeInternalI2CReg(FXOS8700_ID, 0x2A, 0); // turn off chip before configuring
		writeInternalI2CReg(FXOS8700_ID, 0x2A, 0x1B); // 100 Hz sample rate, fast read, turn on
	} else {
		accelType = accel_none;
	}
	accelStarted = true;
}

static int readAcceleration(int registerID) {
	if (!accelStarted) startAccelerometer();
	int sign = -1;
	int val = 0;
	switch (accelType) {
	case accel_MMA8653:
		val = readInternalI2CReg(MMA8653_ID, registerID);
		break;
	case accel_LSM303:
		if (1 == registerID) { val = readInternalI2CReg(LSM303_ID, 0x29); sign = 1; } // x-axis
		if (3 == registerID) val = readInternalI2CReg(LSM303_ID, 0x2B); // y-axis
		if (5 == registerID) val = readInternalI2CReg(LSM303_ID, 0x2D); // z-axis
		break;
	case accel_FXOS8700:
		val = readInternalI2CReg(FXOS8700_ID, registerID);
		break;
	default:
		val = 0;
		break;
	}
	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = sign * ((val * 200) / 127); // scale to range 0-200 and multiply by sign
	return val;
}

static int setAccelRange(int range) {
	// xxx work in progress...
	writeInternalI2CReg(LSM303_ID, 0x23, 0x30); // +/- 16G
}

static int readTemperature() {
	volatile int *startReg = (int *) 0x4000C000;
	volatile int *readyReg = (int *) 0x4000C100;
	volatile int *tempReg = (int *) 0x4000C508;

	*startReg = 1;
	while (!(*readyReg)) { /* busy wait */ }
	return (*tempReg / 4) - 6; // callibrated at 26 degrees C using average of 3 micro:bits
}

#elif defined(ARDUINO_CALLIOPE_MINI)

#define BMX055 24

static int readAcceleration(int registerID) {
	int val = 0;
	if (1 == registerID) val = readI2CReg(BMX055, 5); // x-axis
	if (3 == registerID) val = readI2CReg(BMX055, 3); // y-axis
	if (5 == registerID) val = readI2CReg(BMX055, 7); // z-axis

	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = -((val * 200) / 127); // invert sign and scale to range 0-200
	if (5 == registerID) val = -val; // invert z-axis
	return val;
}

static int readTemperature() {
	int fudgeFactor = 2;
	return (readI2CReg(BMX055, 8) / 2) + 23 - fudgeFactor;
}

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)

#define LIS3DH_ID 25

static int readAcceleration(int registerID) {
	if (!accelStarted) {
		Wire1.begin(); // use internal I2C bus
		Wire1.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)

		// turn on the accelerometer
		Wire1.beginTransmission(LIS3DH_ID);
		Wire1.write(0x20);
		Wire1.write(0x7F);
		Wire1.endTransmission();
		accelStarted = true;
	}
	Wire1.beginTransmission(LIS3DH_ID);
	Wire1.write(0x28 + registerID);
	int error = Wire1.endTransmission(false);
	if (error) return 0; // error; return 0

	Wire1.requestFrom(LIS3DH_ID, 1);
	while (!Wire1.available());
	int val = Wire1.read();

	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = ((val * 200) / 127); // scale to range 0-200
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

#elif defined(ARDUINO_NRF52840_CLUE)

#define LSM6DS 106

static void startAccelerometer() {
	writeI2CReg(LSM6DS, 0x10, 0x40); // enable accelerometer,  104 Hz sample rate
	accelStarted = true;
}

static int readAcceleration(int registerID) {
	if (!accelStarted) startAccelerometer();
	int val = 0;
	if (1 == registerID) val = readI2CReg(LSM6DS, 0x29); // x-axis
	if (3 == registerID) val = readI2CReg(LSM6DS, 0x2B); // y-axis
	if (5 == registerID) val = readI2CReg(LSM6DS, 0x2D); // z-axis

	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = ((val * 200) / 127); // invert sign and scale to range 0-200
	if (5 == registerID) val = -val; // invert z-axis
	return val;
}

static int readTemperature() {
	if (!accelStarted) startAccelerometer();
	int temp = (readI2CReg(LSM6DS, 0x21) << 8) | readI2CReg(LSM6DS, 0x20);
	if (temp >= 32768) temp = temp - 65536; // negative
	return 25 + (temp / 16);
}

#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5Stick_C) || defined(ARDUINO_M5Atom_Matrix_ESP32)

#ifdef ARDUINO_M5Stack_Core_ESP32
	#define Wire1 Wire
#endif

#define MPU6886_ID			0x68
#define MPU6886_SMPLRT_DIV	0x19
#define MPU6886_CONFIG		0x1A
#define MPU6886_PWR_MGMT_1	0x6B
#define MPU6886_PWR_MGMT_2	0x6C
#define MPU6886_WHO_AM_I	0x75

static int readAccelReg(int regID) {
	Wire1.beginTransmission(MPU6886_ID);
	Wire1.write(regID);
	int error = Wire1.endTransmission();
	if (error) return 0;

	Wire1.requestFrom(MPU6886_ID, 1);
	while (!Wire1.available());
	return (Wire1.read());
}

static void writeAccelReg(int regID, int value) {
	Wire1.beginTransmission(MPU6886_ID);
	Wire1.write(regID);
	Wire1.write(value);
	Wire1.endTransmission();
}

static char is6886 = false;

static void startAccelerometer() {
	#ifdef ARDUINO_M5Atom_Matrix_ESP32
		Wire1.begin(25, 21);
		Wire1.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)
	#else
		Wire1.begin(); // use internal I2C bus with default pins
		Wire1.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)
	#endif

	writeAccelReg(MPU6886_PWR_MGMT_1, 0x80); // reset (must be done by itself)
	delay(1); // required to avoid hang

	writeAccelReg(MPU6886_SMPLRT_DIV, 4); // 200 samples/sec
	writeAccelReg(MPU6886_CONFIG, 5); // low-pass filtering: 0-6
	writeAccelReg(MPU6886_PWR_MGMT_1, 1); // use best clock rate (required!)
	writeAccelReg(MPU6886_PWR_MGMT_2, 7); // disable the gyroscope

	is6886 = (25 == readAccelReg(MPU6886_WHO_AM_I));
	accelStarted = true;
}

static int readAcceleration(int registerID) {
	if (!accelStarted) startAccelerometer();

	int sign = 1;
	int val = 0;
	#if defined(ARDUINO_M5Stick_C)
		if (1 == registerID) val = readAccelReg(61);
		if (3 == registerID) val = readAccelReg(59);
	#elif defined(ARDUINO_M5Atom_Matrix_ESP32)
		if (1 == registerID) val = readAccelReg(59);
		if (3 == registerID) val = readAccelReg(61);
		if (5 == registerID) sign = -1;
	#else
		if (1 == registerID) { sign = -1; val = readAccelReg(59); }
		if (3 == registerID) val = readAccelReg(61);
	#endif
	if (5 == registerID) val = readAccelReg(63);

	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = ((val * 200) / 127); // scale to range 0-200
	return sign * val;
}

static int readTemperature() {
	// Return the temperature in Celcius

	if (!accelStarted) startAccelerometer();

	int temp = 0;
	short int rawTemp = (readAccelReg(65) << 8) | readAccelReg(66);
	if (is6886) {
		temp = (int) ((float) rawTemp / 326.8) + 8;
	} else {
		if ((0 == rawTemp) && (0 == readAccelReg(MPU6886_WHO_AM_I))) return 0; // no accelerometer
		temp = (rawTemp / 40) + 9; // approximate constants for mpu9250, empirically determined
	}
	return temp;
}

#elif defined(ARDUINO_CITILAB_ED1)

#define LIS3DH_ID 25

static int readAcceleration(int registerID) {
	if (!accelStarted) {
		writeI2CReg(LIS3DH_ID, 0x20, 0x7F); // turn on accelerometer, 400 Hz update, 8-bit
		writeI2CReg(LIS3DH_ID, 0x1F, 0xC0); // enable temperature reporting
		accelStarted = true;
	}
	int val = readI2CReg(LIS3DH_ID, 0x28 + registerID);
	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = ((val * 200) / 127); // scale to range 0-200
	val = -val; // invert sign for all axes
	return val;
}

static int readTemperature() {
	if (!accelStarted) readAcceleration(1); // initialize accelerometer if necessary

	writeI2CReg(LIS3DH_ID, 0x23, 0x80); // enable block data update (needed for temperature)
	int hiByte = readI2CReg(LIS3DH_ID, 0x0D);
	int lowByte = readI2CReg(LIS3DH_ID, 0x0C);
	writeI2CReg(LIS3DH_ID, 0x23, 0); // disable block data update
	int offsetDegreesC;

	if (hiByte <= 127) { // positive offset
		offsetDegreesC = hiByte + ((lowByte >= 128) ? 1 : 0); // round up
	} else { // negative offset
		offsetDegreesC = (hiByte - 256) + ((lowByte >= 128) ? -1 : 0); // round down
	}
	return 20 + offsetDegreesC;
}

#else // stubs for non-micro:bit boards

static int readAcceleration(int reg) { return 0; }
static int readTemperature() { return 0; }

#endif // micro:bit primitve support

static void i2cReadBytes(int deviceID, int reg, int *buf, int bufSize) {
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || \
		defined(ARDUINO_NRF52840_CIRCUITPLAY) || \
		defined(ARDUINO_M5Stack_Core_ESP32) || \
		defined(ARDUINO_M5Stick_C) || \
		defined(ARDUINO_M5Atom_Matrix_ESP32)

		// Use Wire1, the internal i2c bus
		Wire1.beginTransmission(deviceID);
		Wire1.write(reg);
		int error = Wire1.endTransmission();
		if (error) return;
		Wire1.requestFrom(deviceID, bufSize);
		for (int i = 0; i < bufSize; i++) {
			buf[i] = Wire1.available() ? Wire1.read() : 0;
		}
	#else
		// Use Wire, the primary/external i2c bus
		Wire.beginTransmission(deviceID);
		Wire.write(reg);
		int error = Wire.endTransmission((bool) false);
		if (error) return;

		#if defined(NRF51)
			noInterrupts();
			Wire.requestFrom(deviceID, bufSize);
			interrupts();
		#else
			Wire.requestFrom(deviceID, bufSize);
		#endif

		for (int i = 0; i < bufSize; i++) {
			buf[i] = Wire.available() ? Wire.read() : 0;
		}
	#endif
}

OBJ primAcceleration(int argCount, OBJ *args) {
	// Return the magnitude of the acceleration vector, regardless of device orientation.

	int deviceID = -1, reg;

	if (!accelStarted) readAcceleration(1); // initialize the accelerometer

	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_SINOBIT)
		if (accel_unknown == accelType) startAccelerometer();
		switch (accelType) {
		case accel_MMA8653:
			deviceID = MMA8653_ID;
			reg = 1;
			break;
		case accel_LSM303:
			deviceID = LSM303_ID;
			reg = 0x29 | 0x80; // address + auto-increment flag
			break;
		case accel_FXOS8700:
			deviceID = FXOS8700_ID;
			reg = 1;
			break;
		default:
			break;
		}
		deviceID = -1; // xxx disable this optimization on micro:bit for now
	#elif defined(ARDUINO_CALLIOPE_MINI)
		deviceID = BMX055;
		reg = 3;
	#elif defined(ARDUINO_CITILAB_ED1)
		deviceID = LIS3DH_ID;
		reg = 0x29 | 0x80; // address + auto-increment flag
	#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		deviceID = LIS3DH_ID;
		reg = 0x29 | 0x80; // address + auto-increment flag
	#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5Stick_C) || defined(ARDUINO_M5Atom_Matrix_ESP32)
		deviceID = MPU6886_ID;
		reg = 0x3B;
	#endif

	int x, y, z;
	if (deviceID < 0) { // read x, y, and z as independent calls
		x = readAcceleration(1);
		y = readAcceleration(3);
		z = readAcceleration(5);
	} else { // use bulk read using the primary i2c bus (Wire)
		const int bufSize = 5;
		int buf[bufSize] = {0, 0, 0, 0, 0};
		i2cReadBytes(deviceID, reg, buf, bufSize);
		// convert to signed values in range -128 to 127
		x = buf[0] > 127 ? buf[0] - 256 : buf[0];
		y = buf[2] > 127 ? buf[2] - 256 : buf[2];
		z = buf[4] > 127 ? buf[4] - 256 : buf[4];
		x = ((x * 200) >> 7);
		y = ((y * 200) >> 7);
		z = ((z * 200) >> 7);
	}
	int accel = (int) sqrt((x * x) + (y * y) + (z * z));
	return int2obj(accel);
}

OBJ primSetAccelerometerRange(int argCount, OBJ *args) {
	// xxx this is a work in progress; not yet used in libraries

	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	int range = obj2int(args[0]);

	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_BBC_MICROBIT_V2)
		setAccelRange(range);
	#endif

	return falseObj;
}

OBJ primMBTemp(int argCount, OBJ *args) { return int2obj(readTemperature()); }
OBJ primMBTiltX(int argCount, OBJ *args) { return int2obj(readAcceleration(1)); }
OBJ primMBTiltY(int argCount, OBJ *args) { return int2obj(readAcceleration(3)); }
OBJ primMBTiltZ(int argCount, OBJ *args) { return int2obj(readAcceleration(5)); }

// Capacitive Touch Primitives for ESP32

#ifdef ARDUINO_ARCH_ESP32

#ifdef ARDUINO_CITILAB_ED1

extern int buttonReadings[6];

static OBJ primTouchRead(int argCount, OBJ *args) {
	//return int2obj(touchRead(obj2int(args[0])));
	int pin = obj2int(args[0]);
	switch (pin) {
		case 2: return int2obj(buttonReadings[0]);
		case 4: return int2obj(buttonReadings[1]);
		case 13: return int2obj(buttonReadings[2]);
		case 14: return int2obj(buttonReadings[3]);
		case 15: return int2obj(buttonReadings[4]);
		case 27: return int2obj(buttonReadings[5]);
		default: return int2obj(touchRead(pin));
	}
}

#else

static OBJ primTouchRead(int argCount, OBJ *args) {
	return int2obj(touchRead(obj2int(args[0])));
}

#endif

#else // stubs for non-ESP32 boards

static OBJ primTouchRead(int argCount, OBJ *args) { return int2obj(0); }

#endif // Capacitive Touch Primitives

// DHT Humidity/Temperature Sensor

#ifndef ARDUINO_RASPBERRY_PI_PICO

static uint8_t dhtData[5];

static int readDHTData(int pin) {
	// Read DHT data into dhtData. Return true if successful, false if timeout.

	// read the start pulse
	setPinMode(pin, INPUT);
	int pulseWidth = pulseIn(pin, HIGH, 2000);
	if (!pulseWidth) return false; // timeout

	for (int i = 0; i < 5; i++) {
		int byte = 0;
		for (int shift = 7; shift >= 0; shift--) {
			pulseWidth = pulseIn(pin, HIGH, 1000);
			if (!pulseWidth) return false; // timeout
			if (pulseWidth > 40) byte |= (1 << shift);
		}
		dhtData[i] = byte;
	}
	return true;
}

static OBJ primReadDHT(int argCount, OBJ *args) {
	// Read DHT data into dhtData. Assume the the 18 msec LOW start pulse has been sent.
	// Return a five-byte ByteArray if successful, false on failure (e.g. no or partial data).

	if (!isInt(args[0])) return fail(needsIntegerError);
	int pin = obj2int(args[0]);
	if ((pin < 0) || (pin > pinCount())) return falseObj;
	if (!readDHTData(pin)) return falseObj;

	OBJ result = newObj(ListType, 6, zeroObj); // list size + five items, all zeros
	if (falseObj != result) {
		FIELD(result, 0) = int2obj(5); // list size
		for (int i = 0; i < 5; i++) {
			FIELD(result, i + 1) = int2obj(dhtData[i]);
		}
	}
	return result;
}

#else

static OBJ primReadDHT(int argCount, OBJ *args) { return falseObj; }

#endif

// Microphone Support

#if defined(ARDUINO_NRF52840_CIRCUITPLAY) || defined(ARDUINO_NRF52840_CLUE)

#define USE_PDM_MICROPHONE 1

static NRF_PDM_Type *nrf_pdm = NRF_PDM;
static int mic_initialized = false;

static int16_t mic_sample;

static void initPDM() {
	if (mic_initialized) return;
	mic_initialized = true;

	pinMode(PIN_PDM_CLK, OUTPUT);
	digitalWrite(PIN_PDM_CLK, LOW);
	pinMode(PIN_PDM_DIN, INPUT);

	nrf_pdm->PSEL.CLK = digitalPinToPinName(PIN_PDM_CLK);
	nrf_pdm->PSEL.DIN = digitalPinToPinName(PIN_PDM_DIN);

	// Use the fastest possible sampling rate since we block waiting for the next sample
	// Sampling rate = 1.333 MHz / 64 = 20828 samples/sec (~48 usec/sample)
	nrf_pdm->PDMCLKCTRL = 0x0A800000; // (32 MHz / 24) = 1.333 MHz
	nrf_pdm->RATIO = PDM_RATIO_RATIO_Ratio64;

	nrf_pdm->GAINL = PDM_GAINL_GAINL_DefaultGain;
	nrf_pdm->GAINR = PDM_GAINR_GAINR_DefaultGain;
	nrf_pdm->MODE = PDM_MODE_OPERATION_Mono;

	nrf_pdm->SAMPLE.PTR = (uintptr_t) &mic_sample;
	nrf_pdm->SAMPLE.MAXCNT = 1;

	nrf_pdm->ENABLE = 1;
	nrf_pdm->TASKS_START = 1;
}

static int readPDMMicrophone() {
	if (!mic_initialized) initPDM();
	nrf_pdm->EVENTS_END = 0;
	while (!nrf_pdm->EVENTS_END) /* wait for next sample */;
	return ((int) mic_sample) >> 3; // scale result
}

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)

#define USE_PDM_MICROPHONE 1

// Note: Portions of the following code are from the pdm_analogout.cpp example
// adapted from the AdaFruit ZeroPDM library.

#include "Adafruit_ZeroPDM.h"

#define SAMPLERATE_HZ 22000
#define DECIMATION    64

static Adafruit_ZeroPDM pdm = Adafruit_ZeroPDM(34, 35);

// a windowed sinc filter for 44 khz, 64 samples
static uint16_t sincfilter[DECIMATION] = {0, 2, 9, 21, 39, 63, 94, 132, 179, 236, 302, 379, 467, 565, 674, 792, 920, 1055, 1196, 1341, 1487, 1633, 1776, 1913, 2042, 2159, 2263, 2352, 2422, 2474, 2506, 2516, 2506, 2474, 2422, 2352, 2263, 2159, 2042, 1913, 1776, 1633, 1487, 1341, 1196, 1055, 920, 792, 674, 565, 467, 379, 302, 236, 179, 132, 94, 63, 39, 21, 9, 2, 0, 0};

// a manual loop-unroller!
#define ADAPDM_REPEAT_LOOP_16(X) X X X X X X X X X X X X X X X X

static int mic_initialized = false;

static void initSAMDPDM() {
	pdm.begin();
	if (!pdm.configure(SAMPLERATE_HZ * DECIMATION / 16, true)) {
		outputString("Failed to configure SAMD PDM");
	}
	mic_initialized = true;
}

static int readPDMMicrophone() {
	if (!mic_initialized) initSAMDPDM();

	uint16_t runningsum = 0;
	uint16_t *sinc_ptr = sincfilter;
	uint16_t sample;

	for (int i = 0; i < (DECIMATION / 16); i++) {
		sample = pdm.read() & 0xFFFF; // read a sample; use the low 16 bits

		ADAPDM_REPEAT_LOOP_16({ // manually unroll loop: for (int8_t b=0; b<16; b++)
			// start at the LSB which is the 'first' bit to come down the line, chronologically
			// (Note we had to set I2S_SERCTRL_BITREV to get this to work, but saves us time!)
			if (sample & 0x1) {
				runningsum += *sinc_ptr;     // do the convolution
			}
			sinc_ptr++;
			sample >>= 1;
		})
	}

	int result = (((int) runningsum) >> 5) - 1027; // signed sample, scaled to 11-bits
	// limit to signed 10-bit value range
	if (result < -512) result = -512;
	if (result > 511) result = 511;
	return result;
}

#elif defined(ARDUINO_BBC_MICROBIT_V2)

int readAnalogMicrophone() {
	const int micPin = SAADC_CH_PSELP_PSELP_AnalogInput3;
	const int gain = SAADC_CH_CONFIG_GAIN_Gain4;
	volatile int16_t value = 0;

	NRF_SAADC->RESOLUTION = SAADC_RESOLUTION_VAL_10bit;
	NRF_SAADC->ENABLE = 1;

	for (int i = 0; i < 8; i++) {
		NRF_SAADC->CH[i].PSELN = SAADC_CH_PSELP_PSELP_NC;
		NRF_SAADC->CH[i].PSELP = SAADC_CH_PSELP_PSELP_NC;
	}
	NRF_SAADC->CH[0].CONFIG = ((SAADC_CH_CONFIG_RESP_Bypass     << SAADC_CH_CONFIG_RESP_Pos)   & SAADC_CH_CONFIG_RESP_Msk)
							| ((SAADC_CH_CONFIG_RESP_Bypass     << SAADC_CH_CONFIG_RESN_Pos)   & SAADC_CH_CONFIG_RESN_Msk)
							| ((gain                            << SAADC_CH_CONFIG_GAIN_Pos)   & SAADC_CH_CONFIG_GAIN_Msk)
							| ((SAADC_CH_CONFIG_REFSEL_Internal << SAADC_CH_CONFIG_REFSEL_Pos) & SAADC_CH_CONFIG_REFSEL_Msk)
							| ((SAADC_CH_CONFIG_TACQ_3us        << SAADC_CH_CONFIG_TACQ_Pos)   & SAADC_CH_CONFIG_TACQ_Msk)
							| ((SAADC_CH_CONFIG_MODE_SE         << SAADC_CH_CONFIG_MODE_Pos)   & SAADC_CH_CONFIG_MODE_Msk);

	NRF_SAADC->CH[0].PSELN = micPin;
	NRF_SAADC->CH[0].PSELP = micPin;

	NRF_SAADC->RESULT.PTR = (uint32_t) &value;
	NRF_SAADC->RESULT.MAXCNT = 1; // read a single sample

	NRF_SAADC->TASKS_START = 1;
	while (!NRF_SAADC->EVENTS_STARTED);
	NRF_SAADC->EVENTS_STARTED = 0;

	NRF_SAADC->TASKS_SAMPLE = 1;
	while (!NRF_SAADC->EVENTS_END);
	NRF_SAADC->EVENTS_END = 0;

	NRF_SAADC->TASKS_STOP = 1;
	while (!NRF_SAADC->EVENTS_STOPPED);
	NRF_SAADC->EVENTS_STOPPED = 0;

	NRF_SAADC->ENABLE = 0;

	int result = value;
	result = (result <= 0) ? 0 : result - 556; // if microphone is on, adjust so silence is zero
	return result << 1; // double result to give a range similar to other boards
}

#elif defined(ARDUINO_CALLIOPE_MINI)

int readAnalogMicrophone() {
	const int adcReference = ADC_CONFIG_REFSEL_SupplyOneThirdPrescaling;
	const int adcPrescaling = ADC_CONFIG_INPSEL_AnalogInputOneThirdPrescaling;
	const int adcResolution = ADC_CONFIG_RES_10bit;
	const int adcPin = ADC_CONFIG_PSEL_AnalogInput4;

	NRF_ADC->ENABLE = 1;

	NRF_ADC->CONFIG =
		(adcPin << ADC_CONFIG_PSEL_Pos) |
		(adcReference << ADC_CONFIG_REFSEL_Pos) |
		(adcPrescaling << ADC_CONFIG_INPSEL_Pos) |
		(adcResolution << ADC_CONFIG_RES_Pos);

	NRF_ADC->TASKS_START = 1;
	while(!NRF_ADC->EVENTS_END);
	NRF_ADC->EVENTS_END = 0;

	int value = NRF_ADC->RESULT;

	NRF_ADC->TASKS_STOP = 1;
	NRF_ADC->ENABLE = 0;

	return value -= 517; // adjust so silence is zero
}

#else

int readAnalogMicrophone() {
	// When there's no microphone, read from the first analog pin
	int pin;
#if defined(ARDUINO_CITILAB_ED1)
	pin = 36;
#elif defined(A0)
	pin = A0;
#else
	pin = 0;
#endif
	return (analogRead(pin) >> 2);
}

#endif // Microphone Support

static OBJ primMicrophone(int argCount, OBJ *args) {
	// Read a sound sample from the microphone. Return 0 if board has no built-in microphone.

	int result = 0;

	#if defined(USE_PDM_MICROPHONE)
		result = readPDMMicrophone();
	#else
		result = readAnalogMicrophone();
	#endif

	return int2obj(result);
}

static PrimEntry entries[] = {
	{"acceleration", primAcceleration},
	{"temperature", primMBTemp},
	{"tiltX", primMBTiltX},
	{"tiltY", primMBTiltY},
	{"tiltZ", primMBTiltZ},
	{"setAccelerometerRange", primSetAccelerometerRange},
	{"touchRead", primTouchRead},
	{"i2cRead", primI2cRead},
	{"i2cWrite", primI2cWrite},
	{"readDHT", primReadDHT},
	{"microphone", primMicrophone},
};

void addSensorPrims() {
	addPrimitiveSet("sensors", sizeof(entries) / sizeof(PrimEntry), entries);
}
