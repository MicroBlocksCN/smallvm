/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// ioPrims.cpp - Microblocks IO primitives and hardware dependent functions
// John Maloney, April 2017

#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

#if defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
	// Redefine serial port mapping for Samw25x to use "Target USB" port
	// The default "Debug USB" port fails to accept long scripts.
	#undef Serial
	#define Serial SerialUSB
#endif

static void initPins(void); // forward reference
static void initRandomSeed(void); // forward reference

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

void hardwareInit() {
	Serial.begin(115200);
	initPins();
	initRandomSeed();
	turnOffInternalNeoPixels();
	#if defined(ARDUINO_CITILAB_ED1)
		dacWrite(26, 0); // prevents serial TX noise on buzzer
		touchSetCycles(0x800, 0x800);
	#endif
	#if defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5Stick_C)
		tftInit();
	#endif
}

#endif

// Communication Functions

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
	#define DIGITAL_PINS 16
	#define ANALOG_PINS 11
	#define TOTAL_PINS 27
	static const int analogPin[11] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10};
	static const char digitalPin[16] = {12, 6, 9, 10, 3, 2, 0, 1, 4, 5, 7, 26, 25, 13, 8, 11};
	#define PIN_BUTTON_A 4
	#define PIN_BUTTON_B 5
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH

#elif defined(ARDUINO_NRF52840_CIRCUITPLAY)

	#define BOARD_TYPE "CircuitPlayground Bluefruit"
	#define DIGITAL_PINS 15
	#define ANALOG_PINS 10
	#define TOTAL_PINS 27
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9};
	static const char digitalPin[15] = {12, 6, 9, 10, 3, 2, 0, 1, 4, 5, 7, 25, 26, 13, 8};
	#define PIN_LED 13
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
	#define ANALOG_PINS 4
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 1, 0, 0, 0, 0, 0, 0};
	#define PIN_LED 0
	#define PIN_BUTTON_A 15
	#define PIN_BUTTON_B 14
	static const char analogPinMappings[4] = { 36, 37, 38, 39 };
	static const char digitalPinMappings[4] = { 12, 25, 32, 26 };
	#define CAP_THRESHOLD 16
	static const char buttonsPins[6] = { 2, 4, 13, 14, 15, 27 };
	static int buttonIndex = 0;
	int buttonReadings[6] = {
		CAP_THRESHOLD + 1, CAP_THRESHOLD, CAP_THRESHOLD,
		CAP_THRESHOLD, CAP_THRESHOLD, CAP_THRESHOLD };

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

#elif defined(ARDUINO_M5Stick_C)

	#define BOARD_TYPE "M5StickC"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 37
	#define PIN_BUTTON_B 39
	#define PIN_LED 10
	#define INVERT_USER_LED true
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 1, 1, 1, 1, 1, 1, 1, 0,
		0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
		1, 1, 0, 0, 0, 1, 0, 0, 1, 0};

#elif defined(ARDUINO_M5Atom_Matrix_ESP32)

	#define BOARD_TYPE "M5Atom-Matrix"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 39
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 0, 1, 1, 1, 1, 1, 1, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 1, 1, 1, 1, 1, 0};

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

int mapDigitalPinNum(int userPinNum) {
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		if ((0 <= userPinNum) && (userPinNum < DIGITAL_PINS)) return digitalPin[userPinNum];
	#endif
	return userPinNum;
}

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }

OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(int argCount, OBJ *args) {
	if (!isInt(args[0])) { fail(needsIntegerError); return int2obj(0); }
	int pinNum = obj2int(args[0]);
	#ifdef ARDUINO_CITILAB_ED1
		if ((100 <= pinNum) && (pinNum <= 139)) {
			pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			pinNum = analogPinMappings[pinNum - 1];
		}
	#endif
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
	if ((argCount > 1) && (trueObj == args[1])) { pinMode(pin, INPUT_PULLUP); }
	return int2obj(analogRead(pin));
}

#if defined(ESP32)
	#define MAX_ESP32_CHANNELS 8 // MAX 16
	int esp32Channels[MAX_ESP32_CHANNELS];

	int pinAttached(int pin) {
		// Note: channel 0 is used by Tone
		if (!pin) return 0;
		for (int i = 1; i < MAX_ESP32_CHANNELS; i++) {
			if (esp32Channels[i] == pin) return i;
		}
		return 0; // not attached
	}

	void analogAttach(int pin) {
		int esp32Channel = 1;
		while ((esp32Channel < MAX_ESP32_CHANNELS) && (esp32Channels[esp32Channel] > 0)) {
			esp32Channel++;
		}
		if (esp32Channel < MAX_ESP32_CHANNELS) {
			ledcSetup(esp32Channel, 5000, 10); // 5KHz, 10 bits
			ledcAttachPin(pin, esp32Channel);
			esp32Channels[esp32Channel] = pin;
		}
	}

	void pinDetach(int pin) {
		int esp32Channel = pinAttached(pin);
		if (esp32Channel > 0) {
			ledcWrite(esp32Channel, 0);
			ledcDetachPin(pin);
			esp32Channels[esp32Channel] = 0;
		}
	}

#endif

void primAnalogWrite(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) { fail(needsIntegerError); return; }
	int pinNum = obj2int(args[0]);
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		if (pinNum > 25) return;
	#elif defined(ADAFRUIT_TRINKET_M0)
		if (pinNum > 4) return;
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		#if defined(ARDUINO_CITILAB_ED1)
			if ((100 <= pinNum) && (pinNum <= 139)) {
				pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
			} else if ((1 <= pinNum) && (pinNum <= 4)) {
				pinNum = digitalPinMappings[pinNum - 1];
			}
		#endif
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
	#if defined(ARDUINO_ARCH_SAMD) && defined(PIN_DAC0)
		#if defined(ADAFRUIT_GEMMA_M0)
			if (1 == pinNum) pinNum = PIN_DAC0; // pin 1 is DAC on Gemma M0
		#else
			if (0 == pinNum) pinNum = PIN_DAC0; // pin 0 is DAC on most SAMD boards
		#endif
		if (PIN_DAC0 == pinNum) {
			SET_MODE(pinNum, INPUT);
		} else {
			SET_MODE(pinNum, OUTPUT);
		}
	#else
		SET_MODE(pinNum, OUTPUT);
	#endif
	#if defined(ESP32)
		if ((25 == pinNum) || (26 == pinNum)) { // ESP32 DAC pins
			dacWrite(pinNum, value);
			return;
		}
		if (value == 0) {
			pinDetach(pinNum);
		} else {
			if (!pinAttached(pinNum)) analogAttach(pinNum);
			int esp32Channel = pinAttached(pinNum);
			if (esp32Channel) ledcWrite(esp32Channel, value);
		}
	#else
		analogWrite(pinNum, value); // sets the PWM duty cycle on a digital pin
	#endif
}

OBJ primDigitalRead(int argCount, OBJ *args) {
	if (!isInt(args[0])) { fail(needsIntegerError); return int2obj(0); }
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
	#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		if ((0 <= pinNum) && (pinNum < DIGITAL_PINS)) {
			pinNum = digitalPin[pinNum];
		} else {
			return falseObj;
		}
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pinNum) && (pinNum <= 139)) {
			pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			pinNum = digitalPinMappings[pinNum - 1];
		}
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
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		if (7 == pinNum) mode = INPUT_PULLUP; // slide switch
	#endif
	SET_MODE(pinNum, mode);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

void primDigitalWrite(OBJ *args) {
	if (!isInt(args[0])) { fail(needsIntegerError); return; }
	int pinNum = obj2int(args[0]);
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
	#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		if ((0 <= pinNum) && (pinNum < DIGITAL_PINS)) {
			pinNum = digitalPin[pinNum];
		} else {
			return;
		}
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pinNum) && (pinNum <= 139)) {
			pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			pinNum = digitalPinMappings[pinNum - 1];
		}
		if (RESERVED(pinNum)) return;
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
	#elif defined(ARDUINO_M5Atom_Matrix_ESP32)
		// Treat the first NeoPixel as the User LED
		OBJ pin int2obj(27);
		OBJ color = (trueObj == args[0]) ? int2obj(15 << 16) : int2obj(0);
		primNeoPixelSetPin(1, &pin);
		primNeoPixelSend(1, &color);
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
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		// Momentarily set button pin low before reading (simulates a pull-down resistor)
		primDigitalSet(8, false); // use index in digitalPins array
	#endif
	#ifdef PIN_BUTTON_A
		#if defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
			SET_MODE(PIN_BUTTON_A, INPUT_PULLUP);
		#elif defined(ARDUINO_CITILAB_ED1)
			int value = touchRead(buttonsPins[buttonIndex]);

			if (value < CAP_THRESHOLD) {
				if (buttonReadings[buttonIndex] > 0) {
					buttonReadings[buttonIndex]--;
				}
				if ((value == 0) && (buttonReadings[buttonIndex] > CAP_THRESHOLD)) {
					buttonReadings[buttonIndex] = CAP_THRESHOLD;
				}
			} else {
				buttonReadings[buttonIndex] = CAP_THRESHOLD + 2; // try 3 times
			}
			buttonIndex = (buttonIndex + 1) % 6;
			return (buttonReadings[4] < CAP_THRESHOLD) ? trueObj : falseObj;
		#else
			SET_MODE(PIN_BUTTON_A, INPUT);
		#endif
		return (BUTTON_PRESSED == digitalRead(PIN_BUTTON_A)) ? trueObj : falseObj;
	#else
		return falseObj;
	#endif
}

OBJ primButtonB(OBJ *args) {
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		// Momentarily set button pin low before reading (simulates a pull-down resistor)
		primDigitalSet(9, false); // use index in digitalPins array
	#endif
	#ifdef PIN_BUTTON_B
		#if defined(ARDUINO_CITILAB_ED1)
			return (buttonReadings[3] < CAP_THRESHOLD) ? trueObj : falseObj;
		#else
			SET_MODE(PIN_BUTTON_B, INPUT);
		#endif
		return (BUTTON_PRESSED == digitalRead(PIN_BUTTON_B)) ? trueObj : falseObj;
	#else
		return falseObj;
	#endif
}

// Random number generator seed

static void initRandomSeed() {
	// Initialize the random number generator with a random seed when started (if possible).

	#if defined(ESP8266)
		randomSeed(RANDOM_REG32);
	#elif defined(ARDUINO_ARCH_ESP32)
		randomSeed(esp_random());
	#elif defined(NRF51) || defined(NRF52_SERIES)
		#define RNG_BASE 0x4000D000
		#define RNG_START (RNG_BASE)
		#define RNG_STOP (RNG_BASE + 4)
		#define RNG_VALRDY (RNG_BASE + 0x100)
		#define RNG_VALUE (RNG_BASE + 0x508)
		uint32 seed = 0;
		*((int *) RNG_START) = true; // start random number generation
		for (int i = 0; i < 4; i++) {
			while (!*((volatile int *) RNG_VALRDY)) /* wait */;
			seed = (seed << 8) | *((volatile int *) RNG_VALUE);
			*((volatile int *) RNG_VALRDY) = 0;
		}
		*((int *) RNG_STOP) = true; // end random number generation
		randomSeed(seed);
	#else
		uint32 seed = 0;
		for (int i = 0; i < ANALOG_PINS; i++) {
			int p = analogPin[i];
			pinMode(p, INPUT);
			seed = (seed << 1) ^ analogRead(p);
		}
		randomSeed(seed);
	#endif
}

// Servo and Tone

#if defined(NRF51) || defined(NRF52_SERIES)

// NRF5 Servo State

#define MAX_SERVOS 4
#define UNUSED 255

static int servoIndex = 0;
static char servoPinHigh = false;
static char servoPin[MAX_SERVOS] = {UNUSED, UNUSED, UNUSED, UNUSED};
static unsigned short servoPulseWidth[MAX_SERVOS] = {1500, 1500, 1500, 1500};

// NRF5 Tone State

static int tonePin = -1;
static unsigned short toneHalfPeriod = 1000;
static char tonePinState = 0;
static char servoToneTimerStarted = 0;

static void startServoToneTimer() {
	NRF_TIMER2->TASKS_SHUTDOWN = true;
	NRF_TIMER2->MODE = 0; // timer mode
	NRF_TIMER2->BITMODE = 0; // 16-bits
	NRF_TIMER2->PRESCALER = 4; // 1 MHz (16 MHz / 2^4)
	NRF_TIMER2->INTENSET = TIMER_INTENSET_COMPARE0_Msk | TIMER_INTENSET_COMPARE1_Msk;
	NRF_TIMER2->TASKS_START = true;
	NVIC_EnableIRQ(TIMER2_IRQn);
	servoToneTimerStarted = true;
}

extern "C" void TIMER2_IRQHandler() {
	if (NRF_TIMER2->EVENTS_COMPARE[0]) { // tone waveform generator
		int wakeTime = NRF_TIMER2->CC[0];
		NRF_TIMER2->EVENTS_COMPARE[0] = 0; // clear interrupt
		if (tonePin >= 0) {
			tonePinState = !tonePinState;
			digitalWrite(tonePin, tonePinState);
			NRF_TIMER2->CC[0] = (wakeTime + toneHalfPeriod) & 0xFFFF; // next wake time
		}
	}

	if (NRF_TIMER2->EVENTS_COMPARE[1]) { // servo waveform generator
		int wakeTime = NRF_TIMER2->CC[1] + 12;
		NRF_TIMER2->EVENTS_COMPARE[1] = 0; // clear interrupt

		if (servoPinHigh && (0 <= servoIndex) && (servoIndex < MAX_SERVOS)) {
			digitalWrite(servoPin[servoIndex], LOW); // end the current servo pulse
		}

		// find the next active servo
		servoIndex = (servoIndex + 1) % MAX_SERVOS;
		while ((servoIndex < MAX_SERVOS) && (UNUSED == servoPin[servoIndex])) {
			servoIndex++;
		}

		if (servoIndex < MAX_SERVOS) { // start servo pulse for servoIndex
			digitalWrite(servoPin[servoIndex], HIGH);
			servoPinHigh = true;
			NRF_TIMER2->CC[1] = (wakeTime + servoPulseWidth[servoIndex]) & 0xFFFF;
		} else { // idle until next set of pulses
			servoIndex = -1;
			servoPinHigh = false;
			NRF_TIMER2->CC[1] = (wakeTime + 18000) & 0xFFFF;
		}
	}
}

void stopServos() {
	for (int i = 0; i < MAX_SERVOS; i++) {
		servoPin[i] = UNUSED;
		servoPulseWidth[i] = 1500;
	}
	servoPinHigh = false;
	servoIndex = 0;
}

static void nrfDetachServo(int pin) {
	for (int i = 0; i < MAX_SERVOS; i++) {
		if (pin == servoPin[i]) {
			servoPulseWidth[i] = 1500;
			servoPin[i] = UNUSED;
		}
	}
}

static void setServo(int pin, int usecs) {
	if (!servoToneTimerStarted) startServoToneTimer();

	if (usecs <= 0) { // turn off servo
		nrfDetachServo(pin);
		return;
	}

	for (int i = 0; i < MAX_SERVOS; i++) {
		if (pin == servoPin[i]) { // update the pulse width for the given pin
			servoPulseWidth[i] = usecs;
			return;
		}
	}

	for (int i = 0; i < MAX_SERVOS; i++) {
		if (UNUSED == servoPin[i]) { // found unused servo entry
			servoPin[i] = pin;
			servoPulseWidth[i] = usecs;
			return;
		}
	}
}

#elif defined(ESP32)

static int attachServo(int pin) {
	for (int i = 1; i < MAX_ESP32_CHANNELS; i++) {
		if (0 == esp32Channels[i]) { // free channel
			ledcSetup(i, 50, 10); // 50Hz, 10 bits
			ledcAttachPin(pin, i);
			esp32Channels[i] = pin;
			return i;
		}
	}
	return 0;
}

static void setServo(int pin, int usecs) {
	if (usecs <= 0) {
		pinDetach(pin);
	} else {
		int esp32Channel = pinAttached(pin);
		if (!esp32Channel) esp32Channel = attachServo(pin);
		if (esp32Channel > 0) {
			ledcWrite(esp32Channel, usecs * 1024 / 20000);
		}
	}
}

void stopServos() {
	for (int i = 1; i < MAX_ESP32_CHANNELS; i++) {
		int pin = esp32Channels[i];
		if (pin) pinDetach(pin);
	}
}

#else // use Arduino Servo library

#include <Servo.h>
Servo servo[DIGITAL_PINS];

static void setServo(int pin, int usecs) {
	if (usecs <= 0) {
		if (servo[pin].attached()) servo[pin].detach();
	} else {
		if (!servo[pin].attached()) servo[pin].attach(pin);
		servo[pin].writeMicroseconds(usecs);
	}
}

void stopServos() {
	for (int pin = 0; pin < DIGITAL_PINS; pin++) {
		if (servo[pin].attached()) servo[pin].detach();
	}
}

#endif // servos

// Tone Generation

#if defined(NRF51) || defined(NRF52_SERIES)

static void setTone(int pin, int frequency) {
	tonePin = pin;
	toneHalfPeriod = 500000 / frequency;
	if (!servoToneTimerStarted) {
		startServoToneTimer();
	} else {
		NRF_TIMER2->TASKS_CAPTURE[2] = true;
		NRF_TIMER2->CC[0] = (NRF_TIMER2->CC[2] + toneHalfPeriod) & 0xFFFF; // update
	}
}

void stopTone() { tonePin = -1; }

#elif defined(ESP32)

int tonePin = -1;

static void initESP32Tone(int pin) {
	if ((pin == tonePin) || (pin < 0)) return;
	if (tonePin < 0) {
		tonePin = pin;
		ledcSetup(0, 1E5, 12); // do setup on first call
	} else {
		ledcWrite(0, 0); // stop current tone, if any
		ledcDetachPin(tonePin);
	}
}

static void setTone(int pin, int frequency) {
	if (pin != tonePin) stopTone();
	initESP32Tone(pin);
	if (tonePin >= 0) {
		ledcAttachPin(tonePin, 0);
		ledcWriteTone(0, frequency);
	}
}

void stopTone() {
	if (tonePin >= 0) {
		ledcWrite(0, 0);
		ledcDetachPin(tonePin);
	}
}

#elif !defined(ARDUINO_SAM_DUE)

int tonePin = -1;

static void setTone(int pin, int frequency) {
	if (pin != tonePin) stopTone();
	tonePin = pin;
	tone(tonePin, frequency);
}

void stopTone() {
	if (tonePin >= 0) noTone(tonePin);
	tonePin = -1;
}

#else

static void setTone(int pin, int frequency) { }
void stopTone() { }

#endif // tone

// DAC (digital to analog converter) Support

#if defined(ESP32)

// DAC ring buffer. Size must be a power of 2.
#define DAC_BUF_SIZE 128
#define DAC_BUF_MASK (DAC_BUF_SIZE - 1)
static uint8 ringBuf[DAC_BUF_SIZE];

static volatile uint8 readPtr = 0;
static volatile uint8 writePtr = 0;
static volatile uint8 dacPin = 255;
static volatile uint8 lastValue = 0;

static hw_timer_t *timer = NULL;
static portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED;

// Copy of __dacWrite from esp32-hal-dac.c without the call to pinMode():
#include "soc/sens_reg.h"

static void IRAM_ATTR __dacWrite(uint8_t pin, uint8_t value) {
    if(pin < 25 || pin > 26) return;//not dac pin
//    pinMode(pin, ANALOG); // this call causes a crash when __dacWrite is called from the ISR

    //Disable Tone
    CLEAR_PERI_REG_MASK(SENS_SAR_DAC_CTRL1_REG, SENS_SW_TONE_EN);

    uint8_t channel = pin - 25;
    if (channel) {
        //Disable Channel Tone
        CLEAR_PERI_REG_MASK(SENS_SAR_DAC_CTRL2_REG, SENS_DAC_CW_EN2_M);
        //Set the Dac value
        SET_PERI_REG_BITS(RTC_IO_PAD_DAC2_REG, RTC_IO_PDAC2_DAC, value, RTC_IO_PDAC2_DAC_S);   //dac_output
        //Channel output enable
        SET_PERI_REG_MASK(RTC_IO_PAD_DAC2_REG, RTC_IO_PDAC2_XPD_DAC | RTC_IO_PDAC2_DAC_XPD_FORCE);
    } else {
        //Disable Channel Tone
        CLEAR_PERI_REG_MASK(SENS_SAR_DAC_CTRL2_REG, SENS_DAC_CW_EN1_M);
        //Set the Dac value
        SET_PERI_REG_BITS(RTC_IO_PAD_DAC1_REG, RTC_IO_PDAC1_DAC, value, RTC_IO_PDAC1_DAC_S);   //dac_output
        //Channel output enable
        SET_PERI_REG_MASK(RTC_IO_PAD_DAC1_REG, RTC_IO_PDAC1_XPD_DAC | RTC_IO_PDAC1_DAC_XPD_FORCE);
    }
}

static void IRAM_ATTR onTimer() {
	int value;
	portENTER_CRITICAL_ISR(&timerMux);
		if (readPtr != writePtr) {
			value = ringBuf[readPtr++];
			readPtr &= DAC_BUF_MASK;
		} else {
			// if no data use last sample value to avoid a click
			value = lastValue;
		}
	portEXIT_CRITICAL_ISR(&timerMux);
//value = lastValue ? 0 : 80; // xxx
	if (dacPin != 255) __dacWrite(dacPin, value);
	lastValue = value;
}

static void initDAC(int pin, int sampleRate) {
	// Set the DAC pin and sample rate.

	const int fineTune = -2;
	#if defined(ARDUINO_CITILAB_ED1)
		// On ED1 board pins 2 and 4 are aliases for ESP32 pins 25 and 26
		if (2 == pin) pin = 25;
		if (4 == pin) pin = 26;
	#endif
	if ((25 == pin) || (26 == pin)) {
		pinMode(pin, ANALOG);
		dacPin = pin;
	} else { // disable DAC output if pin is not a DAC pin (i.e. pin 25 or 26)
 		if (timer) timerEnd(timer);
		dacPin = 255;
		return;
	}
	if (sampleRate <= 0) sampleRate = 1;
	if (sampleRate > 100000) sampleRate = 100000;
	timer = timerBegin(0, 1, true);
	timerAttachInterrupt(timer, &onTimer, true);
	timerAlarmWrite(timer, (40000000 / sampleRate) + fineTune, true);
	timerAlarmEnable(timer);
}

static inline int writeDAC(int sample) {
	// If there's room, add the given sample to the DAC ring buffer and return 1.
	// Otherwise return 0.

	if (255 == dacPin) return 0; // DAC not initialized
	if (((writePtr + 1) & DAC_BUF_MASK) == readPtr) return 0; // buffer is full

	if (sample < 0) sample = 0;
	if (sample > 255) sample = 255;
	portENTER_CRITICAL(&timerMux);
		ringBuf[writePtr++] = sample;
		writePtr &= DAC_BUF_MASK;
	portEXIT_CRITICAL(&timerMux);
	return 1;
}

#else

static void initDAC(int pin, int sampleRate) { }
static int writeDAC(int sample) { return 0; }

#endif

// Primitives

OBJ primHasTone(int argCount, OBJ *args) {
	#if defined(ARDUINO_SAM_DUE)
		return falseObj;
	#else
		return trueObj;
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
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		pin = digitalPin[pin];
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pin) && (pin <= 139)) {
			pin = pin - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pin) && (pin <= 4)) {
			pin = digitalPinMappings[pin - 1];
		}
	#endif
	#if defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		if (RESERVED(pin)) return falseObj;
	#endif

	SET_MODE(pin, OUTPUT);
	int frequency = obj2int(freqArg);
	if ((frequency < 16) || (frequency > 100000)) {
		stopTone();
	} else {
		setTone(pin, frequency);
	}
	return trueObj;
}

OBJ primHasServo(int argCount, OBJ *args) { return trueObj; }

OBJ primSetServo(int argCount, OBJ *args) {
	// setServo <pin> <usecs>
	// If usecs > 0, generate a servo control signal with the given pulse width
	// on the given pin. If usecs <= 0 stop generating the servo signal.
	// Return true on success, false if primitive is not supported.

	OBJ pinArg = args[0];
	OBJ usecsArg = args[1];
	if (!isInt(pinArg) || !isInt(usecsArg)) return falseObj;
	int pin = obj2int(pinArg);
	if ((pin < 0) || (pin >= DIGITAL_PINS)) return falseObj;
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		pin = digitalPin[pin];
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pin) && (pin <= 139)) {
			pin = pin - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pin) && (pin <= 4)) {
			pin = digitalPinMappings[pin - 1];
		}
	#endif
	#if defined(ARDUINO_ARCH_ESP32) || defined(ESP8266) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
		if (RESERVED(pin)) return falseObj;
	#endif
	int usecs = obj2int(usecsArg);
	if (usecs > 5000) { usecs = 5000; } // maximum pulse width is 5000 usecs
	SET_MODE(pin, OUTPUT);
	setServo(pin, usecs);
	return trueObj;
}

OBJ primDACInit(int argCount, OBJ *args) {
	// Initialize the DAC pin and (optional) sample rate. If the pin is not a DAC pin (pins
	// 25 or 26 on an ESP32) then disable the DAC. The sample rate defaults to 11025.

	if (argCount < 1) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	int pin = obj2int(args[0]);
	int sampleRate = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 11025;

	initDAC(pin, sampleRate);
	return falseObj;
}

OBJ primDACWrite(int argCount, OBJ *args) {
	// Write sound samples to the DAC output buffer and return the number of samples written.
	// The argument may be an integer representing a single sample or a ByteArray of samples
	// plus an optional starting index withing that buffer.

	if (argCount < 1) return fail(notEnoughArguments);
	OBJ arg0 = args[0];

	int count = 0;
	if (isInt(arg0)) {
		count = writeDAC(obj2int(arg0));
	} else if (IS_TYPE(arg0, ByteArrayType)) {
		uint8 *buf = (uint8 *) &FIELD(arg0, 0);
		int bufSize = BYTES(arg0);
		int startIndex = ((argCount > 1) && isInt(args[1])) ?  obj2int(args[1]) : 1;
		if (startIndex < 1) startIndex = 1;
		if (startIndex > bufSize) startIndex = bufSize;
		for (int i = startIndex - 1; i < bufSize; i++) {
			if (!writeDAC(buf[i])) break;
			count++;
		}
	}
	return int2obj(count);
}

static PrimEntry entries[] = {
	{"hasTone", primHasTone},
	{"playTone", primPlayTone},
	{"hasServo", primHasServo},
	{"setServo", primSetServo},
	{"dacInit", primDACInit},
	{"dacWrite", primDACWrite},
};

void addIOPrims() {
	addPrimitiveSet("io", sizeof(entries) / sizeof(PrimEntry), entries);
}
