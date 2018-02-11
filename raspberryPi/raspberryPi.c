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

int readBytes(uint8 *buf, int count) {
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

int canReadByte() {
	if (pty > 0) {
		int bytesAvailable = 0;
		ioctl(pty, FIONREAD, &bytesAvailable);
		return (bytesAvailable > 0);
	}
	return serialDataAvail(serialPort);
}

int sendByte(char aByte) {
	int fd = (pty > 0) ? pty : serialPort;
	return write(fd, &aByte, 1);
}

// System Functions

const char * boardType() { return "Raspberry Pi"; }
void systemReset() { } // noop on Raspberry Pi

// General Purpose I/O Pins

#define DIGITAL_PINS 17
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
OBJ primAnalogWrite(OBJ *args) { return nilObj; } // analog output not supported

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return nilObj;
	SET_MODE(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return nilObj;
	SET_MODE(pinNum, OUTPUT);
	digitalWrite(pinNum, value);
	return nilObj;
}

OBJ primSetLED(OBJ *args) {
	int value = (args[1] == trueObj) ? HIGH : LOW;
	SET_MODE(PIN_LED, OUTPUT);
	digitalWrite(PIN_LED, value);
	return nilObj;
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
	return nilObj;
}

// Not yet implemented

OBJ primSPISend(OBJ *args) { return nilObj; }
OBJ primSPIRecv(OBJ *args) { return nilObj; }

// Stubs for micro:bit primitives

OBJ primMBDisplay(OBJ *args) { return nilObj; }
OBJ primMBDisplayOff(OBJ *args) { return nilObj; }
OBJ primMBPlot(OBJ *args) { return nilObj; }
OBJ primMBUnplot(OBJ *args) { return nilObj; }
OBJ primMBTiltX(OBJ *args) { return nilObj; }
OBJ primMBTiltY(OBJ *args) { return nilObj; }
OBJ primMBTiltZ(OBJ *args) { return nilObj; }
OBJ primMBTemp(OBJ *args) { return nilObj; }
OBJ primMBButtonA(OBJ *args) { return nilObj; }
OBJ primMBButtonB(OBJ *args) { return nilObj; }

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
