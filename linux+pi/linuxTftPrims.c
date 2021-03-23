/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2020 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxTftPrims.cpp - Microblocks TFT screen primitives simulated on an SDL window
// Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>

#include <SDL2/SDL.h>

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
static SDL_Window *window;
static SDL_Renderer* renderer;
static int lastRefreshTime = 0;

extern int KEY_SCANCODE[];

// Helper Functions

static void setRenderColor(int color24b) {
	SDL_SetRenderDrawColor(
		renderer, (color24b >> 16) & 255, (color24b >> 8) & 255, color24b & 255, 255);
}

void tftClear() {
	tftInit();
	setRenderColor(0);
	SDL_RenderClear(renderer);
}

// Text Rendering with PangoCairo

#ifdef USE_PANGO

#include <pango/pangocairo.h>

int onePixel;
PangoFontDescription *pangoFont = NULL;
cairo_surface_t *textMeasureSurface = NULL;

static void setFont(char *fontName, int fontSize, int isBold, int isItalic) {
	if (!pangoFont) pangoFont = pango_font_description_new();
	pango_font_description_set_family(pangoFont, fontName);
	int fudgeFactor = (pango_version() > 14403) ? 1 : 0;
	pango_font_description_set_size(pangoFont, (fontSize - fudgeFactor) * PANGO_SCALE);
	if (isBold) pango_font_description_set_weight(pangoFont, 700);
	if (isItalic) pango_font_description_set_style(pangoFont, PANGO_STYLE_ITALIC);
}

static void measureText(char *s, int *width, int *height) {
	if (!textMeasureSurface) {
		cairo_surface_t *cairoSurface = cairo_image_surface_create_for_data(
			(void *) &onePixel, CAIRO_FORMAT_ARGB32, 1, 1, 4);
	}
	cairo_t *cr = cairo_create(textMeasureSurface);
	PangoLayout *layout = pango_cairo_create_layout(cr);
	pango_layout_set_font_description(layout, pangoFont);
	pango_layout_set_text(layout, s, strlen(s));
	pango_layout_get_pixel_size(layout, width, height); // get rendered text size

	// cleanup layout and context
	g_object_unref(layout);
	cairo_destroy(cr);
}

static void drawText(char *s, int x, int y, int color24b, int scale, int wrapFlag) {
	// Draw the given string with the given position, color, scale and wrapFlag
	// TODO wrap is ignored for now

	SDL_Color color = { color24b >> 16, (color24b >> 8) & 255, color24b & 255 };
	int textW, textH;
	int fontSize = 6 * scale;
	setFont("Arial", fontSize, true, false);
	measureText(s, &textW, &textH);

	// Create surface for text rendering (could be cached if slow)
	SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormat(0, textW, textH, 32, SDL_PIXELFORMAT_ARGB8888);

	// PangoCairo setup
	cairo_surface_t *cairoSurface = cairo_image_surface_create_for_data(
		surface->pixels, CAIRO_FORMAT_ARGB32, surface->w, surface->h, (4 * surface->w));
	cairo_t *cr = cairo_create(cairoSurface);
	PangoLayout *layout = pango_cairo_create_layout(cr);
	pango_layout_set_font_description(layout, pangoFont);
	pango_layout_set_text(layout, s, strlen(s));

	// Render the text onto surface
	cairo_set_source_rgba(cr,
		((color24b >> 16) & 255) / 255.0,
		((color24b >> 8) & 255) / 255.0,
		(color24b & 255) / 255.0,
		1.0);
	pango_cairo_show_layout(cr, layout);

	// PangoCairo clean up
	g_object_unref(layout);
	cairo_destroy(cr);
	cairo_surface_destroy(cairoSurface);

	// Copy rendered text to the display
	SDL_Rect rect = {x, y, surface->w, surface->h};
	SDL_Texture* tempTexture = SDL_CreateTextureFromSurface(renderer, surface);
	SDL_RenderCopy(renderer, tempTexture, NULL, &rect);
	SDL_DestroyTexture(tempTexture);
	SDL_FreeSurface(surface);
}

#else

#include <SDL2/SDL_ttf.h>

static int ttfInitialized = false;
extern char fontLiberationMonoRegular[];

static void base64decode(uint8_t *data, int len, uint8_t *out, int *outLen); // forward reference

static TTF_Font* openTTFFont(int pointSize) {
	unsigned char fontFile[108200];
	int fontFileLen = sizeof(fontFile);

	char *base64Data = fontLiberationMonoRegular;
	base64decode((uint8_t *) base64Data, strlen(base64Data), fontFile, &fontFileLen);

	TTF_Font *result = TTF_OpenFontRW(SDL_RWFromConstMem(fontFile, fontFileLen), true, pointSize);
	if (!result) printf("Font open error: %s\n", TTF_GetError());
	return result;
}

static void drawText(char *s, int x, int y, int color24b, int scale, int wrapFlag) {
	// Draw the given string with the given position, color, scale and wrapFlag
	// TODO wrap is ignored for now

	if (!ttfInitialized) { // initialize TTF before first use
		int err = TTF_Init();
		if (err) {
			printf("TTF_Init error: %s\n", TTF_GetError());
			return;
		}
		ttfInitialized = true;
	}

	SDL_Color color = { color24b >> 16, (color24b >> 8) & 255, color24b & 255 };

	TTF_Font* font = openTTFFont(10 * scale);
	if (!font) return;

	SDL_Surface* surface = TTF_RenderUTF8_Solid(font, s, color);

	int width, height;
	TTF_SizeText(font, s, &width, &height);
	SDL_Rect rect = { x, y, width, height };

	SDL_Texture* message = SDL_CreateTextureFromSurface(renderer, surface);
	SDL_RenderCopy(renderer, message, NULL, &rect);

	SDL_FreeSurface(surface);
	SDL_DestroyTexture(message);
	TTF_CloseFont(font);
}

// A fast base 64 decoder adapted from polfosol's answer in this thread:
// https://stackoverflow.com/questions/180947/base64-decode-snippet-in-c

static int b64[256] = {
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  62, 63, 62, 62, 63,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0,  0,  0,  0,  0,  0,
    0,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0,  0,  0,  0,  63,
    0,  26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51
};

static void base64decode(uint8_t *data, int len, uint8_t *out, int *outLen) {
	int bytesNeeded = 3 * (len / 4);
	if (*outLen < bytesNeeded) {
		printf("base64decode ouput buffer is too small; %d bytes needed\n", bytesNeeded);
		return;
	}

	uint8_t *p = data;
	int pad1 = (len % 4) || p[len - 1] == '=';
	int pad2 = pad1 && (((len % 4) > 2) || (p[len - 2] != '='));
	int last = (len - pad1) / 4 << 2; // number of 4-byte groups

	int j = 0;
	for (int i = 0; i < last; i += 4) {
		int n = b64[p[i]] << 18 | b64[p[i + 1]] << 12 | b64[p[i + 2]] << 6 | b64[p[i + 3]];
		out[j++] = (n >> 16) & 0xFF;
		out[j++] = (n >> 8) & 0xFF;
		out[j++] = n & 0xFF;
	}
	if (pad1) {
		int n = (b64[p[last]] << 18) | (b64[p[last + 1]] << 12);
		out[j++] = n >> 16;
		if (pad2) {
			n |= b64[p[last + 2]] << 6;
			out[j++] = (n >> 8) & 0xFF;
		}
	}
	*outLen = j;
}

#endif

// Events and SDL Window Support

static void initKeys() {
	for (int i = 0; i < 255; i++) {
		KEY_SCANCODE[i] = false;
	}
}

static void processEvents() {
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
			case SDL_KEYDOWN:
				// Using keysyms detects keys by their name, not position,
				// but gives huge values for keys that aren't characters, like
				// the arrow keys, numpad keys or modifiers. Scancodes will be
				// different for different keyboard layouts.
				KEY_SCANCODE[e.key.keysym.scancode] = 1;
                break;
            case SDL_KEYUP:
				KEY_SCANCODE[e.key.keysym.scancode] = 0;
				break;
			default:
				break;
		}
	}
}

void tftInit() {
	if (!tftEnabled) {
		lastRefreshTime = millisecs();
//		SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO);
if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0) {
    // Unrecoverable error, exit here.
    printf("SDL_Init failed: %s\n", SDL_GetError());
    return;
}
		window = SDL_CreateWindow("MicroBlocks for Linux",
				SDL_WINDOWPOS_UNDEFINED,
				SDL_WINDOWPOS_UNDEFINED,
				DEFAULT_WIDTH,
				DEFAULT_HEIGHT,
				SDL_WINDOW_RESIZABLE);

		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
		SDL_RenderClear(renderer);
		initKeys();
		tftEnabled = true;
	}
}

void updateMicrobitDisplay() {
	processEvents();
	if (tftEnabled) {
		uint32_t now = millisecs();
		if (now < lastRefreshTime) lastRefreshTime = 0; // clock wrap
		if ((now - lastRefreshTime > REFRESH_MSECS)) {
			SDL_RenderPresent(renderer);
			lastRefreshTime = now;
		}
	}
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
	if (!window) return zeroObj;
	int w, h;
	SDL_GetWindowSize(window, &w, &h);
	return int2obj(w);
}

static OBJ primGetHeight(int argCount, OBJ *args) {
	if (!window) return zeroObj;
	int w, h;
	SDL_GetWindowSize(window, &w, &h);
	return int2obj(h);
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

static void drawOctaves(int x, int y, int originX, int originY, int fill, int quadrant) {
	// when filling we also want to render the contour, otherwise there are
	// artifacts in the pixels next to the borders
	// top left quarter
	if (!quadrant || quadrant == 1) {
		SDL_RenderDrawPoint(renderer, originX - x, originY - y);
		SDL_RenderDrawPoint(renderer, originX - y, originY - x);
	}
	// top right quarter
	if (!quadrant || quadrant == 2) {
		SDL_RenderDrawPoint(renderer, originX + x, originY - y);
		SDL_RenderDrawPoint(renderer, originX + y, originY - x);
	}
	// bottom right quarter
	if (!quadrant || quadrant == 3) {
		SDL_RenderDrawPoint(renderer, originX + x, originY + y);
		SDL_RenderDrawPoint(renderer, originX + y, originY + x);
	}
	// bottom left quarter
	if (!quadrant || quadrant == 4) {
		SDL_RenderDrawPoint(renderer, originX - x, originY + y);
		SDL_RenderDrawPoint(renderer, originX - y, originY + x);
	}
	if (fill) {
		SDL_RenderDrawLine(renderer, originX - x, originY + y, originX + x, originY + y);
		SDL_RenderDrawLine(renderer, originX - x, originY - y, originX + x, originY - y);
		SDL_RenderDrawLine(renderer, originX - y, originY + x, originX + y, originY + x);
		SDL_RenderDrawLine(renderer, originX - y, originY - x, originX + y, originY - x);
	}
}

static void drawCircle(int originX, int originY, int radius, int fill, int quadrant) {
	// Bresenham's circle algorithm
	int x = 0;
	int y = radius;
	int decision = 3 - 2 * radius;
	drawOctaves(x, y, originX, originY, fill, quadrant);
	while (x < y) {
		x++;
		if (decision > 0) {
			y--;
			decision = decision + 4 * (x - y) + 10;
		} else {
			decision = decision + 4 * x + 6;
		}
		drawOctaves(x, y, originX, originY, fill, quadrant);
	}
}

static OBJ primCircle(int argCount, OBJ *args) {
	tftInit();
	int originX = obj2int(args[0]);
	int originY = obj2int(args[1]);
	int radius = obj2int(args[2]);
	setRenderColor(obj2int(args[3]));
	int fill = (argCount > 4) ? (trueObj == args[4]) : true;
	drawCircle(originX, originY, radius, fill, 0);
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
		drawCircle(x + radius, y + radius + 1, radius, fill, 0);
		drawCircle(x + width - radius - 1, y + radius + 1, radius, fill, 0);
		drawCircle(x + radius, y + height - radius - 1, radius, fill, 0);
		drawCircle(x + width - radius - 1, y + height - radius - 1, radius, fill, 0);
	} else {
		SDL_RenderDrawLine(renderer, x + radius, y, x + width - radius, y);
		SDL_RenderDrawLine(renderer, x + radius, y + height, x + width - radius, y + height);
		SDL_RenderDrawLine(renderer, x, y + radius, x, y + height - radius);
		SDL_RenderDrawLine(renderer, x + width, y + radius, x + width, y + height - radius);
		drawCircle(x + radius, y + radius + 1, radius, 0, 1);
		drawCircle(x + width - radius, y + radius, radius, 0, 2);
		drawCircle(x + width - radius - 1, y + height - radius - 1, radius, 0, 3);
		drawCircle(x + radius, y + height - radius - 1, radius, 0, 4);
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
		while ((abs(x[1]) < DEFAULT_WIDTH) && // This should never happen
				(area != 0) &&
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
	if (!window) return;

	int width, height;
	SDL_GetWindowSize(window, &width, &height);

	int minDimension, xInset = 0, yInset = 0;
	if (width > height) {
		minDimension = height;
		xInset = (width - height) / 2;
	} else {
		minDimension = width;
		yInset = (height - width) / 2;
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
