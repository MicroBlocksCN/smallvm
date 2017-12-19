// raspberryPi.c - Microblocks for Raspberry Pi
// John Maloney, December 2017

#include <stdio.h>
#include <wiringPi.h>
#include <wiringSerial.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Timing Functions

uint32 microsecs() { return (uint32) micros(); }
uint32 millisecs() { return (uint32) millis(); }

// Communciation/System Functions

static int serialPort;

void putSerial(char *s) { serialPuts(serialPort, s); }

int readBytes(uint8 *buf, int count) {
	int readCount = 0;
	while (readCount < count) {
		if (!serialDataAvail(serialPort)) return readCount;
		buf[readCount++] = serialGetchar(serialPort);
	}
	return readCount;
}

int canReadByte() { return serialDataAvail(serialPort); }
int canSendByte() { return true; }
void sendByte(char aByte) { serialPutchar(serialPort, aByte); }

// System Functions

void systemReset() { } // noop on Raspberry Pi

// General Purpose I/O Pins

#define DIGITAL_PINS 17
#define ANALOG_PINS 0
#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
#define PIN_LED 0

// Pin Modes

// The current pin input/output mode is recorded in the currentMode[] array to
// avoid calling pinMode() unless mode has actually changed. This speeds up pin I/O.

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

	for (int i; i < TOTAL_PINS; i++) currentMode[i] = MODE_NOT_SET;
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

OBJ primI2cGet(OBJ *args) { return int2obj(0); } // not yet implemented
OBJ primI2cSet(OBJ *args) { return nilObj; } // not yet implemented

int main() {
	wiringPiSetup();
	serialPort = serialOpen("/dev/ttyGS0", 115200);
	if (serialPort < 0) {
		printf("Could not open serial port; exiting.\n");
		return -1;
	}
	initPins();
	memInit(5000); // 5k words = 20k bytes
	restoreScripts();
	startAll();
	printf("MicroBlocks is running...\n");
	outputString("Welcome to uBlocks for Raspberry Pi!");
	vmLoop();
}
