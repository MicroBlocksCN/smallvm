/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxTftPrims.cpp - Microblocks TFT screen primitives simulated on an SDL
//                     window
// Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

#include "mem.h"
#include "interp.h"

// Debug: Uncommenting the above causes openSDLWindow to fail with a segmentation fault
// on John's Ubuntu 20.04.
// void notCalled() { TTF_Init(); }

// Define this to disable SDL_ttf and avoids segmentation fault on John's Ubuntu 20.04
// #define DISABLE_TRUE_TYPE

#define TFT_WIDTH 800
#define TFT_HEIGHT 600

static int mouseDown = false;
static int mouseX = -1;
static int mouseY = -1;
static int mouseDownTime = 0;

static int tftEnabled = false;
static SDL_Window *window;
static SDL_Renderer* renderer;
static int ticks = 0;

// Helper Functions

static void drawText(char *s, int x, int y, int color24b, int scale, int wrapFlag) {
	// Draw the given string with the given position, color, scale and wrapFlag
	// TODO wrap is ignored for now

	SDL_Color color = { color24b >> 16, (color24b >> 8) & 255, color24b & 255 };

#ifndef DISABLE_TRUE_TYPE
	TTF_Font* font = TTF_OpenFont("LiberationMono-Regular.ttf", 10);
	SDL_Surface* surface = TTF_RenderUTF8_Solid(font, s, color);

	int width, height;
	TTF_SizeText(font, s, &width, &height);
	SDL_Rect rect = { x, y, width, height };

	SDL_Texture* message = SDL_CreateTextureFromSurface(renderer, surface);
	SDL_RenderCopy(renderer, message, NULL, &rect);

	SDL_FreeSurface(surface);
	SDL_DestroyTexture(message);
	TTF_CloseFont(font);
#endif
}

void updateMicrobitDisplay() {
	ticks = (ticks + 1) % 100;
	SDL_Event e;
	while (SDL_PollEvent(&e) > 0) {
        switch(e.type) {
            case SDL_QUIT:
                SDL_DestroyWindow(window);
				SDL_Quit();
				tftEnabled = false;
				exit(0); // quit from GnuBlocks
				break;
			case SDL_MOUSEBUTTONDOWN:
				mouseDownTime = millisecs();
                mouseDown = true;
                break;
			case SDL_MOUSEBUTTONUP:
                mouseDown = false;
				mouseX = -1;
				mouseY = -1;
                break;
		}
	}
	if (tftEnabled && (ticks == 0)) {
		SDL_RenderPresent(renderer);
	}
}

void tftInit() {
	if (!tftEnabled) {
		SDL_Init(SDL_INIT_EVERYTHING);
		window = SDL_CreateWindow("MicroBlocks for Linux",
				SDL_WINDOWPOS_UNDEFINED,
				SDL_WINDOWPOS_UNDEFINED,
				TFT_WIDTH,
				TFT_HEIGHT,
				0);
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
		SDL_RenderClear(renderer);

#ifndef DISABLE_TRUE_TYPE
		TTF_Init();
#endif
		tftEnabled = true;
	}
}

static void setRenderColor(int color24b) {
	SDL_SetRenderDrawColor(
			renderer,
			color24b >> 16,
			(color24b >> 8) & 255,
			color24b & 255,
			255);
}

void tftClear() {
	tftInit();
	setRenderColor(0);
	SDL_RenderClear(renderer);
}

// TFT Primitives

static OBJ primEnableDisplay(int argCount, OBJ *args) {
	if (trueObj == args[0]) {
		tftInit();
	} else {
		if (window) {
			SDL_DestroyWindow(window);
			SDL_Quit();
			tftEnabled = false;
		}
	}
	return falseObj;
}

static OBJ primGetWidth(int argCount, OBJ *args) {
	return int2obj(TFT_WIDTH);
}

static OBJ primGetHeight(int argCount, OBJ *args) {
	return int2obj(TFT_HEIGHT);
}

static OBJ primSetPixel(int argCount, OBJ *args) {
	tftInit();
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	setRenderColor(obj2int(args[2]));
	SDL_RenderDrawPoint(renderer, x, y);
	return falseObj;
}

static OBJ primLine(int argCount, OBJ *args) {
	tftInit();
	int x0 = obj2int(args[0]);
	int y0 = obj2int(args[1]);
	int x1 = obj2int(args[2]);
	int y1 = obj2int(args[3]);
	setRenderColor(obj2int(args[4]));
	SDL_RenderDrawLine(renderer, x0, y0, x1, y1);
	return falseObj;
}

static void drawRect(int x, int y, int width, int height, int fill) {
	SDL_Rect rect = { x, y, width, height };
	if (fill) {
		SDL_RenderFillRect(renderer, &rect);
	} else {
		SDL_RenderDrawRect(renderer, &rect);
	}
}

static OBJ primRect(int argCount, OBJ *args) {
	tftInit();
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int width = obj2int(args[2]);
	int height = obj2int(args[3]);
	int fill = (argCount > 5) ? (trueObj == args[5]) : true;
	setRenderColor(obj2int(args[4]));
	drawRect(x, y, width, height, fill);
	return falseObj;
}

static void drawOctaves(int x, int y, int originX, int originY, int fill) {
	// when filling we also want to render the contour, otherwise there are
	// artifacts in the pixels next to the borders
	SDL_RenderDrawPoint(renderer, originX + x, originY + y);
	SDL_RenderDrawPoint(renderer, originX + x, originY - y);
	SDL_RenderDrawPoint(renderer, originX - x, originY + y);
	SDL_RenderDrawPoint(renderer, originX - x, originY - y);
	SDL_RenderDrawPoint(renderer, originX + y, originY + x);
	SDL_RenderDrawPoint(renderer, originX + y, originY - x);
	SDL_RenderDrawPoint(renderer, originX - y, originY + x);
	SDL_RenderDrawPoint(renderer, originX - y, originY - x);
	if (fill) {
		SDL_RenderDrawLine(renderer, originX - x, originY + y, originX + x, originY + y);
		SDL_RenderDrawLine(renderer, originX - x, originY - y, originX + x, originY - y);
		SDL_RenderDrawLine(renderer, originX - y, originY + x, originX + y, originY + x);
		SDL_RenderDrawLine(renderer, originX - y, originY - x, originX + y, originY - x);
	}
}

static void drawCircle(int originX, int originY, int radius, int fill) {
	// Bresenham's circle algorithm
	int x = 0;
	int y = radius;
	int decision = 3 - 2 * radius;
	drawOctaves(x, y, originX, originY, fill);
	while (x < y) {
		x++;
		if (decision > 0) {
			y--;
			decision = decision + 4 * (x - y) + 10;
		} else {
			decision = decision + 4 * x + 6;
		}
		drawOctaves(x, y, originX, originY, fill);
	}
}

static OBJ primCircle(int argCount, OBJ *args) {
	tftInit();
	int originX = obj2int(args[0]);
	int originY = obj2int(args[1]);
	int radius = obj2int(args[2]);
	setRenderColor(obj2int(args[3]));
	int fill = (argCount > 4) ? (trueObj == args[4]) : true;
	drawCircle(originX, originY, radius, fill);
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

	setRenderColor(obj2int(args[5]));
	int fill = (argCount > 6) ? (trueObj == args[6]) : true;
	if (fill) {
		drawRect(x, y + radius, width, height - 2 * radius, fill);
		drawRect(x + radius, y, width - 2 * radius, height, fill);
		drawCircle(x + radius, y + radius + 1, radius, fill);
		drawCircle(x + width - radius - 1, y + radius + 1, radius, fill);
		drawCircle(x + radius, y + height - radius - 1, radius, fill);
		drawCircle(x + width - radius - 1, y + height - radius - 1, radius, fill);
	}
	return falseObj;
}

static int triangleArea2x(int x[], int y[]) {
	return (x[0] * (y[1] - y[2]) +
			x[1] * (y[2] - y[0]) +
			x[2] * (y[0] - y[1]));
}

static void debugTriangle(int x[], int y[], int increment) {
	// DEBUG show vertex names
	char txt[100];
	int width, height;
	SDL_Color color = {255,255,255};

	sprintf(txt, "v0(%d,%d)", x[0],y[0]);
	drawText(txt, x[0], y[0], 0xFFFFFF, 1, true);

	sprintf(txt, "v1(%d,%d)%s", x[1],y[1], increment == 1 ? "->" : "<-");
	drawText(txt, x[1], y[1], 0xFFFFFF, 1, true);

	sprintf(txt, "v2(%d,%d)", x[2],y[2]);
	drawText(txt, x[2], y[2], 0xFFFFFF, 1, true);

	sprintf(txt, "area: %d", abs(triangleArea2x(x,y)));
	drawText(txt, 10, 20, 0xFFFFFF, 1, true);
}

static void sortVertices(int x[], int y[], int x0, int y0, int x1, int y1, int x2, int y2) {
	// TODO this can be simplified
	// Special case: two vertices share the same y
	if (y0 == y1) {
		if (y0 > y2) {
			x[0] = x2; y[0] = y2;
			x[1] = x1; y[1] = y1;
			x[2] = x0; y[2] = y0;
		} else {
			x[0] = x0; y[0] = y0;
			x[1] = x1; y[1] = y1;
			x[2] = x2; y[2] = y2;
		}
		return;
	} else if (y0 == y2) {
		if (y0 > y1) {
			x[0] = x1; y[0] = y1;
			x[1] = x0; y[1] = y0;
			x[2] = x2; y[2] = y2;
		} else {
			x[0] = x0; y[0] = y0;
			x[1] = x2; y[1] = y2;
			x[2] = x1; y[2] = y1;
		}
		return;
	} else if (y1 == y2) {
		if (y1 > y0) {
			x[0] = x0; y[0] = y0;
			x[1] = x1; y[1] = y1;
			x[2] = x2; y[2] = y2;
		} else {
			x[0] = x2; y[0] = y2;
			x[1] = x1; y[1] = y1;
			x[2] = x0; y[2] = y0;
		}
		return;
	}

	// Find the topmost vertex
	if ((y0 < y1) && (y0 < y2)) {
		x[0] = x0; y[0] = y0;
	} else if ((y1 < y0) && (y1 < y2)) {
		x[0] = x1; y[0] = y1;
	} else {
		x[0] = x2; y[0] = y2;
	}
	// Find the middle vertex
	if (((y0 > y2) && (y0 < y1)) || ((y0 < y2) && (y0 > y1))) {
		x[1] = x0; y[1] = y0;
	} else if (((y1 > y0) && (y1 < y2)) || ((y1 < y0) && (y1 > y2))) {
		x[1] = x1; y[1] = y1;
	} else {
		x[1] = x2; y[1] = y2;
	}
	// Find the bottommost vertex
	if ((y0 > y1) && (y0 > y2)) {
		x[2] = x0; y[2] = y0;
	} else if ((y1 > y0) && (y1 > y2)) {
		x[2] = x1; y[2] = y1;
	} else {
		x[2] = x2; y[2] = y2;
	}
}

static OBJ primTriangle(int argCount, OBJ *args) {
	tftInit();
	setRenderColor(obj2int(args[6]));

	int x[3];
	int y[3];

	// Sort the vertices so that x[0],y[0] is the topmost one and x[2],y[2] is
	// the bottommost one
	sortVertices(
			x,
			y,
			obj2int(args[0]),
			obj2int(args[1]),
			obj2int(args[2]),
			obj2int(args[3]),
			obj2int(args[4]),
			obj2int(args[5]));

	// Just draw three lines
	SDL_RenderDrawLine(renderer, x[0], y[0], x[1], y[1]);
	SDL_RenderDrawLine(renderer, x[1], y[1], x[2], y[2]);
	SDL_RenderDrawLine(renderer, x[2], y[2], x[0], y[0]);

	if (y[0] == y[1] && y[1] == y[2]) return falseObj;
	if (x[0] == x[1] && x[1] == x[2]) return falseObj;

	int area = triangleArea2x(x, y);
	int increment = (area < 0) ? 1 : -1;
	int fill = (argCount > 7) ? (trueObj == args[7]) : true;
	if (fill) {
		while ((abs(x[1]) < TFT_WIDTH) && // This should never happen
				(increment != area/abs(area))) {
			SDL_RenderDrawLine(renderer, x[1], y[1], x[0], y[0]);
			SDL_RenderDrawLine(renderer, x[1], y[1], x[2], y[2]);
			x[1] += increment;
			area = triangleArea2x(x,y);
		}
	} else {
		//debugTriangle(x, y, increment);
	}

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

	drawText(text, x, y, color24b, scale, wrap);
	return falseObj;
}

// Simulating a 5x5 LED Matrix

void tftSetHugePixel(int x, int y, int state) {
	// simulate a 5x5 array of square pixels like the micro:bit LED array
	tftInit();
	int minDimension, xInset = 0, yInset = 0;
	if (TFT_WIDTH > TFT_HEIGHT) {
		minDimension = TFT_HEIGHT;
		xInset = (TFT_WIDTH - TFT_HEIGHT) / 2;
	} else {
		minDimension = TFT_WIDTH;
		yInset = (TFT_HEIGHT - TFT_WIDTH) / 2;
	}
	int lineWidth = (minDimension > 60) ? 3 : 1;
	int squareSize = (minDimension - (6 * lineWidth)) / 5;

	setRenderColor(state ? 0x00FF00 : 0x000000);

	SDL_Rect rect = {
		xInset + ((x - 1) * squareSize) + (x * lineWidth),
		yInset + ((y - 1) * squareSize) + (y * lineWidth),
		squareSize,
		squareSize,
	};

	SDL_RenderFillRect(renderer, &rect);
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

static OBJ primTftTouched(int argCount, OBJ *args) {
	return mouseDown ? trueObj : falseObj;
}

static OBJ primTftTouchX(int argCount, OBJ *args) {
	SDL_GetMouseState(&mouseX, &mouseY);
	return int2obj(mouseDown ? mouseX : -1);
}

static OBJ primTftTouchY(int argCount, OBJ *args) {
	SDL_GetMouseState(&mouseX, &mouseY);
	return int2obj(mouseDown ? mouseY : -1);
}

static OBJ primTftTouchPressure(int argCount, OBJ *args) {
	int mousePressure;
	if (mouseDown) {
		mousePressure = (millisecs() - mouseDownTime);
		if (mousePressure > 4095) mousePressure = 4095;
	} else {
		mousePressure = -1;
	}
	return int2obj(mousePressure);
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
	{"tftTouched", primTftTouched},
	{"tftTouchX", primTftTouchX},
	{"tftTouchY", primTftTouchY},
	{"tftTouchPressure", primTftTouchPressure},
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
