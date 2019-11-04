/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// arrayPrims.cpp - Microblocks arrau primitives
// John Maloney, September 2017

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Helper Functions

static int stringSize(OBJ obj) {
	int wordCount = objWords(obj);
	if (!wordCount) return 0; // empty string
	char *s = (char *) &FIELD(obj, 0);
	int byteCount = 4 * (wordCount - 1);
	for (int i = 0; i < 4; i++) {
		// scan the last word for the null terminator byte
		if (s[byteCount] == 0) break; // found terminator
		byteCount++;
	}
	return byteCount;
}

OBJ primNewArray(int argCount, OBJ *args) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return fail(arraySizeError);
	OBJ result = newObj(ArrayType, obj2int(n), int2obj(0)); // filled with zero integers
	return result;
}

OBJ primNewByteArray(int argCount, OBJ *args) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return fail(arraySizeError);
	OBJ result = newObj(ByteArrayType, (obj2int(n) + 3) / 4, 0); // filled with zero bytes
	return result;
}

OBJ primArrayFill(int argCount, OBJ *args) {
	OBJ array = args[0];
	OBJ value = args[1];

	if (IS_TYPE(array, ArrayType)) {
		int end = objWords(array) + HEADER_WORDS;
		for (int i = HEADER_WORDS; i < end; i++) ((OBJ *) array)[i] = value;
	} else if (IS_TYPE(array, ByteArrayType)) {
		if (!isInt(value)) return fail(byteArrayStoreError);
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return fail(byteArrayStoreError);
		uint8 *dst = (uint8 *) &FIELD(array, 0);
		uint8 *end = dst + (4 * objWords(array));
		while (dst < end) *dst++ = byteValue;
	} else {
		fail(needsArrayError);
	}
	return falseObj;
}

OBJ primArrayAt(int argCount, OBJ *args) {
	if (!isInt(args[0])) return fail(needsIntegerIndexError);
	int i = obj2int(args[0]);
	OBJ array = args[1];

	if (IS_TYPE(array, ArrayType)) {
		if ((i < 1) || (i > objWords(array))) return fail(indexOutOfRangeError);
		return FIELD(array, (i - 1));
	} else if (IS_TYPE(array, ByteArrayType) || IS_TYPE(array, StringType)) {
		int byteCount = 4 * objWords(array);
		if IS_TYPE(array, StringType) byteCount = stringSize(array);
		if ((i < 1) || (i > byteCount)) return fail(indexOutOfRangeError);
		uint8 *bytes = (uint8 *) &FIELD(array, 0);
		return int2obj(bytes[i - 1]);
	}
	return fail(needsArrayError);
}

OBJ primArrayAtPut(int argCount, OBJ *args) {
	if (!isInt(args[0])) return fail(needsIntegerIndexError);
	int i = obj2int(args[0]);
	OBJ array = args[1];
	OBJ value = args[2];

	if (IS_TYPE(array, ArrayType)) {
		if ((i < 1) || (i > objWords(array))) return fail(indexOutOfRangeError);
		FIELD(array, (i - 1)) = value;
	} else if (IS_TYPE(array, ByteArrayType)) {
		if ((i < 1) || (i > (objWords(array) * 4))) return fail(indexOutOfRangeError);
		if (!isInt(value)) return fail(byteArrayStoreError);
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return fail(byteArrayStoreError);
		((uint8 *) &FIELD(array, 0))[i - 1] = byteValue;
	} else return fail(needsArrayError);
	return falseObj;
}

OBJ primLength(int argCount, OBJ *args) {
	OBJ obj = args[0];

	if (IS_TYPE(obj, ArrayType)) {
		return int2obj(objWords(obj));
	} else if (IS_TYPE(obj, ByteArrayType)) {
		return int2obj(4 * objWords(obj));
	} else if (IS_TYPE(obj, StringType)) {
		return int2obj(stringSize(obj));
	}
	return fail(needsArrayError);
}

// Named primitives

OBJ primCopyFromTo(int argCount, OBJ *args) {
	// Return a copy of the first argument (a string or list) between the indices give by
	// the second and third arguments. If the optional third argument is not supplied it
	// is taken to be the last index.

	if (argCount < 2) return fail(notEnoughArguments);
	OBJ src = args[0];
	if (!isInt(args[1])) return fail(needsIntegerError);
	int startIndex = obj2int(args[1]);
	if (startIndex < 1) startIndex = 1;
	if ((argCount > 2) && !isInt(args[2])) return fail(needsIntegerError);

	int srcLen = 0;
	if (IS_TYPE(src, ArrayType)) srcLen = WORDS(src);
	if (IS_TYPE(src, StringType)) srcLen = stringSize(src);
	int endIndex = (argCount > 2) ? obj2int(args[2]) : srcLen;
	if (startIndex > srcLen) startIndex = srcLen;
	if (endIndex > srcLen) endIndex = srcLen;
	int resultLen = (endIndex - startIndex) + 1;
	if (resultLen < 0) resultLen = 0;

	OBJ result = falseObj;
	if (IS_TYPE(src, ArrayType)) {
		result = newObj(ArrayType, resultLen, int2obj(0));
		if (result) {
			OBJ *dst = &FIELD(src, 0);
			for (int i = startIndex; i <= endIndex; i++) *dst++ = FIELD(src, i - 1);
		}
	} else if (IS_TYPE(src, StringType)) {
		result = newString(resultLen);
		if (result) {
			memcpy(obj2str(result), obj2str(src) + startIndex - 1, resultLen);
		}
	} else {
		return fail(needsIndexible);
	}
	return result;
}

OBJ primFindInString(int argCount, OBJ *args) {
	// Return the index of next instance the second string in the first or -1 if not found.
	// An optional third argument can be used to specify the starting point for the search.

	if (argCount < 2) return fail(notEnoughArguments);
	OBJ arg0 = args[0];
	OBJ arg1 = args[1];
	int startOffset = ((argCount > 2) && isInt(args[2])) ? obj2int(args[2]) : 1;
	if (startOffset < 1) startOffset = 1;

	if (!(IS_TYPE(arg0, StringType) && IS_TYPE(arg1, StringType))) return fail(needsStringError);
	if (startOffset && (startOffset > stringSize(arg1))) return int2obj(-2); // xxx -1 not found

	char *s = obj2str(arg1);
	char *sought = obj2str(arg0);
	char *match  = strstr(s + startOffset - 1, sought);
	return int2obj(match ? (match - s) + 1 : -1);
}

OBJ primJoin(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	int count, resultCount = 0;
	OBJ arg, arg1 = args[0];
	OBJ result = falseObj;

	if (IS_TYPE(arg1, ArrayType)) {
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (!IS_TYPE(arg, ArrayType)) return fail(joinArgsNotSameType);
			resultCount += WORDS(arg);
		}
		result = newObj(ArrayType, resultCount, int2obj(0));
		if (!result) return result; // allocation failed
		OBJ *dst = &FIELD(result, 0);
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			count = WORDS(arg);
			for (int j = 0; j < count; j++) *dst++ = FIELD(arg, j);
		}
	} else if (IS_TYPE(arg1, StringType)) {
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (!IS_TYPE(arg, StringType)) return fail(joinArgsNotSameType);
			resultCount += stringSize(arg);
		}
		result = newString(resultCount);
		if (!result) return result; // allocation failed
		char *dst = (char *) &FIELD(result, 0);
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			count = stringSize(arg);
			memcpy(dst, obj2str(arg), count);
			dst += count;
		}
		*dst = 0; // null terminator
	} else {
		fail(needsIndexible);
	}
	return result;
}

OBJ primMakeList(int argCount, OBJ *args) {
	OBJ result = newObj(ArrayType, argCount, int2obj(0));
	if (!result) return result; // allocation failed

	for (int i = 0; i < argCount; i++) FIELD(result, i) = args[i];
	return result;
}

// Primitives

// To do:
// joinStrings -- takes a list of strings and optional separator string
// splitString -- takes a string to be split and a separator string

static PrimEntry entries[] = {
	{"copyFromTo", primCopyFromTo},
	{"findInString", primFindInString},
	{"join", primJoin},
	{"makeList", primMakeList},
};

void addDataPrims() {
	addPrimitiveSet("data", sizeof(entries) / sizeof(PrimEntry), entries);
}
