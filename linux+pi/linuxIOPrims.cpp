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

// sound

const int AMPLITUDE = 28000;
const int SAMPLE_RATE = 44100;

int frequency;
int sample_nr = 0;

SDL_AudioSpec want;
SDL_AudioSpec have;

void audio_callback(void *user_data, Uint8 *raw_buffer, int bytes) {
    Sint16 *buffer = (Sint16*)raw_buffer;
    int length = bytes / 2; // 2 bytes per sample for AUDIO_S16SYS
    int &sample_nr(*(int*)user_data);

    for(int i = 0; i < length; i++, sample_nr++) {
        double time = (double)sample_nr / (double)SAMPLE_RATE;
        buffer[i] = (Sint16)(AMPLITUDE * sin(2.0f * M_PI * frequency * time));
    }
}

void stopTone() {
    SDL_PauseAudio(1); // stop playing sound
    SDL_CloseAudio();
}

OBJ primHasTone(int argCount, OBJ *args) { return trueObj; }

OBJ primPlayTone(int argCount, OBJ *args) {
	want.freq = SAMPLE_RATE; // number of samples per second
	want.format = AUDIO_S16SYS; // sample type (here: signed short i.e. 16 bit)
	want.channels = 1; // only one channel
	want.samples = 2048; // buffer-size
	want.callback = audio_callback; // function SDL calls periodically to refill the buffer
	want.userdata = &sample_nr; // counter, keeping track of current sample number
    SDL_OpenAudio(&want, &have);
	frequency = obj2int(args[1]);
    SDL_PauseAudio(0); // start playing sound
	return falseObj;
}

OBJ primHasServo(int argCount, OBJ *args) { return trueObj; }
OBJ primSetServo(int argCount, OBJ *args) { return trueObj; }
OBJ primDACInit(int argCount, OBJ *args) { return trueObj; }
OBJ primDACWrite(int argCount, OBJ *args) { return trueObj; }

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
