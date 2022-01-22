// textAndFontPrims.c
// John Maloney, November 2014

#define _GNU_SOURCE

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "dict.h"

#ifndef EMSCRIPTEN
	#include <SDL.h>
	extern SDL_Surface *screenBitmap;
#endif

// ***** Helpers *****

static OBJ failedNoFont() { return primFailed("No font"); }
static OBJ badUTF8String() { return primFailed("Invalid UTF8 string"); }

static inline int intValue(OBJ obj) {
	// Return the value of an Integer or Float object.
	if (isInt(obj)) return obj2int(obj);
	if (IS_CLASS(obj, FloatClass)) return (int) round(evalFloat(obj));
	return 0;
}

static int isBitmap(OBJ bitmap) {
	if ((objWords(bitmap) < 3) ||
		!isInt(FIELD(bitmap, 0)) ||
		!isInt(FIELD(bitmap, 1)) ||
		!IS_CLASS(FIELD(bitmap, 2), BinaryDataClass))
			return false;

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	return (objWords(data) == (w * h));
}

static int isRectangle(OBJ rect) {
	return
		(objWords(rect) >= 4) &&
		(isInt(FIELD(rect, 0)) || IS_CLASS(FIELD(rect, 0), FloatClass)) &&
		(isInt(FIELD(rect, 1)) || IS_CLASS(FIELD(rect, 1), FloatClass)) &&
		(isInt(FIELD(rect, 2)) || IS_CLASS(FIELD(rect, 2), FloatClass)) &&
		(isInt(FIELD(rect, 3)) || IS_CLASS(FIELD(rect, 3), FloatClass));
}

// ***** Platform Dependent Operations *****

// MacOS and iOS

#if defined(__APPLE__) && defined(__MACH__)

#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

typedef CTFontRef FontRef; // each platform must define FontRef

static FontRef openFont(char *fontName, int fontSize) {
	CFStringRef fName = CFStringCreateWithCString(kCFAllocatorDefault, fontName, kCFStringEncodingUTF8);

	CFStringRef keys[] = { kCTFontDisplayNameAttribute };
	CFTypeRef values[] = { fName };
	CFDictionaryRef fontAttributes = CFDictionaryCreate(
		kCFAllocatorDefault,
		(const void**) &keys,
		(const void**) &values, sizeof(keys) / sizeof(keys[0]),
		&kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks);
	CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(fontAttributes);
	CTFontRef result = CTFontCreateWithFontDescriptor(descriptor, (float) fontSize, NULL);

	CFRelease(descriptor);
	CFRelease(fontAttributes);
	CFRelease(fName);

	return result;
}

static void closeFont(FontRef font) { CFRelease(font); }
static int ascent(FontRef font) { return (int) ceil(CTFontGetAscent(font)); }
static int descent(FontRef font) { return (int) ceil(CTFontGetDescent(font)); }

static CGColorSpaceRef colorSpace = NULL; // initialized first time needed

static CGContextRef bitmap2context(OBJ bitmap) {
	if (!colorSpace) colorSpace = CGColorSpaceCreateDeviceRGB();

	if (nilObj == bitmap) {
		SDL_Surface *screen = screenBitmap;
		if (!screen) return NULL;
		return CGBitmapContextCreate(
			screen->pixels, screen->w, screen->h, 8, (4 * screen->w),
			colorSpace, kCGImageAlphaPremultipliedLast);
	}

	if (!isBitmap(bitmap)) return NULL;
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return NULL;

	return CGBitmapContextCreate(&FIELD(data, 0), w, h, 8, (4 * w), colorSpace, kCGImageAlphaPremultipliedLast);
}

static void setCGClipRect(CGContextRef ctx, OBJ clipRect, int bmHeight) {
	if (!isRectangle(clipRect)) return;

	int x = intValue(FIELD(clipRect, 0));
	int y = intValue(FIELD(clipRect, 1));
	int w = intValue(FIELD(clipRect, 2));
	int h = intValue(FIELD(clipRect, 3));
	y = bmHeight - (y + h); // y origin is at bottom of bitmap in Quartz
	CGRect r = CGRectMake(x, y, w, h);
	CGContextClipToRect(ctx, r);
}

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y, OBJ clipRect) {
	CGContextRef context = bitmap2context(bm);
	if (!context) {
		printf("drawString target must be a bitmap (Mac)\n");
		return;
	}
	int bmHeight;
	if (nilObj == bm) {
		bmHeight = screenBitmap->h;
	} else {
		bmHeight = obj2int(FIELD(bm, 1));
	}
	CGContextSaveGState(context);
	setCGClipRect(context, clipRect, bmHeight);

	// default color is black
	int r = 0;
	int g = 0;
	int b = 0;
	int a = 255;
	if (objWords(color) >= 4) { // extract components from color
		OBJ n = FIELD(color, 0);
		if (isInt(n)) r = clip(obj2int(n), 0, 255);
		n = FIELD(color, 1);
		if (isInt(n)) g = clip(obj2int(n), 0, 255);
		n = FIELD(color, 2);
		if (isInt(n)) b = clip(obj2int(n), 0, 255);
		n = FIELD(color, 3);
		if (isInt(n)) a = clip(obj2int(n), 0, 255);
	}

	CFStringRef string = CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8);

	// Note: RGB order is reversed between SDL2 and Mac OS.
	CGFloat rgba[] = {b / 255.0, g / 255.0, r / 255.0, a / 255.0};
	if (!colorSpace) colorSpace = CGColorSpaceCreateDeviceRGB();
	CGColorRef cgColor = CGColorCreate(colorSpace, rgba);
	CFStringRef keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
	CFTypeRef values[] = { font, cgColor };
	CFDictionaryRef attributes = CFDictionaryCreate(
		kCFAllocatorDefault, (const void**) &keys,
		(const void**) &values, sizeof(keys) / sizeof(keys[0]),
		&kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks);

	CFAttributedStringRef attrString = CFAttributedStringCreate(kCFAllocatorDefault, string, attributes);
	CTLineRef line = CTLineCreateWithAttributedString(attrString);

	// Set text position and draw the line into the graphics context
	y = bmHeight - ascent(font) - y; // flip y
	CGContextSetTextPosition(context, (float) x, (float) y);
	CTLineDraw(line, context);

	CGContextRestoreGState(context);
	CFRelease(line);
	CFRelease(attrString);
	CFRelease(attributes);
	CFRelease(cgColor);
	CFRelease(string);
	CGContextRelease(context);
}

static int stringWidth(char *s, FontRef font) {
	CFStringRef string = CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8);

	CFStringRef keys[] = { kCTFontAttributeName };
	CFTypeRef values[] = { font };
	CFDictionaryRef attributes = CFDictionaryCreate(
		kCFAllocatorDefault, (const void**) &keys,
		(const void**) &values, sizeof(keys) / sizeof(keys[0]),
		&kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks);

	CFAttributedStringRef attrString = CFAttributedStringCreate(kCFAllocatorDefault, string, attributes);
	CTLineRef line = CTLineCreateWithAttributedString(attrString);

	CGFloat ignore = 0;
	double width = CTLineGetTypographicBounds(line, &ignore, &ignore, &ignore);
	int w = (int) ceil(width);

	CFRelease(line);
	CFRelease(attrString);
	CFRelease(attributes);
	CFRelease(string);

	return w;
}

static OBJ fontNames() {
	char cName[500]; // buffer for copying font name

	CFDictionaryRef allFonts = CFDictionaryCreate(
		kCFAllocatorDefault, NULL, NULL, 0,
		&kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks);
	CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(allFonts);

	CFArrayRef fontList = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, NULL);
	int count = CFArrayGetCount(fontList) & 0x7FFF; // limit to a maximum of 32767 fonts
	OBJ result = newArray(count);
	for (int i = 0; i < count; i++) {
		CTFontDescriptorRef fDescr = CFArrayGetValueAtIndex(fontList, i); // owned by Array, so don't release
		CTFontRef font = CTFontCreateWithFontDescriptor(fDescr, 0.0, NULL);
		CFStringRef fName = CTFontCopyFullName(font);
		cName[0] = 0;
		CFStringGetCString(fName, cName, 200, kCFStringEncodingMacRoman);
		FIELD(result, i) = newString(cName);
		CFRelease(fName);
		CFRelease(font);
	}
	CFRelease(fontList);
	CFRelease(descriptor);
	CFRelease(allFonts);

	return result;
}

#endif // MacOS and iOS

#if defined(__linux__)

#include <pango/pangocairo.h>

typedef PangoFontDescription *FontRef;

PangoLayout *cachedLayout = NULL; // used for measuring

static void initCachedLayout() {
	cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_A8, 1, 1);
	cairo_t *cr = cairo_create(surface);
	cachedLayout = pango_cairo_create_layout(cr);
}

static FontRef openFont(char *fontName, int fontSize) {
	char familyName[200];
	strncpy(familyName, fontName, 200);
	familyName[199] = 0; // ensure zero termination

	char *boldIndex = strcasestr(familyName, "Bold");
	char *italicIndex = strcasestr(familyName, "Italic");
	if (boldIndex) *boldIndex = 0;
	if (italicIndex) *italicIndex = 0;

	for (int i = (strlen(familyName) - 1); ((i >= 0) && (familyName[i] <= 32)); i--) {
		familyName[i] = 0; // trim blanks
	}

	FontRef result = pango_font_description_new();
	pango_font_description_set_family(result, familyName);
	int fudgeFactor = (pango_version() > 14403) ? 1 : 0;
	pango_font_description_set_size(result, (fontSize - fudgeFactor) * PANGO_SCALE);
	if (boldIndex) pango_font_description_set_weight(result, 700);
	if (italicIndex) pango_font_description_set_style(result, PANGO_STYLE_ITALIC);

	return result;
}

static void closeFont(FontRef font) {
	pango_font_description_free(font);
}

static int ascent(FontRef font) {
	if (!cachedLayout) initCachedLayout();
	pango_layout_set_font_description(cachedLayout, font);
	PangoContext *context = pango_layout_get_context(cachedLayout);
	PangoFontMetrics *metrics = pango_context_get_metrics(context, font, NULL);
	int fudgeFactor = (pango_version() > 14403) ? 1 : 0;
	return (pango_font_metrics_get_ascent(metrics) / PANGO_SCALE) + fudgeFactor;
}

static int descent(FontRef font) {
	if (!cachedLayout) initCachedLayout();
	pango_layout_set_font_description(cachedLayout, font);
	PangoContext *context = pango_layout_get_context(cachedLayout);
	PangoFontMetrics *metrics = pango_context_get_metrics(context, font, NULL);
	int fudgeFactor = (pango_version() > 14403) ? 1 : 0;
	return (pango_font_metrics_get_descent(metrics) / PANGO_SCALE) + fudgeFactor;
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

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y, OBJ clipRect) {
	cairo_surface_t *surface = NULL;
	SDL_Surface *screen = screenBitmap;
	if ((nilObj == bm) && screen) {
		surface = cairo_image_surface_create_for_data(
			screen->pixels, CAIRO_FORMAT_ARGB32, screen->w, screen->h, (4 * screen->w));
	} else if (isBitmap(bm)) {
		int w = obj2int(FIELD(bm, 0));
		int h = obj2int(FIELD(bm, 1));
		OBJ data = FIELD(bm, 2);

		surface = cairo_image_surface_create_for_data(
			(unsigned char *) &FIELD(data, 0), CAIRO_FORMAT_ARGB32, w, h, (4 * w));
	} else {
		printf("drawString target must be a bitmap (Linux)\n");
		return;
	}

	cairo_t *cr = cairo_create(surface);
	setCairoClipRect(cr, clipRect);
	PangoLayout *layout = pango_cairo_create_layout(cr);

	pango_layout_set_font_description(layout, font);
	pango_layout_set_text(layout, s, strlen(s));

	// extract color components (default color is black)
	int r = 0;
	int g = 0;
	int b = 0;
	int a = 255;
	if (objWords(color) >= 4) { // extract components from color
		OBJ n = FIELD(color, 0);
		if (isInt(n)) r = clip(obj2int(n), 0, 255);
		n = FIELD(color, 1);
		if (isInt(n)) g = clip(obj2int(n), 0, 255);
		n = FIELD(color, 2);
		if (isInt(n)) b = clip(obj2int(n), 0, 255);
		n = FIELD(color, 3);
		if (isInt(n)) a = clip(obj2int(n), 0, 255);
	}

	cairo_set_source_rgba(cr, r / 255.0, g / 255.0, b / 255.0, a / 255.0);
	cairo_translate(cr, x, y);
	pango_cairo_show_layout(cr, layout);

	g_object_unref(layout);
	cairo_destroy(cr);
	cairo_surface_destroy(surface);
}

static int stringWidth(char *s, FontRef font) {
	if (!cachedLayout) initCachedLayout();
	pango_layout_set_font_description(cachedLayout, font);
	pango_layout_set_text(cachedLayout, s, strlen(s));
	int width, height;
	pango_layout_get_pixel_size(cachedLayout, &width, &height);
	return width;
}

static OBJ fontNames() {
	PangoFontMap *fontMap;
	PangoFontFamily **fontFomilies;
	int count;

	if (cachedLayout == NULL) {
		cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_A8, 1, 1);
		cairo_t *cr = cairo_create(surface);
		cachedLayout = pango_cairo_create_layout(cr);
	}
	fontMap = pango_context_get_font_map(pango_layout_get_context(cachedLayout));
	pango_font_map_list_families(fontMap, &fontFomilies, &count);

	OBJ result = newArray(count);
	for (int i = 0; i < count; i++) {
		FIELD(result, i) = newString((char *) pango_font_family_get_name(fontFomilies[i]));
	}
	g_free(fontFomilies);

	return result;
}

#endif // linux

// Windows

#if defined(_WIN32)

#include <string.h>
#include <windows.h>
#include <usp10.h>

typedef HFONT FontRef;

static FontRef openFont(char *fontName, int fontSize) {
	// Note: ANTIALIASED_QUALITY does not work. Only CLEARTYPE_QUALITY results in smoothing.
	// Negative font size selects font based on character height, not cell height.

	return CreateFont(
		-abs(fontSize), 0, 0, 0,
		FW_DONTCARE, false, false, false,
		0, OUT_OUTLINE_PRECIS,
		0, CLEARTYPE_QUALITY, FF_DONTCARE,
		fontName);
}

static void closeFont(FontRef font) {
	DeleteObject(font);
}

static int ascent(FontRef font) {
	if (!font) return 0;

	TEXTMETRIC metrics;
	HDC hdc = CreateCompatibleDC(0);
	SelectObject(hdc, font);
	int ok = GetTextMetrics(hdc, &metrics);
	DeleteDC(hdc);

	return (ok ? metrics.tmAscent : 0);
}

static int descent(FontRef font) {
	if (!font) return 0;

	TEXTMETRIC metrics;
	HDC hdc = CreateCompatibleDC(0);
	SelectObject(hdc, font);
	int ok = GetTextMetrics(hdc, &metrics);
	DeleteDC(hdc);

	return (ok ? metrics.tmDescent : 0);
}

// maximum wide string length
#define MAX_STRING 5000

static SCRIPT_STRING_ANALYSIS analyze(HDC hdc, char *s) {
	WCHAR wStr[MAX_STRING];
	SCRIPT_STRING_ANALYSIS ssa = NULL;
	SCRIPT_CONTROL scriptControl = {0};
	SCRIPT_STATE scriptState = {0};

	int wLength = MultiByteToWideChar(CP_UTF8, 0, s, strlen(s), wStr, MAX_STRING);
	if (wLength < 1) return NULL;

	ScriptStringAnalyse(
		hdc,
		wStr, wLength, (2 * wLength) + 16,
		-1, // Unicode string
		SSA_GLYPHS | SSA_FALLBACK,
		0, // no clipping
		&scriptControl, &scriptState,
		0, 0, 0,
		&ssa);

	return ssa;
}

static void setWinClipRect(HDC hdc, int x, int y, OBJ clipRect) {
	if (!isRectangle(clipRect)) return;

	int clipX = intValue(FIELD(clipRect, 0)) - x;
	int clipY = intValue(FIELD(clipRect, 1)) - y;
	int clipR = clipX + intValue(FIELD(clipRect, 2)); // right
	int clipB = clipY + intValue(FIELD(clipRect, 3)); // bottom
	IntersectClipRect(hdc, clipX, clipY, clipR, clipB);
}

static HBITMAP createBitmap(HDC hdc, int w, int h, uint32_t **pixelsPtr) {
	// Create and return a device independent bitmap of the given size.

	BITMAPINFO bi;
	bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	bi.bmiHeader.biWidth = w;
	bi.bmiHeader.biHeight = -h; // negative indicates top-down bitmap
	bi.bmiHeader.biPlanes = 1;
	bi.bmiHeader.biBitCount = 32;
	bi.bmiHeader.biCompression = BI_RGB;
	bi.bmiHeader.biSizeImage = 0;
	bi.bmiHeader.biXPelsPerMeter = 0;
	bi.bmiHeader.biYPelsPerMeter = 0;
	bi.bmiHeader.biClrUsed = 0;
	bi.bmiHeader.biClrImportant	= 0;
	return CreateDIBSection(hdc, &bi, DIB_RGB_COLORS, (void *) pixelsPtr, NULL, 0);
}

// static bitmap used for rendering most text strings

#define TEXT_BM_WIDTH 500
#define TEXT_BM_HEIGHT 50
static HBITMAP textBM = NULL;
static uint32_t *textBMPixels = NULL;

static void initTextBitmap() {
	// Initialize a persistent bitmap to be used for drawing small strings (i.e. most strings).
	// This saves the cost of creating a new bitmap for every call to drawString().

	if (!textBM) {
		HDC hdc = CreateCompatibleDC(0);
		textBM = createBitmap(hdc, TEXT_BM_WIDTH, TEXT_BM_HEIGHT, &textBMPixels);
		DeleteDC(hdc);
	}
}

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int dstX, int dstY, OBJ clipRect) {
	HDC hdc = NULL;
	SCRIPT_STRING_ANALYSIS ssa = NULL;
	HBITMAP hBitmap = NULL;
	uint32_t *bmPixels;
	int bmSpan;
	HGDIOBJ oldObj;

	// select target bitmap
	int w = 0, h = 0;
	uint32_t *pixelData = NULL;
	if ((nilObj == bm) && screenBitmap) {
		w = screenBitmap->w;
		h = screenBitmap->h;
		pixelData = screenBitmap->pixels;
	} else if (isBitmap(bm)) {
		w = obj2int(FIELD(bm, 0));
		h = obj2int(FIELD(bm, 1));
		pixelData = &FIELD(FIELD(bm, 2), 0);
	} else {
		printf("drawString target must be a bitmap (Win)\n");
		return;
	}

	// set font
	hdc = CreateCompatibleDC(0);
	SelectObject(hdc, font);

	// analyze the string
	ssa = analyze(hdc, s);
	if (ssa == NULL) {
		primFailed("Could not analyze string");
		goto cleanup;
	}

	// get rendered text dimensions
	CONST SIZE *pSize = ScriptString_pSize(ssa);
	if (pSize == NULL) {
		primFailed("Could not get string size");
		goto cleanup;
	}
	int textW = pSize->cx;
	int textH = pSize->cy;

	if ((textW <= TEXT_BM_WIDTH) && (textH <= TEXT_BM_HEIGHT)) {
		// most strings -- reuse the text rendering bitmap
		if (!textBM) initTextBitmap();
		memset(textBMPixels, 0, (4 * TEXT_BM_WIDTH * TEXT_BM_HEIGHT)); // clear
		hBitmap = textBM;
		bmPixels = textBMPixels;
		bmSpan = TEXT_BM_WIDTH;
	} else {
		// large string -- create a one-time use bitmap
		hBitmap = createBitmap(hdc, textW, textH, &bmPixels);
		bmSpan = textW;
	}
	if (!hBitmap) goto cleanup; // failed to create bitmap

	// set the color (defaults to black)
	int r = 0, g = 0, b = 0;
	if (objWords(color) >= 3) { // extract RGB components from color
		OBJ n = FIELD(color, 0);
		if (isInt(n)) r = clip(obj2int(n), 0, 255);
		n = FIELD(color, 1);
		if (isInt(n)) g = clip(obj2int(n), 0, 255);
		n = FIELD(color, 2);
		if (isInt(n)) b = clip(obj2int(n), 0, 255);
	}
	uint32_t textRGB = (255 << 24)| (r << 16) | (g << 8) | b; // opaque text color

	oldObj = SelectObject(hdc, hBitmap);
	if (oldObj != NULL) {
		setWinClipRect(hdc, dstX, dstY, clipRect);

		// Render the string as white. Pixel brightness will used as the source alpha.
		SetBkMode(hdc, TRANSPARENT);
		SetTextColor(hdc, RGB(255, 255, 255));
		ScriptStringOut(ssa, 0, 0, 0, NULL, 0, 0, FALSE);

		// copy all non-transparent pixels to target bitmap, using the brightness of each
		// pixel as the source alpha for the output color, textRGB.
		int endX = dstX + textW;
		int endY = dstY + textH;
		for (int y = dstY, srcY = 0; y < endY; y++, srcY++) {
			uint32_t *src = &bmPixels[srcY * bmSpan];
			for (int x = dstX; x < endX; x++) {
				unsigned int pix = *src++;
				if (pix != 0) { // if not transparent
					if ((0 <= x) && (x < w) && (0 <= y) && (y < h)) {
						// Note: Windows cleartype does subpixel rendering so R, G, and B
						// have different values for edge pixels. The green channel is close
						// to the average of all three channels.
						int alpha = (pix >> 8) & 255; // use green channel as alpha
						if (alpha > 220) { // consider alphas above this threshold opaque
							pix = textRGB;
						} else { // do alpha blending
							int dstPix = pixelData[(y * w) + x];
							int dstAlpha = (dstPix >> 24) & 255;
							int invAlpha = 255 - alpha;
							int rOut = ((alpha * r) + (invAlpha * ((dstPix >> 16) & 255))) / 255;
							int gOut = ((alpha * g) + (invAlpha * ((dstPix >> 8) & 255))) / 255;
							int bOut = ((alpha * b) + (invAlpha * (dstPix & 255))) / 255;
							int aOut = (alpha > dstAlpha) ? alpha : dstAlpha;
							pix = (aOut << 24) | (rOut << 16) | (gOut << 8) | bOut;
						}
						pixelData[(y * w) + x] = pix;
					}
				}
			}
		}
		SelectObject(hdc, oldObj);
	}

cleanup:
	if (hBitmap && (hBitmap != textBM)) DeleteObject(hBitmap);
	if (ssa) ScriptStringFree(&ssa);
	if (hdc) DeleteDC(hdc);
}

static int stringWidth(char *s, FontRef font) {
	CONST SIZE *pSize;
	int width = 0;
	HDC hdc = CreateCompatibleDC(0);
	SelectObject(hdc, font);
	SCRIPT_STRING_ANALYSIS ssa = analyze(hdc, s);
	if (ssa != NULL) {
		pSize = ScriptString_pSize(ssa);
		if (pSize != NULL) width = pSize->cx;
		ScriptStringFree(&ssa);
	}
	DeleteDC(hdc);
	return width;
}

// variables used for font enumeration

static char lastFontFamily[200];
static OBJ g_fontList = nilObj; // array for collecting font names
static int g_fontCount = 0;

static int CALLBACK fontEnumCallback(ENUMLOGFONTEX *lpelfe, NEWTEXTMETRICEX *lpntme, DWORD fontType, LPARAM lParam) {
	if (!g_fontList || !IS_CLASS(g_fontList, ArrayClass)) return true; // shouldn't happen
	if (g_fontCount >= objWords(g_fontList)) return true; // no more room
	if (fontType != TRUETYPE_FONTTYPE) return true;

	char *s = (char *) lpelfe->elfFullName;
	if ('@' == s[0]) s = &s[1]; // skip first character if it is '@'
	if (strcmp(s, lastFontFamily) != 0) {
		FIELD(g_fontList, g_fontCount++) = newString(s);
		strncpy(lastFontFamily, s, 200);
		lastFontFamily[199] = 0; // ensure null termination
	}
	return true;
}

static OBJ fontNames() {
	g_fontList = newArray(500);
	g_fontCount = 0;

	LOGFONT fontSpec;
	memset(&fontSpec, 0, sizeof(fontSpec));
	fontSpec.lfCharSet = DEFAULT_CHARSET;
	fontSpec.lfFaceName[0] = 0; // empty string; enumerates font families

	HDC hdc = CreateCompatibleDC(0);
	EnumFontFamiliesEx(hdc, &fontSpec, (FONTENUMPROC) fontEnumCallback, 0, 0);
	DeleteDC(hdc);

	OBJ result = copyObj(g_fontList, g_fontCount, 1);
	g_fontList = nilObj;
	return result;
}

#endif // Windows

#ifdef EMSCRIPTEN

#include <emscripten.h>

// imported from vectorPrims.c:
int setTargetCanvas(OBJ obj, OBJ clipRect);

typedef char *FontRef;

char fullFontName[1000];
int lastFontSize = 12;

static FontRef openFont(char *fontName, int fontSize) {
	char baseFontName[200];

	// strip Bold and/or Italic prefixes from fontName
	int len = strlen(fontName);
	char *boldStart = strstr(fontName, " Bold");
	if (boldStart) len = boldStart - fontName;
	char *italicStart = strstr(fontName, " Italic");
	if (italicStart) {
		if (!boldStart || (italicStart < boldStart)) len = italicStart - fontName;
	}

	if (len >= sizeof(baseFontName)) len = (sizeof(baseFontName) - 1);
	memmove(baseFontName, fontName, len); // copy len characters into baseFontName
	baseFontName[len] = 0; // null terminate

	// create a CSS-format font name
	snprintf(fullFontName, sizeof(fullFontName), "%s%s%dpx %s",
		italicStart ? "italic " : "",
		boldStart ? "bold " : "",
		fontSize,
		baseFontName);

	lastFontSize = fontSize;
	return fullFontName;
}

static void closeFont(FontRef font) {
	// nothing to do
}

static int ascent(FontRef font) {
	// approximate; HTML5 Canvas does not support real font metrics
	return (int) (0.95 * lastFontSize);
}

static int descent(FontRef font) {
	// approximate; HTML5 Canvas does not support real font metrics
	return (int) (0.3 * lastFontSize);
}

static void toColorString(OBJ colorObj, char *result, int resultSize) {
	// Write a Javascript color string for the given color into the result.

	int words = objWords(colorObj);
	result[0] = 0;
	if (words < 3) {
		snprintf(result, resultSize, "rgba(0, 0, 0, 1)"); // black
		return;
	}
	int r = clip(obj2int(FIELD(colorObj, 0)), 0, 255);
	int g = clip(obj2int(FIELD(colorObj, 1)), 0, 255);
	int b = clip(obj2int(FIELD(colorObj, 2)), 0, 255);
	int a = (words <= 3) ? 255 : clip(obj2int(FIELD(colorObj, 3)), 0, 255);
	snprintf(result, resultSize, "rgba(%d, %d, %d, %f)", r, g, b, a / 255.0);
}

static void drawStringOnTexture(char *s, FontRef font, OBJ texture, OBJ color, int x, int y, OBJ clipRect) {
	int ok = setTargetCanvas(texture, clipRect);
	if (!ok) return;

	char colorString[1000];
	toColorString(color, colorString, sizeof(colorString));

	y -= lastFontSize / 10; // adjust y offset to match other platforms
	EM_ASM_({
		var s = UTF8ToString($0);
		var fontName = UTF8ToString($1);
		var colorString = UTF8ToString($2);
		var x = $3;
		var y = $4;

		GP.ctx.font = fontName;
		GP.ctx.fillStyle = colorString;
		GP.ctx.fillText(s, x, y);
		GP.ctx.restore();
	}, s, font, colorString, x, (y + lastFontSize));
}

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y, OBJ clipRect) {
	if (!isBitmap(bm)) {
		drawStringOnTexture(s, font, bm, color, x, y, clipRect);
		return;
	}

	// extract bitmap fields
	int bmWidth = obj2int(FIELD(bm, 0));
	int bmHeight = obj2int(FIELD(bm, 1));
	OBJ bmData = FIELD(bm, 2);
	if (objWords(bmData) != (bmWidth * bmHeight)) return;

	// default color is black
	int r = 0;
	int g = 0;
	int b = 0;
	int a = 255;
	if (objWords(color) >= 4) { // extract components from color
		OBJ n = FIELD(color, 0);
		if (isInt(n)) r = clip(obj2int(n), 0, 255);
		n = FIELD(color, 1);
		if (isInt(n)) g = clip(obj2int(n), 0, 255);
		n = FIELD(color, 2);
		if (isInt(n)) b = clip(obj2int(n), 0, 255);
		n = FIELD(color, 3);
		if (isInt(n)) a = clip(obj2int(n), 0, 255);
	}

	y -= lastFontSize / 10; // adjust y offset to match other platforms
	EM_ASM_({
		var s = UTF8ToString($0);
		var fontName = UTF8ToString($1);
		var fontHeight = $2;
		var bmData = $3;
		var bmWidth = $4;
		var bmHeight = $5;
		var r = $6;
		var g = $7;
		var b = $8;
		var a = $9;
		var x = $10;
		var y = $11;

		var cnv = document.createElement('canvas');
		var ctx = cnv.getContext('2d');
		ctx.font = fontName;
		cnv.width = Math.ceil(ctx.measureText(s).width);
		cnv.height = bmHeight;
		ctx.font = fontName; // font gets cleared by changing canvas size (in Chrome, at least)
		ctx.fillStyle = '#000';
		ctx.fillRect(0, 0, cnv.width, cnv.height); // fill w/ black
		ctx.fillStyle = '#FFF'; // draw w/ white
		ctx.fillText(s, 0, fontHeight);

		var cnvData = (ctx.getImageData(0, 0, cnv.width, cnv.height)).data;
		var srcStartX = Math.max(0, -x);
		var dstStartX = Math.max(0, x);
		var dstXCount = Math.min(cnv.width, (bmWidth - dstStartX));

		var srcIndex = 4 * srcStartX;
		for (var dstY = y; dstY < bmHeight; dstY++) {
			if (dstY >= 0) {
				var dstIndex = bmData + (4 * ((dstY * bmWidth) + dstStartX));
				for (var i = 0; i < dstXCount; i++) {
					var j = srcIndex + (4 * i);
					// due to subpixel sampling, R/G/B channels may be different; alpha is average
					var alpha = (cnvData[j] + cnvData[j+1] + cnvData[j+2]) / 3;
					if (alpha < 20) {
						// transparent pixels
						dstIndex += 4;
					} else if (alpha > 250) {
						// opaque pixels
						Module.HEAPU8[dstIndex++] = r;
						Module.HEAPU8[dstIndex++] = g;
						Module.HEAPU8[dstIndex++] = b;
						Module.HEAPU8[dstIndex++] = 255;
					} else {
						// do alpha blending
						var invAlpha = 255 - alpha;
						var rOut = Math.round(((invAlpha * Module.HEAPU8[dstIndex]) + (alpha * r)) / 255);
						var gOut = Math.round(((invAlpha * Module.HEAPU8[dstIndex + 1]) + (alpha * g)) / 255);
						var bOut = Math.round(((invAlpha * Module.HEAPU8[dstIndex + 2]) + (alpha * b)) / 255);
						var aOut = Math.max(alpha, Module.HEAPU8[dstIndex + 3]);
						Module.HEAPU8[dstIndex++] = rOut;
						Module.HEAPU8[dstIndex++] = gOut;
						Module.HEAPU8[dstIndex++] = bOut;
						Module.HEAPU8[dstIndex++] = aOut;
					}
				}
			}
			srcIndex += (4 * cnv.width);
		}
	}, s, font, lastFontSize, &FIELD(bmData, 0), bmWidth, bmHeight, r, g, b, a, x, y);
}

static int stringWidth(char *s, FontRef font) {
	int result = EM_ASM_INT({
		var s = UTF8ToString($0);
		var cnv = document.createElement('canvas');
		var ctx = cnv.getContext('2d');
		ctx.font = UTF8ToString($1);
		return Math.round(ctx.measureText(s).width);
	}, s, font);
	return result;
}

static OBJ fontNames() {
	// Returns empty array because HTML5 does not support font enumeration.
	(void) isRectangle; // suppress compiler warning that isRectangle is unused by Emscripten
	(void) intValue; // suppress compiler warning that intValue is unused by Emscripten
	return newArray(0);
}

#endif // EMSCRIPTEN

// ***** Current Font *****

static FontRef currentFont = NULL;

// ***** Font cache *****

#define FONT_CACHE_SIZE 20
#define FONT_NAME_SIZE 100

typedef struct {
	char fontName[FONT_NAME_SIZE];
	int fontSize;
	FontRef font;
} FontCacheEntry;

static FontCacheEntry fontCache2[FONT_CACHE_SIZE];

static void initFontCache() {
	memset(&fontCache2, 0, FONT_CACHE_SIZE * sizeof(FontCacheEntry));
}

static FontRef fontCacheLookup(char *fontName, int fontSize) {
	// Return the given font if it is in the cache or NULL if it it isn't.

	for (int i = 0; i < FONT_CACHE_SIZE; i++) {
		FontCacheEntry *entry = &fontCache2[i];
		if (entry->font && (fontSize == entry->fontSize) && (strcmp(fontName, entry->fontName) == 0)) {
			return entry->font;
		}
	}
	return NULL;
}

static void fontCacheAdd(char *fontName, int fontSize, FontRef font) {
	// Add the given font to the font cache.

	// first, look for an empty entry
	int replaceIndex = -1;
	for (int i = 0; i < FONT_CACHE_SIZE; i++) {
		if (!fontCache2[i].font) { replaceIndex = i; break; }
	}

	// if no empty entry is found, replace a random entry
	if (replaceIndex < 0) replaceIndex = rand() % FONT_CACHE_SIZE;

	FontCacheEntry *entry = &fontCache2[replaceIndex];
	if (entry->font) closeFont(entry->font);
	strncpy(entry->fontName, fontName, FONT_NAME_SIZE);
	entry->fontSize = fontSize;
	entry->font = font;
}

// ***** Primitives *****

static OBJ primDrawString(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!currentFont) return failedNoFont();

	OBJ bm = args[0];
	char *s = strArg(1, "", nargs, args);
	OBJ color = (nargs > 2) ? args[2] : nilObj;
	int x = intOrFloatArg(3, 0, nargs, args);
	int y = intOrFloatArg(4, 0, nargs, args);
	OBJ clipRect = (nargs > 5) ? args[5] : nilObj;

	if (isBadUTF8(s)) {
		printf("drawString: invalid UTF8 string (%d bytes)\n", (int) strlen(s));
		return nilObj;
	}
	if (NOT_CLASS(args[1], StringClass)) return primFailed("Second argument must be a String");
	if (!*s) return nilObj; // empty string; do nothing

	drawString(s, currentFont, bm, color, x, y, clipRect);
	return nilObj;
}

static OBJ primSetFont(int nargs, OBJ args[]) {
	char *fontName = strArg(0, "Helvetica", nargs, args);
	if (strlen(fontName) == 0) return primFailed("Bad font name");
	if (isBadUTF8(fontName)) return badUTF8String();
	int fontSize = intOrFloatArg(1, 18, nargs, args);

#ifdef EMSCRIPTEN
	// Enscripten doesn't do font caching
	currentFont = openFont(fontName, fontSize);
	return nilObj;
#endif

	FontRef cachedFont = fontCacheLookup(fontName, fontSize);
	if (cachedFont) {
		currentFont = cachedFont;
	} else {
		FontRef newFont = openFont(fontName, fontSize);
		if (newFont) {
			fontCacheAdd(fontName, fontSize, newFont);
			currentFont = newFont;
		} else {
			printf("Could not find font %s; using fallback\n", fontName);
		}
	}
	return nilObj;
}

static OBJ primStringWidth(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!currentFont) return failedNoFont();

	char *s = strArg(0, "", nargs, args);
	if (!*s) return int2obj(0); // empty string
	if (isBadUTF8(s)) return int2obj(0); // invalid strings are effectively zero width
	return int2obj(stringWidth(s, currentFont));
}

static OBJ primFontNames(int nargs, OBJ args[]) {
	return fontNames();
}

static OBJ primFontAscent(int nargs, OBJ args[]) {
	if (!currentFont) return failedNoFont();
	return int2obj(ascent(currentFont));
}

static OBJ primFontDescent(int nargs, OBJ args[]) {
	if (!currentFont) return failedNoFont();
	return int2obj(descent(currentFont));
}

// ***** Graphics Primitive Lookup *****

PrimEntry textAndFontPrimList[] = {
	{"-----", NULL, "Graphics: Font and Text"},
	{"drawString",		primDrawString,				"Draw a string on a bitmap. Arguments: bitmap string [color x y]"},
	{"stringWidth",		primStringWidth,			"Return the width a string drawn with the current font. Arguments: string"},
	{"fontNames",		primFontNames,				"Return an array of available font names."},
	{"setFont",			primSetFont,				"Set the font size and name. Arguments: fontName fontSize"},
	{"fontAscent",		primFontAscent,				"Return the ascent of the current font (maximum character height above the baseline)"},
	{"fontDescent",		primFontDescent,			"Return the descent of the current font (maximum character descent below the baseline)"},
};

PrimEntry* textAndFontPrimitives(int *primCount) {
	initFontCache();
	*primCount = sizeof(textAndFontPrimList) / sizeof(PrimEntry);
	return textAndFontPrimList;
}
