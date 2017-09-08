// ioPrims_mbmed.cpp - Microblocks IO primitives the BBC micro:bit on the mbed platform
// John Maloney, April 2017

#include <stdio.h>

#include "mbed.h"
#include <gpio_api.h>
#include <PinNames.h>

#include "mem.h"
#include "interp.h"

// Timing Functions

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

// Communications and System Reset

Serial pc(USBTX, USBRX, 115200);

int readBytes(uint8 *buf, int count) {
	int bytesRead = 0;
	while ((bytesRead < count) && pc.readable()) {
		buf[bytesRead++] = pc.getc();
	}
	return bytesRead;
}

int canReadByte() { return pc.readable(); }
int canSendByte() { return pc.writeable(); }
void sendByte(char aByte) { pc.putc(aByte); }

void systemReset() { NVIC_SystemReset(); }

// GPIO Pin Map

#if defined(TARGET_NRF51_MICROBIT)

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
gpio_t digitalPin[TOTAL_PIN_COUNT];
pwmout_t pwmPin[TOTAL_PIN_COUNT];

int pwmPeriodusecs = 1000; // 1 millisecond

// Pin Modes

#define digitalReadMode 1
#define digitalWriteMode 2
#define analogReadMode 3
#define analoglWriteMode 4

uint8 pinMode[TOTAL_PIN_COUNT]; // current mode of each pin

static void setPinMode(int pinNum, int newMode) {
	// Change the mode of the given pin.
	// Assumes client has ensured that the new mode is allowed for the given pin.

	int oldMode = pinMode[pinNum];
	pinMode[pinNum] = newMode;

	// turn off old output, if any
	if (analoglWriteMode == oldMode) pwmout_free(&pwmPin[pinNum]);
	gpio_dir(&digitalPin[pinNum], PIN_INPUT);

	// set new output mode if needed
	if (analoglWriteMode == newMode) {
		pwmout_init(&pwmPin[pinNum], pinMap[pinNum]);
		pwmout_period_us(&pwmPin[pinNum], pwmPeriodusecs);
	}
	if (digitalWriteMode == newMode) {
		gpio_dir(&digitalPin[pinNum], PIN_OUTPUT);
	}
}

// Initialization

void hardwareInit() {
	initClock_NRF51();
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

// Pin Primitives

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > ANALOG_PIN_COUNT)) return int2obj(0);

	if (analogReadMode != pinMode[pinNum]) setPinMode(pinNum, analogReadMode);
	int value = analogin_read_u16(&analogIn[pinNum]); // 16-bit
	return int2obj(value);
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > TOTAL_PIN_COUNT)) return nilObj;
	float value = obj2int(args[1]) / 1023.0; // range: 0-1023 (10-bit)

	if (analoglWriteMode != pinMode[pinNum]) setPinMode(pinNum, analoglWriteMode);
	pwmout_write(&pwmPin[pinNum], value);
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
