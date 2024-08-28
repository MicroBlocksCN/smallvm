/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2024 John Maloney, Bernat Romagosa, and Jens Mönig

// encoderPrims.cpp - Primitives to track quadrature encoders.
// Russell Owen, August 2024

#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

#if !defined(NOT_AN_INTERRUPT)
  #define NOT_AN_INTERRUPT (-1)
#endif

// start of code to be replaced
// Quadrature Encoder Implementation (to be replaced by Russell)

#define NUM_ENCODERS 4

/*
 * Data for a quadrature incremental encoder
 */
struct encoder_t {
    uint8_t pin_a;
    uint8_t pin_b;
    volatile bool prev_state_a;
    volatile bool prev_state_b;
    volatile bool isRunning;
    volatile int count;
};

struct encoder_t encoders[NUM_ENCODERS];

/*
 * Update the data for the specified quadrature incremental encoder
 */
void encoder_handler_impl(encoder_t &encoder) {
    bool state_a = digitalRead(encoder.pin_a);
    bool state_b = digitalRead(encoder.pin_b);

    if (state_a != encoder.prev_state_a) {
        encoder.count += state_a == state_b ? -1 : 1;
        encoder.prev_state_a = state_a;
    } else if (state_b != encoder.prev_state_b) {
        encoder.count += state_a == state_b ? 1 : -1;
        encoder.prev_state_b = state_b;
    }
}

// Interrupts accept no arguments, so we cannot assign encoder_handler_impl;
// instead, declare one free function per encoder.
void encoder_handler_0() { encoder_handler_impl(encoders[0]); }
void encoder_handler_1() { encoder_handler_impl(encoders[1]); }
void encoder_handler_2() { encoder_handler_impl(encoders[2]); }
void encoder_handler_3() { encoder_handler_impl(encoders[3]); }

// start of code added by John (can be replaced with C++ calls)
/*
 * Stop the interrupts for the given encoder
 */
void stopEncoder(const int encoderIndex) {
	if (encoderIndex < 1 || encoderIndex > NUM_ENCODERS) return;
	if (!encoders[encoderIndex].isRunning) return; // not running

	detachInterrupt(digitalPinToInterrupt(encoders[encoderIndex].pin_a));
	detachInterrupt(digitalPinToInterrupt(encoders[encoderIndex].pin_b));
	encoders[encoderIndex].isRunning = false;
}

/*
 * Specify the encoder pins and start the interrupt handler for the given encoder
 */
int startEncoder(const int encoderIndex, const uint8_t pin_a, const uint8_t pin_b) {
	if (encoderIndex < 1 || encoderIndex > NUM_ENCODERS) {
		return -1; // encoderIndex out of range
	}

	stopEncoder(encoderIndex); // stop the encoder if it is already running

	int interruptA = digitalPinToInterrupt(pin_a);
	int interruptB = digitalPinToInterrupt(pin_b);
	if ((interruptA == NOT_AN_INTERRUPT) || (interruptB == NOT_AN_INTERRUPT)) {
		return -2; // a pin does not support interrupts
	}

	void (*handler)();
	switch (encoderIndex) {
	case 1: handler = encoder_handler_0; break;
	case 2: handler = encoder_handler_1; break;
	case 3: handler = encoder_handler_2; break;
	case 4: handler = encoder_handler_3; break;
	}

	encoders[encoderIndex].pin_a = pin_a;
	encoders[encoderIndex].pin_b = pin_b;
	encoders[encoderIndex].prev_state_a = false;
	encoders[encoderIndex].prev_state_b = false;
	encoders[encoderIndex].isRunning = true;
	encoders[encoderIndex].count = 0;

	attachInterrupt(interruptA, handler, CHANGE);
	attachInterrupt(interruptB, handler, CHANGE);

	return 0; // success
}

// end of code added by John
// end of code to be replaced

// Primitive Functions

OBJ primEncoderStart(int argCount, OBJ *args) {
	if (argCount < 3) return fail(notEnoughArguments);
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) {
		return fail(needsIntegerIndexError);
	}
	int encoderIndex = obj2int(args[0]);
	int pinA = obj2int(args[1]);
	int pinB = obj2int(args[2]);
	int rc = startEncoder(encoderIndex, pinA, pinB);
	if (rc != 0) return fail(encoderNotStarted);

	return falseObj;
}

OBJ primEncoderStop(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
	int encoderIndex = obj2int(args[0]);

	if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
		stopEncoder(encoderIndex);
	}
	return falseObj;
}

OBJ primEncoderReset(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
	int encoderIndex = obj2int(args[0]);

	if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
    	encoders[encoderIndex].count = 0;
	}
	return falseObj;
}

OBJ primEncoderCount(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
	int encoderIndex = obj2int(args[0]);

	int result = 0;
	if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
    	result = encoders[encoderIndex].count;
	}
	return int2obj(result);
}

// Primitives

static PrimEntry entries[] = {
	{"start", primEncoderStart},
	{"stop", primEncoderStop},
	{"reset", primEncoderReset},
	{"count", primEncoderCount},
};

void addEncoderPrims() {
	addPrimitiveSet(EncoderPrims, "encoder", sizeof(entries) / sizeof(PrimEntry), entries);
}
