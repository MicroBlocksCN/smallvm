// microBlocksPrims.cpp - Microblocks primitives
// John Maloney, April 2017

#include <stdio.h>

#include "mem.h"
#include "interp.h"

// Helper Functions

#ifndef ARDUINO
// On non-Arduino platforms, implement millisecs() using the microsecond clock.
// Note: mbed doesn't have a millisecond clock and not all mbed boards have a
// realtime clock, so gettimeofday() doesn't work, either (it just returns 0).

static uint32 msecsSinceStart = 0;
static uint32 lastTicks = 0;
static uint32 extraTicks = 0;

uint32 millisecs() {
	uint32 now = TICKS();
	extraTicks += (now - lastTicks);
	while (extraTicks >= 1000) {
		extraTicks -= 1000;
		msecsSinceStart += 1;
	}
	lastTicks = now;
	return msecsSinceStart;
}
#endif // not ARDUINO

OBJ sizeFailure() { return failure("Size must be a positive integer"); }
OBJ arrayClassFailure() { return failure("Must must be an Array or ByteArray"); }
OBJ byteValueFailure() { return failure("A ByteArray can only store integer values between 0 and 255"); }
OBJ indexClassFailure() { return failure("Index must be an integer"); }
OBJ outOfRangeFailure() { return failure("Index out of range"); }

// Platform Agnostic Primitives

OBJ primNewArray(OBJ *args) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return sizeFailure();
	OBJ result = newObj(ArrayClass, obj2int(n), int2obj(0)); // filled with zero integers
	return result;
}

OBJ primNewByteArray(OBJ *args) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return sizeFailure();
	OBJ result = newObj(ByteArrayClass, (obj2int(n) + 3) / 4, nilObj); // filled with zero bytes
	return result;
}

OBJ primArrayFill(OBJ *args) {
	OBJ array = args[0];
	if (!(IS_CLASS(array, ArrayClass) || IS_CLASS(array, ByteArrayClass))) return arrayClassFailure();
	OBJ value = args[1];

	if (IS_CLASS(array, ArrayClass)) {
		int end = objWords(array) + HEADER_WORDS;
		for (int i = HEADER_WORDS; i < end; i++) ((OBJ *) array)[i] = value;
	} else {
		if (!isInt(value)) return byteValueFailure();
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return byteValueFailure();
		uint8 *dst = (uint8 *) &FIELD(array, 0);
		uint8 *end = dst + (4 * objWords(array));
		while (dst < end) *dst++ = byteValue;
	}
	return nilObj;
}

OBJ primArrayAt(OBJ *args) {
	OBJ array = args[0];
	if (!isInt(args[1])) return indexClassFailure();
	int i = obj2int(args[1]);

	if (IS_CLASS(array, ArrayClass)) {
		if ((i < 1) || (i > objWords(array))) return outOfRangeFailure();
		return FIELD(array, (i - 1));
	} else if (IS_CLASS(array, ByteArrayClass)) {
		if ((i < 1) || (i > (objWords(array) * 4))) return outOfRangeFailure();
		uint8 *bytes = (uint8 *) &FIELD(array, 0);
		return int2obj(bytes[i - 1]);
	} else return arrayClassFailure();
	return nilObj;
}

OBJ primArrayAtPut(OBJ *args) {
	OBJ array = args[0];
	if (!isInt(args[1])) return indexClassFailure();
	int i = obj2int(args[1]);
	OBJ value = args[2];

	if (IS_CLASS(array, ArrayClass)) {
		if ((i < 1) || (i > objWords(array))) return outOfRangeFailure();
		FIELD(array, (i - 1)) = value;
	} else if (IS_CLASS(array, ByteArrayClass)) {
		if ((i < 1) || (i > (objWords(array) * 4))) return outOfRangeFailure();
		if (!isInt(value)) return byteValueFailure();
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return byteValueFailure();
		((uint8 *) &FIELD(array, 0))[i - 1] = byteValue;
	} else return arrayClassFailure();
	return nilObj;
}

OBJ primPeek(OBJ *args) {
	if (!isInt(args[0])) return int2obj(0);
	int *addr = (int *) obj2int(args[0]);
	return int2obj(*addr);
}

OBJ primPoke(OBJ *args) {
	if (!isInt(args[0])) return nilObj;
	int *addr = (int *) obj2int(args[0]);
	*addr = obj2int(args[1]);
	return nilObj;
}

// Platform specific primitives

#if defined(ARDUINO)

#include "Arduino.h"

// Arduino Helper Functions (callable from C)

uint32 microsecs() { return (uint32) micros(); }
uint32 millisecs() { return (uint32) millis(); }

void putSerial(char *s) { Serial.print(s); }
int serialDataAvailable() { return Serial.available(); }

int readBytes(uint8 *buf, int count) {
	int bytesRead = Serial.available();
	for (int i = 0; i < bytesRead; i++) {
		buf[i] = Serial.read();
	}
	return bytesRead;
}

void writeBytes(uint8 *buf, int count) {
	for (int i = 0; i < count; i++) {
		Serial.write(buf[i]);
	}
}

void systemReset() {
	NVIC_SystemReset();
}

// Arduino Primitives

static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > 5)) return int2obj(0);
	int pin = analogPin[pinNum];
	pinMode(pin, INPUT);
	return int2obj(analogRead(pin));
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = obj2int(args[1]);
	if ((pinNum < 0) || (pinNum > 5)) return nilObj;
	int pin = analogPin[pinNum];
	pinMode(pin, OUTPUT);
	analogWrite(pin, value);
	return nilObj;
}

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if (pinNum < 0) return falseObj;
	pinMode(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	if (pinNum < 0) return nilObj;
	pinMode(pinNum, OUTPUT);
	digitalWrite(pinNum, value);
	return nilObj;
}

OBJ primSetLED(OBJ *args) {
	int value = (args[0] == trueObj) ? LOW : HIGH; // LOW turns the LED on
	pinMode(PIN_LED, OUTPUT);
	digitalWrite(PIN_LED, value);
	return nilObj;
}

#elif defined(__MBED__)

// MBED Helper Functions

#include "mbed.h"
#include <gpio_api.h>
#include <PinNames.h>

Serial pc(USBTX, USBRX);

int serialDataAvailable() { return pc.readable(); }

int readBytes(uint8 *buf, int count) {
	int bytesRead = 0;
	while ((bytesRead < count) && pc.readable()) {
		buf[bytesRead++] = pc.getc();
	}
	return bytesRead;
}

void writeBytes(uint8 *buf, int count) {
	for (int i = 0; i < count; i++) {
		pc.putc(buf[i]);
	}
}

void systemReset() {
	NVIC_SystemReset();
}

// Pin Maps (for the micro:bit)

#if defined(TARGET_LPC176X)

#define TOTAL_PIN_COUNT 25
#define ANALOG_PIN_COUNT 5

PinName pinMap[] = { }; // LPC1768 pins not yet implemented

#elif defined(TARGET_NRF51_MICROBIT)

#define TOTAL_PIN_COUNT 25
#define ANALOG_PIN_COUNT 4

PinName pinMap[] = {
 	P0_3, P0_2, P0_1, P0_4, // edge pins 0-3 (analog)
 	P0_5, // edge pin 4, COL1 (does not work as digital out if set for analog in)
 	P0_17, // edge pin 5, button A
 	P0_12, P0_11, P0_18, P0_10, P0_6, // edge pins 6-10
 	P0_26, // edge pin 11, button B
 	P0_20, P0_23, P0_22, P0_21, P0_16, // edge pins 12-16
 	// edge pins 17-18 are 3.3v power
	P0_0, P0_30, // uBlocks pins 17-18 -> edge pins 19-20
	P0_7, P0_8, P0_9, // LED MATRIX COLS 4-6 (not on edge connector)
	P0_13, P0_14, P0_15,  // LED MATRIX ROWS 1-3 (not on edge connector)
};

#endif

// Pin Records

analogin_t analogIn[ANALOG_PIN_COUNT];
pwmout_t analogOut[ANALOG_PIN_COUNT];
gpio_t digitalPin[TOTAL_PIN_COUNT];

int pwmPeriodusecs = 1000; // 1 millisecond

// Pin Modes

#define digitalReadMode 1
#define digitalWriteMode 2
#define analogReadMode 3
#define analoglWriteMode 4

// This array records the most recent use of each pin:
uint8 pinMode[TOTAL_PIN_COUNT];

static void setPinMode(int pinNum, int newMode) {
	// Change the mode of the given pin.
	// Assumes client has ensured that the new mode is allowed for the given pin.

	int oldMode = pinMode[pinNum];
	pinMode[pinNum] = newMode;

	// turn off old output, if any
	if (analoglWriteMode == oldMode) pwmout_free(&analogOut[pinNum]);
	gpio_dir(&digitalPin[pinNum], PIN_INPUT);

	// set new output mode if needed
	if (analoglWriteMode == newMode) {
		pwmout_init(&analogOut[pinNum], pinMap[pinNum]);
		pwmout_period_us(&analogOut[pinNum], pwmPeriodusecs);
	}
	if (digitalWriteMode == newMode) {
		gpio_dir(&digitalPin[pinNum], PIN_OUTPUT);
	}
}

void hardwareInit() {
	for (int i = 0; i < ANALOG_PIN_COUNT; i++) {
		if (i != 4) {
			// Workaround. If pin4 is initialized for analogIn, it doesn't
			// work as a digital out. Why is pin 4 special?
			analogin_init(&analogIn[i], pinMap[i]);
		}
	}
	for (int i = 0; i < TOTAL_PIN_COUNT; i++) {
		pinMode[i] = digitalReadMode;
		gpio_init(&digitalPin[i], pinMap[i]);
		gpio_dir(&digitalPin[i], PIN_INPUT);
	}
}

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > ANALOG_PIN_COUNT)) return int2obj(0);

	if (analogReadMode != pinMode[pinNum]) setPinMode(pinNum, analogReadMode);
	int value = analogin_read_u16(&analogIn[pinNum]); // 16-bit
	return int2obj(value);
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > ANALOG_PIN_COUNT)) return nilObj;
	float value = obj2int(args[1]) / 65535.0; // range: 0-65535 (16-bit unsigned)

	if (analoglWriteMode != pinMode[pinNum]) setPinMode(pinNum, analoglWriteMode);
	pwmout_write(&analogOut[pinNum], value);
	return nilObj;
}

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > TOTAL_PIN_COUNT)) return falseObj;

	if (digitalReadMode != pinMode[pinNum]) setPinMode(pinNum, digitalReadMode);
	int value = gpio_read(&digitalPin[pinNum]);
	return value ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > TOTAL_PIN_COUNT)) return falseObj;
	int value = (args[1] == trueObj) ? 1 : 0;

	if (digitalWriteMode != pinMode[pinNum]) setPinMode(pinNum, digitalWriteMode);
	gpio_write(&digitalPin[pinNum], value);
	return nilObj;
}

OBJ primSetLED(OBJ *args) {
	int value = (args[0] == trueObj) ? 1 : 0;

	const int col2 = 4;
	const int row1 = 22;

	setPinMode(col2, digitalWriteMode);
	setPinMode(row1, digitalWriteMode);
	if (value) {
		gpio_write(&digitalPin[col2], 0);
		gpio_write(&digitalPin[row1], 1);
	} else {
		gpio_write(&digitalPin[col2], 1);
		gpio_write(&digitalPin[row1], 0);
	}
	return nilObj;
}

#else

// stubs for compiling/testing on laptop

int serialDataAvailable() { return false; }
int readBytes(uint8 *buf, int count) { return 0; }
void writeBytes(uint8 *buf, int count) {}

void hardwareInit() {}
void systemReset() {}

OBJ primAnalogRead(OBJ *args) { return int2obj(0); }
OBJ primAnalogWrite(OBJ *args) { return nilObj; }
OBJ primDigitalRead(OBJ *args) { return falseObj; }
OBJ primDigitalWrite(OBJ *args) { return nilObj; }
OBJ primSetLED(OBJ *args) { return nilObj; }

#endif
