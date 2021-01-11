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

OBJ badUTF8String() { return primFailed("Invalid UTF8 string"); }

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
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return NULL;

	if (!colorSpace) colorSpace = CGColorSpaceCreateDeviceRGB();
	return CGBitmapContextCreate(&FIELD(data, 0), w, h, 8, (4 * w), colorSpace, kCGImageAlphaPremultipliedLast);
}

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y) {
	CGContextRef context = bitmap2context(bm);
	if (!context) {
		primFailed("Could not create graphic context for bitmap");
		return;
	}

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
	y = (obj2int(FIELD(bm, 1)) - ascent(font) - y); // flip y
	CGContextSetTextPosition(context, (float) x, (float) y);
	CTLineDraw(line, context);

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

PangoLayout *cachedLayout = NULL;  // used for measuring

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

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y) {
	int w = obj2int(FIELD(bm, 0));
	int h = obj2int(FIELD(bm, 1));
	OBJ data = FIELD(bm, 2);
	if (HAS_OBJECTS(data) || ((w * h) <= 0) || (objWords(data) != (w * h))) {
		primFailed("Could not create graphic context for bitmap");
		return;
	}

	cairo_surface_t *surface = cairo_image_surface_create_for_data(
		(unsigned char *) &FIELD(data, 0), CAIRO_FORMAT_ARGB32, w, h, (4 * w));
	cairo_t *cr = cairo_create(surface);
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

// Windows (just stubs for now)

#if defined(_WIN32)

#define UNICODE 1  // use WCHAR API's

#include <string.h>
#include <windows.h>
#include <usp10.h>

#define MAX_STRING 5000

typedef HFONT FontRef;

static FontRef openFont(char *fontName, int fontSize) {
	return CreateFont(
		-abs(fontSize), 0, 0, 0,
		FW_DONTCARE, false, false, false,
		0, OUT_OUTLINE_PRECIS, /* OUT_DEFAULT_PRECIS, */
		0, CLEARTYPE_QUALITY, /* ANTIALIASED_QUALITY, */ FF_DONTCARE,
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

static SCRIPT_STRING_ANALYSIS analyze(HDC hdc, char *s) {
	WCHAR wStr[MAX_STRING];
	SCRIPT_STRING_ANALYSIS ssa = NULL;
 	SCRIPT_CONTROL scriptControl = {0};
	SCRIPT_STATE scriptState = {0};

	int length = strlen(s);
	if (length == 0) return NULL;
	if (length > MAX_STRING) length = MAX_STRING;

	int wLength = MultiByteToWideChar(CP_UTF8, 0, s, length, wStr, MAX_STRING);
	if (wLength < 1) return NULL;

	ScriptStringAnalyse(
		hdc,
		wStr, wLength, (2 * wLength) + 16,
		-1,  // Unicode string
		SSA_GLYPHS | SSA_FALLBACK,
		0, // no clipping
		&scriptControl, &scriptState,
		0, 0, 0,
		&ssa);
	return ssa;
}

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y) {
	HDC hdc = NULL;
	SCRIPT_STRING_ANALYSIS ssa = NULL;
	HBITMAP hBitmap = NULL;
	BITMAPINFO bi;
	unsigned int	*dibBits;
	HGDIOBJ			oldObj;

	int w = obj2int(FIELD(bm, 0));
	int h = obj2int(FIELD(bm, 1));
	OBJ data = FIELD(bm, 2);
	if (HAS_OBJECTS(data) || (w < 1) || (h < 1) || (objWords(data) != (w * h))) {
		primFailed("Bad bitmap");
		return;
	}

	hdc = CreateCompatibleDC(0);
	SelectObject(hdc, font);
	ssa = analyze(hdc, s);
	if (ssa == NULL) {
		primFailed("Could not analyze string");
		goto cleanup;
	}

	// get text size
	CONST SIZE *pSize = ScriptString_pSize(ssa);
	if (pSize == NULL) {
		primFailed("Could not get string size");
		goto cleanup;
	}
	int textW = pSize->cx;
	int textH = pSize->cy;

	// default color is black
	int r = 0;
	int g = 0;
	int b = 0;
	if (objWords(color) >= 3) { // extract RGB components from color
		OBJ n = FIELD(color, 0);
		if (isInt(n)) r = clip(obj2int(n), 0, 255);
		n = FIELD(color, 1);
		if (isInt(n)) g = clip(obj2int(n), 0, 255);
		n = FIELD(color, 2);
		if (isInt(n)) b = clip(obj2int(n), 0, 255);
	}
	unsigned int textRGB = ((r << 16) | (g << 8) | b);

	// create a device independent bitmap
	bi.bmiHeader.biSize          = sizeof(BITMAPINFOHEADER);
	bi.bmiHeader.biWidth         = textW;
	bi.bmiHeader.biHeight        = -textH;  // negative indicates top-down bitmap
	bi.bmiHeader.biPlanes        = 1;
	bi.bmiHeader.biBitCount      = 32;
	bi.bmiHeader.biCompression   = BI_RGB;
	bi.bmiHeader.biSizeImage     = 0;
	bi.bmiHeader.biXPelsPerMeter = 0;
	bi.bmiHeader.biYPelsPerMeter = 0;
	bi.bmiHeader.biClrUsed       = 0;
	bi.bmiHeader.biClrImportant  = 0;
	hBitmap = CreateDIBSection(hdc, &bi, DIB_RGB_COLORS, (void *) &dibBits, NULL, 0);
	if (hBitmap == NULL) goto cleanup;

	oldObj = SelectObject(hdc, hBitmap);
	if (oldObj != NULL) {
		// set fg and bg colors and render the string
		SetBkMode(hdc, TRANSPARENT);
		SetBkColor(hdc, RGB(0, 0, 0));
		SetTextColor(hdc, RGB(255, 255, 255));
		ScriptStringOut(ssa, 0, 0, 0, NULL, 0, 0, FALSE);

		unsigned int *src = dibBits;
		unsigned int *dst = (unsigned int *) &FIELD(data, 0);
		int endX = x + textW;
		int endY = y + textH;

		for (int dstY = y; dstY < endY; dstY++) {
			for (int dstX = x; dstX < endX; dstX++) {
				unsigned int pix = *src++;
				if (pix != 0) { // if not transparent
					if ((0 <= dstX) && (dstX < w) && (0 <= dstY) && (dstY < h)) {
						int alpha = (((pix >> 16) & 225) + ((pix >> 8) & 225) + (pix & 255)) / 3;
						dst[(dstY * w) + dstX] = (alpha << 24) | textRGB;
					}
				}
			}
		}
		SelectObject(hdc, oldObj);
	}

cleanup:
	if (hBitmap) DeleteObject(hBitmap);
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

// Variables used during font enumeration:
static OBJ g_fontDict = nilObj;
static OBJ g_fontList = nilObj;
static int g_fontCount = 0;

static int CALLBACK fontEnumCallback(ENUMLOGFONTEX *lpelfe, NEWTEXTMETRICEX *lpntme, DWORD fontType, LPARAM lParam) {
	if (!g_fontList || !g_fontDict) return true;
	if (fontType != TRUETYPE_FONTTYPE) return true;

	char *s = (char *) lpelfe->elfFullName;
	if ('@' == s[0]) s = &s[1];  // skip first character if it is '@'
	OBJ fontName = newString(s);

	if (dictHasKey(g_fontDict, fontName)) return true; // duplicate
	dictAtPut(g_fontDict, fontName, trueObj);

	if (g_fontCount >= objWords(g_fontList)) {
		// grow font array
		g_fontList = copyObj(g_fontList, 2 * objWords(g_fontList), 1);
	}
	FIELD(g_fontList, g_fontCount++) = fontName;
	return true;
}

static OBJ collectFonts(char *family) {
	g_fontDict = newDict(1000);
	g_fontList = newArray(100);
	g_fontCount = 0;

	LOGFONT fontSpec;
	memset(&fontSpec, 0, sizeof(fontSpec));
	fontSpec.lfCharSet = DEFAULT_CHARSET;
	fontSpec.lfFaceName[0] = 0;

	strcpy(fontSpec.lfFaceName, family);

	HDC hdc = CreateCompatibleDC(0);
	EnumFontFamiliesEx(hdc, &fontSpec, (FONTENUMPROC) fontEnumCallback, 0, 0);
	DeleteDC(hdc);

	OBJ result = copyObj(g_fontList, g_fontCount, 1);

	g_fontDict = nilObj;
	g_fontList = nilObj;
	return result;
}

static OBJ fontNames() {
	OBJ result = newArray(100);
	int resultCount = 0;
	OBJ recorded = newDict(1000);

	OBJ fontFamilies = collectFonts("");
	int n = objWords(fontFamilies);
	for (int i = 0; i < n; i++) {
		// get the members of font family[i]
		OBJ family = collectFonts(obj2str(FIELD(fontFamilies, i)));
		int familySize = objWords(family);
		for (int j = 0; j < familySize; j++) {
			OBJ thisFont = FIELD(family, j);
			if (!dictHasKey(recorded, thisFont)) { // add family member to result if not already added
				dictAtPut(recorded, thisFont, trueObj);
				if (resultCount >= objWords(result)) {
					// grow the result array
					result = copyObj(result, 2 * objWords(result), 1);
				}
				FIELD(result, resultCount++) = thisFont;
			}
		}
	}
	return result;
}

#endif // Windows

#ifdef EMSCRIPTEN

#include <emscripten.h>

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
 	return lastFontSize;
}

static int descent(FontRef font) {
	// approximate; HTML5 Canvas does not support real font metrics
	return (int) (0.3 * lastFontSize);
}

static void drawString(char *s, FontRef font, OBJ bm, OBJ color, int x, int y) {
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
					if (alpha > 0) {
						Module.HEAPU8[dstIndex++] = b;
						Module.HEAPU8[dstIndex++] = g;
						Module.HEAPU8[dstIndex++] = r;
						Module.HEAPU8[dstIndex++] = alpha;
					} else {
						dstIndex += 4;
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
	// HTML5 does not support font enumeration
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

// ***** Helpers *****

static OBJ failedNoFont() { return primFailed("No font"); }

static int isBitmap(OBJ bitmap) {
	return
		(objWords(bitmap) >= 3) &&
		isInt(FIELD(bitmap, 0)) && isInt(FIELD(bitmap, 1)) &&
		IS_CLASS(FIELD(bitmap, 2), BinaryDataClass);
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

	if (isBadUTF8(s)) {
		printf("drawString: invalid UTF8 string (%d bytes)\n", (int) strlen(s));
		return nilObj;
	}
	if (!isBitmap(bm)) return primFailed("Bad bitmap");
	if (NOT_CLASS(args[1], StringClass)) return primFailed("Second argument must be a String");
	if (!*s) return nilObj; // empty string; do nothing

	drawString(s, currentFont, bm, color, x, y);
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
