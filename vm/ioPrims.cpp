// ioPrims.cpp - Microblocks IO primitives and hardware dependent functions
// John Maloney, April 2017

#include "Arduino.h"
#include "Wire.h"
#include <stdio.h>

#include "mem.h"
#include "interp.h"

static void initPins(void); // forward reference

// Timing Functions

#ifdef NRF51

static char *clock_base = (char *) 0x40008000;

void initClock_NRF51() {
	*((int *) (clock_base + 0x010)) = 1; // shutdown & clear
	*((int *) (clock_base + 0x504)) = 0; // timer mode
	*((int *) (clock_base + 0x508)) = 3; // 32-bit
	*((int *) (clock_base + 0x510)) = 4; // prescale - divides 16MHz by 2^N
	*((int *) (clock_base + 0x0)) = 1; // start
}

uint32 microsecs() {
	*((int *) (clock_base + 0x40)) = 1; // capture into cc1
	return *((uint32 *) (clock_base + 0x540)); // return contents of cc1
}

uint32 millisecs() {
	// Approximate milliseconds as (usecs / 1024) using a bitshift, since divide is very slow.
	// This avoids the need for a second hardware timer for milliseconds, but the millisecond
	// clock is effectively only 22 bits, and (like the microseconds clock) it wraps around
	// every 72 minutes.

	return microsecs() >> 10;
}

void hardwareInit() {
	initClock_NRF51();
	initPins();
	Wire.begin();
}

#else

uint32 microsecs() { return (uint32) micros(); }
uint32 millisecs() { return (uint32) millis(); }

void hardwareInit() {
	initPins();
}

#endif

// Communciation/System Functions

void putSerial(char *s) { Serial.print(s); } // callable from C; used to simulate printf for debugging

int readBytes(uint8 *buf, int count) {
	int bytesRead = Serial.available();
	for (int i = 0; i < bytesRead; i++) {
		buf[i] = Serial.read();
	}
	return bytesRead;
}

int canReadByte() { return Serial.available(); }
int canSendByte() { return true; } // Serial.availableForWrite not implemented for Primo
void sendByte(char aByte) { Serial.write(aByte); }

// System Reset

void systemReset() { NVIC_SystemReset(); }

// General Purpose I/O Pins

#ifdef ARDUINO_SAM_DUE // Arduino DUE

	#define DIGITAL_PINS 54
	#define ANALOG_PINS 12
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11};

#endif

#ifdef ARDUINO_NRF52_PRIMO // Arduino Primo

	#define DIGITAL_PINS 14
	#define ANALOG_PINS 6
	#define DEDICATED_PINS 2 // USER1_BUTTON (20) and BUZZER (21)
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS + DEDICATED_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

#endif

#ifdef ARDUINO_BBC_MICROBIT // BBC micro:bit

	#define DIGITAL_PINS 29
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

	// See variant.cpp in variants/BBCMicrobit folder for a detailed pin map.
	// Pins 0-20 are for micro:bit pads and edge connector
	//   (but pin numbers 17-18 correspond to 3.3 volt pads, not actual I/O pins)
	// Pins 21-22: RX, TX (for USB Serial?)
	// Pins 23-28: COL4, COL5, COL6, ROW1, ROW2, ROW3
	// Button A: pin 5
	// Button B: pin 11
	// Analog pins: The micro:bit does not have dedicated analog input pins;
	// the analog pins are aliases for digital pins 0-4 and 10.

#endif

#ifdef ARDUINO_SAMD_MKRZERO

	#define DIGITAL_PINS 8
	#define ANALOG_PINS 7
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6};

	#define PIN_LED 32

#endif

// Pin Modes

// The current pin input/output mode is recorded in the currentMode[] array to
// avoid calling pinMode() unless mode has actually changed. (This speeds up pin I/O.)

#define MODE_NOT_SET (-1)
static char currentMode[TOTAL_PINS];

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
	#ifdef ARDUINO_NRF52_PRIMO
		pinMode(USER1_BUTTON, INPUT);
		pinMode(BUZZER, OUTPUT);
	#endif
}

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

static OBJ needs8BitIntFailure() { return failure(needs8BitIntError, "All arguments must be integers in the range 0-255"); }

OBJ primI2cGet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) return needs8BitIntFailure();
	int deviceID = obj2int(args[0]) & 127;
	int registerID = obj2int(args[1]) & 255;

	Wire.beginTransmission(deviceID);
	Wire.write(registerID);
	int error = Wire.endTransmission(false);
	if (error) return int2obj(0 - error);  // error; bad device ID?

	Wire.requestFrom(deviceID, 1);
	while (!Wire.available());
	return int2obj(Wire.read());
}

OBJ primI2cSet(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) return needs8BitIntFailure();
	int deviceID = obj2int(args[0]) & 127;
	int registerID = obj2int(args[1]) & 255;
	int value = obj2int(args[2]) & 255;

	Wire.beginTransmission(deviceID);
	Wire.write(registerID);
	Wire.write(value);
	Wire.endTransmission();

	return nilObj;
}
