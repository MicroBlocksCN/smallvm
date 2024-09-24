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

#if defined(PICO_ED) || defined(XRP) || defined(GIZMO_MECHATRONICS)
	#define Wire Wire1
#endif

#if defined(MAKERPORT_V2) || defined(MAKERPORT_V3)
	#define MAKERPORT_ACCEL
#endif

// Override the default i2c pins on some boards

#if defined(PICO_ED) || defined(XRP)
	#define PIN_WIRE_SCL 19
	#define PIN_WIRE_SDA 18
#elif defined(XESGAME) //学而思游戏机
	#define PIN_WIRE_SCL 15
	#define PIN_WIRE_SDA 21
#elif defined(COCUBE)
	#define PIN_WIRE_SCL 22
	#define PIN_WIRE_SDA 21
#elif defined(WUKONG2040)
	#define PIN_WIRE_SCL 17
	#define PIN_WIRE_SDA 16
#elif defined(STICK_HAT)
	#define PIN_WIRE_SCL 26
	#define PIN_WIRE_SDA 0
#elif defined(ARDUINO_M5Stick_C2)
	#define PIN_WIRE_SCL 33
	#define PIN_WIRE_SDA 32
#elif defined(HALOCODE) || defined(LUWU_CYKEBOT)
	#define PIN_WIRE_SCL 18
	#define PIN_WIRE_SDA 19
#elif defined(ARDUINO_M5Stack_Core_PIANO)
	#define PIN_WIRE_SCL 5
	#define PIN_WIRE_SDA 26
#elif defined(FUTURE_LITE)|| defined(M5_CARDPUTER)|| defined(M5_DIN_METER) || defined(M5_ATOMS3LITE) || defined(M5_ATOMS3)
	#define PIN_WIRE_SCL 1
	#define PIN_WIRE_SDA 2
#elif defined(TX_FT_BOX)
	#define PIN_WIRE_SCL 40
	#define PIN_WIRE_SDA 39	
#elif defined(ARDUINO_M5STACK_CORES3)
	#define PIN_WIRE_SCL 11
	#define PIN_WIRE_SDA 12
#elif defined(ARDUINO_M5STACK_Core2_IN)
	#define PIN_WIRE_SCL 22
	#define PIN_WIRE_SDA 21
#elif defined(CHAONENG)
	#define PIN_WIRE_SCL 25
	#define PIN_WIRE_SDA 26
#elif defined(ARDUINO_Mbits)
	// Note: SDA and SCL are reversed from most other ESP32 boards!
	#define PIN_WIRE_SCL 21
	#define PIN_WIRE_SDA 22
#elif defined(ARDUINO_M5Atom_Matrix_ESP32)
	// Note: SDA and SCL are reversed from most other ESP32 boards!
	#define PIN_WIRE_SCL 21
	#define PIN_WIRE_SDA 25
#elif !defined(PIN_WIRE_SCL)
	#if defined(PIN_WIRE0_SCL)
		#define PIN_WIRE_SCL PIN_WIRE0_SCL
		#define PIN_WIRE_SDA PIN_WIRE0_SDA
	#elif defined(ARDUINO_ARCH_ESP32)
		#define PIN_WIRE_SCL SCL
		#define PIN_WIRE_SDA SDA
	#endif
#endif

// i2c helper functions

static int wireStarted = false;

int hasI2CPullups() {
	// Return true if the board has pullup resistors on the i2c pins.
	// To avoid hanging, do not use Wire if I2C lines do not have pullups.

	// First, drive the I2C lines low to discharge them
	pinMode(PIN_WIRE_SCL, OUTPUT);
	pinMode(PIN_WIRE_SDA, OUTPUT);
	digitalWrite(PIN_WIRE_SCL, LOW);
	digitalWrite(PIN_WIRE_SDA, LOW);

	// Switch to input mode
	pinMode(PIN_WIRE_SCL, INPUT);
	pinMode(PIN_WIRE_SDA, INPUT);

	wireStarted = false; // force Wire to be restarted

	// Both SCL and SDA should read high if those pins have pullups
	return ((digitalRead(PIN_WIRE_SCL) == HIGH) && (digitalRead(PIN_WIRE_SDA) == HIGH));
}

static void startWire() {
	#if defined(ARDUINO_ARCH_RP2040)
		Wire.setSDA(PIN_WIRE_SDA);
		Wire.setSCL(PIN_WIRE_SCL);
	#elif defined(ARDUINO_ARCH_ESP32)
		Wire.setPins(PIN_WIRE_SDA, PIN_WIRE_SCL);
	#endif

	#if defined(ARDUINO_ARCH_SAMD)
		// Some Adafruit SAMD21 boards lack external pullups.
		// To avoid hang on I2C operations, do not start Wire if the I2C lines are not high.
		if (!hasI2CPullups()) return;
	#endif
	Wire.begin();
	Wire.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)
	#if defined(ARDUINO_ARCH_RP2040)
		// Needed on RP2040 to reset the I2C bus after a timeout
		Wire.setTimeout(100, true);
	#endif
	wireStarted = true;
}

int readI2CReg(int deviceID, int reg) {
	if (!wireStarted) startWire();
	if (!wireStarted) return -100; // could not start I2C; missing pullup resistors?

	Wire.beginTransmission(deviceID);
	Wire.write(reg);
	#if defined(ARDUINO_ARCH_ESP32)
		// This is needed to avoid error reports on ESP32.
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
	if (!wireStarted) return;

	Wire.beginTransmission(deviceID);
	Wire.write(reg);
	Wire.write(value);
	Wire.endTransmission();
}

// other helper functions

static inline int fix16bitSign(int n) {
	if (n >= 32768) n -= 65536; // negative 16-bit value
	return n;
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

static OBJ primI2cExists(int argCount, OBJ *args) {
	// Return true if there is an i2c device at the given address. Used for i2c scanning.

	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	int i2cAddress = obj2int(args[0]);

	if (!wireStarted) startWire();
	if (!wireStarted) return falseObj;

	Wire.beginTransmission(i2cAddress);
    int error = Wire.endTransmission();
    return error ? falseObj : trueObj;
}

static OBJ primI2cRead(int argCount, OBJ *args) {
	// Read multiple bytes from the given I2C device into the given list and return the
	// number of bytes read. The list size determines the number of bytes to read (up to a
	// max of 32). This operation is usually preceded by an I2C write to request some data.

	if ((argCount < 2) || !isInt(args[0])) return zeroObj;
	int deviceID = obj2int(args[0]);
	OBJ obj = args[1];
	int count = 0;
	uint8 *bytes = NULL; // will point to byte array bytes if obj is a byte array

	if (IS_TYPE(obj, ListType)) {
		count = obj2int(FIELD(obj, 0));
	} else if (IS_TYPE(obj, ByteArrayType)) {
		count = BYTES(obj);
		bytes = (uint8 *) &FIELD(obj, 0);
	} else {
		return fail(needsByteArray);
	}
	if (count <= 0) return zeroObj;
	if (count > 32) count = 32; // the Arduino Wire library limits reads to a max of 32 bytes

	if (!wireStarted) startWire();
	if (!wireStarted) return zeroObj;

	taskSleep(-1); // do background tasks sooner
	#if defined(NRF51)
		noInterrupts();
		Wire.requestFrom(deviceID, count);
		interrupts();
	#else
		Wire.requestFrom(deviceID, count);
	#endif

	for (int i = 0; i < count; i++) {
		uint8 byte = Wire.available() ? Wire.read() : 255; // 255 if no data available
		if (bytes) {
			bytes[i] = byte;
		} else {
			FIELD(obj, i + 1) = int2obj(byte);
		}
	}
	return int2obj(count);
}

static OBJ primI2cWrite(int argCount, OBJ *args) {
	// Write one or multiple bytes to the given I2C device. If the second argument is an
	// integer, write it as a single byte. If it is a byte array or list of bytes, write them.
	// The list should contain integers in the range 0..255.

	if ((argCount < 2) || !isInt(args[0])) return zeroObj;
	int deviceID = obj2int(args[0]);
	OBJ data = args[1];
	int stop = ((argCount < 3) || (trueObj == args[2]));

	if (!wireStarted) startWire();
	if (!wireStarted) return falseObj;

	taskSleep(-1); // do background tasks sooner
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
	} else if (IS_TYPE(data, StringType)) {
		uint8 *src = (uint8 *) obj2str(data);
		int count = strlen((char *) data);
		for (int i = 0; i < count; i++) {
			Wire.write(*src++);
		}
	}
	int error = Wire.endTransmission(stop);
	if (error) reportNum("i2c write error", error);

	return falseObj;
}

static OBJ primI2cSetClockSpeed(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	int newSpeed = obj2int(args[0]);
	if (newSpeed > 1) {
		if (!wireStarted) startWire();
		if (!wireStarted) return falseObj;
		Wire.setClock(newSpeed);
	}
	return falseObj;
}

#if defined(ARDUINO_ARCH_RP2040)

static int legal_rp2040_SDA_pin(int pin) {
	if ((pin < 0) || (pin > 29)) return false;
	return (&Wire != &Wire1) ? ((pin % 4) == 0) : ((pin % 4) == 2);
}

static int legal_rp2040_SCL_pin(int pin) {
	if ((pin < 0) || (pin > 29)) return false;
	return (&Wire != &Wire1) ? ((pin % 4) == 1) : ((pin % 4) == 3);
}

#endif

static OBJ primI2cSetPins(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerError);
	int pinSDA = obj2int(args[0]);
	int pinSCL = obj2int(args[1]);

	#if defined(ARDUINO_ARCH_ESP32) || defined(NRF52_SERIES)
		Wire.end();
		Wire.setPins(pinSDA, pinSCL);
		Wire.begin();
	#elif defined(ARDUINO_ARCH_RP2040)
		if (!legal_rp2040_SDA_pin(pinSDA)) return falseObj;
		if (!legal_rp2040_SCL_pin(pinSCL)) return falseObj;

		// stop Wire and set pins
		Wire.end();
		Wire.setSDA(pinSDA);
		Wire.setSCL(pinSCL);

		// restart Wire
		Wire.begin();
		Wire.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)
		#if defined(ARDUINO_ARCH_RP2040)
			// Needed on RP2040 to reset the I2C bus after a timeout
			Wire.setTimeout(100, true);
		#endif
		wireStarted = true;
	#else
		return fail(primitiveNotImplemented);
	#endif
	return falseObj;
}

// SPI prims

#if defined(PICO_ED)
  #define SPI SPI1
  #define PIN_SPI_MISO (8u)
  #define PIN_SPI_SS   (9u)
  #define PIN_SPI_SCK  (10u)
  #define PIN_SPI_MOSI (11u)
#elif defined(WUKONG2040)
  #define PIN_SPI_MISO (4u)
  #define PIN_SPI_SS   (5u)
  #define PIN_SPI_SCK  (2u)
  #define PIN_SPI_MOSI (3u)
#elif defined(ARDUINO_ARCH_RP2040) && !defined(PIN_SPI_MISO)
  #define PIN_SPI_MISO PIN_SPI0_MISO
  #define PIN_SPI_MOSI PIN_SPI0_MOSI
  #define PIN_SPI_SCK  PIN_SPI0_SCK
#endif

#if defined(ESP8266) || defined(ESP32) || defined(ARDUINO_TEENSY40) || defined(ARDUINO_TEENSY41)
  #define BitOrder int
#endif

static int spiSpeed = 1000000;
static int spiMode = SPI_MODE0;
static BitOrder spiBitOrder = MSBFIRST;

static void initSPI() {
	#if defined(ARDUINO_ARCH_ESP32)
		setPinMode(MISO, INPUT);
		setPinMode(MOSI, OUTPUT);
		setPinMode(SCK, OUTPUT);
	#elif !defined(__ZEPHYR__)
		setPinMode(PIN_SPI_MISO, INPUT);
		setPinMode(PIN_SPI_SCK, OUTPUT);
		setPinMode(PIN_SPI_MOSI, OUTPUT);
	#endif
	#if defined(PICO_ED) || defined(WUKONG2040)
		setPinMode(PIN_SPI_SS, OUTPUT);
		SPI.setRX(PIN_SPI_MISO);
		SPI.setCS(PIN_SPI_SS);
		SPI.setSCK(PIN_SPI_SCK);
		SPI.setTX(PIN_SPI_MOSI);
	#endif
	SPI.begin();
	SPI.beginTransaction(SPISettings(spiSpeed, spiBitOrder, spiMode));
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
	spiBitOrder = MSBFIRST;
	if ((argCount > 3) && IS_TYPE(args[3], StringType) && strcmp(obj2str(args[3]), "LSB")) {
		spiBitOrder = LSBFIRST;
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
		writeI2CReg(LSM303_ID, 0x23, 0); // clear BDU bit in case it was set by Makecode
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

#elif defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)

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
	int error = Wire1.endTransmission((bool) false);
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
		writeInternalI2CReg(LSM303_ID, 0x23, 0); // clear BDU bit in case it was set by Makecode
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

	#if defined(CALLIOPE_V3)
		// flip y and z on Calliope V3
		if ((3 == registerID) || (5 == registerID)) val = -val;
	#endif
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

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY) || defined(MAKERPORT_ACCEL)

#define LIS3DH_ID 25

#if defined(MAKERPORT_ACCEL)
  // use Wire on MakerPort_v2/v3
  #define Wire1 Wire
  #undef LIS3DH_ID
  #define LIS3DH_ID 24
#endif

static void setAccelRange(int range); // forward reference

static int readAcceleration(int registerID) {
	if (!accelStarted) {
		Wire1.begin(); // use internal I2C bus
		Wire1.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)

		// turn on the accelerometer
		Wire1.beginTransmission(LIS3DH_ID);
		Wire1.write(0x20);
		Wire1.write(0x77); // 400 Hz sampling rate, 10-bit resolution, enable x/y/z
		Wire1.endTransmission();
		delay(2);
		setAccelRange(0); // also disables block data update
		#if defined(MAKERPORT_ACCEL)
			writeI2CReg(LIS3DH_ID, 0x1F, 0xC0); // enable temperature reporting
		#endif
		accelStarted = true;
	}
	Wire1.beginTransmission(LIS3DH_ID);
	Wire1.write((0x28 + registerID) | 0x80); // address + auto-increment flag
	int error = Wire1.endTransmission(false);
	if (error) return 0; // error; return 0

	Wire1.requestFrom(LIS3DH_ID, 2);
	signed char highBits = Wire1.available() ? Wire1.read() : 0;
	signed char lowBits = Wire1.available() ? Wire1.read() : 0;
	int val =  (highBits << 2) | ((lowBits >> 6) & 3);
	val = (200 * val) >> 9;
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

	int adc = 0;

	#if defined(MAKERPORT_ACCEL)
		int degreesC = 0;
		uint8 regValue = readI2CReg(LIS3DH_ID, 0x23);
		writeI2CReg(LIS3DH_ID, 0x23, regValue | 0x80); // enable block data update (needed for temperature)
		uint8 hiByte = readI2CReg(LIS3DH_ID, 0x0D);
		uint8 lowByte = readI2CReg(LIS3DH_ID, 0x0C);
		writeI2CReg(LIS3DH_ID, 0x23, regValue); // disable block data update
		if (hiByte <= 127) { // positive offset
			degreesC = hiByte + ((lowByte >= 128) ? 1 : 0); // round up
		} else { // negative offset
			degreesC = (hiByte - 256) + ((lowByte >= 128) ? -1 : 0); // round down
		}
		return  20 + degreesC; // adjusted temperature
	#else
		setPinMode(A9, INPUT);
		adc = analogRead(A9);
		return ((int) (0.116 * adc)) - 37; // linear approximation
	#endif

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

#elif defined(ARDUINO_NRF52840_CLUE) || defined(XRP)

#if defined(XRP)
  #define LSM6DS 107
#else
  #define LSM6DS 106
#endif

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
	#if defined(XRP)
		if (1 == registerID) val = -val; // invert x-axis
	#elif defined(ARDUINO_NRF52840_CLUE)
		if (5 == registerID) val = -val; // invert z-axis
	#endif
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

#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE) || defined(ARDUINO_M5Stick_C) || \
	defined(ARDUINO_M5Atom_Matrix_ESP32) || defined(ARDUINO_M5STACK_Core2) || defined(M5_ATOMS3)

#ifdef ARDUINO_M5Stack_Core_ESP32
 #define Wire1 Wire
#endif
#ifdef ARDUINO_M5STACK_FIRE
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
	return Wire1.available() ? Wire1.read() : 0;
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
	#else
		#ifdef ARDUINO_M5Stick_C2
		Wire1.begin(21, 22);
		#else
			#ifdef M5_ATOMS3
			Wire1.begin(38, 39);
			#else
			Wire1.begin(); // use internal I2C bus with default pins
			#endif
		#endif
	#endif

	Wire1.setClock(400000); // i2c fast mode (seems pretty ubiquitous among i2c devices)

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
		temp = (rawTemp / 40) + 9; // approximate constants, empirically determined
	}
	return temp;
}

#ifdef BM8563_RTC //RTC
#define RTC8563_ADDR	0x51

static uint8_t bcd2ToByte(uint8_t value) {
	uint8_t tmp = 0;
	tmp = ((uint8_t)(value & (uint8_t)0xF0) >> (uint8_t)0x4) * 10;
	return (tmp + (value & (uint8_t)0x0F));
}
static uint8_t byteToBcd2(uint8_t value) {
	uint8_t bcdhigh = 0;
	while (value >= 10) {
		bcdhigh++;
		value -= 10;
	}
	return ((uint8_t)(bcdhigh << 4) | value);
}

static OBJ primRTCSetDate(int argCount, OBJ *args) {
	//yyyy,MM,dd,dayofweek
	Wire1.begin(21, 22);
	Wire1.setClock(400000);
	Wire1.beginTransmission(RTC8563_ADDR);
	Wire1.write(0x05);
	Wire1.write(byteToBcd2(obj2int(args[2])));
	Wire1.write(byteToBcd2(obj2int(args[3])));
	Wire1.write(byteToBcd2(obj2int(args[1])));
	Wire1.write(byteToBcd2(obj2int(args[0]) % 100));
	Wire1.endTransmission();
	return falseObj;
}

static OBJ primRTCSetTime(int argCount, OBJ *args) {
	Wire1.begin(21, 22);
	Wire1.setClock(400000);
	Wire1.beginTransmission(RTC8563_ADDR);
	Wire1.write(0x02);
	Wire1.write(byteToBcd2(obj2int(args[2])));
	Wire1.write(byteToBcd2(obj2int(args[1])));
	Wire1.write(byteToBcd2(obj2int(args[0])));
	Wire1.endTransmission();
	return falseObj;
}

static OBJ primRTCReadDate(int argCount, OBJ *args) {
	OBJ result = newObj(ListType, 5, zeroObj);
	if (!result) return falseObj; // allocation failed
	uint8_t buf[4] = {0};
	Wire1.begin(21, 22);
	// Wire1.setClock(400000);
	Wire1.beginTransmission(RTC8563_ADDR);
	Wire1.write(0x05);
	Wire1.endTransmission();
	Wire1.requestFrom(RTC8563_ADDR, 4);
	for (int i = 0; i < 4; i++) {
		buf[i] = Wire1.available() ? Wire1.read() : 0;
	}
	FIELD(result, 0) = int2obj(4);
	FIELD(result, 1) = int2obj(2000 + bcd2ToByte(buf[3] & 0xff));
	FIELD(result, 2) = int2obj(bcd2ToByte(buf[2] & 0x1f));
	FIELD(result, 3) = int2obj(bcd2ToByte(buf[0] & 0x3f));
	FIELD(result, 4) = int2obj(bcd2ToByte(buf[1] & 0x07));
	return result;
}

static OBJ primRTCReadTime(int argCount, OBJ *args) {
	OBJ result = newObj(ListType, 4, zeroObj);
	if (!result) return falseObj; // allocation failed
	uint8_t buf[3] = {0};
	Wire1.begin(21, 22);
	// Wire1.setClock(400000);
	Wire1.beginTransmission(RTC8563_ADDR);
	Wire1.write(0x02);
	Wire1.endTransmission();
	Wire1.requestFrom(RTC8563_ADDR, 3);
	for (int i = 0; i < 3; i++) {
		buf[i] = Wire1.available() ? Wire1.read() : 0;
	}
	FIELD(result, 0) = int2obj(3);
	FIELD(result, 3) = int2obj(bcd2ToByte(buf[0] & 0x7f));
	FIELD(result, 2) = int2obj(bcd2ToByte(buf[1] & 0x7f));
	FIELD(result, 1) = int2obj(bcd2ToByte(buf[2] & 0x3f));
	return result;
}

#endif

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
		writeI2CReg(LIS3DH_ID, 0x23, 0); // disable block data update
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


#elif defined(ARDUINO_Mbits)

#define MPU6050 0x69
#define MPU6050_ACCEL_XOUT_H 59
#define MPU6050_PWR_MGMT_1 107

static uint8 mpuData[6];

static void mpu6050readData() {
	if (!accelStarted) {
		if (!wireStarted) startWire();
		if (!wireStarted) return;

		writeI2CReg(MPU6050, MPU6050_PWR_MGMT_1, 1); // use x-gyro clock
		delay(1);
		accelStarted = true;
	}

	// Request accelerometer data
	Wire.beginTransmission(MPU6050);
	Wire.write(MPU6050_ACCEL_XOUT_H);
	Wire.endTransmission();

	// Read data
	int count = sizeof(mpuData);
	Wire.requestFrom(MPU6050, count);

	for (int i = 0; i < count; i++) {
		mpuData[i] = Wire.available() ? Wire.read() : 0;
	}
}

static int readAcceleration(int registerID) {
	mpu6050readData();

	int val = 0;
	if (1 == registerID) val = fix16bitSign((mpuData[2] << 8) | mpuData[3]); // x-axis
	if (3 == registerID) val = -fix16bitSign((mpuData[0] << 8) | mpuData[1]); // y-axis
	if (5 == registerID) val = -fix16bitSign((mpuData[4] << 8) | mpuData[5]); // z-axis

	return (100 * val) >> 14;
}

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See MPU-9250 Register Map and Descriptions, ACCEL_CONFIG, pg. 14.

	if ((range < 0) || (range > 3)) return; // out of range
	writeI2CReg(MPU6050, 0x1C, (range << 3));
}

#define TMP75_ADDR 0x48
#define TMP75_TEMP_REG 0

static int readTemperature() {
	if (!wireStarted) startWire();
	if (!wireStarted) return 0;

	// read temperature (two bytes)
	Wire.beginTransmission(TMP75_ADDR);
	Wire.write(TMP75_TEMP_REG);
	Wire.endTransmission();
	Wire.requestFrom(TMP75_ADDR, 2);
	uint8_t msb = Wire.available() ? Wire.read() : 0;
	uint8_t lsb = Wire.available() ? Wire.read() : 0;
	int fudgeFactor = 3;
	return (fix16bitSign((msb << 8) | lsb) >> 8) - fudgeFactor; // temperture C
}

//学而思游戏机
#elif defined(XESGAME)

#define MPU6050 0x68
#define MPU6050_ACCEL_XOUT_H 59
#define MPU6050_PWR_MGMT_1 107

static uint8 mpuData[6];

static void mpu6050readData() {
	if (!accelStarted) {
		if (!wireStarted) startWire();
		if (!wireStarted) return;

		writeI2CReg(MPU6050, MPU6050_PWR_MGMT_1, 1); // use x-gyro clock
		delay(1); // xxx 10 works
		accelStarted = true;
	}

	// Request accelerometer data
	Wire.beginTransmission(MPU6050);
	Wire.write(MPU6050_ACCEL_XOUT_H);
	Wire.endTransmission();

	// Read data
	int count = sizeof(mpuData);
	Wire.requestFrom(MPU6050, count);

	for (int i = 0; i < count; i++) {
		if (!Wire.available()) break; /* no more data */;
		mpuData[i] = Wire.read();
	}
}

static int readAcceleration(int registerID) {
	mpu6050readData();

	int val = 0;
	if (3 == registerID) val = fix16bitSign((mpuData[0] << 8) | mpuData[1]); // y-axis
	if (1 == registerID) val =  -fix16bitSign((mpuData[2] << 8) | mpuData[3]); // x-axis
	if (5 == registerID) val =  -fix16bitSign((mpuData[4] << 8) | mpuData[5]); // z-axis

	return (100 * val) >> 14;
}

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See MPU-9250 Register Map and Descriptions, ACCEL_CONFIG, pg. 14.

	if ((range < 0) || (range > 3)) return; // out of range
	writeI2CReg(MPU6050, 0x1C, (range << 3));
}

static int readTemperature() {
	setPinMode(39, INPUT);
	// 常温下热敏电阻的阻值
	const float nominalResistance = 10000;
	// 常温（25°C）下的温度
	const float nominalTemperature = 25.0;
	// 热敏电阻的B值
	const float bCoefficient = 3950;
	// 串联电阻值
	const float seriesResistor = 10000;
	// ADC最大值
	const int adcMaxValue = 4095;
	// Arduino的参考电压
	const float referenceVoltage = 3.3;
	// 读取热敏电阻的ADC值
	int adcValue = analogRead(39);
	// 计算热敏电阻的电压
	float voltage = (adcValue / (float)adcMaxValue) * referenceVoltage;
	// 计算热敏电阻的阻值
	float resistance = (seriesResistor * (referenceVoltage / voltage - 1.0));
	// 计算温度（使用Steinhart-Hart方程）
  	float steinhart;
  	steinhart = resistance / nominalResistance;              // (R/Ro)
  	steinhart = log(steinhart);                              // ln(R/Ro)
  	steinhart /= bCoefficient;                               // 1/B * ln(R/Ro)
  	steinhart += 1.0 / (nominalTemperature + 273.15);        // + (1/To)
  	steinhart = 1.0 / steinhart;                             // Invert
  	steinhart -= 273.15;                                     // convert to Celsius

	return (steinhart);
}
//学而思游戏机

#elif defined(COCOROBO)

#define MPU6050 0x68
#define MPU6050_ACCEL_XOUT_H 59
#define MPU6050_PWR_MGMT_1 107

static uint8 mpuData[6];

static void mpu6050readData() {
	if (!accelStarted) {
		if (!wireStarted) startWire();
		if (!wireStarted) return;

		writeI2CReg(MPU6050, MPU6050_PWR_MGMT_1, 1); // use x-gyro clock
		delay(1); // xxx 10 works
		accelStarted = true;
	}

	// Request accelerometer data
	Wire.beginTransmission(MPU6050);
	Wire.write(MPU6050_ACCEL_XOUT_H);
	Wire.endTransmission();

	// Read data
	int count = sizeof(mpuData);
	Wire.requestFrom(MPU6050, count);

	for (int i = 0; i < count; i++) {
		if (!Wire.available()) break; /* no more data */;
		mpuData[i] = Wire.read();
	}
}

static int readAcceleration(int registerID) {
	mpu6050readData();

	int val = 0;
	if (1 == registerID) val = -fix16bitSign((mpuData[0] << 8) | mpuData[1]); // x-axis
	if (3 == registerID) val =  fix16bitSign((mpuData[2] << 8) | mpuData[3]); // y-axis
	if (5 == registerID) val =  fix16bitSign((mpuData[4] << 8) | mpuData[5]); // z-axis

	return (100 * val) >> 14;
}

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See MPU-9250 Register Map and Descriptions, ACCEL_CONFIG, pg. 14.

	if ((range < 0) || (range > 3)) return; // out of range
	writeI2CReg(MPU6050, 0x1C, (range << 3));
}

#define AHT_ADDR 0x38
#define AHT10_START_MEASURMENT_CMD 0xAC
#define AHT10_DATA_MEASURMENT_CMD  0x33 
#define AHT10_DATA_NOP             0x00

static uint8 ahtData[6]; 

static int readTemperature() {
	
	Wire1.begin(32, 33); 
	Wire1.setClock(400000);
	delay(5);
	Wire1.beginTransmission(AHT_ADDR);
	Wire1.write(AHT10_START_MEASURMENT_CMD);
  	Wire1.write(AHT10_DATA_MEASURMENT_CMD);
  	Wire1.write(AHT10_DATA_NOP);
	Wire1.endTransmission();

	int count = sizeof(ahtData);
	Wire1.requestFrom(AHT_ADDR, count);
	for (int i = 0; i < count; i++) {
		if (!Wire1.available()) break; /* no more data */;
		ahtData[i] = Wire1.read();
	}

	uint32_t tdata = ahtData[3] & 0x0F;
	tdata <<= 8;
	tdata |= ahtData[4];
	tdata <<= 8;
	tdata |= ahtData[5];
	return (tdata * 191 / 1000000 - 50 );
}

static int readHumidity() {
	
	Wire1.begin(32, 33); 
	Wire1.setClock(400000);
	delay(5);
	Wire1.beginTransmission(AHT_ADDR);
	Wire1.write(AHT10_START_MEASURMENT_CMD);
  	Wire1.write(AHT10_DATA_MEASURMENT_CMD);
  	Wire1.write(AHT10_DATA_NOP);
	Wire1.endTransmission();

	int count = sizeof(ahtData);
	Wire1.requestFrom(AHT_ADDR, count);
	for (int i = 0; i < count; i++) {
		if (!Wire1.available()) break; /* no more data */;
		ahtData[i] = Wire1.read();
	}
	
	uint32_t tdata = ahtData[1];
	tdata <<= 8;
	tdata |= ahtData[2];
	tdata <<= 4;
	tdata |= ahtData[3] >> 4;
	return (tdata * 95 / 1000000);
}
static OBJ primHumidity(int argCount, OBJ *args) {
	return int2obj(readHumidity());
}

#elif defined(MINGBAI)
static uint8 accelData[6];

#define QMI8658_I2C_ADDR 106

static void startAccelerometer() {
	writeI2CReg(QMI8658_I2C_ADDR, 0x60, 0x01);
	delayMicroseconds(20);
	writeI2CReg(QMI8658_I2C_ADDR, 0x02, 0x60);
	writeI2CReg(QMI8658_I2C_ADDR, 0x08, 0x03);
	writeI2CReg(QMI8658_I2C_ADDR, 0x03, 0x1c);
	writeI2CReg(QMI8658_I2C_ADDR, 0x04, 0x40);
	writeI2CReg(QMI8658_I2C_ADDR, 0x06, 0x55);
	readI2CReg(QMI8658_I2C_ADDR, 0x00);
	writeI2CReg(QMI8658_I2C_ADDR, 0x03, (readI2CReg(QMI8658_I2C_ADDR, 0x03) & 0x8f));
	delay(100);
	accelStarted = true;
}
static void accelreadData() {
	if (!accelStarted) {
		startAccelerometer();
	}
	// Request accelerometer data
	Wire.beginTransmission(QMI8658_I2C_ADDR);
	Wire.write(0x35);
	Wire.endTransmission();

	// Read data
	int count = sizeof(accelData);
	Wire.requestFrom(QMI8658_I2C_ADDR, count);

	for (int i = 0; i < count; i++) {
		if (!Wire.available()) break; /* no more data */;
		accelData[i] = Wire.read();
	}

}

static int readAcceleration(int registerID) {
	accelreadData();

	int val = 0;
	if (1 == registerID) val = - fix16bitSign((accelData[3] << 8) | accelData[2]);  // x-axis
	if (3 == registerID) val =   fix16bitSign((accelData[1] << 8) | accelData[0]);  // y-axis
	if (5 == registerID) val = - fix16bitSign((accelData[5] << 8) | accelData[4]);  // z-axis

	return (100 * val) >> 14;
}

#define AHT_ADDR 0x38
enum registers
{
    sfe_aht20_reg_reset = 0xBA,
    sfe_aht20_reg_initialize = 0xBE,
    sfe_aht20_reg_measure = 0xAC,
};
static int readTemperature() {
	if (!wireStarted) startWire();
	if (!wireStarted) return 0;	

	Wire.requestFrom(AHT_ADDR, (uint8_t)1);
    if (Wire.available()){
		uint8_t statusByte = Wire.read();
		if(!(statusByte & (1 << 3))){
			//initialize
			//Send 0xBE0800
			Wire.beginTransmission(AHT_ADDR);
			Wire.write(sfe_aht20_reg_initialize);
			Wire.write(0x08);
			Wire.write(0x00);
			Wire.endTransmission();
			delay(75);
		}
	}
	//Immediately trigger a measurement. Send 0xAC3300
	Wire.beginTransmission(AHT_ADDR);
    Wire.write(sfe_aht20_reg_measure);
    Wire.write(0x33);
    Wire.write(0x00);
	Wire.endTransmission();
	delay(50);
	if (Wire.requestFrom(AHT_ADDR, 6) > 0)
	{
		Wire.read(); // Read and discard state
		uint32_t incoming = 0;
		incoming |= (uint32_t)Wire.read() << (8 * 2);
		incoming |= (uint32_t)Wire.read() << (8 * 1);
		uint8_t midByte = Wire.read();
		incoming |= midByte;// humidity data not use

		uint32_t tdata = midByte;
		tdata <<= 8;
		tdata |=Wire.read();
		tdata <<= 8;
		tdata |=Wire.read();
		//Need to get rid of data in bits > 20
		tdata = tdata & (~(0xFFF00000));
		return (tdata * 191 / 1000000 - 50 );
	}
	return 0;
}

static void setAccelRange(int range) {
	//not apply this method
	return;
}

#elif defined(ARDUINO_Labplus_mPython) //not finish yet
static uint8 accelData[6];

#if defined(MATRIXBIT) //QMI8658
#define QMI8658_I2C_ADDR 107

static void startAccelerometer() {
	writeI2CReg(QMI8658_I2C_ADDR, 0x60, 0x01);
	delayMicroseconds(20);
	writeI2CReg(QMI8658_I2C_ADDR, 0x02, 0x60);
	writeI2CReg(QMI8658_I2C_ADDR, 0x08, 0x03);
	writeI2CReg(QMI8658_I2C_ADDR, 0x03, 0x1c);
	writeI2CReg(QMI8658_I2C_ADDR, 0x04, 0x40);
	writeI2CReg(QMI8658_I2C_ADDR, 0x06, 0x55);
	readI2CReg(QMI8658_I2C_ADDR, 0x00);
	writeI2CReg(QMI8658_I2C_ADDR, 0x03, (readI2CReg(QMI8658_I2C_ADDR, 0x03) & 0x8f));
	delay(100);
	accelStarted = true;
}
static void accelreadData() {
	if (!accelStarted) {
		startAccelerometer();
	}
	// Request accelerometer data
	Wire.beginTransmission(QMI8658_I2C_ADDR);
	Wire.write(0x35);
	Wire.endTransmission();

	// Read data
	int count = sizeof(accelData);
	Wire.requestFrom(QMI8658_I2C_ADDR, count);

	for (int i = 0; i < count; i++) {
		if (!Wire.available()) break; /* no more data */;
		accelData[i] = Wire.read();
	}

}

static int readAcceleration(int registerID) {
	accelreadData();

	int val = 0;
	if (1 == registerID) val = - fix16bitSign((accelData[3] << 8) | accelData[2]);  // x-axis
	if (3 == registerID) val =   fix16bitSign((accelData[1] << 8) | accelData[0]);  // y-axis
	if (5 == registerID) val = - fix16bitSign((accelData[5] << 8) | accelData[4]);  // z-axis

	return (100 * val) >> 14;
}

#else //MSA300
#define MSA300_I2C_ADDR 38
static void startAccelerometer() {
	writeI2CReg(MSA300_I2C_ADDR, 0x0F, 0x08);
	writeI2CReg(MSA300_I2C_ADDR, 0x11, 0x00);
	delay(100);
	accelStarted = true;
}

static void accelreadData() {
	if (!accelStarted) {
		startAccelerometer();
	}

	// Request accelerometer data
	Wire.beginTransmission(MSA300_I2C_ADDR);
	Wire.write(0x02);
	Wire.endTransmission();

	// Read data
	int count = sizeof(accelData);
	Wire.requestFrom(MSA300_I2C_ADDR, count);

	for (int i = 0; i < count; i++) {
		if (!Wire.available()) break; /* no more data */;
		accelData[i] = Wire.read();
	}

}

#if defined(QIANKUN)
static int readAcceleration(int registerID) {
	accelreadData();

	int val = 0;
	if (1 == registerID) val =  fix16bitSign((accelData[3] << 8) | accelData[2]); // x-axis
	if (3 == registerID) val =  - fix16bitSign((accelData[1] << 8) | accelData[0]); // y-axis
	if (5 == registerID) val =  - fix16bitSign((accelData[5] << 8) | accelData[4]); // z-axis

	return (100 * val) >> 14;
}

#else
static int readAcceleration(int registerID) {
	accelreadData();

	int val = 0;
	if (1 == registerID) val =  - fix16bitSign((accelData[3] << 8) | accelData[2]); // x-axis
	if (3 == registerID) val =  fix16bitSign((accelData[1] << 8) | accelData[0]); // y-axis
	if (5 == registerID) val =  - fix16bitSign((accelData[5] << 8) | accelData[4]); // z-axis

	return (100 * val) >> 14;
}
#endif

#endif

static int readTemperature() {
	return 0;
}
static void setAccelRange(int range) {
	return;
}

#elif defined(DATABOT)

typedef enum {
	accel_unknown = -1,
	accel_none = 0,
	accel_ICM20948 = 1,
	accel_MPU9250 = 2,
} AccelerometerType_t;

static AccelerometerType_t accelType = accel_unknown;

#define ICM20948 0x68
#define MPU9250 0x69

// ICM20948 registers
#define ICM20948_PWR_MGMNT_1 0x06
#define ICM20948_PWR_MGMNT_2 0x07
#define ICM20948_ACCEL_CONFIG 0x14
#define ICM20948_BANK_SEL 0x7F
#define ICM20948_FILTERING 0x11

// MPU9250 registers (decimal, following datasheet)
#define MPU9250_BYPASS_EN 55
#define MPU9250_ACCEL_XOUT_H 59
#define MPU9250_PWR_MGMT_1 107

static uint8 databotData[6];

// forward references
static int databotAK09916MageneticField();
static int databotAK8963MageneticField();

static void setRegisterBank(int regBank) {
	// Set ICM20948 register bank
	switch(regBank) {
	case 0: writeI2CReg(ICM20948, ICM20948_BANK_SEL, 0); break;
	case 1: writeI2CReg(ICM20948, ICM20948_BANK_SEL, 16); break;
	case 2: writeI2CReg(ICM20948, ICM20948_BANK_SEL, 32); break;
	case 3: writeI2CReg(ICM20948, ICM20948_BANK_SEL, 48); break;
	}
}

static void startAccelerometer() {
	if (!wireStarted) startWire();
	if (!wireStarted) return;

	if (readI2CReg(ICM20948, 0) == 234) {
		accelType = accel_ICM20948;
		setRegisterBank(0);
		writeI2CReg(ICM20948, ICM20948_PWR_MGMNT_1, 0x80); // reset
		delay(5); // leave time for reset
		writeI2CReg(ICM20948, ICM20948_PWR_MGMNT_1, 1); // wake up and use auto clock select
		setRegisterBank(2);
		writeI2CReg(ICM20948, ICM20948_ACCEL_CONFIG, ICM20948_FILTERING);
		setRegisterBank(0);
		databotAK09916MageneticField(); // initialize magnetometer
	} else {
		accelType = accel_MPU9250;
		writeI2CReg(MPU9250, MPU9250_PWR_MGMT_1, 128); // reset accelerometer
		writeI2CReg(MPU9250, MPU9250_PWR_MGMT_1, 0);
		writeI2CReg(MPU9250, MPU9250_PWR_MGMT_1, 1);
		writeI2CReg(MPU9250, MPU9250_BYPASS_EN, 2); // allows i2c access to magnetometer
		databotAK8963MageneticField();  // initialize magnetometer
		delay(20); // allow time for accelerometer startup
	}
	accelStarted = true;
}
static void databotReadData(int i2cAddr, int reg) {
	// Request data starting at reg
	Wire.beginTransmission(i2cAddr);
	Wire.write(reg);
	Wire.endTransmission();

	// Read data
	int count = sizeof(databotData);
	Wire.requestFrom(i2cAddr, count);
	for (int i = 0; i < count; i++) {
		databotData[i] = Wire.available() ? Wire.read() : 0;
	}
}

static int databotSigned16IntAt(int i) {
	// Return signed 16-bit value at the given index in databotData.

	int val = (databotData[i] << 8) | databotData[i + 1];
	if (val >= 32768) val -= 65536; // negative 16-bit value
	return val;
}

static int readAcceleration(int registerID) {
	if (!accelStarted) startAccelerometer();
	int val = 0;

	switch (accelType) {
	case accel_ICM20948:
		setRegisterBank(0);
		databotReadData(ICM20948, 0x2D);
		if (1 == registerID) val = databotSigned16IntAt(0); // x-axis
		if (3 == registerID) val = databotSigned16IntAt(2); // y-axis
		if (5 == registerID) val = databotSigned16IntAt(4); // z-axis
		return (100 * val) >> 14;
	case accel_MPU9250:
		databotReadData(MPU9250, MPU9250_ACCEL_XOUT_H);
		if (1 == registerID) val = databotSigned16IntAt(2); // x-axis
		if (3 == registerID) val = databotSigned16IntAt(0); // y-axis
		if (5 == registerID) val = databotSigned16IntAt(4); // z-axis
		return (100 * val) >> 14;
	}
	return 0;
}

static void setAccelRange(int range) {
	// Range is 0, 1, 2, or 3 for +/- 2, 4, 8, or 16 g.
	// See ICM20948 Register Map and Descriptions, ACCEL_CONFIG, pg. 64.
	// See MPU9250 Register Map and Descriptions, ACCEL_CONFIG, pg. 14.

	if ((range < 0) || (range > 3)) return; // out of range
	switch (accelType) {
	case accel_ICM20948:
		setRegisterBank(2);
		writeI2CReg(ICM20948, ICM20948_ACCEL_CONFIG, ICM20948_FILTERING | (range << 1));
		break;
	case accel_MPU9250:
		writeI2CReg(MPU9250, 0x1C, (range << 3));
		break;
	}
}

static int readTemperature() {
	#define LPS22HD 0x5C
	writeI2CReg(LPS22HD, 0x11, 1);
	delay(1); // wait for data
	int val = readI2CReg(LPS22HD, 0x2B); // low byte
	val |= (readI2CReg(LPS22HD, 0x2C) << 8); // high byte
	if (val >= 32768) val -= 65536;
	int fudgeFactor = 1230; // partially compensate for the heat inside Databot case
	taskSleep(10);
	return (val - fudgeFactor) / 100; // degrees C
}

// AK09916 magnetometer built into ICM20948
#define AK09916_ADDR 0x0C
#define AK09916_SLAVE_ADDR 0x03
#define AK09916_SLAVE_REG 0x04
#define AK09916_SLAVE_CTRL 0x05
#define AK09916_SLAVE_D0 0x06
#define AK09916_MAG_DATA 0x3B

// AK8963 magnetometer built into MPU9250
#define AK8963 0x0C
#define AK8963_X_LOW 0x03
#define AK8963_CONTROL_1 0x0A

static int databotMagStarted = false;

static void writeAK09916Register(int magReg, int value) {
	setRegisterBank(3);
	writeI2CReg(ICM20948, AK09916_SLAVE_ADDR, AK09916_ADDR);
	writeI2CReg(ICM20948, AK09916_SLAVE_REG, magReg);
	writeI2CReg(ICM20948, AK09916_SLAVE_D0, value);
	writeI2CReg(ICM20948, AK09916_SLAVE_CTRL, 0x81);
}

static void startReadingAK09916() {
	setRegisterBank(3);
	writeI2CReg(ICM20948, AK09916_SLAVE_ADDR, 128 | AK09916_ADDR); // read bit + address
	writeI2CReg(ICM20948, AK09916_SLAVE_REG, 17); // 17 is start of mag data in AK09916
	writeI2CReg(ICM20948, AK09916_SLAVE_CTRL, 128 | 8); // must read 8 bytes, including status
	setRegisterBank(0);
}

static int databotAK09916MageneticField() {
	static uint8 magData[6];

	if (!databotMagStarted) {
		setRegisterBank(0);
		writeI2CReg(ICM20948, 3, 32);  // set up I2C communications with magnetometer
		setRegisterBank(3);
		writeI2CReg(ICM20948, 1, 7); // set I2C clock rate
		writeAK09916Register(0x32, 1); // reset magnetometer
		delay(10);
		writeAK09916Register(0x31, 8); // sample magnetometer at 100 Hz
		startReadingAK09916();
		delay(20); // allow time to aquire the first sample
		databotMagStarted = true;
	}

	// Request mag data
	setRegisterBank(0);
	Wire.beginTransmission(ICM20948);
	Wire.write(AK09916_MAG_DATA);
	Wire.endTransmission(true);

	// Read mag data
	int count = sizeof(magData);
	Wire.requestFrom(ICM20948, count);
	for (int i = 0; i < count; i++) {
		magData[i] = Wire.available() ? Wire.read() : 0;
	}

	int magX = fix16bitSign((magData[1] << 8) + magData[0]);
	int magY = fix16bitSign((magData[3] << 8) + magData[2]);
	int magZ = fix16bitSign((magData[5] << 8) + magData[4]);

	return sqrt((magX * magX) + (magY * magY) + (magZ * magZ));
}

static int databotAK8963MageneticField() {
	static uint8 magData[7]; // includes ST2 register

	if (!databotMagStarted) {
		delay(1);
		writeI2CReg(AK8963, AK8963_CONTROL_1, 0); // switch to powerdown mode
		delay(1);
		writeI2CReg(AK8963, AK8963_CONTROL_1, 0x16); // 16-bit, 100 Hz, continuous
		delay(10); // wait for first sample (min 8 msecs)
		databotMagStarted = true;
	}

	// Request data starting at reg
	Wire.beginTransmission(AK8963);
	Wire.write(AK8963_X_LOW);
	Wire.endTransmission();

	// Read data
	int count = sizeof(magData);
	Wire.requestFrom(AK8963, count);
	for (int i = 0; i < count; i++) {
		magData[i] = Wire.available() ? Wire.read() : 0;
	}

	int magX = fix16bitSign((magData[1] << 8) + magData[0]);
	int magY = fix16bitSign((magData[3] << 8) + magData[2]);
	int magZ = fix16bitSign((magData[5] << 8) + magData[4]);

	return sqrt((magX * magX) + (magY * magY) + (magZ * magZ));
}

static int databotMageneticField() {
	if (!accelStarted) startAccelerometer(); // detect accelerometer type
	switch (accelType) {
	case accel_ICM20948:
		return databotAK09916MageneticField();
	case accel_MPU9250:
		return databotAK8963MageneticField();
	}
	return 0;
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
		defined(ARDUINO_M5STACK_FIRE) || \
		defined(ARDUINO_M5STACK_Core2) || \
		defined(ARDUINO_M5Stick_C) || \
		defined(ARDUINO_M5Atom_Matrix_ESP32)

		// Use Wire1, the internal i2c bus
		Wire1.beginTransmission(deviceID);
		Wire1.write(reg);
		int error = Wire1.endTransmission((bool) false);
		if (error) {
			reportNum("i2c read error", error);
			return;
		}
		Wire1.requestFrom(deviceID, bufSize);
		for (int i = 0; i < bufSize; i++) {
			buf[i] = Wire1.available() ? Wire1.read() : 0;
		}
	#else
		// Use Wire, the primary/external i2c bus
		Wire.beginTransmission(deviceID);
		Wire.write(reg);
		int error = Wire.endTransmission((bool) false);
		if (error) {
			reportNum("i2c read error", error);
			return;
		}

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

	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_SINOBIT) || \
		defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)
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
	#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE) || defined(ARDUINO_M5STACK_Core2) || defined(ARDUINO_M5Stick_C) || defined(ARDUINO_M5Atom_Matrix_ESP32)
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
	taskSleep(2);
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
			magnetometerAddr = MAG_LSM303; // different from accelerometer address
			magnetometerDataReg = 104;
			magnetometerBigEndian = false;
			writeI2CReg(MAG_LSM303, 0x60, 12); // 50 samples/sec
			writeI2CReg(MAG_LSM303, 0x61, 2); // offset cancellation
		} else if (0xFA == readI2CReg(BMX055, 0)) {
			magnetometerAddr = MAG_BMX055; // different from accelerometer address
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
		sixByteBuffer[i] = Wire.available() ? Wire.read() : 0;
	}
}

#if defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)

void readMagMicrobitV2(uint8 *sixByteBuffer) {
	if (!internalWireStarted) startInternalWire();

	if (magnetometerAddr < 0) { // detect and initialize magnetometer
		if (0x33 == readInternalI2CReg(LSM303, 0x0F)) {
			magnetometerAddr = MAG_LSM303; // different from accelerometer address
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
		sixByteBuffer[i] = Wire1.available() ? Wire1.read() : 0;
	}
}

#endif

OBJ primMagneticField(int argCount, OBJ *args) {
	// Return the magnitude of the magnetic field vector, regardless of orientation.

	uint8 buf[6] = {0, 0, 0, 0, 0, 0};

	#if defined(DATABOT)
		return int2obj(databotMageneticField());
	#elif defined(ESP32_ORIGINAL)
		return int2obj(hall_sensor_read());
	#elif defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE_MINI) || \
			defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_SINOBIT)
		readMagMicrobitV1CalliopeClue(buf);
		processMessage(); // process messages now
	#elif defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)
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

static OBJ primTouchRead(int argCount, OBJ *args) { return zeroObj; }

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
	// Read DHT data into dhtData. Assume the 18 msec LOW start pulse has been sent.
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

#define USE_DIGITAL_MICROPHONE 1

static NRF_PDM_Type *nrf_pdm = NRF_PDM;
static int mic_initialized = false;

static int16_t mic_sample;

static void initPDM() {
	if (mic_initialized) return;
	mic_initialized = true;

	pinMode(PIN_PDM_CLK, OUTPUT);
	digitalWrite(PIN_PDM_CLK, LOW);
	pinMode(PIN_PDM_DIN, INPUT);

	nrf_pdm->PSEL.CLK = g_ADigitalPinMap[PIN_PDM_CLK];
	nrf_pdm->PSEL.DIN = g_ADigitalPinMap[PIN_PDM_DIN];

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

static int readDigitalMicrophone() {
	if (!mic_initialized) initPDM();
	nrf_pdm->EVENTS_END = 0;
	while (!nrf_pdm->EVENTS_END) /* wait for next sample */;
	return ((int) mic_sample) >> 3; // scale result
}

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)

#define USE_DIGITAL_MICROPHONE 1

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

static int readDigitalMicrophone() {
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

#elif defined(M5_CARDPUTER) 
// || defined(FUTURE_LITE) || defined(ARDUINO_M5Stick_C) || defined(ARDUINO_M5STACK_Core2)

#define USE_DIGITAL_MICROPHONE 1

#include <driver/i2s.h>
#define I2S_PORT I2S_NUM_0

#if defined(M5_CARDPUTER)
	#define PIN_CLK  43
	#define PIN_DATA 46
#elif defined(FUTURE_LITE)
	#define PIN_CLK  39
	#define PIN_DATA 41
#elif defined(ARDUINO_M5Stick_C) || defined(ARDUINO_M5STACK_Core2) 
	#define PIN_CLK  0
	#define PIN_DATA 34
#endif

// Microphone input buffer (minimum sample count is 8)
// Use smallest possible buffer to minimize latency
#define MIC_BUF_LEN 128
static int16_t micBuffer[MIC_BUF_LEN];
static int micNextSample = MIC_BUF_LEN;

static int microphoneInitialized = false;

void initI2SMicrophone() {
	if (microphoneInitialized) return;
	const i2s_config_t i2s_config = {
		//| I2S_MODE_PDM
	.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX | I2S_MODE_PDM),
	.sample_rate = 22050,
	.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT, // is fixed at 12bit, stereo, MSB
	.channel_format = I2S_CHANNEL_FMT_ONLY_RIGHT,
	.communication_format = I2S_COMM_FORMAT_I2S,
	.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
	.dma_buf_count = 2,
	.dma_buf_len = 8,
	.use_apll = false
	};
	i2s_driver_install(I2S_NUM_0, &i2s_config, 0, NULL);
		// configure microphone pins
	const i2s_pin_config_t pin_config = {
		.bck_io_num = I2S_PIN_NO_CHANGE,
		.ws_io_num = PIN_CLK,
		.data_out_num = I2S_PIN_NO_CHANGE,
		.data_in_num = PIN_DATA
	};

	//Serial.println("Init i2s_set_pin");
    i2s_set_pin(I2S_NUM_0, &pin_config);
	// start I2S driver
	// i2s_start(I2S_PORT);
	i2s_set_clk(I2S_NUM_0, 22050, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_MONO);
	microphoneInitialized = true;
}

static int readDigitalMicrophone() {
	if (!microphoneInitialized) initI2SMicrophone();
	if (micNextSample >= MIC_BUF_LEN) {
		// read another buffer of samples
		size_t bytesIn = 0;
		i2s_read(I2S_NUM_0, &micBuffer, sizeof(micBuffer), &bytesIn, 1);
		micNextSample = 0;
	}
	return micBuffer[micNextSample++];
}

#elif defined(DATABOT)

#define USE_DIGITAL_MICROPHONE 1

#include <driver/i2s.h>

// I2S port and pins
#define I2S_PORT I2S_NUM_0
#define I2S_WS 19
#define I2S_SD 18
#define I2S_SCK 5

// Microphone input buffer (minimum sample count is 8)
// Use smallest possible buffer to minimize latency
#define MIC_BUF_LEN 8
static int16_t micBuffer[MIC_BUF_LEN];
static int micNextSample = MIC_BUF_LEN;

static int microphoneInitialized = false;

void initI2SMicrophone() {
	if (microphoneInitialized) return;

	// configure I2S driver
	const i2s_config_t i2s_config = {
		.mode = i2s_mode_t(I2S_MODE_MASTER | I2S_MODE_RX),
		.sample_rate = 22050,
		.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
		.channel_format = I2S_CHANNEL_FMT_ONLY_RIGHT,
		.communication_format = I2S_COMM_FORMAT_STAND_I2S,
		.intr_alloc_flags = 0,
		.dma_buf_count = 2, // 2 is the minumum
		.dma_buf_len = MIC_BUF_LEN, // 8 is the minimum
		.use_apll = false
	};
	i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);

	// configure microphone pins
	const i2s_pin_config_t pin_config = {
		.bck_io_num = I2S_SCK,
		.ws_io_num = I2S_WS,
		.data_out_num = -1,
		.data_in_num = I2S_SD
	};
	i2s_set_pin(I2S_PORT, &pin_config);

	// start I2S driver
	i2s_start(I2S_PORT);
	microphoneInitialized = true;
}

static int readDigitalMicrophone() {
	if (!microphoneInitialized) initI2SMicrophone();
	if (micNextSample >= MIC_BUF_LEN) {
		// read another buffer of samples
		size_t bytesIn = 0;
		i2s_read(I2S_PORT, &micBuffer, sizeof(micBuffer), &bytesIn, 1);
		micNextSample = 0;
	}
	return micBuffer[micNextSample++];
}

#elif defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)

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

	#if defined(ARDUINO_BBC_MICROBIT_V2)
		#define ZERO_OFFSET 556
	#elif defined(CALLIOPE_V3)
		#define ZERO_OFFSET 548
	#endif
	int result = value;
	result = (result <= 0) ? 0 : result - ZERO_OFFSET; // if microphone is on, adjust so silence is zero
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
	#elif defined(ARDUINO_Mbits)
		int pin = 35;
		return (analogRead(pin) >> 2);
	#endif
	return 0;
}

#endif // Microphone Support

static OBJ primMicrophone(int argCount, OBJ *args) {
	// Read a sound sample from the microphone. Return 0 if board has no built-in microphone.

	int result = 0;

	#if defined(USE_DIGITAL_MICROPHONE)
		result = readDigitalMicrophone();
	#else
		result = readAnalogMicrophone();
	#endif

	return int2obj(result);
}

// CoCube Position Sensor
#if defined (COCUBE)
	#include <CoCubeSensor.h>
	CoCubeSensor cocube;
	void cocubeSensorInit(){
		cocube.Init();
	}

	void cocubeSensorUpdate(){
		cocube.Update();
		cocube.EncoderUpdate();
	}

	static OBJ primPositionX(int argCount, OBJ *args){
		int result = cocube.GetX();
		return int2obj(result);
	}

	static OBJ primPositionY(int argCount, OBJ *args){
			int result = cocube.GetY();
			return int2obj(result);
		}

	static OBJ primPositionYaw(int argCount, OBJ *args){
			int result = cocube.GetAngle();
			return int2obj(result);
	}

	static OBJ primIndex(int argCount, OBJ *args){
            int result = cocube.GetIndex();
            return int2obj(result);
    }

    static OBJ primCubeStatus(int argCount, OBJ *args) {
        if (cocube.GetState())
            return trueObj;
        else
            return falseObj;
    }

    static OBJ primPositionSpeedLeft(int argCount, OBJ *args){
			int result = cocube.GetSpeedLeft();
			return int2obj(result);
	}

	static OBJ primPositionSpeedRight(int argCount, OBJ *args){
			int result = cocube.GetSpeedRight();
			return int2obj(result);
	}
#endif

// Signal Capture

#define MAX_PULSE_TIMES 128
int16_t pulseTimes[MAX_PULSE_TIMES];

int pulsePin = -1;
int pulseIndex = 0;
uint32 lastEdgeTime = 0;

void pinChangeInterrupt() {
	if (pulseIndex < MAX_PULSE_TIMES) {
		uint32 now = microsecs();
		int usecs = now - lastEdgeTime;
		if (digitalRead(pulsePin) == LOW) usecs = -usecs;
		pulseTimes[pulseIndex++] = usecs;
		lastEdgeTime = now;
	}
}

OBJ captureStartPrim(int argCount, OBJ *args) {
	if (pulsePin >= 0) detachInterrupt(pulsePin); // stop pin change interrupts, if any
	pulsePin = -1;

	int pin = mapDigitalPinNum(obj2int(args[0]));
	if (pin < 0) return falseObj; // invalid pin number

	pulsePin = pin;
	setPinMode(pulsePin, INPUT);
	attachInterrupt(pulsePin, pinChangeInterrupt, CHANGE);
	pulseIndex = 0;
	lastEdgeTime = microsecs();
	return trueObj;
}

OBJ primCaptureCount(int argCount, OBJ *args) {
	return int2obj(pulseIndex);
}

OBJ primCaptureEnd(int argCount, OBJ *args) {
	detachInterrupt(pulsePin); // stop pin change interrupts, if any
	pulsePin = -1;

	int count = pulseIndex;
	pulseIndex = 0; // clear capture

	OBJ result = newObj(ListType, count + 1, falseObj);
	if (!result) return falseObj; // allocation failed

	FIELD(result, 0) = int2obj(count);
	for (int i = 0; i < count; i++) {
		FIELD(result, i + 1) = int2obj(pulseTimes[i]);
	}
	return result;
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
	{"i2cExists", primI2cExists},
	{"i2cRead", primI2cRead},
	{"i2cWrite", primI2cWrite},
	{"i2cSetClockSpeed", primI2cSetClockSpeed},
	{"i2cSetPins", primI2cSetPins},
	{"spiExchange", primSPIExchange},
	{"spiSetup", primSPISetup},
	{"readDHT", primReadDHT},
	{"microphone", primMicrophone},
	{"captureStart", captureStartPrim},
	{"captureCount", primCaptureCount},
	{"captureEnd", primCaptureEnd},
	
	#if defined(COCOROBO)
	{"Humidity", primHumidity},		
  	#endif
	#if defined(BM8563_RTC)
	{"setDate", primRTCSetDate},	
	{"setTime", primRTCSetTime},
	{"readDate", primRTCReadDate},	
	{"readTime", primRTCReadTime},	
  	#endif
	#if defined(COCUBE)
	{"position_x", primPositionX},
	{"position_y", primPositionY},
	{"position_yaw", primPositionYaw},
	{"cube_index", primIndex},
	{"cube_status", primCubeStatus},
	{"speed_left", primPositionSpeedLeft},
	{"speed_right", primPositionSpeedRight},
  	#endif
};

void addSensorPrims() {
	addPrimitiveSet(SensorPrims, "sensors", sizeof(entries) / sizeof(PrimEntry), entries);
}
