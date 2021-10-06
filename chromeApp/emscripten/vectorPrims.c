#include <math.h>
#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#ifdef EMSCRIPTEN
	#include <emscripten.h>
	#include <emscripten/html5.h>
	typedef void cairo_t;

	#define closePath cairo_close_path
	#define curveTo cairo_curve_to
	#define lineTo cairo_line_to
	#define moveTo cairo_move_to
#else
	#include <cairo/cairo.h>

	#define closePath cairo_close_path
	#define curveTo cairo_curve_to
	#define lineTo cairo_line_to
	#define moveTo cairo_move_to
#endif

// Helper Functions

static inline int intValue(OBJ obj) {
	// Return the value of an Integer or Float object.
	if (isInt(obj)) return obj2int(obj);
	if (IS_CLASS(obj, FloatClass)) return (int) round(evalFloat(obj));
	return 0;
}

static int isBitmap(OBJ bitmap) {
	return
		(objWords(bitmap) >= 3) &&
		isInt(FIELD(bitmap, 0)) && isInt(FIELD(bitmap, 1)) &&
		IS_CLASS(FIELD(bitmap, 2), BinaryDataClass) &&
		(objWords(FIELD(bitmap, 2)) == (obj2int(FIELD(bitmap, 0)) * obj2int(FIELD(bitmap, 1))));
}

static int isRectangle(OBJ rect) {
	return
		(objWords(rect) >= 4) &&
		(isInt(FIELD(rect, 0)) || IS_CLASS(FIELD(rect, 0), FloatClass)) &&
		(isInt(FIELD(rect, 1)) || IS_CLASS(FIELD(rect, 1), FloatClass)) &&
		(isInt(FIELD(rect, 2)) || IS_CLASS(FIELD(rect, 2), FloatClass)) &&
		(isInt(FIELD(rect, 3)) || IS_CLASS(FIELD(rect, 3), FloatClass));
}

static void interpretPath(cairo_t *ctx, OBJ path) {
	int count = objWords(path);
	double x = 0, y = 0;
	double c1x, c1y, c2x, c2y, qx, qy;
	double firstX = 0, lastX = 0;
	double firstY = 0, lastY = 0;
	int i = 0;
	while (i < count) {
		OBJ cmdObj = FIELD(path, i++);
		if (NOT_CLASS(cmdObj, StringClass)) {
			printf("Non-string command in path\n");
			return;
		}
		char *cmd = obj2str(cmdObj);
		if (strcmp("L", cmd) == 0) {
			x = evalFloat(FIELD(path, i++));
			y = evalFloat(FIELD(path, i++));
			#ifdef EMSCRIPTEN
				EM_ASM_({GP.ctx.lineTo($0, $1)}, x, y);
			#else
				cairo_line_to(ctx, x, y);
			#endif
		} else if (strcmp("C", cmd) == 0) { // quadratic Bezier curve
			x = evalFloat(FIELD(path, i++));
			y = evalFloat(FIELD(path, i++));
			qx = evalFloat(FIELD(path, i++));
			qy = evalFloat(FIELD(path, i++));
			// compute cubic Bezier control points
			c1x = lastX + ((2 * (qx - lastX)) / 3);
			c1y = lastY + ((2 * (qy - lastY)) / 3);
			c2x = x + ((2 * (qx - x)) / 3);
			c2y = y + ((2 * (qy - y)) / 3);
			#ifdef EMSCRIPTEN
				EM_ASM_({GP.ctx.quadraticCurveTo($0, $1, $2, $3)}, qx, qy, x, y);
			#else
				cairo_curve_to(ctx, c1x, c1y, c2x, c2y, x, y);
			#endif
		} else if (strcmp("B", cmd) == 0) { // cubic Bezier curve
			x = evalFloat(FIELD(path, i++));
			y = evalFloat(FIELD(path, i++));
			c1x = evalFloat(FIELD(path, i++));
			c1y = evalFloat(FIELD(path, i++));
			c2x = evalFloat(FIELD(path, i++));
			c2y = evalFloat(FIELD(path, i++));
			#ifdef EMSCRIPTEN
				EM_ASM_({GP.ctx.bezierCurveTo($0, $1, $2, $3, $4, $5)}, c1x, c1y, c2x, c2y, x, y);
			#else
				cairo_curve_to(ctx, c1x, c1y, c2x, c2y, x, y);
			#endif
		} else if (strcmp("M", cmd) == 0) {
			x = evalFloat(FIELD(path, i++));
			y = evalFloat(FIELD(path, i++));
			firstX = x;
			firstY = y;
			#ifdef EMSCRIPTEN
				EM_ASM_({GP.ctx.moveTo($0, $1)}, x, y);
			#else
				cairo_move_to(ctx, x, y);
			#endif
		} else if (strcmp("Z", cmd) == 0) {
			#ifdef EMSCRIPTEN
				EM_ASM({ GP.ctx.closePath() }, 0);
			#else
				cairo_close_path(ctx);
			#endif
		} else {
			printf("Unknown path command %s\n", cmd);
			return;
		}
		lastX = x;
		lastY = y;
	}
	if ((fabs(lastX - firstX) < 0.0001) &&
		(fabs(lastY - firstY) < 0.0001)) {
			#ifdef EMSCRIPTEN
				EM_ASM({ GP.ctx.closePath() }, 0);
			#else
				cairo_close_path(ctx);
			#endif
	}
}

#ifdef EMSCRIPTEN

static int canvasID(OBJ obj) {
	// If obj is a texture reference, return its id. Otherwise, return -1.

	if (objWords(obj) < 3) return -1;
	OBJ ref = FIELD(obj, 2);
	if (NOT_CLASS(ref, ExternalReferenceClass)) return -1;
	ADDR *a = (ADDR*)BODY(ref);
	return (int) a[0];
}

static void setCanvasClipRect(OBJ clipRect) {
	if (!isRectangle(clipRect)) return;

	int x = intValue(FIELD(clipRect, 0));
	int y = intValue(FIELD(clipRect, 1));
	int w = intValue(FIELD(clipRect, 2));
	int h = intValue(FIELD(clipRect, 3));
	EM_ASM_({
		GP.ctx.save();
		GP.ctx.beginPath();
		GP.ctx.rect($0, $1, $2, $3);
		GP.ctx.clip();
		GP.ctx.beginPath();
	}, x, y, w, h);
}

int setTargetCanvas(OBJ obj, OBJ clipRect) {
	int id = (nilObj == obj) ? 0 : canvasID(obj); // if obj == nil, use the screen
	if (id < 0) return false;

	EM_ASM_({
		var cnvID = $0 - 1;
		if ((0 <= cnvID) && (cnvID < GP.canvasCache.length) && GP.canvasCache[cnvID]) {
			var canvas = GP.canvasCache[cnvID];
			GP.ctx = canvas.getContext('2d');
		} else {
			GP.ctx = (document.getElementById('canvas')).getContext('2d');
		}
	}, id);
	setCanvasClipRect(clipRect);
	return true;
}

static void copyResultToBitmap(OBJ bitmap, OBJ edgeColor) {
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ bmData = FIELD(bitmap, 2);

	// the edge color is used for the RGB of any pixels with alpha between 1 and 254
	// (to avoid mixing the background color into edge pixel colors, which causes fringing)
	int edgeR = clip(obj2int(FIELD(edgeColor, 0)), 0, 255);
	int edgeG = clip(obj2int(FIELD(edgeColor, 1)), 0, 255);
	int edgeB = clip(obj2int(FIELD(edgeColor, 2)), 0, 255);

	EM_ASM_({
		var bmData = $0;
		var w = $1;
		var h = $2;
		var edgeR = $3;
		var edgeG = $4;
		var edgeB = $5;

		var cnv = GP.ctx.canvas;
		var cnvData = (GP.ctx.getImageData(0, 0, cnv.width, cnv.height)).data;
		if ((cnv.width != w) || (cnv.height != h)) {
			console.log('Bitmap and canvas dimensions do not match.'); // should never happen
			return;
		}
		for (var y = 0; y < h; y++) {
			var srcIndex = (4 * y * w);
			var dstIndex = bmData + (4 * y * w);
			for (var x = 0; x < w; x++) {
				var alpha = cnvData[srcIndex + 3];
				if (alpha == 0) {
					// Totally transparent
					dstIndex += 4;
				} else if (alpha == 255) {
					// Totally opaque
					Module.HEAPU8[dstIndex++] = cnvData[srcIndex + 2];
					Module.HEAPU8[dstIndex++] = cnvData[srcIndex + 1];
					Module.HEAPU8[dstIndex++] = cnvData[srcIndex];
					Module.HEAPU8[dstIndex++] = 255;
				} else {
					// Semi-transparent (e.g. an edge pixel)
					// Note: Typically many fewer of this case than opaque or transparent cases
					var dstAlpha = Module.HEAPU8[dstIndex + 3];
					if (dstAlpha == 0) {
						// Drawing onto a totally transparent pixel
						Module.HEAPU8[dstIndex++] = edgeB;
						Module.HEAPU8[dstIndex++] = edgeG;
						Module.HEAPU8[dstIndex++] = edgeR;
						Module.HEAPU8[dstIndex++] = alpha;
					} else {
						// Mixing with the destination
						// Mixing with destination color does not currently take the destination
						// alpha into account, but the result looks good. (This only arises when
						// the destination is partly transparent.
						// The new alpha is product of transparencies. For example, drawing 25%
						// tranparent over 50% transparent results in 12.5% transparent
						// (0.25 * 0.5 = 0.125). Note that transparency is the inverse of
						// alpha, 1.0-alpha (i.e. 255-alpha).

						var invAlpha = 255 - alpha;
						var newAlpha = 255 - ((((255 - alpha) * (255 - dstAlpha)) / 255) | 0);
						var v = (((alpha * cnvData[srcIndex + 2]) + (invAlpha * Module.HEAPU8[dstIndex])) / 255) | 0;
						Module.HEAPU8[dstIndex++] = v;
						v = (((alpha * cnvData[srcIndex + 1]) + (invAlpha * Module.HEAPU8[dstIndex])) / 255) | 0;
						Module.HEAPU8[dstIndex++] = v;
						v = (((alpha * cnvData[srcIndex]) + (invAlpha * Module.HEAPU8[dstIndex])) / 255) | 0;
						Module.HEAPU8[dstIndex++] = v;
						Module.HEAPU8[dstIndex++] = newAlpha;
					}
				}
				srcIndex += 4;
			}
		}
	}, &FIELD(bmData, 0), w, h, edgeR, edgeG, edgeB);
}

static int createCanvas(OBJ bitmap, OBJ clipRect) {
	// Create a canvas and context on it and store the context in GP.ctx.

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ bmData = FIELD(bitmap, 2);
	if ((w < 1) || (h < 1) || (objWords(bmData) != (w * h))) return false;

	EM_ASM_({
			var canvas = document.createElement('canvas');
			canvas.width = $0;
			canvas.height = $1;
			GP.ctx = canvas.getContext('2d');
	}, w, h);
	setCanvasClipRect(clipRect);

	return true;
}

static void toColorString(OBJ colorObj, char *result, int resultSize) {
	// Write a Javascript color string for the given color into the result.

	int words = objWords(colorObj);
	result[0] = 0;
	if (words < 3) {
		snprintf(result, resultSize, "rgba(0, 0, 0, 255)"); // black
		return;
	}
	int r = clip(obj2int(FIELD(colorObj, 0)), 0, 255);
	int g = clip(obj2int(FIELD(colorObj, 1)), 0, 255);
	int b = clip(obj2int(FIELD(colorObj, 2)), 0, 255);
	int a = (words <= 3) ? 255 : clip(obj2int(FIELD(colorObj, 3)), 0, 255);
	snprintf(result, resultSize, "rgba(%d, %d, %d, %f)", r, g, b, a / 255.0);
}

static void fillPath(OBJ bitmapOrTexture, OBJ path, OBJ fillColor, OBJ clipRect) {
	char fillColorString[1000];
	toColorString(fillColor, fillColorString, sizeof(fillColorString));

	int isBM = false;
	if (isBitmap(bitmapOrTexture)) {
		isBM = true;
		int ok = createCanvas(bitmapOrTexture, clipRect);
		if (!ok) return;
	} else {
		int ok = setTargetCanvas(bitmapOrTexture, clipRect);
		if (!ok) return;
	}

	interpretPath(NULL, path);
	EM_ASM_({
		if (GP.shadowColor) setContextShadow(GP.ctx);
		GP.ctx.fillStyle = UTF8ToString($0);
		GP.ctx.fill();
	}, fillColorString);
	if (isBM) copyResultToBitmap(bitmapOrTexture, fillColor);
	EM_ASM({
		GP.ctx.restore();
		GP.ctx.shadowColor = 'transparent';
		GP.ctx = (document.getElementById('canvas')).getContext('2d');
	}, 0);
}

static void strokePath(OBJ bitmapOrTexture, OBJ path, OBJ strokeColor, double lineWidth, int jointStyle, int capStyle, OBJ clipRect) {
	char strokeColorString[1000];
	toColorString(strokeColor, strokeColorString, sizeof(strokeColorString));

	char *lineJoin = "round";
	if (0 == jointStyle) lineJoin = "miter";
	if (1 == jointStyle) lineJoin = "round";
	if (2 == jointStyle) lineJoin = "bevel";

	char *lineCap = "round";
	if (0 == capStyle) lineCap = "butt";
	if (1 == capStyle) lineCap = "round";
	if (2 == capStyle) lineCap = "square";

	int isBM = false;
	if (isBitmap(bitmapOrTexture)) {
		isBM = true;
		int ok = createCanvas(bitmapOrTexture, clipRect);
		if (!ok) return;
	} else {
		int ok = setTargetCanvas(bitmapOrTexture, clipRect);
		if (!ok) return;
	}

	interpretPath(NULL, path);
	EM_ASM_({
		if (GP.shadowColor) setContextShadow(GP.ctx);
		GP.ctx.strokeStyle = UTF8ToString($0);
		GP.ctx.lineWidth = $1;
		GP.ctx.lineJoin = UTF8ToString($2);
		GP.ctx.lineCap = UTF8ToString($3);
		GP.ctx.stroke();
	}, strokeColorString, lineWidth, lineJoin, lineCap);
	if (isBM) copyResultToBitmap(bitmapOrTexture, strokeColor);
	EM_ASM({
		GP.ctx.restore();
		GP.ctx.shadowColor = 'transparent';
		GP.ctx = (document.getElementById('canvas')).getContext('2d');
	}, 0);
}

#else

#include <cairo/cairo.h>

#include <SDL.h>
extern SDL_Surface *screenBitmap;

static inline cairo_surface_t * bitmap2surface(OBJ bitmap) {
	if (nilObj == bitmap) {
		SDL_Surface *screen = screenBitmap;
		if (!screen) return NULL;
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

static inline void setColor(cairo_t *ctx, OBJ colorObj) {
	int words = objWords(colorObj);
	if (words < 3) return;
	int r = clip(obj2int(FIELD(colorObj, 0)), 0, 255);
	int g = clip(obj2int(FIELD(colorObj, 1)), 0, 255);
	int b = clip(obj2int(FIELD(colorObj, 2)), 0, 255);
	if (words > 3) {
		int a = clip(obj2int(FIELD(colorObj, 3)), 0, 255);
		cairo_set_source_rgba(ctx, r / 255.0, g / 255.0, b / 255.0, a / 255.0);
	} else {
		cairo_set_source_rgb(ctx, r / 255.0, g / 255.0, b / 255.0);
	}
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

static void fillPath(OBJ bitmap, OBJ path, OBJ fillColor, OBJ clipRect) {
	cairo_surface_t *surface = bitmap2surface(bitmap);
	if (!surface) return;
	cairo_t *ctx = cairo_create(surface);
	setCairoClipRect(ctx, clipRect);

	interpretPath(ctx, path);
	setColor(ctx, fillColor);
	cairo_fill(ctx);

	cairo_destroy(ctx);
	cairo_surface_destroy(surface);
}

static void strokePath(OBJ bitmap, OBJ path, OBJ strokeColor, double lineWidth, int jointStyle, int capStyle, OBJ clipRect) {
	cairo_surface_t *surface = bitmap2surface(bitmap);
	if (!surface) return;
	cairo_t *ctx = cairo_create(surface);
	setCairoClipRect(ctx, clipRect);

	interpretPath(ctx, path);
	setColor(ctx, strokeColor);
	cairo_set_line_width(ctx, lineWidth);
	cairo_set_line_join(ctx, jointStyle);
	cairo_set_line_cap(ctx, capStyle);
	cairo_stroke(ctx);

	cairo_destroy(ctx);
	cairo_surface_destroy(surface);
}

#endif

// Vector Primitives

OBJ primVectorFill(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ bitmapOrTexture = args[0];
	OBJ path = args[1];
	OBJ color = args[2];
	OBJ clipRect = (nargs > 3) ? args[3] : nilObj;

	if (NOT_CLASS(path, ArrayClass)) return primFailed("Bad path");

	fillPath(bitmapOrTexture, path, color, clipRect);
	return nilObj;
}

OBJ primVectorStroke(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ bitmapOrTexture = args[0];
	OBJ path = args[1];
	OBJ color = args[2];
	double lineWidth = 1.0;
	if (nargs > 3) lineWidth = evalFloat(args[3]);
	int jointStyle = intArg(4, 0, nargs, args);
	int capStyle = intArg(5, 0, nargs, args);
	OBJ clipRect = (nargs > 6) ? args[6] : nilObj;

	if (NOT_CLASS(path, ArrayClass)) return primFailed("Bad path");

	strokePath(bitmapOrTexture, path, color, lineWidth, jointStyle, capStyle, clipRect);
	return nilObj;
}

PrimEntry vectorPrimList[] = {
	{"-----", NULL, "Vector Graphics"},
	{"vectorFillPath",		primVectorFill,		"Fill a path on the given Bitmap. Arguments: bitmap, path, color [clipRect]"},
	{"vectorStrokePath",	primVectorStroke,	"Stroke a path on the given Bitmap. Arguments: bitmap, path, color [width, jointStyle, capStyle, clipRect]"},
};

PrimEntry* vectorPrimitives(int *primCount) {
	*primCount = sizeof(vectorPrimList) / sizeof(PrimEntry);
	return vectorPrimList;
}
