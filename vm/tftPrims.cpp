/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// tftPrims.cpp - Microblocks TFT screen primitives for the Citilab ED1 board
// Bernat Romagosa, November 2018

#ifdef ARDUINO_CITILAB_ED1

#include <Arduino.h>
#include <stdio.h>

#include "mem.h"
#include "interp.h"

#include <SPI.h>
#include <TFT_eSPI.h>

TFT_eSPI tft = TFT_eSPI();

void tftInit() {
	tft.init();
	tft.setRotation(0);
	tftClear();
}

void tftClear() {
	tft.fillScreen(TFT_BLACK);
}

OBJ primTftSetPixel(int argCount, OBJ *args) {
	// Re-encode color from 24 bits into 16 bits
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int color24b = obj2int(args[2]);
	int r = (color24b >> 16) & 0xFF;
	int g = (color24b >> 8) & 0xFF;
	int b = color24b & 0xFF;
	int color16b = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
	tft.drawPixel(x, y, color16b);
}

void tftSetHugePixel(int x, int y, int state) {
	// simulate a 5x5 LED array like the one in the micro:bit
	int w = tft.width() / 5;
	int h = tft.height() / 5;
	tft.fillRect(
		(x - 1) * w,	// x position
		(y - 1) * h,	// y position
		w,				// "pixel" width
		h,				// "pixel" height
		state ? TFT_GREEN : TFT_BLACK);
}

void tftSetHugePixelBits(int bits) {
	for (int x = 1; x <= 5; x++) {
		for (int y = 1; y <= 5; y++) {
			tftSetHugePixel(x, y, bits & (1 << ((5 * (y - 1) + x) - 1)));
		}
	}
}

// Primitives

static PrimEntry entries[] = {
	"setPixel", primTftSetPixel,
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}

#endif
