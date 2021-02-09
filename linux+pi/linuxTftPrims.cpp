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

#define TFT_WIDTH 800
#define TFT_HEIGHT 600

int useTFT = true;
int tftEnabled = false;
int touchEnabled = false;

SDL_Window *window;
SDL_Renderer* renderer;

int ticks = 0;

void updateMicrobitDisplay() {
	ticks = (ticks + 1) % 100;
	SDL_Event e;
	while (SDL_PollEvent(&e) > 0) {
        switch(e.type) {
            case SDL_QUIT:
                SDL_DestroyWindow(window);
				SDL_Quit();
				tftEnabled = false;
				break;
		}
	}
	if (tftEnabled && (ticks == 0)) {
		SDL_RenderPresent(renderer);
	}
}

void tftInit() {
	if (!tftEnabled) {
		SDL_Init(SDL_INIT_VIDEO);
		window = SDL_CreateWindow("MicroBlocks for Linux",
				SDL_WINDOWPOS_UNDEFINED,
				SDL_WINDOWPOS_UNDEFINED,
				TFT_WIDTH,
				TFT_HEIGHT,
				0);
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
		SDL_RenderClear(renderer);
		tftEnabled = true;
	}
}

void setRenderColor(int color24b) {
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

static OBJ primRect(int argCount, OBJ *args) {
	tftInit();
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int width = obj2int(args[2]);
	int height = obj2int(args[3]);
	int fill = (argCount > 5) ? (trueObj == args[5]) : true;
	setRenderColor(obj2int(args[4]));
	SDL_Rect rect = { x, y, width, height };

	if (fill) {
		SDL_RenderFillRect(renderer, &rect);
	} else {
		SDL_RenderDrawRect(renderer, &rect);
	}

	return falseObj;
}

// TODO We're missing SDL primitives for these.
// I guess I'll have to implement them myself :)
static OBJ primRoundedRect(int argCount, OBJ *args) { return falseObj; }
static OBJ primCircle(int argCount, OBJ *args) { return falseObj; }
static OBJ primTriangle(int argCount, OBJ *args) { return falseObj; }

static OBJ primText(int argCount, OBJ *args) {
	OBJ value = args[0];
	char text[256];
	int x = obj2int(args[1]);
	int y = obj2int(args[2]);
	int color24b = obj2int(args[3]);
	int scale = (argCount > 4) ? obj2int(args[4]) : 2;
	// TODO wrap is ignored for now
	int wrap = (argCount > 5) ? (trueObj == args[5]) : true;
	int width, height;

	TTF_Init();
	TTF_Font* font = TTF_OpenFont("LiberationMono-Regular.ttf", scale * 10);
	SDL_Color color = {
		color24b >> 16,
		(color24b >> 8) & 255,
		color24b & 255
	};

	if (IS_TYPE(value, StringType)) {
		sprintf(text, "%s", obj2str(value));
	} else if (trueObj == value) {
		sprintf(text, "true");
	} else if (falseObj == value) {
		sprintf(text, "false");
	} else if (isInt(value)) {
		sprintf(text, "%d", obj2int(value));
	}

	SDL_Surface* surface = TTF_RenderText_Solid(font, text, color);
	SDL_Texture* message = SDL_CreateTextureFromSurface(renderer, surface);

	TTF_SizeText(font, text, &width, &height);

	SDL_Rect rect = { x, y, width, height };

	SDL_RenderCopy(renderer, message, NULL, &rect);
	SDL_FreeSurface(surface);
	SDL_DestroyTexture(message);
	TTF_CloseFont(font);
	return falseObj;
}

// TODO We could implement some of these via mouse events
static OBJ primTftTouched(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchX(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchY(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchPressure(int argCount, OBJ *args) { return falseObj; }

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

