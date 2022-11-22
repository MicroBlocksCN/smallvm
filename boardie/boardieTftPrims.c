/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2020 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxTftPrims.cpp - Microblocks TFT screen primitives simulated on an SDL window
// Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>
#include "mem.h"
#include "interp.h"

#define DEFAULT_WIDTH 320
#define DEFAULT_HEIGHT 240

// Keyboard Support

extern int KEY_SCANCODE[];

// static void initKeys() {
// 	for (int i = 0; i < 255; i++) {
// 		KEY_SCANCODE[i] = false;
// 	}
// }

void tftInit() {}
void tftClear() {}

void updateMicrobitDisplay() {}

// Simulating a 5x5 LED Matrix

void primSetUserLED(OBJ *args) { }

void tftSetHugePixel(int x, int y, int state) {}
void tftSetHugePixelBits(int bits) {}

// TFT Primitives (stubs)

static OBJ primEnableDisplay(int argCount, OBJ *args) { return falseObj; }
static OBJ primGetWidth(int argCount, OBJ *args) { return falseObj; }
static OBJ primGetHeight(int argCount, OBJ *args) { return falseObj; }
static OBJ primSetPixel(int argCount, OBJ *args) { return falseObj; }
static OBJ primLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primRect(int argCount, OBJ *args) { return falseObj; }
static OBJ primCircle(int argCount, OBJ *args) { return falseObj; }
static OBJ primRoundedRect(int argCount, OBJ *args) { return falseObj; }
static OBJ primTriangle(int argCount, OBJ *args) { return falseObj; }
static OBJ primText(int argCount, OBJ *args) { return falseObj; }

// TFT Touch Primitives

static OBJ primTftTouched(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchX(int argCount, OBJ *args) { return zeroObj; }
static OBJ primTftTouchY(int argCount, OBJ *args) { return zeroObj; }
static OBJ primTftTouchPressure(int argCount, OBJ *args) { return zeroObj; }

// Primitives

static PrimEntry entries[] = {
	{"enableDisplay", primEnableDisplay},
	{"getWidth", primGetWidth},
	{"getHeight", primGetHeight},
	{"setPixel", primSetPixel},
	{"line", primLine},
	{"rect", primRect},
	{"roundedRect", primRoundedRect},
	{"circle", primCircle},
	{"triangle", primTriangle},
	{"text", primText},
	{"tftTouched", primTftTouched},
	{"tftTouchX", primTftTouchX},
	{"tftTouchY", primTftTouchY},
	{"tftTouchPressure", primTftTouchPressure},
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
