/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxIOPrims.c - File system primitives for Linux boards.
// John Maloney, April 2020
// Adapted to Linux VM by Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "mem.h"
#include "interp.h"
#include <math.h>
#include <SDL2/SDL.h>

void primSetUserLED(OBJ *args) {
	tftSetHugePixel(3, 1, (trueObj == args[0]));
}

// Button simulation, and keyboard input

extern int KEY_SCANCODE[];

OBJ primButtonA(OBJ *args) {
	// simulate button A with the left arrow key
	return KEY_SCANCODE[80] ? trueObj : falseObj;
}

OBJ primButtonB(OBJ *args) {
	// simulate button B with the right arrow key
	return KEY_SCANCODE[79] ? trueObj : falseObj;
}

// Tone generation

const int AMPLITUDE = 16000;
const int DESIRED_SAMPLING_RATE = 22050;
const double TWOPI = 6.28318530718; // the number of radians per cycle

static int samplingRate = 0; // 0 means audio is not started; -1 means error when starting

static int isPlaying = false;
static double phase = 0.0; // phase angle of sine wave (radians)
static double phaseIncrement = 0.0; // phase increment per sample (radians)

void audio_callback(void *user_data, Uint8 *raw_buffer, int bytes) {
	Sint16 *buffer = (Sint16 *) raw_buffer;
	int length = bytes / 2; // 2 bytes per sample for AUDIO_S16SYS

	for (int i = 0; i < length; i++) {
		buffer[i] = (Sint16) (AMPLITUDE * sin(phase));
		phase += phaseIncrement;
		if (phase > TWOPI) {
			if (isPlaying) {
				phase -= TWOPI; // wrap around and keep playing
			} else {
				// start playing silence (because sin(0) is 0)
				// Note: transition to silence at zero-crossing to avoid clicks
				phase = 0.0;
				phaseIncrement = 0.0;
			}
		}
	}
}

static void initAudio() {
	SDL_AudioSpec want, have;
	want.freq = DESIRED_SAMPLING_RATE; // number of samples per second
	want.format = AUDIO_S16SYS; // sample type (here: signed short i.e. 16 bit)
	want.channels = 1; // only one channel
	want.samples = 64; // buffer-size
	want.callback = audio_callback; // function SDL calls periodically to refill the buffer
	int err = SDL_OpenAudio(&want, &have);
	if (err) {
		printf("Could not start SDL Audio: %s\n", SDL_GetError());
		samplingRate = -1; // don't try again
	} else {
		samplingRate = have.freq;
	}
	SDL_PauseAudio(false); // start audio callbacks
	SDL_Delay(100); // leave some time for ALSA to get going
}

void stopTone() { isPlaying = false; }

OBJ primHasTone(int argCount, OBJ *args) { return trueObj; }

OBJ primPlayTone(int argCount, OBJ *args) {
	if ((argCount < 2) || !isInt(args[1])) return falseObj;
	int frequency = obj2int(args[1]);

	if (!samplingRate) initAudio();
	if ((frequency < 16) || (frequency > 11025)) {
		isPlaying = false;
	} else {
		phaseIncrement = (TWOPI * frequency) / samplingRate;
		isPlaying = true;
	}
	return falseObj;
}

// Other primitives (stubs for now)

OBJ primHasServo(int argCount, OBJ *args) { return falseObj; }
OBJ primSetServo(int argCount, OBJ *args) { return falseObj; }
OBJ primDACInit(int argCount, OBJ *args) { return falseObj; }
OBJ primDACWrite(int argCount, OBJ *args) { return falseObj; }

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
