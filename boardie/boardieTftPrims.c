/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieTftPrims.cpp - Microblocks TFT primitives simulated on JS Canvas
// Bernat Romagosa, November 2022

#include <stdio.h>
#include <stdlib.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"

#define DEFAULT_WIDTH 320
#define DEFAULT_HEIGHT 240
#define REFRESH_MSECS 16 // screen refresh interval (~60 frames/sec)

static int mouseDown = false;
static int mouseX = -1;
static int mouseY = -1;
static int mouseDownTime = 0;

static int tftEnabled = false;
static int lastRefreshTime = 0;

static int ttfInitialized = false;

// Helpers

static int decodeColor (int color24b) {
	return (color24b >> 16) & 255, (color24b >> 8) & 255, color24b & 255, 255;
}


void tftClear() {
	tftInit();
}

void tftInit() {
	if (!tftEnabled) {
		lastRefreshTime = millisecs();
		tftEnabled = true;
	}
}

void updateMicrobitDisplay() {
	if (tftEnabled) {
		uint32_t now = millisecs();
		if (now < lastRefreshTime) lastRefreshTime = 0; // clock wrap
		if ((now - lastRefreshTime > REFRESH_MSECS)) {
			// do the rendering
			lastRefreshTime = now;
		}
	}
}

// TFT Primitives

static OBJ primEnableDisplay(int argCount, OBJ *args) {
	if (trueObj == args[0]) {
		tftInit();
	} else {
		tftClear();
		tftEnabled = false;
	}
	return falseObj;
}

static OBJ primGetWidth(int argCount, OBJ *args) {
	return int2obj(DEFAULT_WIDTH);
}

static OBJ primGetHeight(int argCount, OBJ *args) {
	return int2obj(DEFAULT_HEIGHT);
}

static OBJ primSetPixel(int argCount, OBJ *args) {
	tftInit();
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	// paint the pixel
	return falseObj;
}

static OBJ primLine(int argCount, OBJ *args) {
	tftInit();
	int x0 = obj2int(args[0]);
	int y0 = obj2int(args[1]);
	int x1 = obj2int(args[2]);
	int y1 = obj2int(args[3]);
	// paint the line
	return falseObj;
}

static OBJ primRect(int argCount, OBJ *args) {
	tftInit();

	EM_ASM_({
			var x = $0;
			var y = $1;
			var width = $2;
			var height = $3;
			var fill = $5;
			var ctx = document.querySelector('#screen').getContext('2d');
			if (fill) {
				ctx.fillStyle = $4; // not working
				ctx.fillRect(x, y, width, height);
			} else {
				ctx.strokeStyle = $4; // not working
				ctx.rect(x, y, width, height);
				ctx.stroke();
			}
		},
		obj2int(args[0]),
		obj2int(args[1]),
		obj2int(args[2]),
		obj2int(args[3]),
		decodeColor(obj2int(args[4])),
		(argCount > 5) ? (trueObj == args[5]) : true);
	return falseObj;
}

static OBJ primCircle(int argCount, OBJ *args) {
	tftInit();
	int originX = obj2int(args[0]);
	int originY = obj2int(args[1]);
	int radius = obj2int(args[2]);
	//setRenderColor(obj2int(args[3]));
	int fill = (argCount > 4) ? (trueObj == args[4]) : true;
	// draw circle
	return falseObj;
}

static OBJ primRoundedRect(int argCount, OBJ *args) {
	tftInit();
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int width = obj2int(args[2]);
	int height = obj2int(args[3]);
	int radius = obj2int(args[4]);

	if (2 * radius >= height) {
		radius = height / 2 - 1;
	}
	if (2 * radius >= width) {
		radius = width / 2 - 1;
	}

	int fill = (argCount > 6) ? (trueObj == args[6]) : true;
	if (fill) {
		// draw filled rounded rect
	} else {
		// draw rounded rect outline
	}
	return falseObj;
}

static OBJ primTriangle(int argCount, OBJ *args) {
	tftInit();

	// draw triangle
	/*
			obj2int(args[0]),
			obj2int(args[1]),
			obj2int(args[2]),
			obj2int(args[3]),
			obj2int(args[4]),
			obj2int(args[5])
	*/

	return falseObj;
}

static OBJ primText(int argCount, OBJ *args) {
	tftInit();
	OBJ value = args[0];
	char text[256];
	int x = obj2int(args[1]);
	int y = obj2int(args[2]);
	int color24b = obj2int(args[3]);
	int scale = (argCount > 4) ? obj2int(args[4]) : 2;
	int wrap = (argCount > 5) ? (trueObj == args[5]) : true;

	if (IS_TYPE(value, StringType)) {
		sprintf(text, "%s", obj2str(value));
	} else if (trueObj == value) {
		sprintf(text, "true");
	} else if (falseObj == value) {
		sprintf(text, "false");
	} else if (isInt(value)) {
		sprintf(text, "%d", obj2int(value));
	}

	// draw text

	return falseObj;
}

// Simulating a 5x5 LED Matrix

void tftSetHugePixel(int x, int y, int state) {
	// simulate a 5x5 array of square pixels like the micro:bit LED array
	tftInit();

	int lineWidth = 1;
	int squareSize = (DEFAULT_WIDTH + 3) / 5;

	//setRenderColor(state ? 0x00FF00 : 0x000000);

//	draw rectangle:
/*		xInset + ((x - 1) * squareSize) + (x * lineWidth),
		yInset + ((y - 1) * squareSize) + (y * lineWidth),
		squareSize,
		squareSize,
	*/
}

void tftSetHugePixelBits(int bits) {
	if (0 == bits) {
		tftClear();
	} else {
		for (int x = 1; x <= 5; x++) {
			for (int y = 1; y <= 5; y++) {
				tftSetHugePixel(x, y, bits & (1 << ((5 * (y - 1) + x) - 1)));
			}
		}
	}
}

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
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
