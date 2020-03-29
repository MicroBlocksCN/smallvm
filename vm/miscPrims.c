/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// miscPrims.c - Miscellaneous primitives
// John Maloney, May 2019

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "tinyJSON.h"

OBJ primHexToInt(int argCount, OBJ *args) {
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);

	char *s = obj2str(args[0]);
	if ('#' == *s) s++; // skip leading # if there is one
	long result = strtol(s, NULL, 16);
	if ((result < -536870912) || (result > 536870911)) return fail(hexRangeError);
	return int2obj(result);
}

static OBJ primSine(int argCount, OBJ *args) {
	// Returns the sine of the given angle * 2^14 (i.e. a fixed point integer with 13 bits of
	// fraction). The input is the angle in hundreths of a degree (e.g. 4500 means 45 degrees).

	const float hundrethsToRadians = 6.2831853071795864769 / 36000.0;
	return int2obj((int) round(16384.0 * sin(evalInt(args[0]) * hundrethsToRadians)));
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

// Primitives

static PrimEntry entries[] = {
	{"hexToInt", primHexToInt},
	{"sin", primSine},
	{"jsonGet", primJSONGet},
	{"jsonCount", primJSONCount},
	{"jsonValueAt", primJSONValueAt},
	{"jsonKeyAt", primJSONKeyAt},
};

void addMiscPrims() {
	addPrimitiveSet("misc", sizeof(entries) / sizeof(PrimEntry), entries);
}
