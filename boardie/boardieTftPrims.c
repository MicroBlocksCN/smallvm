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

static int touchEnabled = false;
static int tftEnabled = false;
static int tftShouldUpdate = false;

void tftChanged() { tftShouldUpdate = true; }

void tftClear() {
	tftInit();
	EM_ASM_({
		window.ctx.fillStyle = "#000";
		window.ctx.fillRect(0, 0, $0, $1);
	}, DEFAULT_WIDTH, DEFAULT_HEIGHT);
	tftChanged();
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

			var adafruitFont = new FontFace('adafruit', 'url(adafruit_font.ttf)');

			adafruitFont.load().then((font) => { document.fonts.add(font); });

			window.rgbFrom24b = function (color24b) {
				return 'rgb(' + ((color24b >> 16) & 255) + ',' +
					((color24b >> 8) & 255) + ',' + (color24b & 255) + ')';
			};
		}, DEFAULT_WIDTH, DEFAULT_HEIGHT);
	}
}

void updateMicrobitDisplay() {
	// transfer the offscreen canvas image to the main canvas
	if (tftEnabled && tftShouldUpdate) {
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
		tftShouldUpdate = false;
	}
}

// TFT Primitives

static OBJ primSetBacklight(int argCount, OBJ *args) {
	return falseObj; // noop in Boardie
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
	tftChanged();
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
	tftChanged();
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
	tftChanged();
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
	tftChanged();
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
	tftChanged();
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
			window.ctx.lineTo($4, $5);
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
	tftChanged();
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
			var textColor = $3;
			var scale = $4;
			var wrap = $5;
			var bgColor = $6;
			var x = $1 - scale;
			var y = $2 - scale;
			if (bgColor >= 0) {
				var w = scale * 6 * text.length;
				var h = scale * 8; // text height on boards is scale * 8
				window.ctx.fillStyle = window.rgbFrom24b(bgColor);
				window.ctx.fillRect(x + scale, y + scale, w, h);
			}
			// there is a weird rounding artifact at scale 3
			var fontSize = (scale == 3) ? (scale * 10.5) : (scale * 11);
			window.ctx.font = fontSize + 'px adafruit';
			window.ctx.fillStyle = window.rgbFrom24b(textColor);
			window.ctx.textBaseline = 'top';
			text.split("").forEach(
				(c) => {
					window.ctx.fillText(c, x, y);
					x += scale * 6;
					if (wrap && (x + scale * 6 >= window.ctx.canvas.width)) {
						// wrap
						x = 0 - scale;
						y += fontSize * 3 / 4;
					}
				}
			);
		},
		text, // text
		obj2int(args[1]), // x
		obj2int(args[2]), // y
		obj2int(args[3]), // text color
		(argCount > 4) ? obj2int(args[4]) : 2, // scale
		(argCount > 5) ? (trueObj == args[5]) : true, // wrap
		(argCount > 6) ? obj2int(args[6]) : -1 // background color
	);

	tftChanged();
	return falseObj;
}

static OBJ primClear(int argCount, OBJ *args) {
	tftClear();
	return falseObj;
}

// defer/force update

static OBJ primDeferUpdates(int argCount, OBJ *args) {
	return falseObj; // noop; Boardie always defers updates
}

static OBJ primResumeUpdates(int argCount, OBJ *args) {
	// Return control to the browser to allow display update.

	taskSleep(0); // ends the current interpreter step
	return falseObj;
}

// 8-bit primitives

static OBJ primMergeBitmap(int argCount, OBJ *args) {
	tftInit();
	EM_ASM_({
			var bufferWidth = window.ctx.canvas.width / $4;
			var bufferHeight = window.ctx.canvas.height / $4;
			var bitmapHeight = $2 / $1;
			for (var y = 0; y < bitmapHeight; y++) {
				if ((y + $7) < bufferHeight && (y + $7) >= 0) {
					for (var x = 0; x < $1; x++) {
						if ((x + $6) < bufferWidth && (x + $6) >= 0) {
							var pixelValue = HEAPU8[$0 + y * $1 + x];
							if (pixelValue !== $5) {
								var bufIndex = ($7 + y) * bufferWidth + x + $6;
								HEAPU8[$3 + bufIndex] = pixelValue;
							}
						}
					}
				}
			}
		},
		(uint8 *) &FIELD(args[0], 0),	// $0, bitmap
		obj2int(args[1]),				// $1, bitmap width
		BYTES(args[0]),					// $2, bitmap byte size
		(uint8 *) &FIELD(args[2], 0),	// $3, buffer
		obj2int(args[3]),				// $4, scale
		obj2int(args[4]),				// $5, transparent color index
		obj2int(args[5]),				// $6, destination x
		obj2int(args[6])				// $7, destination y
	);
	return falseObj;
}

static OBJ primDrawBuffer(int argCount, OBJ *args) {
	tftInit();

	int originX = 0;
	int originY = 0;
	int copyWidth = -1;
	int copyHeight = -1;

	if (argCount > 6) {
		originX = obj2int(args[3]);
		originY = obj2int(args[4]);
		copyWidth = obj2int(args[5]);
		copyHeight = obj2int(args[6]);
	}

	// read palette into a JS object first
	for (int i = 0; i < obj2int(FIELD(args[1], 0)); i ++) {
		EM_ASM_({
				if (!window.palette) { window.palette = []; }
				window.palette[$1] = $0;
			},
			obj2int(FIELD(args[1], i + 1)),
			i
		);
	}

	EM_ASM_({
			var scale = $1 || 1;
			var originX = $2;
			var originY = $3;
			var bufferWidth = Math.ceil(window.ctx.canvas.width / scale);
			var bufferHeight = Math.ceil(window.ctx.canvas.height / scale);
			var originWidth = $4 >= 0 ? $4 : bufferWidth;
			var originHeight = $5 >= 0 ? $5 : bufferHeight;

			var imgData = window.ctx.createImageData(originWidth, originHeight);
			var pixelIndex = 0;

			// Make an extra canvas where we'll draw the buffer first, so we can
			// later scale it up to the offscreen canvas.
			var canvas = document.createElement('canvas');
			canvas.width = originWidth;
			canvas.height = originHeight;

			// Read the indices from the buffer and turn them into color values
			// from the palette, and transfer them into the imgData object.
			for (var y = originY; y < (originY + originHeight); y ++) {
				for (var x = originX; x < (originX + originWidth); x ++) {
					var color =
						window.palette[HEAPU8[$0 + y * bufferWidth + x]];
					imgData.data[pixelIndex] = color >> 16; // R
					imgData.data[pixelIndex + 1] = (color >> 8) & 255; // G
					imgData.data[pixelIndex + 2] = color & 255; // B
					imgData.data[pixelIndex + 3] = 255; // A
					pixelIndex += 4;
				}
			}

			// Draw the image data into the canvas, then draw it scaled to the
			// offscreen canvas.
			// Note: we could do the same without an extra canvas by using
			// createImageBitmap, but that returns a promise and we need this
			// operation to be synchronous. Additionally, we've measured this
			// method to be pretty much as fast as the other one.
			canvas.getContext('2d').putImageData(imgData, 0, 0);
			window.ctx.drawImage(
				canvas,
				originX * scale,
				originY * scale,
				originWidth * scale,
				originHeight * scale
			);
		},
		(uint8 *) &FIELD(args[0], 0),	// $0, buffer
		obj2int(args[2]),				// $1, scale
		originX,						// $2
		originY,						// $3
		copyWidth,						// $4
		copyHeight						// $5
	);
	tftChanged();
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
			if (!window.mbDisplayColor) { window.mbDisplayColor = 0x00FF00; }
			window.ctx.fillStyle = $3 == 0 ?
				'#000' :
				window.rgbFrom24b(window.mbDisplayColor);
			window.ctx.fillRect($0, $1, $2, $2);
		},
		xInset + ((x - 1) * squareSize) + (x * lineWidth), // x
		yInset + ((y - 1) * squareSize) + (y * lineWidth), // y
		squareSize,
		state
	);

	tftChanged();
}

void tftSetHugePixelBits(int bits) {
	tftClear(); // erase any TFT graphics that might be on the screen
	for (int x = 1; x <= 5; x++) {
		for (int y = 1; y <= 5; y++) {
			tftSetHugePixel(x, y, bits & (1 << ((5 * (y - 1) + x) - 1)));
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
	{"setBacklight", primSetBacklight},
	{"getWidth", primGetWidth},
	{"getHeight", primGetHeight},
	{"setPixel", primSetPixel},
	{"line", primLine},
	{"rect", primRect},
	{"roundedRect", primRoundedRect},
	{"circle", primCircle},
	{"triangle", primTriangle},
	{"text", primText},
	{"clear", primClear},

	{"deferUpdates", primDeferUpdates},
	{"resumeUpdates", primResumeUpdates},

	{"mergeBitmap", primMergeBitmap},
	{"drawBuffer", primDrawBuffer},

	{"tftTouched", primTftTouched},
	{"tftTouchX", primTftTouchX},
	{"tftTouchY", primTftTouchY},
	{"tftTouchPressure", primTftTouchPressure},
};

void addTFTPrims() {
	addPrimitiveSet(TFTPrims, "tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
