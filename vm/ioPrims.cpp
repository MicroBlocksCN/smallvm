/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// ioPrims.cpp - Microblocks IO primitives and hardware dependent functions
// John Maloney, April 2017

#include <Arduino.h>
#include <stdio.h>

#include "mem.h"
#include "interp.h"

#if defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
	// Redefine serial port mapping for Samw25x to use "Target USB" port
	// The default "Debug USB" port fails to accept long scripts.
	#undef Serial
	#define Serial SerialUSB
#endif

static void initPins(void); // forward reference

// Timing Functions and Hardware Initialization

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
	// Note: The divide operation makes this slower than microsecs(), so use microsecs()
	// when high-performance is needed. The millisecond clock is effectively only 22 bits
	// so, like the microseconds clock, it wraps around every 72 minutes.

	return microsecs() / 1000;
}

static void initRandomSeed() {
	// Initialize the random number generator with a random seed when started (if possible).
	// Not yet implemented; will use nrf51 hardware RNG
}

void hardwareInit() {
	Serial.begin(115200);
	initClock_NRF51();
	initPins();
	initRandomSeed();
	turnOffInternalNeoPixels();
}

#else // not NRF51

  #if (defined(ARDUINO_SAMD_ZERO) || defined(ARDUINO_SAM_ZERO)) && defined(SERIAL_PORT_USBVIRTUAL)
	#undef Serial
	#define Serial SERIAL_PORT_USBVIRTUAL
  #endif

uint32 microsecs() { return (uint32) micros(); }
uint32 millisecs() { return (uint32) millis(); }

static void initRandomSeed() {
	// Initialize the random number generator with a random seed when started (if possible).

	#if defined(ESP8266)
		randomSeed(RANDOM_REG32);
	#elif defined(ARDUINO_ARCH_ESP32)
		randomSeed(esp_random());
	#else
		// Not yet implemented for non-ESP boards: collect some random bits from analog pins
	#endif
}

void hardwareInit() {
	Serial.begin(115200);
	initPins();
	initRandomSeed();
	turnOffInternalNeoPixels();
	#if defined(ARDUINO_CITILAB_ED1)
		dacWrite(26, 0); // prevents serial TX noise on buzzer
        	touchSetCycles(0x800, 0x800);
	#endif
	#if defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_M5Stack_Core_ESP32)
		tftInit();
	#endif
}

#endif

// Communication Functions

void putSerial(char *s) { Serial.print(s); } // callable from C; used to simulate printf for debugging

int recvBytes(uint8 *buf, int count) {
	int bytesRead = Serial.available();
	if (bytesRead > count) bytesRead = count; // there is only enough room for count bytes
	for (int i = 0; i < bytesRead; i++) {
		buf[i] = Serial.read();
	}
	return bytesRead;
}

int sendByte(char aByte) { return Serial.write(aByte); }

void restartSerial() {
 	Serial.end();
 	Serial.begin(115200);
}

// General Purpose I/O Pins

#define BUTTON_PRESSED LOW

#if defined(ARDUINO_SAMD_MKR1000) || defined(ARDUINO_SAMD_MKRWIFI1010) || \
	defined(ARDUINO_SAMD_MKRZERO) || defined(ARDUINO_SAMD_MKRFox1200) || \
	defined(ARDUINO_SAMD_MKRGSM1400) || defined(ARDUINO_SAMD_MKRWAN1300)
		#define ARDUINO_SAMD_MKR
#endif

#if defined(ARDUINO_SAM_DUE)

	#define BOARD_TYPE "Due"
	#define DIGITAL_PINS 54
	#define ANALOG_PINS 14
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, DAC0, DAC1};

#elif defined(ARDUINO_NRF52_PRIMO)
	// Special pins: USER1_BUTTON (22->34) and BUZZER (23->35)

	#define BOARD_TYPE "Primo"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};
	#define PIN_BUTTON_A 34

#elif defined(ARDUINO_BBC_MICROBIT)

	#define BOARD_TYPE "micro:bit"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

	// See variant.cpp in variants/BBCMicrobit folder for a detailed pin map.
	// Pins 0-20 are for micro:bit pads and edge connector
	//	(but pin numbers 17-18 correspond to 3.3 volt pads, not actual I/O pins)
	// Pins 21-22: RX, TX (for USB Serial?)
	// Pins 23-28: COL4, COL5, COL6, ROW1, ROW2, ROW3
	// Button A: pin 5
	// Button B: pin 11
	// Analog pins: The micro:bit does not have dedicated analog input pins;
	// the analog pins are aliases for digital pins 0-4 and 10.

#elif defined(ARDUINO_CALLIOPE_MINI)

	#define BOARD_TYPE "Calliope"
	#define DIGITAL_PINS 26
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

	// See variant.cpp in variants/Calliope folder for a detailed pin map.
	// Pins 0-19 are for the large pads and 26 pin connector
	// Button A: pin 20
	// Microphone: pin 21
	// Button B: pin 22
	// Motor/Speaker: pins 23-25
	// Analog pins: The Calliope does not have dedicated analog input pins;
	// the analog pins are aliases for digital pins 6, 1, 2, 21 (microphone), 4, 5.

#elif defined(ARDUINO_SINOBIT)

	#define BOARD_TYPE "sino:bit"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

	// See variant.cpp in variants/Sinbit folder for a detailed pin map.
	// Pins 0-19 are for the large pads and 26 pin connector
	//	(but pin numbers 17-18 correspond to 3.3 volt pads, not actual I/O pins)
	// Pins 21-22: RX, TX (for USB Serial?)
	// Pins 23-28: COL4, COL5, COL6, ROW1, ROW2, ROW3
	// Button A: pin 5
	// Button B: pin 11
	// Analog pins: The sino:bit does not have dedicated analog input pins;
	// the analog pins are aliases for digital pins 0-4 and 10.

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)
	// Note: This case muse come before the ARDUINO_SAMD_ZERO case.
	// Note: Pin count does not include pins 36-38, the USB serial pins

	#define BOARD_TYPE "CircuitPlayground"
	#define DIGITAL_PINS 27
	#define ANALOG_PINS 11
	#define TOTAL_PINS 27
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10};
	#define PIN_BUTTON_A 4
	#define PIN_BUTTON_B 5
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH

#elif defined(ADAFRUIT_GEMMA_M0)

	#define BOARD_TYPE "Gemma M0"
	#define DIGITAL_PINS 5
	#define ANALOG_PINS 3
	#define TOTAL_PINS 14
	static const int analogPin[] = {A0, A1, A2};

#elif defined(ADAFRUIT_ITSYBITSY_M0)

	#define BOARD_TYPE "Itsy Bitsy M0"
	#define DIGITAL_PINS 28
	#define ANALOG_PINS 12
	#define TOTAL_PINS 42
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11};

#elif defined(ADAFRUIT_TRINKET_M0)

	#define BOARD_TYPE "Trinket M0"
	#define DIGITAL_PINS 7
	#define ANALOG_PINS 5
	#define TOTAL_PINS 14
	static const int analogPin[] = {A0, A1, A2, A3, A4};

#elif defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
	// Note: The VM for this board can only be built with PlatformIO.
	// Note: This case must come before the ARDUINO_SAMD_MKR case when using PlatformIO.

	#define BOARD_TYPE "SAMW25_XPRO"
	#define DIGITAL_PINS 18
	#define ANALOG_PINS 3
	#define TOTAL_PINS DIGITAL_PINS
	#define INVERT_USER_LED true
	#define PIN_BUTTON_A 13 // PB10, pin13 in PlatformIO
	static const int analogPin[] = {A0, A1, A2};
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 1, 1, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0};

#elif defined(ARDUINO_SAMD_MKR)

	#define BOARD_TYPE "MKR Series"
	#define DIGITAL_PINS 15
	#define ANALOG_PINS 7
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6};

#elif defined(ARDUINO_SAMD_ZERO)

	#define BOARD_TYPE "Zero"
	#define DIGITAL_PINS 14
	#define ANALOG_PINS 6
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

#elif defined(ARDUINO_SAM_ZERO)

	#define BOARD_TYPE "M0"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 6
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

#elif defined(ESP8266)

	#define BOARD_TYPE "ESP8266"
	#define DIGITAL_PINS 17
	#define ANALOG_PINS 1
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0};
	#define PIN_LED LED_BUILTIN
	#define PIN_BUTTON_A 0
	#define INVERT_USER_LED true
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1};

#elif defined(ARDUINO_CITILAB_ED1)

	#define BOARD_TYPE "Citilab ED1"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	static const char reservedPin[TOTAL_PINS] = {
		1, 0, 1, 0, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 1, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
		0, 0, 1, 0, 1, 0, 0, 0, 0, 0};
	#define PIN_LED 0
	#define PIN_BUTTON_A 15
	#define PIN_BUTTON_B 14

#elif defined(ARDUINO_M5Stack_Core_ESP32)

	#define BOARD_TYPE "M5Stack-Core"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 39
	#define PIN_BUTTON_B 38
	#ifdef BUILTIN_LED
		#define PIN_LED BUILTIN_LED
	#else
		#define PIN_LED 2
	#endif
	#ifdef KEY_BUILTIN
		#define PIN_BUTTON_A KEY_BUILTIN
	#endif
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 0, 1, 1, 0, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 1, 0, 0, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 1, 1};

#elif defined(ARDUINO_ARCH_ESP32)
	#ifdef ARDUINO_IOT_BUS
		#define BOARD_TYPE "IOT-BUS"
	#else
		#define BOARD_TYPE "ESP32"
	#endif
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 15
	#define PIN_BUTTON_B 14
	#ifdef BUILTIN_LED
		#define PIN_LED BUILTIN_LED
	#else
		#define PIN_LED 2
	#endif
	#ifdef KEY_BUILTIN
		#define PIN_BUTTON_A KEY_BUILTIN
	#endif
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};

#else // unknown board

	#define BOARD_TYPE "Unknown Board"
	#define DIGITAL_PINS 0
	#define ANALOG_PINS 0
	#define TOTAL_PINS 0
	static const int analogPin[] = {};
	#define PIN_LED 0

#endif

// Board Type

const char * boardType() { return BOARD_TYPE; }

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

// Check for reserved pin on boards that define a reservedPin array
#define RESERVED(pin) (((pin) < 0) || ((pin) >= TOTAL_PINS) || (reservedPin[(pin)]))

int pinCount() { return TOTAL_PINS; }

void setPinMode(int pin, int newMode) {
	// Function to set pin modes from other modules. (The SET_MODE macro is local to this file.)

	SET_MODE(pin, newMode);
}

static void initPins(void) {
	// Initialize currentMode to MODE_NOT_SET (neither INPUT nor OUTPUT)
	// to force the pin's mode to be set on first use.

	#if !defined(ESP8266) && !defined(ARDUINO_ARCH_ESP32)
		analogWriteResolution(10); // 0-1023; low-order bits ignored on boards with lower resolution
	#endif

	for (int i = 0; i < TOTAL_PINS; i++) {
		currentMode[i] = MODE_NOT_SET;
	}

	#ifdef ARDUINO_NRF52_PRIMO
		pinMode(USER1_BUTTON, INPUT);
		pinMode(BUZZER, OUTPUT);
	#endif

	#ifdef ARDUINO_CITILAB_ED1
		// set up buttons
		pinMode(2, INPUT_PULLUP); // ←
		pinMode(4, INPUT_PULLUP); // ↑
		pinMode(13, INPUT_PULLUP); // ↓
		pinMode(14, INPUT_PULLUP); // X
		pinMode(15, INPUT_PULLUP); // OK
		pinMode(27, INPUT_PULLUP); // →
	#endif
}

void turnOffPins() {
	for (int pin = 0; pin < TOTAL_PINS; pin++) {
		if (OUTPUT == currentMode[pin]) {
			pinMode(pin, INPUT);
			currentMode[pin] = INPUT;
		}
	}
}

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }

OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	#ifdef ARDUINO_ARCH_ESP32
		// use the ESP32 pin number directly (if not reserved)
		if (RESERVED(pinNum)) return int2obj(0);
		SET_MODE(pinNum, INPUT);
		return int2obj(analogRead(pinNum) >> 2); // convert from 12-bit to 10-bit resolution
	#elif defined(ARDUINO_SAM_DUE)
		if (pinNum < 2) return int2obj(0);
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return int2obj(0);
	#endif
	if ((pinNum < 0) || (pinNum >= ANALOG_PINS)) return int2obj(0);
	int pin = analogPin[pinNum];
	SET_MODE(pin, INPUT);
	return int2obj(analogRead(pin));
}

void primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		if (pinNum > 25) return;
	#elif defined(ADAFRUIT_TRINKET_M0)
		if (pinNum > 4) return;
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		if (RESERVED(pinNum)) return;
	#elif defined(ARDUINO_SAM_DUE)
		if (pinNum < 2) return;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return;
	#endif
	int value = obj2int(args[1]);
	if (value < 0) value = 0;
	if (value > 1023) value = 1023;
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return;
	SET_MODE(pinNum, OUTPUT);
	#ifndef ARDUINO_ARCH_ESP32
		analogWrite(pinNum, value); // sets the PWM duty cycle on a digital pin
	#endif
}

OBJ primDigitalRead(int argCount, OBJ *args) {
	int pinNum = obj2int(args[0]);
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		if (pinNum > 25) return falseObj;
	#elif defined(ADAFRUIT_TRINKET_M0)
		if (pinNum > 4) return falseObj;
	#elif defined(ARDUINO_NRF52_PRIMO)
		if (22 == pinNum) return (LOW == digitalRead(USER1_BUTTON)) ? trueObj : falseObj;
		if (23 == pinNum) return falseObj;
	#elif defined(ARDUINO_SAM_DUE)
		if (pinNum < 2) return falseObj;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return falseObj;
	#elif defined(ARDUINO_CITILAB_ED1)
		if (pinNum == 2 || pinNum == 4 || pinNum == 13 ||
			pinNum == 14 || pinNum == 15 || pinNum == 27) {
			// Do not reset pin mode, it should remain INPUT_PULLUP as set in initPins.
			// These buttons are reversed, too.
			return (HIGH == digitalRead(pinNum)) ? falseObj : trueObj;
		}
		if (RESERVED(pinNum)) return falseObj;
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		if (RESERVED(pinNum)) return falseObj;
	#endif
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return falseObj;
	int mode = INPUT;
	if ((argCount > 1) && (trueObj == args[1])) mode = INPUT_PULLUP;
	#ifdef ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS
		if (7 == pinNum) mode = INPUT_PULLUP; // slide switch
	#endif
	SET_MODE(pinNum, mode);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

void primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	#if defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		if (RESERVED(pinNum)) return;
	#elif defined(ARDUINO_SAM_DUE)
		if (pinNum < 2) return;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return;
	#endif
	int flag = (trueObj == args[1]);
	primDigitalSet(pinNum, flag);
}

void primDigitalSet(int pinNum, int flag) {
	// This supports a compiler optimization. If the arguments of a digitalWrite
	// are compile-time constants, the compiler can generate a digitalSet or digitalClear
	// instruction, thus saving the cost of pushing the pin number and boolean.
	// (This can make a difference in time-sensitives applications like sound generation.)
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return;
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		// Map pins 26 & 27 to the DotStar LED (internal pins 41 and 40)
		if (pinNum == 26) pinNum = 41; // DotStar data
		else if (pinNum == 27) pinNum = 40; // DotStar clock
		else if (pinNum > 27) return;
	#elif defined(ADAFRUIT_TRINKET_M0)
		// Map pins 5 & 6 to the DotStar LED (internal pins 7 and 8)
		if (pinNum == 5) pinNum = 7;
		else if (pinNum == 6) pinNum = 8;
		else if (pinNum > 6) return;
	#elif defined(ARDUINO_NRF52_PRIMO)
		if (22 == pinNum) return;
		if (23 == pinNum) { digitalWrite(BUZZER, (flag ? HIGH : LOW)); return; }
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		if (RESERVED(pinNum)) return;
	#elif defined(ARDUINO_SAM_DUE)
		if (pinNum < 2) return;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return;
	#endif
	SET_MODE(pinNum, OUTPUT);
	digitalWrite(pinNum, (flag ? HIGH : LOW));
}

// User LED

void primSetUserLED(OBJ *args) {
	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE_MINI)
		// Special case: Plot or unplot one LED in the LED matrix.
		OBJ coords[2] = { int2obj(3), int2obj(1) };
		if (trueObj == args[0]) {
			primMBPlot(2, coords);
		} else {
			primMBUnplot(2, coords);
		}
	#elif defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_M5Stack_Core_ESP32)
		tftSetHugePixel(3, 1, (trueObj == args[0]));
	#else
		if (PIN_LED < TOTAL_PINS) {
			SET_MODE(PIN_LED, OUTPUT);
		} else {
			pinMode(PIN_LED, OUTPUT);
		}
		int output = (trueObj == args[0]) ? HIGH : LOW;
		#ifdef INVERT_USER_LED
			output = !output;
		#endif
		digitalWrite(PIN_LED, output);
	#endif
}

// User Buttons

OBJ primButtonA(OBJ *args) {
	#ifdef ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS
		// Momentarily set button pin low before reading (simulates a pull-down resistor)
		primDigitalSet(PIN_BUTTON_A, false);
	#endif
	#ifdef PIN_BUTTON_A
		#if defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
			SET_MODE(PIN_BUTTON_A, INPUT_PULLUP);
		#else
			SET_MODE(PIN_BUTTON_A, INPUT);
		#endif
		return (BUTTON_PRESSED == digitalRead(PIN_BUTTON_A)) ? trueObj : falseObj;
	#else
		return falseObj;
	#endif
}

OBJ primButtonB(OBJ *args) {
	#ifdef ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS
		// Momentarily set button pin low before reading (simulates a pull-down resistor)
		primDigitalSet(PIN_BUTTON_B, false);
	#endif
	#ifdef PIN_BUTTON_B
		#if defined(ARDUINO_CITILAB_ED1)
			SET_MODE(PIN_BUTTON_A, INPUT_PULLUP);
		#else
			SET_MODE(PIN_BUTTON_B, INPUT);
		#endif
		return (BUTTON_PRESSED == digitalRead(PIN_BUTTON_B)) ? trueObj : falseObj;
	#else
		return falseObj;
	#endif
}

// Servo

#define HAS_SERVO !(defined(NRF51) || defined(ARDUINO_NRF52_PRIMO) || defined(ESP32))

#if HAS_SERVO
	#include <Servo.h>
	Servo servo[DIGITAL_PINS];
#endif

void resetServos() {
	#if HAS_SERVO
		for (int pin = 0; pin < DIGITAL_PINS; pin++) {
			if (servo[pin].attached()) servo[pin].detach();
		}
	#endif
}

OBJ primHasServo(int argCount, OBJ *args) {
	#if HAS_SERVO
		return trueObj;
	#else
		return falseObj;
	#endif
}

OBJ primSetServo(int argCount, OBJ *args) {
	// setServo <pin> <usecs>
	// If usecs > 0, generate a servo control signal with the given pulse width
	// on the given pin. If usecs <= 0 stop generating the servo signal.
	// Return true on success, false if primitive is not supported.
	#if HAS_SERVO
		OBJ pinArg = args[0];
		OBJ usecsArg = args[1];
		if (!isInt(pinArg) || !isInt(usecsArg)) return falseObj;
		int pin = obj2int(pinArg);
		if ((pin < 0) || (pin >= DIGITAL_PINS)) return falseObj;
		int usecs = obj2int(usecsArg);
		if (usecs > 15000) usecs = 15000; // maximum pulse width is 15000 usecs
		if (usecs <= 0) {
			if (servo[pin].attached()) servo[pin].detach();
		} else {
			if (!servo[pin].attached()) servo[pin].attach(pin);
			servo[pin].writeMicroseconds(usecs);
		}
		return trueObj;
	#else
		return falseObj;
	#endif
}

// Tone Generation

#define HAS_TONE !(defined(NRF51) || defined(ESP32) || defined(ARDUINO_SAM_DUE))

int tonePin = -1;

#ifdef ESP32
	static void initESP32Tone(int pin) {
		if (pin == tonePin) return;
		if (tonePin < 0) {
			ledcSetup(0, 1E5, 12); // do setup on first call
		} else {
			ledcWrite(0, 0); // stop current tone, if any
 			ledcDetachPin(tonePin);
		}
		tonePin = pin;
	}
#endif

void stopTone() {
	#if HAS_TONE
		if (tonePin >= 0) noTone(tonePin);
		tonePin = -1;
	#elif defined(ESP32)
		if (tonePin >= 0) {
			ledcWrite(0, 0);
 			ledcDetachPin(tonePin);
		}
	#endif
}

OBJ primHasTone(int argCount, OBJ *args) {
	#if (HAS_TONE || defined(ESP32))
		return trueObj;
	#else
		return falseObj;
	#endif
}

OBJ primPlayTone(int argCount, OBJ *args) {
	// playTone <pin> <freq>
	// If freq > 0, generate a 50% duty cycle square wave of the given frequency
	// on the given pin. If freq <= 0 stop generating the square wave.
	// Return true on success, false if primitive is not supported.

	OBJ pinArg = args[0];
	OBJ freqArg = args[1];
	if (!isInt(pinArg) || !isInt(freqArg)) return falseObj;
	int pin = obj2int(pinArg);
	if ((pin < 0) || (pin >= DIGITAL_PINS)) return falseObj;

	#if HAS_TONE
		int frequency = obj2int(freqArg);
		if ((frequency > 0) && (frequency <= 500000)) {
			if (pin != tonePin) stopTone();
			tonePin = pin;
			tone(tonePin, frequency);
		} else {
			stopTone();
		}
		return trueObj;
	#elif defined(ESP32)
		int frequency = obj2int(freqArg);
		if ((frequency > 0) && (frequency <= 500000)) {
			initESP32Tone(pin);
			if (tonePin >= 0) {
				ledcAttachPin(tonePin, 0);
				ledcWriteTone(0, frequency);
			}
		} else {
			stopTone();
		}
		return trueObj;
	#else
		return falseObj;
	#endif
}

static PrimEntry entries[] = {
	"hasTone", primHasTone,
	"playTone", primPlayTone,
	"hasServo", primHasServo,
	"setServo", primSetServo,
};

void addIOPrims() {
	addPrimitiveSet("io", sizeof(entries) / sizeof(PrimEntry), entries);
}
