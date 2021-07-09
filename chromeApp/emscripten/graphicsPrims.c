// graphicsPrims.c
// John Maloney, October 2013

#include <cairo/cairo.h>
#include <dirent.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL.h>

#include "mem.h"
#include "interp.h"

// Note: Although SDL2 officially supports textures as large as 8192x8192, I got
// crashes, long pauses, and other strange behavior with textures larger than about
// 5000x5000. The conservative limit below appears to be safe, at least on a MacBook Pro.
#define MAX_TEXTURE_SIZE 2048

static int initialized = false;
SDL_Window *window = NULL; // used by events.c
static SDL_Renderer *renderer = NULL;
static SDL_Texture *tmpTexture = NULL;

SDL_Surface *screenBitmap = NULL; // used by textAndFontPrims.c and vectorPrims.c
static SDL_Texture *screenTexture = NULL;

static int rgb = 0; // color when drawing on a surface (vs. a texture)
static int alpha = 255; // alpha when drawing on a surface (vs. a texture)
static int lineBlendMode = SDL_BLENDMODE_NONE;

static int flipWhenReadingTextures = false;

// Used by events.c
int mouseScale;
int windowWidth;
int windowHeight;

void initGraphics() {
	if (initialized) return; // already initialized

	SDL_Init(SDL_INIT_VIDEO);
	atexit(SDL_Quit);
	initialized = true;
}

void closeWindow() {
	if (renderer) SDL_DestroyRenderer(renderer);
	if (window) SDL_DestroyWindow(window);
	if (tmpTexture) SDL_DestroyTexture(tmpTexture);
	window = NULL;
	renderer = NULL;
	tmpTexture = NULL;
}

static OBJ failedNoRenderer() { return primFailed("No graphics renderer"); }
static OBJ failedNoWindow() { return primFailed("No graphics window"); }

static inline int intValue(OBJ obj) {
	// Return the value of an Integer or Float object.
	if (isInt(obj)) return obj2int(obj);
	if (IS_CLASS(obj, FloatClass)) return (int) round(evalFloat(obj));
	return 0;
}

static int isRectangle(OBJ rect) {
	return
		(objWords(rect) >= 4) &&
		(isInt(FIELD(rect, 0)) || IS_CLASS(FIELD(rect, 0), FloatClass)) &&
		(isInt(FIELD(rect, 1)) || IS_CLASS(FIELD(rect, 1), FloatClass)) &&
		(isInt(FIELD(rect, 2)) || IS_CLASS(FIELD(rect, 2), FloatClass)) &&
		(isInt(FIELD(rect, 3)) || IS_CLASS(FIELD(rect, 3), FloatClass));
}

static int isBitmap(OBJ bitmap) {
	return
		(objWords(bitmap) >= 3) &&
		isInt(FIELD(bitmap, 0)) && isInt(FIELD(bitmap, 1)) &&
		IS_CLASS(FIELD(bitmap, 2), BinaryDataClass) &&
		(objWords(FIELD(bitmap, 2)) == (obj2int(FIELD(bitmap, 0)) * obj2int(FIELD(bitmap, 1))));
}

static SDL_Surface* bitmap2Surface(OBJ bitmap) {
	if ((nilObj == bitmap) && screenBitmap) return screenBitmap;
	if (!isBitmap(bitmap)) return NULL;

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return NULL;

	SDL_Surface *result = SDL_CreateRGBSurfaceFrom(&FIELD(data, 0), w, h, 32, (4 * w), 0xFF0000, 0xFF00, 0xFF, 0xFF000000);
	return result;
}

static void setRendererClipRect(OBJ clipRect, OBJ dst) {
	if (!isRectangle(clipRect)) return;

	SDL_Rect clipR;
	clipR.x = intValue(FIELD(clipRect, 0));
	clipR.y = intValue(FIELD(clipRect, 1));
	clipR.w = intValue(FIELD(clipRect, 2));
	clipR.h = intValue(FIELD(clipRect, 3));
	if (flipWhenReadingTextures && dst && (objWords(dst) > 2)) {
		// measure y from bottom of dst texture
		int dstH = intValue(FIELD(dst, 1));
		clipR.y = dstH - (clipR.y + clipR.h);
	}
	SDL_RenderSetClipRect(renderer, &clipR);
}

static void setSurfaceClipRect(SDL_Surface *surface, OBJ clipRect) {
	if (!isRectangle(clipRect)) return;

	SDL_Rect clipR;
	clipR.x = intValue(FIELD(clipRect, 0));
	clipR.y = intValue(FIELD(clipRect, 1));
	clipR.w = intValue(FIELD(clipRect, 2));
	clipR.h = intValue(FIELD(clipRect, 3));
	SDL_SetClipRect(surface, &clipR);
}

static void setCairoClipRect(cairo_t *ctx, OBJ clipRect) {
	if (!isRectangle(clipRect)) return;

	int x = intValue(FIELD(clipRect, 0));
	int y = intValue(FIELD(clipRect, 1));
	int w = intValue(FIELD(clipRect, 2));
	int h = intValue(FIELD(clipRect, 3));
	cairo_rectangle(ctx, x, y, w, h);
	cairo_clip(ctx);
	cairo_new_path(ctx); // clear path
}

static SDL_Texture * obj2texture(OBJ textureObj) {
	// Assume that the external reference holds a texture pointer.
	if (objWords(textureObj) < 3) return NULL;
	OBJ ref = FIELD(textureObj, 2);
	if (NOT_CLASS(ref, ExternalReferenceClass)) return NULL;
	return (SDL_Texture *)*(ADDR*)BODY(ref);
}

static void finalizeTexture(OBJ ref) {
	ADDR *a = (ADDR*)BODY(ref);
	if (NOT_CLASS(ref, ExternalReferenceClass) ||
		(objWords(ref) < ExternalReferenceWords) ||
		(a[1] != (ADDR)finalizeTexture)) {
			return;
	}
	if (a[0]) SDL_DestroyTexture((SDL_Texture *)a[0]);
	a[0] = NULL;
}

static void setColor(OBJ colorObj, int ignoreAlpha) {
	// Set the color for the next drawing operation.
	// Set the renderer's draw color (for texture drawing)
	// and the globals rgb and alpha (for bitmap drawing).
	rgb = 0;
	alpha = 255;
	int words = objWords(colorObj);
	if (words < 3) return;
	int r = isInt(FIELD(colorObj, 0)) ? obj2int(FIELD(colorObj, 0)) : 0;
	int g = isInt(FIELD(colorObj, 1)) ? obj2int(FIELD(colorObj, 1)) : 0;
	int b = isInt(FIELD(colorObj, 2)) ? obj2int(FIELD(colorObj, 2)) : 0;
	int a = ((words > 3) && isInt(FIELD(colorObj, 3))) ? obj2int(FIELD(colorObj, 3)) : 255;
	r = clip(r, 0, 255);
	g = clip(g, 0, 255);
	b = clip(b, 0, 255);
	a = ignoreAlpha ? 255 : clip(a, 0, 255);
	rgb = (r << 16) | (g << 8) | b;
	alpha = a;
	if (renderer) SDL_SetRenderDrawColor(renderer, r, g, b, a);
}

static void detectTextureFlip() {
	// Detect the need to flip textures. (On some platforms, textures are upside down.)

	SDL_Texture *texture = SDL_CreateTexture(
		renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, 1, 2);
	if (!texture) return;

	// clear the texture to white
	SDL_SetRenderTarget(renderer, texture);
	SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
	SDL_RenderClear(renderer);

	// make pixel at (0,0) be black
	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
	SDL_Rect r = {0, 0, 1, 1};
	SDL_RenderFillRect(renderer, &r);

	// read pixels from the texture and check red channel of pixel at (0,0)
	unsigned char pixels[8];
	SDL_Rect r2 = {0, 0, 1, 2};
	SDL_RenderReadPixels(renderer, &r2, SDL_PIXELFORMAT_ARGB8888, pixels, 4);
	if (255 == pixels[1]) flipWhenReadingTextures = true;

	// cleanup
	SDL_DestroyTexture(texture);
	SDL_SetRenderTarget(renderer, NULL); // revert to window
}

void createOrUpdateOffscreenBitmap(int createFlag) {
	// Create or update the size of the offscreen bitmap and texture.

	if (!(createFlag || screenBitmap)) return; // not using offscreen bitmap

	int w, h;
	SDL_GL_GetDrawableSize(window, &w, &h);

	if (renderer) {
		// free old screen and texture
		if (screenBitmap) SDL_FreeSurface(screenBitmap);
		if (screenTexture) SDL_DestroyTexture(screenTexture);

		// Create offscreen bitmap (an SDL surface)
		screenBitmap = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_ARGB8888);
		if (!screenBitmap) printf("Could not create offscreen bitmap");

		// Create offscreen texture
		screenTexture = SDL_CreateTexture(
			renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, w, h);
		if (!screenTexture) printf("Could not create offscreen texture");
	} else {
		screenBitmap = SDL_GetWindowSurface(window);
		screenTexture = NULL;
	}
}

OBJ primOpenWindow(int nargs, OBJ args[]) {
	int w = intOrFloatArg(0, 500, nargs, args);
	int h = intOrFloatArg(1, 500, nargs, args);
	int highDPIFlag = ((nargs > 2) && (args[2] == trueObj)) ? SDL_WINDOW_ALLOW_HIGHDPI : 0;
	char *title = strArg(3, "GP", nargs, args);
	int screenBufferFlag = (nargs > 4) && (trueObj == args[4]); // use bitmap screen buffer
	w = clip(w, 10, 5000);
	h = clip(h, 10, 5000);

	SDL_version compiled, linked;
	SDL_VERSION(&compiled);
	SDL_GetVersion(&linked);
	printf("SDL2 headers: %d.%d.%d; lib: %d.%d.%d\n",
		compiled.major, compiled.minor, compiled.patch,
		linked.major, linked.minor, linked.patch);

	initGraphics();

	if (window) {
		// if window is already open, just resize it
		SDL_SetWindowSize(window, w, h);
		createOrUpdateOffscreenBitmap(false);
		return nilObj;
	}
	closeWindow();

#ifdef MAC
	#define USE_RENDERER true
#endif

#ifndef USE_RENDERER
	if (screenBufferFlag) highDPIFlag = false;
#endif
	window = SDL_CreateWindow(title, 40, 80, w, h, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | highDPIFlag);

	int actualW, logicalW, actualH, logicalH;
	SDL_GL_GetDrawableSize(window, &actualW, &actualH);
	SDL_GetWindowSize(window, &logicalW, &logicalH);
	mouseScale = (actualW == (2 * logicalW)) ? 2 : 1;
	windowWidth = actualW;
	windowHeight = actualH;

#ifdef USE_RENDERER
	renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_TARGETTEXTURE | SDL_RENDERER_PRESENTVSYNC);
	if (!renderer) {
		// creating an accelerated renderer fails on some platforms (e.g. RaspberryPi); try without options
		renderer = SDL_CreateRenderer(window, -1, 0);
		if (!renderer) {
			closeWindow();
			return primFailed("Could not create graphics renderer");
		}
		printf("Using non-accelerated graphics renderer\n");
	}
	detectTextureFlip();

	if (screenBufferFlag) createOrUpdateOffscreenBitmap(true);

	// Create a buffer texture used to quickly render bitmaps
	// Note: On some platforms (e.g. running Windows in VMWare on a Mac), the temporary texture
	// must be a STREAMING texture. On other platforms (e.g. Mac Powerbook Pro with Radeon GPU)
	// it must be a TARGET texture. Here, we try both and use the one that works.
	tmpTexture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, MAX_TEXTURE_SIZE, MAX_TEXTURE_SIZE);
	int onePixel = 0;
	SDL_Rect r = {0, 0, 1, 1};
	int err = SDL_UpdateTexture(tmpTexture, &r, &onePixel, 4);
	if (err != 0) {
		SDL_DestroyTexture(tmpTexture);
		tmpTexture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, MAX_TEXTURE_SIZE, MAX_TEXTURE_SIZE);
	}

	// Clear both buffers
	SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
	SDL_RenderClear(renderer);
	SDL_RenderPresent(renderer);
	SDL_RenderClear(renderer);
#else
	(void) detectTextureFlip; // reference (not a call) to suppress uncalled function warning
	screenBitmap = SDL_GetWindowSurface(window);
	SDL_Rect r = {0, 0, screenBitmap->w, screenBitmap->h};
	SDL_FillRect(screenBitmap, &r, 0xFFFFFFFF);
	SDL_UpdateWindowSurface(window);
#endif
	return nilObj;
}

OBJ primCloseWindow(int nargs, OBJ args[]) {
	closeWindow();
	return nilObj;
}

OBJ primClearWindowBuffer(int nargs, OBJ args[]) {
	if (renderer) SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255); // default to white
	rgb = 0xFFFFFF; // default
	if (nargs > 0) setColor(args[0], true);
	if (screenBitmap) {
		SDL_FillRect(screenBitmap, NULL, (0xFF << 24) | rgb);
	} else {
		SDL_RenderClear(renderer);
	}
	return nilObj;
}

OBJ primFlipWindowBuffer(int nargs, OBJ args[]) {
	if (renderer) {
		if (screenBitmap && screenTexture) {
			// copy the screen bitmap into tmpTexture, render it, and present
			SDL_UpdateTexture(screenTexture, NULL, screenBitmap->pixels, (4 * screenBitmap->w));
			SDL_RenderCopy(renderer, screenTexture, NULL, NULL);
		}
		SDL_RenderPresent(renderer);
	} else {
		SDL_UpdateWindowSurface(window);
	}
	return nilObj;
}

OBJ primWindowSize(int nargs, OBJ args[]) {
	if (!window) return failedNoWindow();

	int logicalW, logicalH, actualW, actualH;
	SDL_GetWindowSize(window, &logicalW, &logicalH);
	SDL_GL_GetDrawableSize(window, &actualW, &actualH);

	OBJ result = newArray(4);
	FIELD(result, 0) = int2obj(logicalW);
	FIELD(result, 1) = int2obj(logicalH);
	FIELD(result, 2) = int2obj(actualW);
	FIELD(result, 3) = int2obj(actualH);

	return result;
}

OBJ primSetFullScreen(int nargs, OBJ args[]) {
	if (!window) return failedNoWindow();
	int fullScreenFlag = (nargs > 0) && (trueObj == args[0]);
	int mode = fullScreenFlag ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0;
	SDL_SetWindowFullscreen(window, mode);
	return nilObj;
}

OBJ primSetWindowTitle(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (IS_CLASS(args[0], StringClass)) {
		SDL_SetWindowTitle(window, obj2str(args[0]));
	}
	return nilObj;
}

OBJ primFillRect(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!initialized) initGraphics();

	OBJ dst = args[0];
	setColor(args[1], false);
	SDL_Rect r;
	r.x = intOrFloatArg(2, 0, nargs, args);
	r.y = intOrFloatArg(3, 0, nargs, args);
	r.w = intOrFloatArg(4, 100, nargs, args);
	r.h = intOrFloatArg(5, 100, nargs, args);
	int blendMode = intArg(6, SDL_BLENDMODE_NONE, nargs, args);
	blendMode = clip(blendMode, 0, 4);

	if ((0 == alpha) && (SDL_BLENDMODE_BLEND == blendMode)) {
		return nilObj; // fully transparent color in blend mode; do nothing
	}

	if (isBitmap(dst) || ((nilObj == dst) && screenBitmap)) {
		SDL_Surface *dstSurface = bitmap2Surface(dst);
		if (dstSurface) {
			if ((SDL_BLENDMODE_BLEND == blendMode) && (255 == alpha)) {
				blendMode = SDL_BLENDMODE_NONE; // faster mode if alpha is 100% opaque
			}
			if (blendMode) {
				SDL_Renderer *softRenderer = SDL_CreateSoftwareRenderer(dstSurface);
				SDL_SetRenderDrawColor(softRenderer, ((rgb >> 16) & 255), ((rgb >> 8) & 255), (rgb & 255), alpha);
				SDL_SetRenderDrawBlendMode(softRenderer, blendMode);
				SDL_RenderFillRect(softRenderer, &r);
				SDL_DestroyRenderer(softRenderer);
			} else {
				SDL_FillRect(dstSurface, &r, ((alpha << 24) | rgb));
			}
			if (dstSurface != screenBitmap) SDL_FreeSurface(dstSurface);
		}
	} else {
		if (!renderer) return failedNoRenderer();
		SDL_Texture *texture = nargs ? obj2texture(dst) : NULL;
		if (texture) SDL_SetRenderTarget(renderer, texture);
		if (blendMode) SDL_SetRenderDrawBlendMode(renderer, blendMode);
		SDL_RenderFillRect(renderer, &r);
		if (blendMode) SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
		SDL_SetRenderTarget(renderer, NULL);
	}
	return nilObj;
}

OBJ primDrawBitmap(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!initialized) initGraphics();

	OBJ dst = args[0];
	OBJ src = args[1];
	if (!isBitmap(src)) return primFailed("Bad bitmap");

	int x = intOrFloatArg(2, 0, nargs, args);
	int y = intOrFloatArg(3, 0, nargs, args);
	int alpha = intOrFloatArg(4, 255, nargs, args);
	alpha = clip(alpha, 0, 255);
	int blendMode = intArg(5, SDL_BLENDMODE_BLEND, nargs, args);
	blendMode = clip(blendMode, 0, 4);
	OBJ clipRect = (nargs > 6) ? args[6] : nilObj;

	int w = obj2int(FIELD(src, 0));
	int h = obj2int(FIELD(src, 1));
	OBJ bitmapData = FIELD(src, 2);
	if (objWords(bitmapData) != (w * h)) return primFailed("Bad bitmap");

	if (isBitmap(dst) || ((nilObj == dst) && screenBitmap)) {
		SDL_Surface *srcSurface = bitmap2Surface(src);
		SDL_Surface *dstSurface = bitmap2Surface(dst);
		if (srcSurface && dstSurface) {
			SDL_SetSurfaceBlendMode(srcSurface, blendMode);
			if (alpha < 255) SDL_SetSurfaceAlphaMod(srcSurface, alpha);
			setSurfaceClipRect(dstSurface, clipRect);
			SDL_Rect dstR = {x, y, w, h};
			SDL_BlitSurface(srcSurface, NULL, dstSurface, &dstR);
			SDL_SetClipRect(dstSurface, NULL);
		}
		SDL_FreeSurface(srcSurface);
		if (dstSurface != screenBitmap) SDL_FreeSurface(dstSurface);
	} else {
		if (!renderer || !tmpTexture) return failedNoRenderer();

		// render tmpTexture to destination
		SDL_SetTextureBlendMode(tmpTexture, blendMode);
		SDL_SetTextureAlphaMod(tmpTexture, alpha);
		SDL_SetRenderTarget(renderer, obj2texture(dst)); // use dst texture if supplied
		setRendererClipRect(clipRect, dst);
		// copy bitmap to destination via tmpTexture, possibly in multiple steps
		int dstY = y;
		for (int srcY = 0; srcY < h; srcY += MAX_TEXTURE_SIZE) {
			int dY = h - srcY;
			if (dY > MAX_TEXTURE_SIZE) dY = MAX_TEXTURE_SIZE;
			int dstX = x;
			for (int srcX = 0; srcX < w; srcX += MAX_TEXTURE_SIZE) {
				int dX = w - srcX;
				if (dX > MAX_TEXTURE_SIZE) dX = MAX_TEXTURE_SIZE;
				SDL_Rect textureR = {0, 0, dX, dY};
				int srcOffset = (srcY * w) + srcX;
				SDL_UpdateTexture(tmpTexture, &textureR, &FIELD(bitmapData, srcOffset), (4 * w));
				SDL_Rect dstR = {dstX, dstY, dX, dY};
				SDL_RenderCopy(renderer, tmpTexture, &textureR, &dstR);
				dstX += MAX_TEXTURE_SIZE;
			}
			dstY += MAX_TEXTURE_SIZE;
		}
		SDL_SetTextureBlendMode(tmpTexture, SDL_BLENDMODE_NONE);
		SDL_SetTextureAlphaMod(tmpTexture, 255);
		SDL_RenderSetClipRect(renderer, NULL);
		SDL_SetRenderTarget(renderer, NULL); // revert to window
	}
	return nilObj;
}

static inline cairo_surface_t * bitmap2cairo(OBJ bitmap) {
	if ((nilObj == bitmap) && screenBitmap) {
		SDL_Surface *screen = screenBitmap;
		return cairo_image_surface_create_for_data(
			screen->pixels, CAIRO_FORMAT_ARGB32, screen->w, screen->h, (4 * screen->w));
	}
	if (!isBitmap(bitmap)) return NULL;

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return NULL;

	return cairo_image_surface_create_for_data((unsigned char *) &FIELD(data, 0), CAIRO_FORMAT_ARGB32, w, h, (4 * w));
}

OBJ primWarpBitmap(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ dst = args[0];
	OBJ src = args[1];
	int centerX = intOrFloatArg(2, 0, nargs, args);
	int centerY = intOrFloatArg(3, 0, nargs, args);
	double scaleX = floatArg(4, 1, nargs, args);
	double scaleY = floatArg(5, 1, nargs, args);
	double rotation = floatArg(6, 0, nargs, args);
	OBJ clipRect = (nargs > 7) ? args[7] : nilObj;

	if (!isBitmap(src)) return primFailed("Bad bitmap");

	int srcW = obj2int(FIELD(src, 0));
	int srcH = obj2int(FIELD(src, 1));
	if (srcW > MAX_TEXTURE_SIZE) srcW = MAX_TEXTURE_SIZE;
	if (srcH > MAX_TEXTURE_SIZE) srcH = MAX_TEXTURE_SIZE;
	int dstW = scaleX * srcW;
	int dstH = scaleY * srcH;

	if (0 == rotation) { // special case: no rotation
		SDL_Surface *srcSurface = bitmap2Surface(src);
		if (isBitmap(dst) || ((nilObj == dst) && screenBitmap)) {
			SDL_Surface *dstSurface = bitmap2Surface(dst);
			if (srcSurface && dstSurface) {
				setSurfaceClipRect(dstSurface, clipRect);
				SDL_Rect dstR = {centerX - (dstW / 2), centerY - (dstH / 2), dstW, dstH};
				SDL_BlitScaled(srcSurface, NULL, dstSurface, &dstR);
				SDL_SetClipRect(dstSurface, NULL);
			}
			if (dstSurface != screenBitmap) SDL_FreeSurface(dstSurface);
		} else if (renderer && tmpTexture) {
			// copy src to tmpTexture
			OBJ bitmapData = FIELD(src, 2);
			SDL_Rect r = {0, 0, srcW, srcH};
			SDL_UpdateTexture(tmpTexture, &r, &FIELD(bitmapData, 0), (4 * srcW));
			SDL_SetTextureBlendMode(tmpTexture, SDL_BLENDMODE_BLEND);
			SDL_SetTextureAlphaMod(tmpTexture, 255); // always opaque for now
			// copy scaled result into destination
			setRendererClipRect(clipRect, dst);
			SDL_SetRenderTarget(renderer, obj2texture(dst)); // set dst texture (nil = window)
			SDL_Rect dstR = {centerX - (dstW / 2), centerY - (dstH / 2), dstW, dstH};
			SDL_RenderCopy(renderer, tmpTexture, &r, &dstR);

			SDL_SetTextureBlendMode(tmpTexture, SDL_BLENDMODE_NONE);
			SDL_SetTextureAlphaMod(tmpTexture, 255);
			SDL_RenderSetClipRect(renderer, NULL);
			SDL_SetRenderTarget(renderer, NULL); // revert to window
		}
		SDL_FreeSurface(srcSurface);
		return nilObj;
	}

	cairo_surface_t *dstSurf = bitmap2cairo(dst);
	cairo_surface_t *srcSurf = bitmap2cairo(src);
	if (!dstSurf || !srcSurf) {
		printf("WarpBitmap: first two arguments must be bitmaps\n");
		return nilObj;
	}

	// general case: rotation with possible scaling as well
	// both src and dst must be bitmaps (not textures)
	int halfW = srcW / 2;
	int halfH = srcH / 2;

	cairo_t *cr = cairo_create(dstSurf);
	setCairoClipRect(cr, clipRect);

	cairo_translate(cr, centerX - halfW, centerY - halfH);
	cairo_translate(cr, halfW, halfH);
	cairo_rotate(cr, (rotation * M_PI) / 180.0);
	cairo_scale(cr, scaleX, scaleY);
	cairo_translate(cr, -halfW, -halfH);
	cairo_set_source_surface(cr, srcSurf, 0, 0);
	cairo_paint(cr);

	cairo_destroy(cr);
	cairo_surface_destroy(dstSurf);
	cairo_surface_destroy(srcSurf);
	return nilObj;
}

static inline void plot(int x, int y, int lineWidth, SDL_Surface *surface) {
	// Plot a square of lineWidth size using the given renderer or surface.
	int halfWidth = lineWidth / 2;
	SDL_Rect r = {x - halfWidth, y - halfWidth, lineWidth, lineWidth};
	SDL_FillRect(surface, &r, ((255 << 24) | rgb));
}

static inline void plotWu(int x, int y, double pixelAlpha, uint32 *pixels, int pixelCount, int width) {
	// Draw a pixel at the given position and alpha in the given pixel array (bitmap).

	int i = x + (y * width);
	if (i >= pixelCount) return;
	int a = (int) (pixelAlpha * alpha);
	if (a > 255) a = 255;
	if (lineBlendMode == SDL_BLENDMODE_NONE) {
		pixels[i] = (a << 24) | rgb;
	} else {
		int invA = 255 - a;
		uint32 dst = pixels[i];
		int r = (((a * (rgb & 0xFF0000)) + (invA * (dst & 0xFF0000))) / 255) & 0xFF0000;
		int g = (((a * (rgb & 0xFF00)) + (invA * (dst & 0xFF00))) / 255) & 0xFF00;
		int b = (((a * (rgb & 0xFF)) + (invA * (dst & 0xFF))) / 255) & 0xFF;
		int dstA = (a + ((invA * ((dst & 0xFF000000) >> 24)) / 255)) & 0xFF;
		pixels[i] = (dstA << 24) | r | g | b;
	}
}

static inline double fractionPart(double n) { return fmod(n, 1.0); }

static void drawWuLine(double x0, double y0, double x1, double y1, OBJ bitmap) {
	// Draw a 1-pixel wide, anti-aliased line using Xialin Wu's algorithm.

	if (!isBitmap(bitmap)) return;
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	int pixelCount = w * h;
	if (pixelCount != objWords(data)) return;
	uint32 *pixels = &FIELD(data, 0);

	if ((x0 == x1) && (y0 == y1)) return;

	double tmp;
	int steep = fabs(y1 - y0) > fabs(x1 - x0);
	if (steep) {
		// swap x0 y0
		double tmp = x0;
		x0 = y0;
		y0 = tmp;

		//swap x1 y1
		tmp = x1;
		x1 = y1;
		y1 = tmp;
	}
	if (x0 > x1) {
		// swap x0 x1
		tmp = x0;
		x0 = x1;
		x1 = tmp;

		//swap y0 y1
		tmp = y0;
		y0 = y1;
		y1 = tmp;
	}

	double dx = x1 - x0;
	double dy = y1 - y0;
	double gradient = dy / dx;

	// handle first endpoint
	int xend = round(x0);
	double yend = y0 + (gradient * (xend - x0));
	double xgap = fractionPart(x0 + 0.5);
	int xpx11 = xend; // used in the main loop
	int ypx11 = yend;
	if (steep) {
		plotWu(ypx11, xpx11, xgap * (1.0 - fractionPart(yend)), pixels, pixelCount, w);
		plotWu((ypx11 + 1), xpx11, xgap * fractionPart(yend), pixels, pixelCount, w);
	} else {
		plotWu(xpx11, ypx11, xgap * (1.0 - fractionPart(yend)), pixels, pixelCount, w);
		plotWu(xpx11, (ypx11 + 1), xgap * fractionPart(yend), pixels, pixelCount, w);
	}
	double intery = yend + gradient; // first y-intersection for main loop

	// handle second endpoint
	xend = round(x1);
	yend = y1 + (gradient * (xend - x1));
	xgap = fractionPart(x1 + 0.5);
	int xpx12 = xend; // used in the main loop
	int ypx12 = yend;
	if (steep) {
		plotWu(ypx12, xpx12, xgap * (1.0 - fractionPart(yend)), pixels, pixelCount, w);
		plotWu(ypx12 + 1, xpx12, xgap * fractionPart(yend), pixels, pixelCount, w);
	} else {
		plotWu(xpx12, ypx12, xgap * (1.0 - fractionPart(yend)), pixels, pixelCount, w);
		plotWu(xpx12, ypx12 + 1, xgap * fractionPart(yend) * xgap, pixels, pixelCount, w);
	}

	// main loop
	for (int i = (xpx11 + 1); i <= (xpx12 - 1); i++) {
		if (steep) {
			plotWu((int) intery, i, 1.0 - fractionPart(intery), pixels, pixelCount, w);
			plotWu(((int) intery) + 1, i, fractionPart(intery), pixels, pixelCount, w);
		} else {
			plotWu(i, (int) intery, 1.0 - fractionPart(intery), pixels, pixelCount, w);
			plotWu(i, ((int) intery) + 1, fractionPart(intery), pixels, pixelCount, w);
		}
		intery = intery + gradient;
	}
}

OBJ primDrawLineOnBitmap(int nargs, OBJ args[]) {
	OBJ dst = args[0];
	int x0 = intOrFloatArg(1, 0, nargs, args);
	int y0 = intOrFloatArg(2, 0, nargs, args);
	int x1 = intOrFloatArg(3, 0, nargs, args);
	int y1 = intOrFloatArg(4, 0, nargs, args);
	OBJ c = (nargs > 5) ? args[5] : nilObj;
	if (c) setColor(c, false);
	else rgb = alpha = 0;
	int lineWidth = intOrFloatArg(6, 1, nargs, args);
	int antiAliasFlag = ((nargs > 7) && (args[7] == trueObj));
	lineBlendMode = intArg(8, SDL_BLENDMODE_NONE, nargs, args); // set global lineBlendMode
	if (lineWidth > 1) antiAliasFlag = false; // only supports 1-pixel wide anti-aliased lines

	SDL_Surface *dstSurface = bitmap2Surface(dst);
	if (!dstSurface) return primFailed("Bad bitmap");

	if (antiAliasFlag) {
		drawWuLine(x0, y0, x1, y1, dst);
	} else {
		// Bresenham's algorithm
		int dx = abs(x1 - x0);
		int dy = abs(y1 - y0);
		int sx = (x0 < x1) ? 1 : -1;
		int sy = (y0 < y1) ? 1 : -1;
		int err = dx - dy;
		while (true) {
			plot(x0, y0, lineWidth, dstSurface);
			if ((x0 == x1) && (y0 == y1)) break;
			int e2 = 2 * err;
			if (e2 > -dy) {
				err -= dy;
				x0 += sx;
			}
			if ((x0 == x1) && (y0 == y1)) {
				plot(x0, y0, lineWidth, dstSurface);
				break;
			}
			if (e2 < dx) {
				err += dx;
				y0 += sy;
			}
		}
	}
	if (dstSurface != screenBitmap) SDL_FreeSurface(dstSurface);
	return nilObj;
}

OBJ primCreateTexture(int nargs, OBJ args[]) {
	if (!renderer) return failedNoRenderer();

	int w = intOrFloatArg(0, -1, nargs, args);
	int h = intOrFloatArg(1, -1, nargs, args);
	OBJ c = (nargs > 2) ? args[2] : nilObj;
	if (c) setColor(c, false);
	else rgb = alpha = 0;

	if (w < 1) w = 1;
	if (w > MAX_TEXTURE_SIZE) w = MAX_TEXTURE_SIZE;
	if (h < 1) h = 1;
	if (h > MAX_TEXTURE_SIZE) h = MAX_TEXTURE_SIZE;

	SDL_Texture *texture = SDL_CreateTexture(
		renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, w, h);
	if (!texture) return primFailed("Could not create texture");

	// clear the texture
	SDL_SetRenderTarget(renderer, texture);
	SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
	SDL_SetRenderDrawColor(renderer, ((rgb >> 16) & 255), ((rgb >> 8) & 255), (rgb & 255), alpha);
	SDL_RenderClear(renderer);
	SDL_SetRenderTarget(renderer, NULL);

	OBJ ref = newBinaryObj(ExternalReferenceClass, ExternalReferenceWords);
	ADDR *a = (ADDR*)BODY(ref);
	a[0] = (ADDR) texture;
	a[1] = (ADDR) finalizeTexture;
	return ref;
}

OBJ primDestroyTexture(int nargs, OBJ args[]) {
	// Note: Takes an ExternalReference to a texture.
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ ref = args[0];
	ADDR *a = (ADDR*)BODY(ref);
	if ((NOT_CLASS(ref, ExternalReferenceClass)) || (a[1] != (ADDR)finalizeTexture)) {
		return primFailed("Bad texture");
	}
	finalizeTexture(ref);
	return nilObj;
}

#if defined (IOS)
void flipBitmapY(int w, int h, unsigned int *pixels) {
	int lastY = h / 2;
	unsigned int *upper;
	unsigned int *lower;
	unsigned int tmp;
	for (int y = 0; y < lastY; y++) {
		upper = pixels + (w * y);
		lower = pixels + (w * ((h - 1) - y));
		for (int x = 0; x < w; x++) {
			tmp = *upper;
			unsigned int t0n = tmp & 0xff000000;
			unsigned int t1 = (tmp >> 16) & 255;
			unsigned int t2n = tmp & 0xff00;
			unsigned int t3 = (tmp >> 0) & 255;
			tmp = *lower;
			unsigned int s0n = tmp & 0xff000000;
			unsigned int s1 = (tmp >> 16) & 255;
			unsigned int s2n = tmp & 0xff00;
			unsigned int s3 = (tmp >> 0) & 255;

			*upper++ = s0n | (s3 << 16) | s2n | (s1 << 0);
			*lower++ = t0n | (t3 << 16) | t2n | (t1 << 0);
		}
	}
	if (h % 2) {
		upper = pixels + (w * lastY);
		for (int x = 0; x < w; x++) {
			tmp = *upper;
			unsigned int t0n = tmp & 0xff000000;
			unsigned int t1 = (tmp >> 16) & 255;
			unsigned int t2n = tmp & 0xff00;
			unsigned int t3 = (tmp >> 0) & 255;
			*upper++ = t0n | (t3 << 16) | t2n | (t1 << 0);
		}
	}
}
#else
void flipBitmapY(int w, int h, unsigned int *pixels) {
	int lastY = h / 2;
	for (int y = 0; y < lastY; y++) {
		unsigned int *upper = pixels + (w * y);
		unsigned int *lower = pixels + (w * ((h - 1) - y));
		for (int x = 0; x < w; x++) {
			unsigned int tmp = *upper;
			*upper++ = *lower;
			*lower++ = tmp;
		}
	}
}
#endif

OBJ primReadTexture(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!renderer) return failedNoRenderer();

	OBJ bitmap = args[0];
	SDL_Texture *srcTexture = obj2texture(args[1]);

	if (!srcTexture) return primFailed("Bad texture");
	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return primFailed("Bad bitmap size");

	SDL_Rect r = {0, 0, w, h};
	int flipResult = false;

	if (flipWhenReadingTextures) {
		// On Mac OS or iOS textures (but not the display buffer) are upside down
		flipResult = true;
		int textureH, ignore;
		SDL_QueryTexture(srcTexture, (Uint32 *) &ignore, &ignore, &ignore, &textureH);
		r.y = textureH - h; // measure y from the bottom
	}

#if defined(_WIN32)
	// Work-around for bug in Windows SDL2, which always reads
	// pixels from the screen buffer regardless of render target.
	//   1. Fill area of original texture with a known "transparent" color
	//   2. Draw the texture (RenderCopy)
	//   3. Read the pixels
	//   4. Set pixels of the "transparent" color to 0
	// Note: This technique causes pixels with alpha < 255 to get
	// blended with the transparent color, so it's not perfect.

	SDL_Rect r2 = {0, 0, w, h};
	SDL_SetRenderDrawColor(renderer, 1, 2, 3, 0);
	SDL_RenderFillRect(renderer, &r2);
	SDL_SetTextureBlendMode(srcTexture, SDL_BLENDMODE_BLEND);
	SDL_RenderCopy(renderer, srcTexture, &r2, &r2);
	SDL_RenderReadPixels(renderer, &r, SDL_PIXELFORMAT_ARGB8888, &FIELD(data, 0), (4 * w));

	int count = objWords(data);
	for (int i = 0; i < count; i++) {
		uint32 pix = FIELD(data, i);
		if (pix == 0xFF010203) FIELD(data, i) = 0;
	}
#else
	SDL_SetRenderTarget(renderer, srcTexture);
	SDL_RenderReadPixels(renderer, &r, SDL_PIXELFORMAT_ARGB8888, &FIELD(data, 0), (4 * w));
	SDL_SetRenderTarget(renderer, NULL); // revert to window
#endif

	if (flipResult) flipBitmapY(w, h, (unsigned int *) &FIELD(data, 0));
	return nilObj;
}

OBJ winUpdateTexture(OBJ bitmapData, SDL_Texture *dstTexture, int w, int h) {
	// Windows SDL_UpdateTexture problem work-around:
	// On Windows SDL_UpdateTexture requires that texture have STREAMING access.
	// However, textures must have TARGET access to allow them to be drawn onto.
	// The workaround is to first use SDL_UpdateTexture to copy the source bitmap
	// into the temporary texture, then use SDL_RenderCopy to draw from the
	// temporary texture onto the target texture.

	if (!renderer || !tmpTexture) return failedNoRenderer();

	// check bounds
	if (objWords(bitmapData) != (w * h)) return nilObj;
	if ((w > MAX_TEXTURE_SIZE) || (h > MAX_TEXTURE_SIZE)) {
		printf("Bitmap too large for winUpdateTexture: %d x %d\n", w, h);
		return nilObj;
	}
	// copy the bitmap into tmpTexture
	SDL_Rect r = {0, 0, w, h};
	SDL_UpdateTexture(tmpTexture, &r, &FIELD(bitmapData, 0), (4 * w));

	// copy tmpTexture to dstTexture
	SDL_SetTextureBlendMode(tmpTexture, SDL_BLENDMODE_NONE);
	SDL_SetTextureAlphaMod(tmpTexture, 255);
	SDL_SetRenderTarget(renderer, dstTexture);
	SDL_RenderCopy(renderer, tmpTexture, &r, &r);
	SDL_SetRenderTarget(renderer, NULL); // revert to window
	return nilObj;
}

OBJ primUpdateTexture(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();

	SDL_Texture *dstTexture = obj2texture(args[0]);
	if (!dstTexture) return primFailed("Bad texture");

	OBJ bitmap = args[1];
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return primFailed("Bad bitmap");

// #ifdef _WIN32
//	winUpdateTexture(data, dstTexture, w, h);
// #else
	SDL_Rect r = {0, 0, w, h};
	SDL_UpdateTexture(dstTexture, &r, &FIELD(data, 0), (4 * w));
// #endif

	return nilObj;
}

OBJ primShowTexture(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!renderer) return failedNoRenderer();

	OBJ dst = args[0];
	SDL_Texture *srcTexture = obj2texture(args[1]);
	if (!srcTexture) return nilObj;
	int x = floatArg(2, 0, nargs, args);
	int y = floatArg(3, 0, nargs, args);
	int alpha = intOrFloatArg(4, 255, nargs, args);
	alpha = clip(alpha, 0, 255);
	double xScale = floatArg(5, 1.0, nargs, args);
	double yScale = floatArg(6, 1.0, nargs, args);
	double rotation = floatArg(7, 0.0, nargs, args);
	int flip = intArg(8, 0, nargs, args); // 0 - none, 1 - horizontal, 2 - vertical
	int blendMode = intArg(9, SDL_BLENDMODE_BLEND, nargs, args);
	OBJ clipRect = (nargs > 10) ? args[10] : nilObj;

	// get srcTexture dimensions:
	int w, h, ignore;
	SDL_QueryTexture(srcTexture, (Uint32 *) &ignore, &ignore, &w, &h);
	SDL_Rect dstR = {x, y, ceil(xScale * w), ceil(yScale * h)};

	SDL_SetTextureBlendMode(srcTexture, blendMode);
	SDL_SetTextureAlphaMod(srcTexture, alpha); // global alpha
	SDL_SetRenderTarget(renderer, obj2texture(dst));
	setRendererClipRect(clipRect, dst);
	if (rotation || flip) {
		SDL_RenderCopyEx(renderer, srcTexture, NULL, &dstR, -rotation, NULL, flip); // rotate counterclockwise
	} else {
		SDL_RenderCopy(renderer, srcTexture, NULL, &dstR);
	}
	SDL_RenderSetClipRect(renderer, NULL);
	SDL_SetRenderTarget(renderer, NULL); // revert to window

	return nilObj;
}

// ***** User Input Primitives *****

OBJ primNextEvent(int nargs, OBJ args[]) { return getEvent(); }

OBJ primGetClipboard(int nargs, OBJ args[]) {
	if (!initialized) initGraphics();
	char *s = SDL_GetClipboardText();
	OBJ result = newString(s ? s : ""); // s is null if clipboard is empty
	if (s) SDL_free(s);
	return result;
}

OBJ primSetClipboard(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Argument must be a string");
	char *s = obj2str(args[0]);

	if (!initialized) initGraphics();
	SDL_SetClipboardText(s);
	return nilObj;
}

OBJ primShowKeyboard(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();

	if (!initialized) initGraphics();
	if (args[0] == trueObj) SDL_StartTextInput();
	else SDL_StopTextInput();
	return nilObj;
}

int cursorIndex (char* cursorName) {
	const char* lookup_table[] = {
		"default", "text", "wait", "crosshair", "", // 0-4
		"nwse-resize", "nesw-resize", "ew-resize", "ns-resize", // 5-8
		"move", "not-allowed", "pointer" // 9-11
	};
	for (int i = 0; i < 12; i++) {
		if (strcmp(lookup_table[i], cursorName) == 0) {
			return i;
		}
	}
	return 0;
};

static SDL_Cursor* currentCursor = NULL;

OBJ primSetCursor(int nargs, OBJ args[]) {
	if ((nargs < 1) || !IS_CLASS(args[0], StringClass)) return nilObj;

	if (currentCursor) {
		SDL_FreeCursor(currentCursor);
		currentCursor = NULL;
	}
	currentCursor = SDL_CreateSystemCursor(cursorIndex(obj2str(args[0])));
	SDL_SetCursor(currentCursor);
	return nilObj;
}

// ***** Graphics Primitive Lookup *****

PrimEntry graphicsPrimList[] = {
	{"-----", NULL, "Graphics: Windows"},
	{"openWindow",		primOpenWindow,				"Open the graphics window. Arguments: [width height tryRetinaFlag title]"},
	{"closeWindow",		primCloseWindow,			"Close the graphics window."},
	{"clearBuffer",		primClearWindowBuffer,		"Clear the offscreen window buffer to a color. Ex. clearBuffer (color 255 0 0); flipBuffer"},
	{"showTexture",		primShowTexture,			"Draw the given texture. Draw to window buffer if dstTexture is nil. Arguments: dstTexture srcTexture [x y alpha xScale yScale rotationDegrees flip blendMode clipRect]"},
	{"flipBuffer",		primFlipWindowBuffer,		"Flip the onscreen and offscreen window buffers to make changes visible."},
	{"windowSize",		primWindowSize,				"Return an array containing the width and height of the window in logical and physical (high resolution) pixels."},
	{"setFullScreen",	primSetFullScreen,			"Set full screen mode. Argument: fullScreenFlag"},
	{"setWindowTitle",	primSetWindowTitle,			"Set the graphics window title to the given string."},
	{"-----", NULL, "Graphics: Textures"},
	{"createTexture",	primCreateTexture,			"Create a reference to new texture (a drawing surface in graphics memory). Arguments: width height [fillColor]. Ex. ref = (createTexture 100 100)"},
	{"destroyTexture",	primDestroyTexture,			"Destroy a texture reference. Ex. destroyTexture ref"},
	{"readTexture",		primReadTexture,			"Copy the given texture into the given bitmap. Arguments: bitmap texture"},
	{"updateTexture",	primUpdateTexture,			"Update the given texture from the given bitmap. Arguments: texture bitmap"},
	{"-----", NULL, "Graphics: Drawing"},
	{"fillRect",		primFillRect,				"Draw a rectangle. Draw to window buffer if textureOrBitmap is nil. Arguments: textureOrBitmap color [x y width height blendMode]."},
	{"drawBitmap",		primDrawBitmap,				"Draw a bitmap. Draw to window buffer if textureOrBitmap is nil. Arguments: textureOrBitmap srcBitmap [x y alpha blendMode clipRect]"},
	{"warpBitmap",		primWarpBitmap,				"Scaled and/or rotate a bitmap. Arguments: dstBitmap srcBitmap [centerX centerY scaleX scaleY rotation]"},
	{"drawLineOnBitmap", primDrawLineOnBitmap,		"Draw a line on a bitmap. Only 1-pixel anti-aliased lines are supported. Arguments: dstBitmap x1 y1 x2 y2 [color lineWidth antiAliasFlag]"},
	{"-----", NULL, "User Input"},
	{"nextEvent",		primNextEvent,				"Return a dictionary representing the next user input event, or nil if the queue is empty."},
	{"getClipboard",	primGetClipboard,			"Return the string from the clipboard, or the empty string if the cliboard is empty."},
	{"setClipboard",	primSetClipboard,			"Set the clipboard to the given string."},
	{"showKeyboard",	primShowKeyboard,			"Show or hide the on-screen keyboard on a touchsceen devices. Argument: true or false."},
	{"setCursor",		primSetCursor,				"Change the mouse pointer appearance. Argument: cursorNumber (0 -> arrow, 3 -> crosshair, 11 -> hand...)"},
};

PrimEntry* graphicsPrimitives(int *primCount) {
	*primCount = sizeof(graphicsPrimList) / sizeof(PrimEntry);
	return graphicsPrimList;
}
