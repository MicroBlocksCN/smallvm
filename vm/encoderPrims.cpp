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
 * - Set the interruptHandler attribute to a function or lambda that calls updateCount.
 *   It must take no arguments and return nothing.
 *   (Unfortunately an interrupt handler cannot be a class member function.)
 * - Call startCounting to configure the encoder pins and start counting.
 * - Call resetCount to zero the count, whenever desired.
 * - Call stopCounting to stop counting and disable interrupts for the given encoder.
 */

#define NUM_ENCODERS 4

class Encoder {
public:
    volatile int count;
    void (*interruptHandler)();
    volatile bool prevStateA;
    volatile bool prevStateB;
    uint8_t pinA = -1;
    uint8_t pinB = -1;

    bool hasInterruptHandler() { return interruptHandler != nullptr; }

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
    int startCounting(const uint8_t pinA, const uint8_t pinB) {
        if (!hasInterruptHandler()) {
            return 1;
        }
        stopCounting();
        if ((pinA == pinB) || (digitalPinToInterrupt(pinA) == -1) || (digitalPinToInterrupt(pinB) == -1)) {
            // One or both pins is unusable as an interrupt
            return 2;
        }
        this->pinA = pinA;
        this->pinB = pinB;
        this->count = 0;
        attachInterrupt(digitalPinToInterrupt(pinA), interruptHandler, CHANGE);
        return 0;
    }

    /*
     * Stop counting and detach the interrupt handler from the pins.
     *
     * Also reset the count to 0, as a clue that we have stopped counting.
     */
    void stopCounting() {
        if (this->pinA >= 0) {
       	    detachInterrupt(digitalPinToInterrupt(this->pinA));
       	}
        this->pinA = -1;
        this->pinB = -1;
        this->count = 0;
    }

    /*
     * Read the pins and update the count attribute
     *
     * This is intended to be called by interrupts, not by the user.
     */
    void updateCount() {
        bool stateA = digitalRead(pinA);
        bool stateB = digitalRead(pinB);
        if (stateA != prevStateA) {
            count += (stateA == stateB ? -1 : 1);
            prevStateA = stateA;
        } else if (stateB != prevStateB) {
            count += (stateA == stateB ? 1 : -1);
            prevStateB = stateB;
        }
    }
};

static Encoder encoders[NUM_ENCODERS];

// Interrupts accept no arguments and must be free functions, not class member functions,
// so we must declare one free function per encoder to call the appropriate member function.
// Using a macro to define the function as a lambda saves some repetition,
// and non-capturing lambdas are supposed to usable as function pointers in standard C++.
#define encoder_handler(ind) []() { encoders[(ind)].updateCount(); }

/*
 * Install an interrupt handler function for each encoder. Called once at startup time.
 */
static void initEncoders() {
    encoders[0].interruptHandler = encoder_handler(0);
    encoders[1].interruptHandler = encoder_handler(1);
    encoders[2].interruptHandler = encoder_handler(2);
    encoders[3].interruptHandler = encoder_handler(3);
}

// Primitive Functions

OBJ primEncoderStart(int argCount, OBJ *args) {
    if (argCount < 3) return fail(notEnoughArguments);
    if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) {
        return fail(needsIntegerIndexError);
    }
    int encoderIndex = obj2int(args[0]);
    int pinA = obj2int(args[1]);
    int pinB = obj2int(args[2]);
    int err = 1;
    if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
        err = encoders[encoderIndex - 1].startCounting(pinA, pinB);
    }
    if (err != 0) return fail(encoderNotStarted);

    return falseObj;
}

OBJ primEncoderStop(int argCount, OBJ *args) {
    if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
    int encoderIndex = obj2int(args[0]);

    if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
        encoders[encoderIndex - 1].stopCounting();
    }
    return falseObj;
}

OBJ primEncoderReset(int argCount, OBJ *args) {
    if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
    int encoderIndex = obj2int(args[0]);

    if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
        encoders[encoderIndex - 1].count = 0;
     }
    return falseObj;
}

OBJ primEncoderCount(int argCount, OBJ *args) {
    if ((argCount < 1) || !isInt(args[0])) return fail(needsIntegerIndexError);
    int encoderIndex = obj2int(args[0]);

    int result = 0;
    if (encoderIndex >= 1 || encoderIndex <= NUM_ENCODERS) {
        result = encoders[encoderIndex - 1].count;
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
	initEncoders();
    addPrimitiveSet(EncoderPrims, "encoder", sizeof(entries) / sizeof(PrimEntry), entries);
}
