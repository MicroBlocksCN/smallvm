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

#define DEFAULT_WIDTH 240
#define DEFAULT_HEIGHT 240

static int tftEnabled = false;
static int tftChanged = false;

void tftClear() {
	tftInit();
	EM_ASM_({
		window.ctx.clearRect(0, 0, $0, $1);
	}, DEFAULT_WIDTH, DEFAULT_HEIGHT);
	tftChanged = true;
}

void tftInit() {
	if (!tftEnabled) {
		tftEnabled = true;
		EM_ASM_({
			// initialize an offscreen canvas
			window.offscreenCanvas = document.createElement('canvas');
			window.offscreenCanvas.width = $0;
			window.offscreenCanvas.height = $1;
			window.ctx = window.offscreenCanvas.getContext('2d', { alpha: false });
			window.ctx.imageSmoothingEnabled = false;

			window.rgbFrom24b = function (color24b) {
				return 'rgb(' + ((color24b >> 16) & 255) + ',' +
					((color24b >> 8) & 255) + ',' + (color24b & 255) + ')';
			};
		}, DEFAULT_WIDTH, DEFAULT_HEIGHT);
	}
}

void updateMicrobitDisplay() {
	// transfer the offscreen canvas image to the main canvas
	if (tftEnabled && tftChanged) {
		EM_ASM_({
			if (!window.mainCtx) {
				window.mainCtx = document.querySelector('#screen').getContext('2d', { alpha: false });
				window.mainCtx.imageSmoothingEnabled = false;
			}
			window.mainCtx.drawImage(window.offscreenCanvas, 0, 0);
		});
		tftChanged = false;
	}
}

// TFT Primitives

static OBJ primEnableDisplay(int argCount, OBJ *args) {
	if (trueObj == args[0]) {
		tftInit();
	} else {
		tftClear();
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
	EM_ASM_({
			window.ctx.fillStyle = window.rgbFrom24b($2);
			window.ctx.fillRect($0, $1, 1, 1);
		},
		obj2int(args[0]), // x
		obj2int(args[1]), // y
		obj2int(args[2]) // color
	);
	tftChanged = true;
	return falseObj;
}

static OBJ primLine(int argCount, OBJ *args) {
	tftInit();
	EM_ASM_({
			window.ctx.strokeStyle = window.rgbFrom24b($4);
			window.ctx.beginPath();
			window.ctx.moveTo($0, $1);
			window.ctx.lineTo($2, $3);
			window.ctx.stroke();
		},
		obj2int(args[0]), // x0
		obj2int(args[1]), // y0
		obj2int(args[2]), // x1
		obj2int(args[3]), // y1
		obj2int(args[4]) // color
	);
	tftChanged = true;
	return falseObj;
}

static OBJ primRect(int argCount, OBJ *args) {
	tftInit();
	EM_ASM_({
			if ($5) {
				window.ctx.fillStyle = window.rgbFrom24b($4);
				window.ctx.fillRect($0, $1, $2, $3);
			} else {
				window.ctx.strokeStyle = window.rgbFrom24b($4);
				window.ctx.strokeRect($0, $1, $2, $3);
			}
		},
		obj2int(args[0]), // x
		obj2int(args[1]), // y
		obj2int(args[2]), // width
		obj2int(args[3]), // height
		obj2int(args[4]), // color
		(argCount > 5) ? (trueObj == args[5]) : true // fill
	);
	tftChanged = true;
	return falseObj;
}

static OBJ primCircle(int argCount, OBJ *args) {
	tftInit();
	EM_ASM_({
			var x = $0;
			var y = $1;
			var r = $2;
			var fill = $4;
			if (fill) {
				window.ctx.fillStyle = window.rgbFrom24b($3);
				window.ctx.beginPath();
				window.ctx.arc(x, y, r, 0, 2 * Math.PI);
				window.ctx.fill();
			} else {
				window.ctx.strokeStyle = window.rgbFrom24b($3);
				window.ctx.beginPath();
				window.ctx.arc(x, y, r, 0, 2 * Math.PI);
				window.ctx.stroke();
			}
		},
		obj2int(args[0]), // x
		obj2int(args[1]), // y
		obj2int(args[2]), // radius
		obj2int(args[3]), // color
		(argCount > 4) ? (trueObj == args[4]) : true // fill
	);
	tftChanged = true;
	return falseObj;
}

static OBJ primRoundedRect(int argCount, OBJ *args) {
	tftInit();
	int width = obj2int(args[2]);
	int height = obj2int(args[3]);
	int radius = obj2int(args[4]);

	if (2 * radius >= height) {
		radius = height / 2 - 1;
	}
	if (2 * radius >= width) {
		radius = width / 2 - 1;
	}

	EM_ASM_({
			if ($6) {
				window.ctx.fillStyle = window.rgbFrom24b($5);
			} else {
				window.ctx.strokeStyle = window.rgbFrom24b($5);
			}
			var x = $0;
			var y = $1;
			var w = $2;
			var h = $3;
			var r = $4;

			window.ctx.beginPath();
			window.ctx.moveTo(x + r, y);

			window.ctx.lineTo(x + w - r, y); // top
			window.ctx.arc(x + w - r, y + r, r, 3 * Math.PI / 2, 0, false); // t-r

			window.ctx.lineTo(x + w, y + h - r); // right
			window.ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2, false); // b-r

			window.ctx.lineTo(x + r, y + h); // bottom
			window.ctx.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI, false); // b-l

			window.ctx.lineTo(x, y + r); // left
			window.ctx.arc(x + r, y + r, r, Math.PI , 3 * Math.PI / 2, false); // t-l

			if ($6) {
				window.ctx.fill();
			} else {
				window.ctx.stroke();
			}
		},
		obj2int(args[0]), // x
		obj2int(args[1]), // y
		width, // (2)
		height, // (3)
		radius, // (4)
		obj2int(args[5]), // color
		(argCount > 6) ? (trueObj == args[6]) : true // fill (6)
	);
	tftChanged = true;
	return falseObj;
}

static OBJ primTriangle(int argCount, OBJ *args) {
	tftInit();

	// draw triangle
	EM_ASM_({
			if ($7) {
				window.ctx.fillStyle = window.rgbFrom24b($6);
			} else {
				window.ctx.strokeStyle = window.rgbFrom24b($6);
			}
			window.ctx.beginPath();
			window.ctx.moveTo($0, $1);
			window.ctx.lineTo($2, $3);
			window.ctx.lineTo($3, $4);
			window.ctx.closePath();
			if ($7) {
				window.ctx.fill();
			} else {
				window.ctx.stroke();
			}
		},
		obj2int(args[0]), // x0
		obj2int(args[1]), // y0
		obj2int(args[2]), // x1
		obj2int(args[3]), // y1
		obj2int(args[4]), // x2
		obj2int(args[5]), // y2
		obj2int(args[6]), // color
		(argCount > 7) ? (trueObj == args[7]) : true // fill
	);

	tftChanged = true;
	return falseObj;
}

static OBJ primText(int argCount, OBJ *args) {
	// TODO wrap using measureText. See: https://stackoverflow.com/a/16599668
	tftInit();
	OBJ value = args[0];
	char text[256];

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
	EM_ASM_({
			window.ctx.fillStyle = window.rgbFrom24b($3);
			window.ctx.font = ($4 * 6) + 'px monospace';
			window.ctx.textBaseline = 'top';
			window.ctx.fillText(UTF8ToString($0), $1, $2);
		},
		text, // text
		obj2int(args[1]), // x
		obj2int(args[2]), // y
		obj2int(args[3]), // color
		(argCount > 4) ? obj2int(args[4]) : 2, // scale
		(argCount > 5) ? (trueObj == args[5]) : true // wrap
	);

	tftChanged = true;
	return falseObj;
}

// Simulating a 5x5 LED Matrix

void tftSetHugePixel(int x, int y, int state) {
	// simulate a 5x5 array of square pixels like the micro:bit LED array
	tftInit();
	int minDimension, xInset = 0, yInset = 0;
	if (DEFAULT_WIDTH > DEFAULT_HEIGHT) {
		minDimension = DEFAULT_HEIGHT;
		xInset = (DEFAULT_WIDTH - DEFAULT_HEIGHT) / 2;
	} else {
		minDimension = DEFAULT_WIDTH;
		yInset = (DEFAULT_HEIGHT - DEFAULT_WIDTH) / 2;
	}
	int lineWidth = (minDimension > 60) ? 3 : 1;
	int squareSize = (minDimension - (6 * lineWidth)) / 5;

	EM_ASM_({
			window.ctx.fillStyle = $3 == 0 ? '#000' : '#0F0';
			window.ctx.fillRect($0, $1, $2, $2);
		},
		xInset + ((x - 1) * squareSize) + (x * lineWidth), // x
		yInset + ((y - 1) * squareSize) + (y * lineWidth), // y
		squareSize,
		state
	);

	tftChanged = true;
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
