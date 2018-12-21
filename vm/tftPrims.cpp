/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// tftPrims.cpp - Microblocks TFT screen primitives for the Citilab ED1 board
// Bernat Romagosa, November 2018

#include <Arduino.h>
#include <SPI.h>
#include <stdio.h>

#include "mem.h"
#include "interp.h"

int useTFT = false;

#if defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_ARCH_ESP32)

	#define TFT_BLACK 0
	#define TFT_GREEN 0x7E0

	#define USE_TFT_ESPI false // true - use TFT_eSPI library, false - use AdaFruit GFX library

	#if USE_TFT_ESPI
		#include <TFT_eSPI.h>

		TFT_eSPI tft = TFT_eSPI();

		void tftInit() {
			tft.init();
			tft.setRotation(0);
			tftClear();
			// Turn on backlight on IoT-Bus
			pinMode(33, OUTPUT);
			digitalWrite(33, HIGH);
			useTFT = true;
		}
	#elif defined(ARDUINO_CITILAB_ED1)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7735.h"

		#define TFT_CS	5
		#define TFT_DC	9
		#define TFT_RST	10
		Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_RST);

		void tftInit() {
			tft.initR(INITR_144GREENTAB);
			tft.setRotation(0);
			tftClear();
			useTFT = true;
		}
	#else
		#include "Adafruit_GFX.h"
		#include "Adafruit_ILI9341.h"

		#define TFT_CS	5
		#define TFT_DC	27
		Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC);

		void tftInit() {
			tft.begin();
			tft.setRotation(1);
			tftClear();
			// Turn on backlight on IoT-Bus
			pinMode(33, OUTPUT);
			digitalWrite(33, HIGH);
			useTFT = true;
		}
	#endif

void tftClear() {
	tft.fillScreen(TFT_BLACK);
}

OBJ primEnableDisplay(int argCount, OBJ *args) {
	if (trueObj == args[0]) {
		if (!useTFT) tftInit();
	} else {
		useTFT = false;
	}
}

OBJ primSetPixel(int argCount, OBJ *args) {
	// Re-encode color from 24 bits into 16 bits
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int color24b = obj2int(args[2]);
	int r = (color24b >> 16) & 0xFF;
	int g = (color24b >> 8) & 0xFF;
	int b = color24b & 0xFF;
	// convert 24-bit RGB888 format to 16-bit RGB565
	int color16b = ((r << 8) & 0xF800) | ((g << 3) & 0x7E0) | ((b >> 3) & 0x1F);
	tft.drawPixel(x, y, color16b);
}

void tftSetHugePixel(int x, int y, int state) {
	// simulate a 5x5 array of square pixels like the micro:bit LED array
	int d, xInset = 0, yInset = 0;
	if (tft.width() > tft.height()) {
		d = tft.height() / 5;
		xInset = (tft.width() - tft.height()) / 2;
	} else {
		d = tft.width() / 5;
		yInset = (tft.height() - tft.width()) / 2;
	}
	tft.fillRect(
		xInset + ((x - 1) * d), // x
		yInset + ((y - 1) * d), // y
		d - 5, d - 5, // rect width and height
		state ? TFT_GREEN : TFT_BLACK);
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

#else // stubs

void tftInit() { }
void tftClear() { }
void tftSetHugePixel(int x, int y, int state) { }
void tftSetHugePixelBits(int bits) { }

OBJ primEnableDisplay(int argCount, OBJ *args) { return falseObj; }
OBJ primSetPixel(int argCount, OBJ *args) { return falseObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	"enableDisplay", primEnableDisplay,
	"setPixel", primSetPixel,
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
