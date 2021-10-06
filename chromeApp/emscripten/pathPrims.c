#include <math.h>
#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#ifdef EMSCRIPTEN
	#include <emscripten.h>
	#include <emscripten/html5.h>

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
#else
	#include <cairo/cairo.h>
	#include <SDL.h>

	extern SDL_Surface *screenBitmap;
	cairo_t *cairoCtx = NULL;
	cairo_surface_t *cairoSurface = NULL;

	static inline void setCairoColor(cairo_t *ctx, OBJ colorObj) {
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
#endif

// Path State

double offsetX, offsetY;
double penX, penY;
double heading;
OBJ clipRect = nilObj;

// Helper Functions

#define COSINE(degrees) (cos((degrees * M_PI) / 180.0))
#define SINE(degrees) (sin((degrees * M_PI) / 180.0))

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

static void initGraphics() {
	// initialize clippint parameters
	int clipX = 0;
	int clipY = 0;
	int clipW = 0;
	int clipH = 0;
	if (isRectangle(clipRect)) {
		clipX = intValue(FIELD(clipRect, 0));
		clipY = intValue(FIELD(clipRect, 1));
		clipW = intValue(FIELD(clipRect, 2));
		clipH = intValue(FIELD(clipRect, 3));
	}

	#ifdef EMSCRIPTEN
		EM_ASM({
			GP.ctx = (document.getElementById('canvas')).getContext('2d');
		}, 0);

		// set clip rectangle
		if (isRectangle(clipRect)) {
			EM_ASM_({
				GP.ctx.save();
				GP.ctx.beginPath();
				GP.ctx.rect($0, $1, $2, $3);
				GP.ctx.clip();
				GP.ctx.beginPath();
			}, clipX, clipY, clipW, clipH);
		}
	#else
		// destroy old context and surface, if any (screen may have changed)
		if (cairoCtx) cairo_destroy(cairoCtx);
		if (cairoSurface) cairo_surface_destroy(cairoSurface);

		// create context and surface on display screen
		SDL_Surface *screen = screenBitmap;
		if (!screen) return;
		cairoSurface = cairo_image_surface_create_for_data(
			screen->pixels, CAIRO_FORMAT_ARGB32, screen->w, screen->h, (4 * screen->w));
		cairoCtx = cairo_create(cairoSurface);

		// set clip rectangle
		if (isRectangle(clipRect)) {
			cairo_rectangle(cairoCtx, clipX, clipY, clipW, clipH);
			cairo_clip(cairoCtx);
			cairo_new_path(cairoCtx); // clear clip path
		}
	#endif
}

static void beginPath() {
	#ifdef EMSCRIPTEN
		EM_ASM({GP.ctx.beginPath()}, 0);
	#else
		cairo_new_path(cairoCtx);
	#endif
}

static void moveTo(double x, double y) {
	#ifdef EMSCRIPTEN
		EM_ASM_({GP.ctx.moveTo($0, $1)}, x, y);
	#else
		cairo_move_to(cairoCtx, x, y);
	#endif
}

static void lineTo(double x, double y) {
	#ifdef EMSCRIPTEN
		EM_ASM_({GP.ctx.lineTo($0, $1)}, x, y);
	#else
		cairo_line_to(cairoCtx, x, y);
	#endif
}

static void curveTo(double lastX, double lastY, double x, double y, double cx, double cy) {
	#ifdef EMSCRIPTEN
		EM_ASM_({GP.ctx.quadraticCurveTo($0, $1, $2, $3)}, cx, cy, x, y);
	#else
		// compute cubic Bezier control points for cairo
		double c1x = lastX + ((2 * (cx - lastX)) / 3);
		double c1y = lastY + ((2 * (cy - lastY)) / 3);
		double c2x = x + ((2 * (cx - x)) / 3);
		double c2y = y + ((2 * (cy - y)) / 3);
		cairo_curve_to(cairoCtx, c1x, c1y, c2x, c2y, x, y);
	#endif
}

static void stroke(OBJ borderColor, double borderWidth) {
	#ifdef EMSCRIPTEN
		char colorString[100];
		toColorString(borderColor, colorString, sizeof(colorString));
		EM_ASM_({
			if (GP.shadowColor) setContextShadow(GP.ctx);
			GP.ctx.strokeStyle = UTF8ToString($0);
			GP.ctx.lineWidth = $1;
			GP.ctx.lineCap = 'round';
			GP.ctx.lineJoin = 'round';
			GP.ctx.stroke();

			// restore GP context
			GP.ctx.restore();
			GP.ctx.shadowColor = 'transparent';
			GP.ctx = (document.getElementById('canvas')).getContext('2d');
		}, colorString, borderWidth);
	#else
		setCairoColor(cairoCtx, borderColor);
		cairo_set_line_width(cairoCtx, borderWidth);
		cairo_set_line_join(cairoCtx, CAIRO_LINE_JOIN_ROUND);
		cairo_set_line_cap(cairoCtx, CAIRO_LINE_CAP_ROUND);
		cairo_stroke(cairoCtx);
	#endif
}

static void fill(OBJ fillColor, int doneFlag) {
	#ifdef EMSCRIPTEN
		char colorString[100];
		toColorString(fillColor, colorString, sizeof(colorString));
		EM_ASM_({
			if (GP.shadowColor) setContextShadow(GP.ctx);
			GP.ctx.fillStyle = UTF8ToString($0);
			GP.ctx.fill();

			if ($1) {
				// restore GP context if done (i.e. not going to also stroke the path)
				GP.ctx.restore();
				GP.ctx.shadowColor = 'transparent';
				GP.ctx = (document.getElementById('canvas')).getContext('2d');
			}
		}, colorString, doneFlag);
	#else
		setCairoColor(cairoCtx, fillColor);
		if (doneFlag) {
			cairo_fill(cairoCtx);
		} else {
			cairo_fill_preserve(cairoCtx);
		}
	#endif
}

// Path Primitives

OBJ primPathX(int nargs, OBJ args[]) {
	return newFloat(penX - offsetX);
}
OBJ primPathY(int nargs, OBJ args[]) {
	return newFloat(penY - offsetY);
}
OBJ primPathSetClipRect(int nargs, OBJ args[]) {
	if (nargs > 0) clipRect = args[0];
	return nilObj;
}
OBJ primPathSetHeading(int nargs, OBJ args[]) {
	if (nargs > 0) heading = evalFloat(args[0]);
	return nilObj;
}

OBJ primPathSetOffset(int nargs, OBJ args[]) {
	double x = (nargs > 0) ? evalFloat(args[0]) : 0;
	double y = (nargs > 1) ? evalFloat(args[1]) : 0;

	offsetX = x;
	offsetY = y;
	return nilObj;
}

OBJ primPathBeginPath(int nargs, OBJ args[]) {
	double x = (nargs > 0) ? evalFloat(args[0]) : 100;
	double y = (nargs > 1) ? evalFloat(args[1]) : 100;

	penX = x + offsetX;
	penY = y + offsetY;
	heading = 0.0;
	initGraphics();
	beginPath();
	moveTo(penX, penY);
	return nilObj;
}

OBJ primPathBeginPathFromHere(int nargs, OBJ args[]) {
	initGraphics();
	beginPath();
	moveTo(penX, penY);
	return nilObj;
}

OBJ primPathLineTo(int nargs, OBJ args[]) {
	double dstX = (nargs > 0) ? evalFloat(args[0]) : 0;
	double dstY = (nargs > 1) ? evalFloat(args[1]) : 0;

	penX = dstX + offsetX;
	penY = dstY + offsetY;
	lineTo(penX, penY);
	return nilObj;
}

OBJ primPathForward(int nargs, OBJ args[]) {
	double dist = (nargs > 0) ? evalFloat(args[0]) : 0;
	double curvature = (nargs > 1) ? evalFloat(args[1]) : 0;

	if (dist == 0) return nilObj;

	double startX = penX;
	double startY = penY;
	penX += dist * COSINE(heading);
	penY += dist * SINE(heading);

	// make almost vertical or horizontal exact (compenstates for tiny floating point errors)
	if (fabs((penX - startX)) < 0.000001) penX = startX;
	if (fabs((penY - startY)) < 0.000001) penY = startY;

	if (curvature == 0) {
		lineTo(penX, penY);
	} else {
		// control point is on a line perpendicular to the segment
		// at it's midpoint, scaled by (curvature / 100)
		double midpointX = (startX + penX) / 2;
		double midpointY = (startY + penY) / 2;
		double cx = midpointX + ((curvature / 100) * (penY - startY));
		double cy = midpointY + ((curvature / 100) * (startX - penX));
		curveTo(startX, startY, penX, penY, cx, cy);
	}
	return nilObj;
}

OBJ primPathTurn(int nargs, OBJ args[]) {
	// If radius is nil or zero, turn in place. If radius > 0, move the given number of
	// degrees along an approximately circular arc. To ensure minimal error, the arc is
	// approximated by a sequence of short, quadratic Bezier arc segments.

	double degrees = (nargs > 0) ? evalFloat(args[0]) : 0;
	double radius = (nargs > 1) ? evalFloat(args[1]) : 0;

	if (degrees == 0) return nilObj; // no turn

	if (radius == 0) { // turn in place
		heading = fmod((heading + degrees), 360);
		return nilObj;
	}

	// computer center and starting angle
	double centerX, centerY, angle;
	if (degrees > 0) { // right turn (clockwise)
		centerX = penX - (radius * SINE(heading));
		centerY = penY + (radius * COSINE(heading));
		angle = heading - 90; // bearing from center point to pen
	} else { // left turn (counter-clockwise)
		centerX = penX + (radius * SINE(heading));
		centerY = penY - (radius * COSINE(heading));
		angle = heading + 90; // bearing from center point to pen
	}

	// draw a circular arc of degrees with the given radius, possibly over multiple steps
	// (uses quadradic Bezier curves to approximate arcs of up to maxDegreesPerStep)
	const double maxDegreesPerStep = 45.0;
	double steps = trunc(fabs(degrees) / maxDegreesPerStep) + 1;
	double degreesPerStep = degrees / steps;
	for (int i = 0; i < steps; i++) {
		double midAngle = angle + (degreesPerStep / 2);
		double endAngle = angle + degreesPerStep;
		double cx = (((-0.5 * (COSINE(angle) + COSINE(endAngle))) + (2 * COSINE(midAngle))) * radius) + centerX;
		double cy = (((-0.5 * (SINE(angle) + SINE(endAngle))) + (2 * SINE(midAngle))) * radius) + centerY;

		double startX = penX;
		double startY = penY;
		penX = centerX + (radius * COSINE(endAngle));
		penY = centerY + (radius * SINE(endAngle));
		angle = endAngle;
		curveTo(startX, startY, penX, penY, cx, cy);
	}

	heading = fmod((heading + degrees), 360);
	return nilObj;
}

OBJ primPathStroke(int nargs, OBJ args[]) {
	OBJ borderColor = (nargs > 0) ? args[0] : nilObj;
	double borderWidth = (nargs > 1) ? evalFloat(args[1]) : 1;
	stroke(borderColor, borderWidth);
	return nilObj;
}

OBJ primPathFill(int nargs, OBJ args[]) {
	OBJ fillColor = (nargs > 0) ? args[0] : nilObj;
	fill(fillColor, true);
	return nilObj;
}

OBJ primPathFillAndStroke(int nargs, OBJ args[]) {
	OBJ fillColor = (nargs > 0) ? args[0] : nilObj;
	OBJ borderColor = (nargs > 1) ? args[1] : nilObj;
	double borderWidth = (nargs > 2) ? evalFloat(args[2]) : 1;

	if (nilObj != fillColor) {
		fill(fillColor, false);
	}
	stroke(borderColor, borderWidth);
	return nilObj;
}

PrimEntry pathPrimList[] = {
	{"-----", NULL, "Vector Graphics - Paths"},
	{"pathX",			primPathX,				"Return the X position of the current path."},
	{"pathY",			primPathY,				"Return the Y position of the current path."},
	{"pathSetClipRect",	primPathSetClipRect,	"Set the path clipping rectangle. Argument: Rectangle"},
	{"pathSetHeading",	primPathSetHeading,		"Set the path heading. Arguments: angleInDegrees"},
	{"pathSetOffset",	primPathSetOffset,		"Set the path offset x and y. Arguments: x, y"},
	{"pathBeginPath",	primPathBeginPath,		"Start a new path from the given x and y. Arguments: x y"},
	{"pathBeginPathFromHere", primPathBeginPathFromHere, "Start a new path from the current position."},
	{"pathLineTo",		primPathLineTo,			"Add a straight line to the given x and y to the path. Arguments: x, y"},
	{"pathForward",		primPathForward,		"Add a segment of the given length and optional curvature to the the path. Arguments: length [curvature]"},
	{"pathTurn",		primPathTurn,			"Add a turn to the path. Arguments: degreesToTurn [radius]"},
	{"pathStroke",		primPathStroke,			"Stroke the path. Arguments: [borderColor borderWidth]"},
	{"pathFill",		primPathFill,			"Fill the path. Arguments: [fillColor]"},
	{"pathFillAndStroke", primPathFillAndStroke, "Fill and stroke the path. Arguments: fillColor [borderColor borderWidth]"},
};

PrimEntry* pathPrimitives(int *primCount) {
	*primCount = sizeof(pathPrimList) / sizeof(PrimEntry);
	return pathPrimList;
}
