/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// raspberryPi.c - Microblocks for Raspberry Pi
// John Maloney, December 2017

#define _XOPEN_SOURCE 600

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <unistd.h>

#include <wiringPi.h>
#include <wiringSerial.h>
#include <wiringPiI2C.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Timing Functions

static int startSecs = 0;

static void initTimers() {
	struct timeval now;
	gettimeofday(&now, NULL);
	startSecs = now.tv_sec;
}

uint32 microsecs() {
	struct timeval now;
	gettimeofday(&now, NULL);
	return (1000000 * (now.tv_sec - startSecs)) + now.tv_usec;
}

uint32 millisecs() {
	struct timeval now;
	gettimeofday(&now, NULL);
	return (1000 * (now.tv_sec - startSecs)) + (now.tv_usec / 1000);
}

// Communication/System Functions

static int serialPort = -1; // hardware serial port (if >= 0)
static int pty = -1; // pseudo terminal (if >= 0)

static void openHardwareSerialPort() {
	serialPort = serialOpen("/dev/ttyGS0", 115200);
	if (serialPort < 0) {
		perror("Could not open hardware serial port '/dev/ttyGS0'; exiting.\n");
		exit(-1);
	}
}

static void openPseudoTerminal() {
	pty = posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (pty < 0) {
		perror("Could not open pseudo terminal; exiting.\n");
		exit(-1);
	}
 	grantpt(pty);
 	unlockpt(pty);
}

int recvBytes(uint8 *buf, int count) {
	int readCount = 0;
	if (pty > 0) {
		readCount = read(pty, buf, count);
		if (readCount < 0) readCount = 0;
	} else {
		while (readCount < count) {
			if (!serialDataAvail(serialPort)) return readCount;
			buf[readCount++] = serialGetchar(serialPort);
		}
	}
	return readCount;
}

// int canReadByte() {
// 	if (pty > 0) {
// 		int bytesAvailable = 0;
// 		ioctl(pty, FIONREAD, &bytesAvailable);
// 		return (bytesAvailable > 0);
// 	}
// 	return serialDataAvail(serialPort);
// }

int sendByte(char aByte) {
	int fd = (pty > 0) ? pty : serialPort;
	return write(fd, &aByte, 1);
}

// System Functions

const char * boardType() { return "Raspberry Pi"; }
void systemReset() { } // noop on Raspberry Pi

// General Purpose I/O Pins

#define DIGITAL_PINS 32
#define ANALOG_PINS 0
#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
#define PIN_LED 0

// Pin Modes

// To speed up pin I/O, the current pin input/output mode is recorded in the currentMode[]
// array to avoid calling pinMode() unless the pin mode has actually changed.

static char currentMode[TOTAL_PINS];

#define MODE_NOT_SET (-1)

#define SET_MODE(pin, newMode) { \
	if ((newMode) != currentMode[pin]) { \
		pinMode((pin), newMode); \
		currentMode[pin] = newMode; \
	} \
}

static void initPins(void) {
	// Initialize currentMode to MODE_NOT_SET (neigher INPUT nor OUTPUT)
	// to force the pin's mode to be set on first use.

	for (int i = 0; i < TOTAL_PINS; i++) currentMode[i] = MODE_NOT_SET;
}

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }
OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(OBJ *args) { return int2obj(0); } // no analog inputs
void primAnalogWrite(OBJ *args) { } // analog output is not supported

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return falseObj;
	SET_MODE(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

void primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	primDigitalSet(pinNum, value);
}

void primDigitalSet(int pinNum, int flag) {
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return;
	SET_MODE(pinNum, OUTPUT);
	digitalWrite(pinNum, flag);
};

void primSetUserLED(OBJ *args) {
	int value = (args[1] == trueObj) ? HIGH : LOW;
	SET_MODE(PIN_LED, OUTPUT);
	digitalWrite(PIN_LED, value);
}

// I2C primitives

OBJ primI2cGet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerError);
	int deviceID = obj2int(args[0]);
	int registerID = obj2int(args[1]);
	if ((deviceID < 0) || (deviceID > 128)) return fail(i2cDeviceIDOutOfRange);
	if ((registerID < 0) || (registerID > 255)) return fail(i2cRegisterIDOutOfRange);

	int fd = wiringPiI2CSetup(deviceID);
	int result = wiringPiI2CReadReg8 (fd, registerID);
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

// Not yet implemented

OBJ primSPISend(OBJ *args) { return int2obj(0); }
OBJ primSPIRecv(OBJ *args) { return int2obj(0); }

// Stubs for micro:bit/Calliope primitives

void primMBDisplay(OBJ *args) { }
void primMBDisplayOff(OBJ *args) { }
void primMBPlot(OBJ *args) { }
void primMBUnplot(OBJ *args) { }
OBJ primMBTiltX(OBJ *args) { return int2obj(0); }
OBJ primMBTiltY(OBJ *args) { return int2obj(0); }
OBJ primMBTiltZ(OBJ *args) { return int2obj(0); }
OBJ primMBTemp(OBJ *args) { return int2obj(0); }
OBJ primButtonA(OBJ *args) { return falseObj; }
OBJ primButtonB(OBJ *args) { return falseObj; }

void primNeoPixelSend(OBJ *args) { }
void primNeoPixelSetPin(int argCount, OBJ *args) { }
void primMBDrawShape(int argCount, OBJ *args) { }
OBJ primMBShapeForLetter(OBJ *args) { return int2obj(0); }

// Other bogus primitives

void resetServos() {}
void stopTone() {}
void turnOffInternalNeoPixels() {}
void turnOffPins() {}
void addDisplayPrims() {}
void addIOPrims() {}
void addNetPrims() {}
void primWifiConnect(OBJ *args) {}
int wifiStatus() { return 0; }
OBJ primMakeWebThing(int argCount, OBJ *args) { return falseObj; }
OBJ primGetIP(int argCount, OBJ *args) { return falseObj; }

// Raspberry Pi Main

int main(int argc, char *argv[]) {
	if (argc == 1) {
		openHardwareSerialPort();
	} else if ((argc == 2) && strcmp("-p", argv[1]) == 0) {
		openPseudoTerminal();
	} else {
		printf("Use '-p' to use a pseduoterminal, no arguments for hardware serial port\n");
		exit(-1);
	}

	wiringPiSetup();
	initTimers();
	initPins();
	memInit(5000); // 5k words = 20k bytes
	restoreScripts();
	startAll();
	printf("MicroBlocks is running...\n");
	if (pty >= 0) printf("Connect on pseduoterminal %s\n", ptsname(pty));
	outputString("Welcome to uBlocks for Raspberry Pi!");
	vmLoop();
}
