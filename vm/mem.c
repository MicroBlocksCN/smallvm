/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// mem.c - object memory
// Just an allocator for now; no garbage collector.
// John Maloney, April 2017

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#if defined(NRF51)
  #define OBJSTORE_BYTES 2500 // max is 2612
#else
  #define OBJSTORE_BYTES 14000 // max that compiles for all boards is 16886 (17624 NodeMCU)
#endif

#define OBJSTORE_WORDS ((OBJSTORE_BYTES / 4) + 2)
static OBJ objstore[OBJSTORE_WORDS];
static OBJ memStart = NULL;
static OBJ memEnd = NULL;
static OBJ freeChunk = NULL;

void memInit() {
	// verify 32-bit architecture
	if (!(sizeof(int) == 4 && sizeof(int*) == 4 && sizeof(float) == 4)) {
		vmPanic("MicroBlocks expects int, int*, and float to all be 32-bits");
	}

	// initialize object heap memory
	memset(objstore, 0, sizeof(objstore));
	memStart = (OBJ) objstore;
	memEnd = (OBJ) (objstore + OBJSTORE_WORDS);
	memClear();
}

void memClear() {
	// Clear object memory and set all global variables to zero.

	freeChunk = memStart;
	for (int i = 0; i < MAX_VARS; i++) vars[i] = int2obj(0);
}

void vmPanic(char *errorMessage) {
	// Called when VM encounters a fatal error. Output the given message and loop forever.
	// NOTE: This call never returns!

	char s[100];
	sprintf(s, "\r\nVM Panic: %s\r\n", errorMessage);
	outputString(s);
	while (true) processMessage(); // there's no way to recover; loop forever!
}

OBJ newObj(int typeID, int wordCount, OBJ fill) {
	if ((freeChunk + HEADER_WORDS + wordCount) > memEnd) {
		return fail(insufficientMemoryError);
	}
	OBJ obj = freeChunk;
	freeChunk += HEADER_WORDS + wordCount;
	for (OBJ p = obj; p < freeChunk; ) *p++ = (int) fill;
	unsigned header = HEADER(typeID, wordCount);
	obj[0] = header;
	return obj;
}

// String Primitives

OBJ newStringFromBytes(uint8 *bytes, int byteCount) {
	// Create a new string object with the given bytes.
	// Round up to an even number of words and pad with nulls.

	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(StringType, wordCount, 0);
	char *dst = (char *) &result[HEADER_WORDS];
	for (int i = 0; i < byteCount; i++) *dst++ = *bytes++;
	*dst = 0; // null terminator byte
	return result;
}

char* obj2str(OBJ obj) {
	if (isInt(obj)) return "<Integer>";
	if (isBoolean(obj)) return ((trueObj == obj) ? "true" : "false");
	if (IS_TYPE(obj, StringType)) return (char *) &obj[HEADER_WORDS];
	if (IS_TYPE(obj, ArrayType)) return "<Array>";
	return "<Object>";
}

// Debugging

void memDumpObj(OBJ obj) {
	char s[100];

	if ((obj < memStart) || (obj >= memEnd)) {
		sprintf(s, "bad object at %ld", (long) obj);
		outputString(s);
		return;
	}
	int typeID = TYPE(obj);
	int wordCount = WORDS(obj);
	sprintf(s, "%x: %d words, typeID %d", (int) obj, wordCount, typeID);
	outputString(s);

	sprintf(s, "Header: %x", obj[0]);
	outputString(s);

	for (int i = 0; i < wordCount; i++) {
		sprintf(s, "	0x%x,", obj[HEADER_WORDS + i]);
		outputString(s);
	}
}
