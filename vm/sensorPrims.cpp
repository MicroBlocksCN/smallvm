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

// Temporary mapping for Robotistan board prototype
#if defined(ROBOTISTAN_PROTOTYPE) || defined(PICO_ED)
	#define Wire Wire1
#endif

// i2c helper functions

static int wireStarted = false;

static void startWire() {
  #if defined(PICO_ED)
	Wire.setSDA(18);
	Wire.setSCL(19);
  #endif
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

void writeI2CReg(int deviceID, int reg, int value) {
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
	// integer, write it as a single byte. If it is a byte array or list of bytes, write them.
	// The list should contain integers in the range 0..255.

	if ((argCount < 2) || !isInt(args[0])) return int2obj(0);
	int deviceID = obj2int(args[0]);
	OBJ data = args[1];

	if (!wireStarted) startWire();
	Wire.beginTransmission(deviceID);
	if (isInt(data)) {
		int byteValue = obj2int(data);
		if ((byteValue < 0) || (byteValue > 255)) fail(i2cValueOutOfRange);
		Wire.write(byteValue & 255);
	} else if (IS_TYPE(data, ListType)) {
		int count = obj2int(FIELD(data, 0));
		for (int i = 0; i < count; i++) {
			OBJ item = FIELD(data, i + 1);
			if (isInt(item)) {
				int byteValue = obj2int(item);
				if ((byteValue < 0) || (byteValue > 255)) fail(i2cValueOutOfRange);
				Wire.write(byteValue & 255);
			} else {
				fail(i2cValueOutOfRange);
			}
		}
	} else if (IS_TYPE(data, ByteArrayType)) {
		uint8 *src = (uint8 *) &FIELD(data, 0);
		int count = BYTES(data);
		for (int i = 0; i < count; i++) {
			Wire.write(*src++);
		}
	}
	int error = Wire.endTransmission();
	if (error) fail(i2cTransferFailed);
	return falseObj;
}

static OBJ primI2cSetClockSpeed(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	int newSpeed = obj2int(args[0]);
	if (newSpeed > 1) {
		if (!wireStarted) startWire();
		Wire.setClock(newSpeed);
	}
	return falseObj;
}

// SPI prims

#if defined(ARDUINO_ARCH_RP2040) && !defined(PIN_SPI_MISO)
  #define PIN_SPI_MISO PIN_SPI0_MISO
  #define PIN_SPI_MOSI PIN_SPI0_MOSI
  #define PIN_SPI_SCK  PIN_SPI0_SCK
#endif

static int spiSpeed = 1000000;
static int spiMode = SPI_MODE0;

static void initSPI() {
	#if defined(ARDUINO_ARCH_ESP32)
		setPinMode(MISO, INPUT);
		setPinMode(MOSI, OUTPUT);
		setPinMode(SCK, OUTPUT);
	#else
		setPinMode(PIN_SPI_MISO, INPUT);
		setPinMode(PIN_SPI_MOSI, OUTPUT);
		setPinMode(PIN_SPI_SCK, OUTPUT);
	#endif
	SPI.begin();
	SPI.beginTransaction(SPISettings(spiSpeed, MSBFIRST, spiMode));
}

OBJ primSPISend(OBJ *args) {
	if (!isInt(args[0])) return fail(needsIntegerError);
	unsigned data = obj2int(args[0]);
	if (data > 255) return fail(i2cValueOutOfRange);
	initSPI();
	SPI.transfer(data); // send data byte to the slave
	SPI.endTransaction();
	return falseObj;
}

OBJ primSPIRecv(OBJ *args) {
	initSPI();
	int result = SPI.transfer(0); // send a zero byte while receiving a data byte from slave
	SPI.endTransaction();
	return int2obj(result);
}

OBJ primSPISetup(int argCount, OBJ *args) {
	// Set SPI speed, mode, and "channel" (i.e. chip enable pin).
	// The mode parameter is optional and defaults to Mode 0.
	// The channel parameter is used only on Linux-based systems.
	// Bit order is always MSBFIRST.

	if ((argCount < 1) || !isInt(args[0])) { return falseObj; }
	spiSpeed = obj2int(args[0]);
	int mode = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 0;
	switch (mode) {
		case 0: spiMode = SPI_MODE0; break;
		case 1: spiMode = SPI_MODE1; break;
		case 2: spiMode = SPI_MODE2; break;
		case 3: spiMode = SPI_MODE3; break;
		default: spiMode = SPI_MODE0;
	}
	return falseObj;
}

OBJ primSPIExchange(int argCount, OBJ *args) {
	if ((argCount < 1) || (objType(args[0]) != ByteArrayType)) return falseObj;

	unsigned char *data = (unsigned char *) &FIELD(args[0], 0);
	int byteCount = BYTES(args[0]);
	initSPI();
	for (int i = 0; i < byteCount; i++) {
		data[i] = SPI.transfer(data[i]);
	}
	SPI.endTransaction();
	return falseObj;
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
		writeI2CReg(MMA8653_ID, 0x2A, 1); // 800 Hz sample rage (max)
	} else if (0x33 == readI2CReg(LSM303_ID, 0x0F)) {
		accelType = accel_LSM303;
		writeI2CReg(LSM303_ID, 0x20, 0x8F); // 1620 Hz sample rate, low power, all axes
	} else if (0xC7 == readI2CReg(FXOS8700_ID, 0x0D)) {
		accelType = accel_FXOS8700;
		writeI2CReg(FXOS8700_ID, 0x2A, 0); // turn off chip before configuring
		writeI2CReg(FXOS8700_ID, 0x2A, 3); // 800 Hz sample rate (max), fast read, turn on
	} else {
		accelType = accel_none;
	}
	delay(2);
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

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.

	if (!accelStarted) startAccelerometer();
	switch (accelType) {
	case accel_MMA8653:
		if (range > 2) range = 2;
		writeI2CReg(MMA8653_ID, 0x2A, 0); // turn off
		writeI2CReg(MMA8653_ID, 0x0E, range);
		writeI2CReg(MMA8653_ID, 0x2A, 1); // 800 Hz sample rage (max)
		break;
	case accel_LSM303:
		writeI2CReg(LSM303_ID, 0x23, (range << 4));
		break;
	case accel_FXOS8700:
		if (range > 2) range = 2;
		writeI2CReg(FXOS8700_ID, 0x0E, range);
		break;
	default:
		break;
	}
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

	Wire1.requestFrom(deviceID, 1);
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
		writeInternalI2CReg(MMA8653_ID, 0x2A, 1); // 800 Hz sample rage (max)
	} else if (0x33 == readInternalI2CReg(LSM303_ID, 0x0F)) {
		accelType = accel_LSM303;
		writeInternalI2CReg(LSM303_ID, 0x20, 0x8F); // 1620 Hz sample rate, low power, all axes
	} else if (0xC7 == readInternalI2CReg(FXOS8700_ID, 0x0D)) {
		accelType = accel_FXOS8700;
		writeInternalI2CReg(FXOS8700_ID, 0x2A, 0); // turn off chip before configuring
		writeInternalI2CReg(FXOS8700_ID, 0x2A, 3); // 800 Hz sample rate, fast read, turn on
	} else {
		accelType = accel_none;
	}
	delay(2);
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

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.

	if (!accelStarted) startAccelerometer();
	switch (accelType) {
	case accel_MMA8653:
		if (range > 2) range = 2;
		writeInternalI2CReg(MMA8653_ID, 0x2A, 0); // turn off
		writeInternalI2CReg(MMA8653_ID, 0x0E, range);
		writeInternalI2CReg(MMA8653_ID, 0x2A, 1); // 800 Hz sample rage (max)
		break;
	case accel_LSM303:
		writeInternalI2CReg(LSM303_ID, 0x23, (range << 4));
		break;
	case accel_FXOS8700:
		if (range > 2) range = 2;
		writeInternalI2CReg(FXOS8700_ID, 0x0E, range);
		break;
	default:
		break;
	}
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
	if (!accelStarted) {
		// Use accelerometer defaults: unfiltered sampling rate 2k Hz
		readI2CReg(BMX055, 5); // do a read operation to start accelerometer
		delay(2);
		accelStarted = true;
	}
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

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See datasheet pg. 57, PMU_RANGE.

	switch (range) {
	case 0:
		writeI2CReg(BMX055, 0x0F, 3);
		break;
	case 1:
		writeI2CReg(BMX055, 0x0F, 5);
		break;
	case 2:
		writeI2CReg(BMX055, 0x0F, 8);
		break;
	case 3:
		writeI2CReg(BMX055, 0x0F, 12);
		break;
	}
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
		Wire1.write(0x8F); // 1600 Hz sampling rate, Low Power, Enable x/y/z
		Wire1.endTransmission();
		delay(2);
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

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See datasheet pg. 37, CTRL_REG4.

	Wire1.beginTransmission(LIS3DH_ID);
	Wire1.write(0x23);
	Wire1.write(range << 4);
	Wire1.endTransmission();
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
	writeI2CReg(LSM6DS, 0x10, 0x80); // enable accelerometer, 1660 Hz sample rate
	delay(2);
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

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See datasheet pg. 47, CTRL1_XL.

	int rangeBits = 0;
	switch (range) {
	case 0: rangeBits = 0; break;
	case 1: rangeBits = 2; break;
	case 2: rangeBits = 3; break;
	case 3: rangeBits = 1; break;
	default: break;
	}
	int sampleRate = 8; // 1660 Hz
	writeI2CReg(LSM6DS, 0x10, (sampleRate << 4) | (rangeBits << 2));
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
#define MPU6886_ACCEL_CONFIG	0x1C
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

	writeAccelReg(MPU6886_SMPLRT_DIV, 0); // 1000 Hz sample rate
	writeAccelReg(MPU6886_CONFIG, 5); // low-pass filtering: 0-6
	writeAccelReg(MPU6886_PWR_MGMT_1, 1); // use best clock rate (required!)
	writeAccelReg(MPU6886_PWR_MGMT_2, 7); // disable the gyroscope

	is6886 = (25 == readAccelReg(MPU6886_WHO_AM_I));
	delay(3);
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

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See datasheet pg. 37, ACCELEROMETER CONFIGURATION.

	writeAccelReg(MPU6886_ACCEL_CONFIG, range << 3);
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

typedef enum {
	accel_unknown = -1,
	accel_none = 0,
	accel_LIS3DH = 1,
	accel_MXC6655 = 2,
} AccelerometerType_t;

static AccelerometerType_t accelType = accel_unknown;

#define LIS3DH_ID 25
#define MXC6655_ID 21

static void startAccelerometer() {
	if (0x33 == readI2CReg(LIS3DH_ID, 0x0F)) {
		writeI2CReg(LIS3DH_ID, 0x20, 0x8F); // turn on accelerometer, 1600 Hz update, 8-bit (low power) mode
		writeI2CReg(LIS3DH_ID, 0x1F, 0xC0); // enable temperature reporting
		accelType = accel_LIS3DH;
	} else if (0x05 == readI2CReg(MXC6655_ID, 0x0F)) {
		accelType = accel_MXC6655;
	}
	delay(2);
	accelStarted = true;
}


static int readAcceleration(int registerID) {
	if (!accelStarted) startAccelerometer();
	int val = 0;
	switch (accelType) {
	case accel_LIS3DH:
		val = readI2CReg(LIS3DH_ID, 0x28 + registerID);
		break;
	case accel_MXC6655:
		val = readI2CReg(MXC6655_ID, 0x02 + registerID);
		break;
	default:
		val = 0;
		break;
	}
	val = (val >= 128) ? (val - 256) : val; // value is a signed byte
	if (val < -127) val = -127; // keep in range -127 to 127
	val = ((val * 200) / 127); // scale to range 0-200
	val = -val; // invert sign for all axes
	#ifdef ARDUINO_CITILAB_ED1
		if ((accelType == accel_MXC6655) && (5 == registerID)) val -= 25; // fix z value from MXC6655
	#endif
	return val;
}

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	switch (accelType) {
	case accel_LIS3DH:
		// See datasheet pg. 37, CTRL_REG4.
		writeI2CReg(LIS3DH_ID, 0x23, range << 4);
	break;
	case accel_MXC6655:
		if (range > 2) range = 2; // only 2, 4 or 8 supported
		writeI2CReg(MXC6655_ID, 0x0D, range << 5);
		break;
	default:
		break;
	}
}

static int readTemperature() {
	if (!accelStarted) startAccelerometer(); // initialize accelerometer if necessary
	int val = 0;
	int offsetDegreesC, hiByte, lowByte;
	switch (accelType) {
	case accel_LIS3DH:
		writeI2CReg(LIS3DH_ID, 0x23, 0x80); // enable block data update (needed for temperature)
		hiByte = readI2CReg(LIS3DH_ID, 0x0D);
		lowByte = readI2CReg(LIS3DH_ID, 0x0C);
		writeI2CReg(LIS3DH_ID, 0x23, 0); // disable block data update
		if (hiByte <= 127) { // positive offset
			offsetDegreesC = hiByte + ((lowByte >= 128) ? 1 : 0); // round up
		} else { // negative offset
			offsetDegreesC = (hiByte - 256) + ((lowByte >= 128) ? -1 : 0); // round down
		}
		val =  20 + offsetDegreesC;
		break;
	case accel_MXC6655:
		val = readI2CReg(MXC6655_ID, 0x09);
		val =(val >= 128) ? (val - 256) : val; // value is a signed byte
		val = 20 + ((val * 568) / 1000);
		break;
	default:
		break;
	}
	return val;
}

#elif defined(RP2040_PHILHOWER)

static int readTemperature() { return analogReadTemp(); }
static int readAcceleration(int reg) { return 0; } // RP2040 has no accelerometer
static void setAccelRange(int range) { } // RP2040 has no accelerometer

#else // stubs for non-micro:bit boards

static int readAcceleration(int reg) { return 0; }
static int readTemperature() { return 0; }
static void setAccelRange(int range) { }

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

	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_SINOBIT) || defined(ARDUINO_BBC_MICROBIT_V2)
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
		if (accelType == accel_LIS3DH) {
			deviceID = LIS3DH_ID;
			reg = 0x29 | 0x80; // address + auto-increment flag
		} else if (accelType == accel_MXC6655) {
			deviceID = MXC6655_ID;
			reg = 0x03;
		}
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
	#ifdef ARDUINO_CITILAB_ED1
		if (accelType == accel_MXC6655) z = -z - 25; // fix z value from MXC6655
	#endif
	int accel = (int) sqrt((x * x) + (y * y) + (z * z));
	return int2obj(accel);
}

OBJ primSetAccelerometerRange(int argCount, OBJ *args) {
	// Argument is 1, 2, 4, or 8 (#g's to read 100) for full scale of +/- 2, 4, 8, or 16g.
	// The argument give the number of G's that output as 100.

	if (argCount < 1) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	int arg = obj2int(args[0]);

	// Map argument to a range setting 0-3
	int rangeSetting = 0;
	if (arg <= 1) { // default
		rangeSetting = 0;
	} else if (arg <= 2) {
		rangeSetting = 1;
	} else if (arg <= 4) {
		rangeSetting = 2;
	} else {
		rangeSetting = 3;
	}
	setAccelRange(rangeSetting);
	delay(2);
	return falseObj;
}

OBJ primMBTemp(int argCount, OBJ *args) { return int2obj(readTemperature()); }
OBJ primMBTiltX(int argCount, OBJ *args) { return int2obj(readAcceleration(1)); }
OBJ primMBTiltY(int argCount, OBJ *args) { return int2obj(readAcceleration(3)); }
OBJ primMBTiltZ(int argCount, OBJ *args) { return int2obj(readAcceleration(5)); }

// Magnetometer

#ifdef ARDUINO_ARCH_ESP32
  #include "driver/adc.h"
#endif

// accelerometer addresses for ID testing:
#define BMX055 24
#define LSM303 25

// magnetometer addresses:
#define MAG_3110 14
#define MAG_BMX055 16
#define MAG_LIS3MDL 28
#define MAG_LSM303 30

int8_t magnetometerAddr = -1;
int8_t magnetometerDataReg = -1;
int8_t magnetometerBigEndian = true;

void readMagMicrobitV1CalliopeClue(uint8 *sixByteBuffer) {
	if (!wireStarted) startWire();

	if (magnetometerAddr < 0) { // detect and initialize magnetometer
		if (0xC4 == readI2CReg(MAG_3110, 0x07)) {
			magnetometerAddr = MAG_3110;
			magnetometerDataReg = 1;
			magnetometerBigEndian = true;
			writeI2CReg(MAG_3110, 16, 1); // 80 samples/sec
			writeI2CReg(MAG_3110, 17, 128); // enable automatic magnetic sensor resets
		} else if (0x33 == readI2CReg(LSM303, 0x0F)) {
			magnetometerAddr = MAG_LSM303; // different from accellerometer address
			magnetometerDataReg = 104;
			magnetometerBigEndian = false;
			writeI2CReg(MAG_LSM303, 0x60, 12); // 50 samples/sec
			writeI2CReg(MAG_LSM303, 0x61, 2); // offset cancellation
		} else if (0xFA == readI2CReg(BMX055, 0)) {
			magnetometerAddr = MAG_BMX055; // different from accellerometer address
			magnetometerDataReg = 0x42;
			magnetometerBigEndian = false;
			writeI2CReg(MAG_BMX055, 0x4B, 1); // power on
			delay(4); // give BMX055 time to start up
			writeI2CReg(MAG_BMX055, 0x4C, 56); // 30 samples/sec
			writeI2CReg(MAG_BMX055, 0x51, 15); // x/y repetitions
			writeI2CReg(MAG_BMX055, 0x52, 27); // z repetitions
		} else if (0x3D == readI2CReg(MAG_LIS3MDL, 0x0F)) {
			magnetometerAddr = MAG_LIS3MDL;
			magnetometerDataReg = 0x28;
			magnetometerBigEndian = false;
			writeI2CReg(MAG_LIS3MDL, 0x20, 0x02);	// low performance x & y; fast mode
			writeI2CReg(MAG_LIS3MDL, 0x22, 0);		// power on, continuous sampling
			writeI2CReg(MAG_LIS3MDL, 0x23, 0);		// low performance z
			writeI2CReg(MAG_LIS3MDL, 0x24, 0x40);	// block update mode
		}
	}
	if (magnetometerAddr < 0) return;

	Wire.beginTransmission(magnetometerAddr);
	Wire.write(magnetometerDataReg);
	Wire.endTransmission();

	Wire.requestFrom(magnetometerAddr, 6);
	for (int i = 0; i < 6; i++) {
		if (!Wire.available()) return; /* no more data */;
		sixByteBuffer[i] = Wire.read();
	}
}

#if defined(ARDUINO_BBC_MICROBIT_V2)

void readMagMicrobitV2(uint8 *sixByteBuffer) {
	if (!internalWireStarted) startInternalWire();

	if (magnetometerAddr < 0) { // detect and initialize magnetometer
		if (0x33 == readInternalI2CReg(LSM303, 0x0F)) {
			magnetometerAddr = MAG_LSM303; // different from accellerometer address
			magnetometerDataReg = 104;
			magnetometerBigEndian = false;
			writeInternalI2CReg(MAG_LSM303, 0x60, 12); // 50 samples/sec
			writeInternalI2CReg(MAG_LSM303, 0x61, 2); // offset cancellation
		}
	}
	if (magnetometerAddr < 0) return;

	Wire1.beginTransmission(magnetometerAddr);
	Wire1.write(magnetometerDataReg);
	Wire1.endTransmission();
	Wire1.requestFrom(magnetometerAddr, 6);
	for (int i = 0; i < 6; i++) {
		if (!Wire1.available()) return; /* no more data */;
		sixByteBuffer[i] = Wire1.read();
	}
}

#endif

OBJ primMagneticField(int argCount, OBJ *args) {
	// Return the magnitude of the magnetic field vector, regardless of orientation.

	uint8 buf[6] = {0, 0, 0, 0, 0, 0};

	#if defined(ARDUINO_ARCH_ESP32) && !defined(ESP32_C3)
		return int2obj(hall_sensor_read());
	#elif defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE_MINI) || \
			defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_SINOBIT)
		readMagMicrobitV1CalliopeClue(buf);
		processMessage(); // process messages now
	#elif defined(ARDUINO_BBC_MICROBIT_V2)
		readMagMicrobitV2(buf);
		processMessage(); // process messages now
	#else
		return zeroObj;
	#endif

	// read signed 16-bit values
	int x, y, z;
	if (magnetometerBigEndian) {
		x = (int16_t) ((buf[0] << 8) | buf[1]);
		y = (int16_t) ((buf[2] << 8) | buf[3]);
		z = (int16_t) ((buf[4] << 8) | buf[5]);
	} else {
		x = (int16_t) ((buf[1] << 8) | buf[0]);
		y = (int16_t) ((buf[3] << 8) | buf[2]);
		z = (int16_t) ((buf[5] << 8) | buf[4]);
	}

	if (MAG_BMX055 == magnetometerAddr) {
		// remove unused low-order bits
		z >>= 1;
		x >>= 3;
		y >>= 3;
	}

	// return the sum of the field strengths
	int result = abs(x) + abs(y) + abs(z);
	return int2obj(result);
}

// Capacitive Touch Primitives for ESP32

#if defined(ARDUINO_ARCH_ESP32) && !defined(ESP32_C3)

#ifdef ARDUINO_CITILAB_ED1

extern int buttonReadings[6];

static OBJ primTouchRead(int argCount, OBJ *args) {
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

static uint8_t dhtData[5];

#if !defined(ARDUINO_ARCH_RP2040)
  // this macro does nothing on non-RP2040 boards
  #define __not_in_flash_func(f) (f)
#endif

static int __not_in_flash_func(readDHTData)(int pin) {
	// Read DHT data into dhtData. Return true if successful, false if timeout.

	// read the start pulse
	setPinMode(pin, INPUT_PULLUP);
	int pulseWidth = pulseIn(pin, HIGH, 2000);
	if (!pulseWidth) {
		setPinMode(pin, INPUT);
		return false; // timeout
	}

	for (int i = 0; i < 5; i++) {
		int byte = 0;
		for (int shift = 7; shift >= 0; shift--) {
			pulseWidth = pulseIn(pin, HIGH, 1000);
			if (!pulseWidth) return false; // timeout
			if (pulseWidth > 40) byte |= (1 << shift);
		}
		dhtData[i] = byte;
	}

	setPinMode(pin, INPUT);
	return true;
}

static OBJ primReadDHT(int argCount, OBJ *args) {
	// Read DHT data into dhtData. Assume the the 18 msec LOW start pulse has been sent.
	// Return a five-byte ByteArray if successful, false on failure (e.g. no or partial data).

	if (!isInt(args[0])) return fail(needsIntegerError);
	int pin = mapDigitalPinNum(obj2int(args[0]));
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
	// If there's no built-in microphone, read the first analog pin on ED1, else return 0.

	#if defined(ARDUINO_CITILAB_ED1)
		int pin = 36; // Pin A0 on ED1
		return (analogRead(pin) >> 2);
	#endif
	return 0;
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
	{"magneticField", primMagneticField},
	{"touchRead", primTouchRead},
	{"i2cRead", primI2cRead},
	{"i2cWrite", primI2cWrite},
	{"i2cSetClockSpeed", primI2cSetClockSpeed},
	{"spiExchange", primSPIExchange},
	{"spiSetup", primSPISetup},
	{"readDHT", primReadDHT},
	{"microphone", primMicrophone},
};

void addSensorPrims() {
	addPrimitiveSet("sensors", sizeof(entries) / sizeof(PrimEntry), entries);
}
