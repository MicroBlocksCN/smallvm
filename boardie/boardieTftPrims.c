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

static int touchEnabled = false;

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
				window.mainCtx =
					document.querySelector('#screen').getContext(
						'2d',
						{ alpha: false }
					);
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
			var text = UTF8ToString($0);
			// subtract a little bit from x, proportional to font scale, to make
			// it match the font on physical boards
			var x = $1 - $4;
			var y = $2 - $4;
			// there is a weird rounding artifact at scale 3
			var fontSize = ($4 == 3) ? ($4 * 10.5) : ($4 * 11);
			window.ctx.font = fontSize + 'px adafruit';
			window.ctx.fillStyle = window.rgbFrom24b($3);
			window.ctx.textBaseline = 'top';
			text.split("").forEach(
				(c) => {
					window.ctx.fillText(c, x, y);
					x += $4 * 6;
					if ($5 && (x + $4 * 6 >= window.ctx.canvas.width)) {
						// wrap
						x = 0 - $4;
						y += fontSize * 3 / 4;
					}
				}
			);
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

static OBJ primDrawBitmap(int argCount, OBJ *args) {
	// Draw an RGB565 bitmap endoded into a byteArray in a file
	tftInit();
	OBJ value = args[0];
	char fromFile = IS_TYPE(value, StringType);
	char bitmapFile[256];

	// args[0] can contain either a file name or a ByteArray with the bitmap
	// encoded in RGB565 format
	if (fromFile) { sprintf(bitmapFile, "%s", obj2str(value)); }

	EM_ASM_({
			var fromFile = $6;
			if (fromFile) { var file = window.localStorage[UTF8ToString($0)]; }
			var imgData = window.ctx.createImageData($3, $4);
			var pixelIndex = 0;

			// ignore the first 4 bytes (header)
			for (var i = 4; i < $3 * $4 * 2 + 4; i += 2) {
				var rgb565 = fromFile ?
					(file.charCodeAt(i) | (file.charCodeAt(i + 1) << 8)) :
					(HEAP8[$0 + i] | (HEAP8[$0 + i + 1] << 8));

				imgData.data[pixelIndex] = (rgb565 >> 11) << 3; // R
				imgData.data[pixelIndex + 1] = ((rgb565 >> 5) & 0x3F) << 2; // G
				imgData.data[pixelIndex + 2] = (rgb565 & 0x1F) << 3; // B
				imgData.data[pixelIndex + 3] = (rgb565 == $5) ? 0 : 0xFF; // A
				pixelIndex += 4;
			}
			// putImageData would destroy the original image and thus
			// transparent pixels would just appear black
			createImageBitmap(imgData).then(
				(image) => { window.ctx.drawImage(image, $1, $2); }
			);
		},
		// we cast the string to uint8 * to prevent compiler warning...
		fromFile ? (uint8 *) bitmapFile : (uint8 *) &FIELD(value, 0),
		obj2int(args[1]), 	// $1, destination x
		obj2int(args[2]),	// $2, destination y
		obj2int(args[3]), 	// $3, width
		obj2int(args[4]), 	// $4, height
		obj2int(args[5]),	// $5, alpha color (in RGB565)
		fromFile
	);

	tftChanged = true;
	yield();
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

// TFT Touch Primitives

// Mouse support
void initMouseHandler() {
	if (!touchEnabled) {
		EM_ASM_({
			var screen = window.document.querySelector('#screen');
			window.mouseX = 0;
			window.mouseY = 0;
			window.mouseDown = false;
			window.mouseDownTime = 0;
			screen.addEventListener('pointermove', function (event) {
				window.mouseX = Math.floor(event.clientX - screen.offsetLeft);
				window.mouseY = Math.floor(event.clientY - screen.offsetTop);
			}, false);
			screen.addEventListener('pointerdown', function (event) {
				window.mouseDown = true;
				window.mouseDownTime = Date.now();
			}, false);
			screen.addEventListener('pointerup', function (event) {
				window.mouseDown = false;
				window.mouseDownTime = 0;
			}, false);
		});
	touchEnabled = true;
	}
}

static OBJ primTftTouched(int argCount, OBJ *args) {
	initMouseHandler();
	return EM_ASM_INT({ return window.mouseDown }) ? trueObj : falseObj;
}

static OBJ primTftTouchX(int argCount, OBJ *args) {
	initMouseHandler();
	return int2obj(EM_ASM_INT({
		return window.mouseDown ? window.mouseX : -1
	}));
}

static OBJ primTftTouchY(int argCount, OBJ *args) {
	initMouseHandler();
	return int2obj(EM_ASM_INT({
		return window.mouseDown ? window.mouseY : -1
	}));
}

static OBJ primTftTouchPressure(int argCount, OBJ *args) {
	initMouseHandler();
	return int2obj(EM_ASM_INT({
		if (window.mouseDown) {
			var mousePressure = (Date.now() - window.mouseDownTime);
			if (mousePressure > 4095) { mousePressure = 4095; }
		} else {
			mousePressure = -1;
		}
		return mousePressure;
	}));
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
	{"drawBitmap", primDrawBitmap},
	{"tftTouched", primTftTouched},
	{"tftTouchX", primTftTouchX},
	{"tftTouchY", primTftTouchY},
	{"tftTouchPressure", primTftTouchPressure},
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
