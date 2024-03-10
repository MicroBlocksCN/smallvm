/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// miscPrims.c - Miscellaneous primitives
// John Maloney, May 2019

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "tinyJSON.h"
#include "version.h"

OBJ primVersion(int argCount, OBJ *args) {
	int result = atoi(&VM_VERSION[1]); // skip initial "v"
	return int2obj(result);
}

OBJ primBLE_ID(int argCount, OBJ *args) {
	OBJ result;
	if (strlen(BLE_ThreeLetterID) == 3) {
		result = newStringFromBytes(BLE_ThreeLetterID, 3);
	} else {
		result = newString(0);
	}
	if (!result) return fail(insufficientMemoryError);
	return result;
}

OBJ primHexToInt(int argCount, OBJ *args) {
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);

	char *s = obj2str(args[0]);
	if ('#' == *s) s++; // skip leading # if there is one
	long result = strtol(s, NULL, 16);
	if ((result < -536870912) || (result > 536870911)) return fail(hexRangeError);
	return int2obj(result);
}

OBJ primRescale(int argCount, OBJ *args) {
	if (argCount < 5) return fail(notEnoughArguments);
	int inVal = evalInt(args[0]);
	int inMin = evalInt(args[1]);
	int inMax = evalInt(args[2]);
	int outMin = evalInt(args[3]);
	int outMax = evalInt(args[4]);

	if (inMax == inMin) return fail(zeroDivide);

	int result = outMin + (((inVal - inMin) * (outMax - outMin)) / (inMax - inMin));
	return int2obj(result);
}

// HSV Colors

static float clampedPercent(int percent) {
	// Return a float between 0.0 and 1.0 for the given percent.

	if (percent < 0) percent = 0;
	if (percent > 100) percent = 100;
	return (float) percent / 100.0;
}

static void extractHSV(int rgb, float *hue, float *sat, float *bri) {
	int r = (rgb >> 16) & 255;
	int g = (rgb >> 8) & 255;
	int b = rgb & 255;

	int min = (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b);
	int max = (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b);

	if (max == min) {
		// gray; hue is arbitrarily chosen to be zero
		*hue = 0.0;
		*sat = 0.0;
		*bri = max / 255.0;
	}

	int f = 0;
	int i = 0;
	if (r == min) {
		f = g - b;
		i = 3;
	} else if(g == min) {
		f = b - r;
		i = 5;
	} else if (b == min) {
		f = r - g;
		i = 1;
	}

	*hue = fmod(60.0 * (i - (((float) f) / (max - min))), 360.0);
	*sat = 0.0;
	if (max > 0) *sat = ((float) (max - min)) / max;
  	*bri = max / 255.0;
}

OBJ primHSVColor(int argCount, OBJ *args) {
	if (argCount < 3) return fail(notEnoughArguments);

	int h = evalInt(args[0]) % 360;
	if (h < 0) h += 360;
	float s = clampedPercent(evalInt(args[1]));
	float v = clampedPercent(evalInt(args[2]));

	int i = h / 60;
	float f = (h / 60.0) - i;
	float p = v * (1.0 - s);
	float q = v * (1.0 - (s * f));
	float t = v * (1.0 - (s * (1.0 - f)));
	float r, g, b;

	switch (i) {
	case 0:
		r = v; g = t; b = p;
		break;
	case 1:
		r = q; g = v; b = p;
		break;
	case 2:
		r = p; g = v; b = t;
		break;
	case 3:
		r = p; g = q; b = v;
		break;
	case 4:
		r = t; g = p; b = v;
		break;
	case 5:
		r = v; g = p; b = q;
		break;
	}

	int rgb = (((int) (255 * r)) << 16) | (((int) (255 * g)) << 8) | ((int) (255 * b));
	return int2obj(rgb);
}

OBJ primColorHue(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	float h, s, v;
	extractHSV(evalInt(args[0]), &h, &s, &v);
	return int2obj((int) h);
}

OBJ primColorSaturation(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	float h, s, v;
	extractHSV(evalInt(args[0]), &h, &s, &v);
	return int2obj((int) (100.0 * s));
}

OBJ primColorBrightness(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	float h, s, v;
	extractHSV(evalInt(args[0]), &h, &s, &v);
	return int2obj((int) (100.0 * v));
}

static OBJ primSine(int argCount, OBJ *args) {
	// Returns the sine of the given angle * 2^14 (i.e. a fixed point integer with 13 bits of
	// fraction). The input is the angle in hundreths of a degree (e.g. 4500 means 45 degrees).

	const float hundrethsToRadians = 6.2831853071795864769 / 36000.0;
	return int2obj((int) round(16384.0 * sin(evalInt(args[0]) * hundrethsToRadians)));
}

static OBJ primSqrt(int argCount, OBJ *args) {
	// Returns the integer part of a square root of a given number multiplied by
	// 1000 (e.g. sqrt(2) = 1414).

	return int2obj((int) round(1000 * sqrt(evalInt(args[0]))));
}

static OBJ primArctan(int argCount, OBJ *args) {
	// Returns angle (in hundredths of a degree) of vector dx, dy.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerError);

	double x = obj2int(args[0]);
	double y = obj2int(args[1]);
	double degreeHundredths = (18000.0 * atan2(y, x)) / 3.141592653589793238463;

	return int2obj((int) round(degreeHundredths));
}

static OBJ primPressureToAltitude(int argCount, OBJ *args) {
	// Computes the altitude difference (in millimeters) for a given pressure difference.
	// dH = 44330 * [ 1 - ( p / p0 ) ^ ( 1 / 5.255) ]

	if (argCount < 2) return fail(notEnoughArguments);
	int p0 = obj2int(args[0]);
	int p = obj2int(args[1]);
	double result = 44330.0 * (1.0 - pow((double) p / p0, (1.0 / 5.255))); // meters
	return int2obj((int) (1000.0 * result)); // return result in millimeters
}

static OBJ jsonValue(char *item) {
	char buf[1024];
	char *end;
	if (!item) return newString(0); // path not found

	switch (tjr_type(item)) {
	case tjr_Array:
	case tjr_Object:
		end = tjr_endOfItem(item);
		return newStringFromBytes(item, (end - item));
	case tjr_Number:
		return int2obj(tjr_readInteger(item));
	case tjr_String:
		tjr_readStringInto(item, buf, sizeof(buf));
		return newStringFromBytes(buf, strlen(buf));
	case tjr_True:
		return trueObj;
	case tjr_False:
		return falseObj;
	case tjr_Null:
		return newStringFromBytes("null", 4);
	}
	return newString(0); // json parse error or end
}

static OBJ primConnectedToIDE(int argCount, OBJ *args) {
	return ideConnected() ? trueObj : falseObj;
}

static OBJ primJSONGet(int argCount, OBJ *args) {
	// Return the value at the given path in a JSON string or the empty string
	// if the path doesn't refer to anything. The optional third argument returns
	// the value of the Nth element of an array or object.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *json = obj2str(args[0]);
	char *path = obj2str(args[1]);
	int i = ((argCount > 2) && isInt(args[2])) ? obj2int(args[2]) : -1;

	char *item = tjr_atPath(json, path);
	int itemType = tjr_type(item);
	if ((tjr_Array == itemType) && (i > 0)) {
		item++; // skip '['
		for (; i > 1; i--) item = tjr_nextElement(item);
	}
	if ((tjr_Object == itemType) && (i > 0)) {
		item++; // skip '{'
		for (; i > 1; i--) {
			item = tjr_nextProperty(item, NULL, 0);
			item = tjr_nextElement(item); // skip value
		}
	}
	return jsonValue(item);
}

static OBJ primJSONCount(int argCount, OBJ *args) {
	// Return the number of entries in the array or entry at the given path of a JSON string.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *json = obj2str(args[0]);
	char *path = obj2str(args[1]);

	char *item = tjr_atPath(json, path);
	return int2obj(tjr_count(item));
}

static OBJ primJSONValueAt(int argCount, OBJ *args) {
	// Return the value for the Nth object or array entry at the given path of a JSON string.

	if (argCount < 3) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	if (!isInt(args[2])) return fail(needsIntegerError);
	char *json = obj2str(args[0]);
	char *path = obj2str(args[1]);
	int i = obj2int(args[2]);

	char *item = tjr_atPath(json, path);
	return jsonValue(tjr_valueAt(item, i));
}

static OBJ primJSONKeyAt(int argCount, OBJ *args) {
	// Return the key for the Nth object entry at the given path of a JSON string.

	if (argCount < 3) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	if (!isInt(args[2])) return fail(needsIntegerError);
	char *json = obj2str(args[0]);
	char *path = obj2str(args[1]);
	int i = obj2int(args[2]);

	char key[100];
	key[0] = '\0';
	char *item = tjr_atPath(json, path);
	tjr_keyAt(item, i, key, sizeof(key));
	return newStringFromBytes(key, strlen(key));
}

static OBJ primBMP680GasResistance(int argCount, OBJ *args) {
	if (argCount < 3) return fail(notEnoughArguments);
	int gas_res_adc = evalInt(args[0]);
	int gas_range = evalInt(args[1]);
	int range_sw_err = evalInt(args[2]);

	// ensure that gas_range is [0..15]
	if (gas_range < 0) gas_range = 0;
	if (gas_range > 15) gas_range = 15;

	/* Look up table 1 for the possible gas range values */
	uint32_t lookupTable1[16] = {
		UINT32_C(2147483647), UINT32_C(2147483647), UINT32_C(2147483647), UINT32_C(2147483647),
		UINT32_C(2147483647), UINT32_C(2126008810), UINT32_C(2147483647), UINT32_C(2130303777),
		UINT32_C(2147483647), UINT32_C(2147483647), UINT32_C(2143188679), UINT32_C(2136746228),
		UINT32_C(2147483647), UINT32_C(2126008810), UINT32_C(2147483647), UINT32_C(2147483647) };

	/* Look up table 2 for the possible gas range values */
	uint32_t lookupTable2[16] = {
		UINT32_C(4096000000), UINT32_C(2048000000), UINT32_C(1024000000), UINT32_C(512000000),
		UINT32_C(255744255), UINT32_C(127110228), UINT32_C(64000000), UINT32_C(32258064), UINT32_C(16016016),
		UINT32_C(8000000), UINT32_C(4000000), UINT32_C(2000000), UINT32_C(1000000), UINT32_C(500000),
		UINT32_C(250000), UINT32_C(125000) };

	int64_t var1 = (int64_t) ((1340 + (5 * (int64_t) range_sw_err)) *
		((int64_t) lookupTable1[gas_range])) >> 16;
	uint64_t var2 = (((int64_t) ((int64_t) gas_res_adc << 15) - (int64_t) (16777216)) + var1);
	int64_t var3 = (((int64_t) lookupTable2[gas_range] * (int64_t) var1) >> 9);
	uint32_t calc_gas_res = (uint32_t) ((var3 + ((int64_t) var2 >> 1)) / (int64_t) var2);

	return int2obj(calc_gas_res);
}

// Primitives

static PrimEntry entries[] = {
	{"version", primVersion},
	{"bleID", primBLE_ID},
	{"hexToInt", primHexToInt},
	{"rescale", primRescale},
	{"hsvColor", primHSVColor},
	{"hue", primColorHue},
	{"saturation", primColorSaturation},
	{"brightness", primColorBrightness},
	{"sin", primSine},
	{"sqrt", primSqrt},
	{"atan2", primArctan},
	{"pressureToAltitude", primPressureToAltitude},
	{"bme680GasResistance", primBMP680GasResistance},
	{"connectedToIDE", primConnectedToIDE},
	{"broadcastToIDE", primBroadcastToIDEOnly},
	{"jsonGet", primJSONGet},
	{"jsonCount", primJSONCount},
	{"jsonValueAt", primJSONValueAt},
	{"jsonKeyAt", primJSONKeyAt},
};

void addMiscPrims() {
	addPrimitiveSet("misc", sizeof(entries) / sizeof(PrimEntry), entries);
}
