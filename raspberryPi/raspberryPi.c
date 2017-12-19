// raspberryPi.c - Microblocks for Raspberry Pi
// John Maloney, December 2017

#include <stdio.h>
#include <wiringPi.h>
#include <wiringSerial.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

static void initPins(void); // forward reference

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

#define DIGITAL_PINS 0
#define ANALOG_PINS 0
#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
static const int analogPin[] = {};
#define PIN_LED 0

#define LOW 0
#define HIGH 1

// Pin Modes

// The current pin input/output mode is recorded in the currentMode[] array to
// avoid calling pinMode() unless mode has actually changed. (This speeds up pin I/O.)

#define MODE_NOT_SET (-1)
static char currentMode[TOTAL_PINS];

#define SET_MODE(pin, newMode) { }
static void initPins(void) { }

int analogRead(int pinNum) { return 0; }
void analogWrite(int pinNum, int value) { }

int digitalRead(int pinNum) { return 0; }
void digitalWrite(int pinNum, int value) { }

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }

OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum >= ANALOG_PINS)) return int2obj(0);
	int pin = analogPin[pinNum];
	SET_MODE(pin, INPUT);
	return int2obj(analogRead(pin));
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = obj2int(args[1]);
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return nilObj;
	SET_MODE(pinNum, OUTPUT);
	analogWrite(pinNum, value); // sets the PWM duty cycle on a digital pin
	return nilObj;
}

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return nilObj;
	#ifdef ARDUINO_NRF52_PRIMO
		if (20 == pinNum) return (HIGH == digitalRead(USER1_BUTTON)) ? trueObj : falseObj;
		if (21 == pinNum) return falseObj;
	#endif
	SET_MODE(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return nilObj;
	#ifdef ARDUINO_NRF52_PRIMO
		if (20 == pinNum) return nilObj;
		if (21 == pinNum) { digitalWrite(BUZZER, value); return nilObj; }
	#endif
	SET_MODE(pinNum, OUTPUT);
	digitalWrite(pinNum, value);
	return nilObj;
}

OBJ primSetLED(OBJ *args) {
	 #ifdef ARDUINO_BBC_MICROBIT
		// Special case: Use a row-column compinaton to turn on one LED in the LED matrix.
		const int col2 = 4;
		const int row1 = 26;
		SET_MODE(col2, OUTPUT);
		SET_MODE(row1, OUTPUT);
		if (trueObj == args[0]) {
			digitalWrite(col2, LOW);
			digitalWrite(row1, HIGH);
		} else {
			digitalWrite(col2, HIGH);
			digitalWrite(row1, LOW);
		}
	#else
		SET_MODE(PIN_LED, OUTPUT);
		digitalWrite(PIN_LED, (trueObj == args[0]) ? HIGH : LOW);
	#endif
	return nilObj;
}

OBJ primI2cGet(OBJ *args) { return nilObj; } // not implemented
OBJ primI2cSet(OBJ *args) { return nilObj; } // not implemented

int main() {
	serialPort = serialOpen("/dev/ttyGS0", 115200);
	if (serialPort < 0) {
		printf("Could not open serial port; exiting.\n");
		return -1;
	}
	printf("Serial port: %d\n", serialPort);
// 	while (true) {
// 		if (canReadByte()) {
// 			char ch = serialGetchar(serialPort);
// 			printf("Char: %d\n", ch);
// 			sendByte(ch - 32);
// 		}
// 	}

	memInit(5000); // 5k words = 20k bytes
	restoreScripts();
	startAll();
	outputString("Welcome to uBlocks for Raspberry Pi!");
	vmLoop();
}
