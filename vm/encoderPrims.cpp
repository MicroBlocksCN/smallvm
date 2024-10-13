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

/*
 * A quadrature incremental encoder
 *
 * To use the class:
 * - Construct an instance
 * - Call startCounting to configure the encoder pins and start counting.
 * - Call resetCount to zero the count, whenever desired.
 * - Call stopCounting to stop counting and disable interrupts for the given encoder.
 */

#define NUM_ENCODERS 4

typedef void (*interruptHandler)(void);
static interruptHandler encoderInterruptHandlerFor(int encoderIndex); // forward reference
static interruptHandler pulseInterruptHandlerFor(int encoderIndex);  // forward reference

class Encoder {
public:
	volatile int count;
	volatile bool prevStateA;
	volatile bool prevStateB;
	uint8_t pinA = -1;
	uint8_t pinB = -1;
	bool fullRes;

	/*
	 * Set the pins and start counting.
	 *
	 * Attach the interrupt handler to both pins.
	 *
	 * This is safe to call if already counting; it stops counting
	 * with the previously configured pins, then starts counting with the new ones.
	 *
	 * Return:
	 * • 0 on success
	 * • 1 if no interrupt handler
	 * • 2 if the pins are invalid (they must be different and must both must support interrupts)
	 */
	int startCounting(int encoderIndex, uint8_t pinA, uint8_t pinB, bool fullRes) {
		stopCounting();

		int interruptA = digitalPinToInterrupt(pinA);
		int interruptB = digitalPinToInterrupt(pinB);
		if ((interruptA == -1) || (fullRes && (interruptB == -1))) {
			return -2; // a pin does not support interrupts
		}

		interruptHandler handler = encoderInterruptHandlerFor(encoderIndex);
		attachInterrupt(interruptA, handler, CHANGE);
		if (fullRes) attachInterrupt(interruptB, handler, CHANGE);

		this->count = 0;
		this->pinA = pinA;
		this->pinB = pinB;
		this->prevStateA = false;
		this->prevStateB = false;
		this->fullRes = fullRes;
		return 0;
	}

	/*
	 * Start a simple pulse counter (rising edges).
	 *
	 * This is safe to call if already counting; it stops counting
	 * with the previously configured pin(s), then starts counting with the new one.
	 *
	 * Return:
	 * • 0 on success
	 * • 1 if no interrupt handler
	 * • 2 if the pins are invalid (they must be different and must both must support interrupts)
	 */
	int startPulseCounter(int encoderIndex, uint8_t pinA) {
		stopCounting();

		int interruptA = digitalPinToInterrupt(pinA);
		if (interruptA == -1) return -2; // a pin does not support interrupts

		interruptHandler handler = pulseInterruptHandlerFor(encoderIndex);
		attachInterrupt(interruptA, handler, RISING);

		this->count = 0;
		this->pinA = pinA;
		this->pinB = -1;
		this->fullRes = false;
		return 0;
	}

	/*
	 * Stop counting and detach the interrupt handler(s) from the pins.
	 * Also reset the count to 0, as a clue that we have stopped counting.
	 */
	void stopCounting() {
		if (pinA >= 0) detachInterrupt(digitalPinToInterrupt(pinA));
		if (pinB >= 0) detachInterrupt(digitalPinToInterrupt(pinB));
		pinA = -1;
		pinB = -1;
		count = 0;
	}

	/*
	 * Called by the interrupt handler to update this encoder's count.
	 */
	void updateCount() {
		bool stateA = digitalRead(pinA);
		bool stateB = digitalRead(pinB);

		if (fullRes) {
			if (stateA != prevStateA) {
				count += (stateA == stateB) ? -1 : 1;
				prevStateA = stateA;
			} else if (stateB != prevStateB) {
				count += (stateA == stateB) ? 1 : -1;
				prevStateB = stateB;
			}
		} else {
			count += (stateA == stateB) ? -1 : 1;
		}
	}
};

static Encoder encoders[NUM_ENCODERS];

// Each encoder has an interrupt handler function that calls updateCount().
static void interruptHandler_0() { encoders[0].updateCount(); }
static void interruptHandler_1() { encoders[1].updateCount(); }
static void interruptHandler_2() { encoders[2].updateCount(); }
static void interruptHandler_3() { encoders[3].updateCount(); }

static interruptHandler encoderInterruptHandlerFor(int encoderIndex) {
	switch(encoderIndex) {
		case 0: return interruptHandler_0; break;
		case 1: return interruptHandler_1; break;
		case 2: return interruptHandler_2; break;
		case 3: return interruptHandler_3; break;
	}
	return interruptHandler_0; // will not get here if encoderIndex is in range
}

// Each pulse counter has an interrupt handler function that increments the count.
static void pulseInterruptHandler_0() { encoders[0].count++; }
static void pulseInterruptHandler_1() { encoders[1].count++; }
static void pulseInterruptHandler_2() { encoders[2].count++; }
static void pulseInterruptHandler_3() { encoders[3].count++; }

static interruptHandler pulseInterruptHandlerFor(int encoderIndex) {
	switch(encoderIndex) {
		case 0: return pulseInterruptHandler_0; break;
		case 1: return pulseInterruptHandler_1; break;
		case 2: return pulseInterruptHandler_2; break;
		case 3: return pulseInterruptHandler_3; break;
	}
	return pulseInterruptHandler_0;
}

// Primitive Functions

static OBJ primEncoderStart(int argCount, OBJ *args) {
	if (argCount < 3) return fail(notEnoughArguments);
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) {
		return fail(needsIntegerIndexError);
	}
	int encoderIndex = obj2int(args[0]) - 1;
	int pinA = obj2int(args[1]);
	int pinB = obj2int(args[2]);
	bool fullRes = (argCount > 3) && (trueObj == args[3]);

	int err = 1;
	if ((encoderIndex >= 0) && (encoderIndex < NUM_ENCODERS)) {
		err = encoders[encoderIndex].startCounting(encoderIndex, pinA, pinB, fullRes);
	}
	if (err != 0) return fail(encoderNotStarted);

	return falseObj;
}

static OBJ primEncoderStop(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
	int encoderIndex = obj2int(args[0]) - 1;

	if ((encoderIndex >= 0) && (encoderIndex < NUM_ENCODERS)) {
		encoders[encoderIndex].stopCounting();
	}
	return falseObj;
}

static OBJ primEncoderReset(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
	int encoderIndex = obj2int(args[0]) - 1;

	if ((encoderIndex >= 0) && (encoderIndex < NUM_ENCODERS)) {
		encoders[encoderIndex].count = 0;
	 }
	return falseObj;
}

static OBJ primEncoderCount(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
	int encoderIndex = obj2int(args[0]) - 1;

	int result = 0;
	if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
		result = encoders[encoderIndex].count;
	}
	return int2obj(result);
}

static OBJ primStartPulseCounter(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0]) || !isInt(args[1])) {
		return fail(needsIntegerIndexError);
	}
	int encoderIndex = obj2int(args[0]) - 1;
	int pin = obj2int(args[1]);

	int err = 1;
	if ((encoderIndex >= 0) && (encoderIndex < NUM_ENCODERS)) {
		err = encoders[encoderIndex].startPulseCounter(encoderIndex, pin);
	}
	if (err != 0) return fail(encoderNotStarted);

	return falseObj;
}


// Primitives

static PrimEntry entries[] = {
	{"start", primEncoderStart},
	{"stop", primEncoderStop},
	{"reset", primEncoderReset},
	{"count", primEncoderCount},
	{"startPulseCounter", primStartPulseCounter},
};

void addEncoderPrims() {
	addPrimitiveSet(EncoderPrims, "encoder", sizeof(entries) / sizeof(PrimEntry), entries);
}
