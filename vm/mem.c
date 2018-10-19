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

static OBJ memStart = NULL;
static OBJ freeStart = NULL;
static OBJ memEnd = NULL;

void memInit(int wordCount) {
	// verify 32-bit architecture
	if (!(sizeof(int) == 4 && sizeof(int*) == 4 && sizeof(float) == 4)) {
		vmPanic("MicroBlocks expects int, int*, and float to all be 32-bits");
	}

	// allocate memory for object heap
	if (memStart) free(memStart); // this allows memInit() to be called more than once
	memStart = (OBJ) malloc(wordCount * sizeof(int));
	if (memStart == NULL) {
		vmPanic("Insufficient memory for MicroBlocks object heap");
	}

	char *stack = (char *) &stack; // the address of this local variable approximates the current C stack pointer
	if (stack > (char *) memStart) {
		// On some platforms (e.g. micro:bit), the malloc() call succeeds even when there is not enough memory.
		// This check makes sure there's enough space for both the MicroBlock object heap and the stack.
		// This check makes sense only if the stack is immediately above the heap.

		stack = stack - 1000; // reserve 1000 bytes for stack (stack grows down in memory)
		if ((memStart + wordCount) > (OBJ) stack) {
			vmPanic("Insufficient memory for MicroBlocks stack");
		}
	}

	if ((unsigned) memStart <= 4) {
		// Reserve object references 0 and 4 for object pointer constants true and false.
		// Details: In the very unlikely case that memStart <= 4, increment it by 8
		// and reduce wordCount by 2 words.
		memStart = (OBJ) ((unsigned) memStart + 8);
		wordCount -= 2;
	}
	freeStart = memStart;
	memEnd = memStart + wordCount;

	// initialize all global variables to zero
	for (int i = 0; i < MAX_VARS; i++) vars[i] = int2obj(0);
}

void memClear() {
	// Clear object memory and set all global variables to zero.

	freeStart = memStart;
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

OBJ newObj(int classID, int wordCount, OBJ fill) {
	if ((freeStart + HEADER_WORDS + wordCount) > memEnd) {
		return fail(insufficientMemoryError);
	}
	OBJ obj = freeStart;
	freeStart += HEADER_WORDS + wordCount;
	for (OBJ p = obj; p < freeStart; ) *p++ = (int) fill;
	unsigned header = HEADER(classID, wordCount);
	obj[0] = header;

	// for checking memory management:
// 	char *stack = (char *) &stack;
// 	char s[100];
// 	sprintf(s, "%d bytes available (of %d total)", 4 * (memEnd - freeStart), 4 * (memEnd - memStart));
// 	outputString(s);
// 	if (stack > memEnd) {
// 		sprintf(s, "%d stack bytes\n", stack - (char *) memEnd);
// 		outputString(s);
// 	} else {
// 		outputString("Unknown stack bytes\n");
// 	}

	return obj;
}

// String Primitives

OBJ newStringFromBytes(uint8 *bytes, int byteCount) {
	// Create a new string object with the given bytes.
	// Round up to an even number of words and pad with nulls.

	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(StringClass, wordCount, 0);
	char *dst = (char *) &result[HEADER_WORDS];
	for (int i = 0; i < byteCount; i++) *dst++ = *bytes++;
	*dst = 0; // null terminator byte
	return result;
}

char* obj2str(OBJ obj) {
	if (!IS_CLASS(obj, StringClass)) {
		fail(needsStringError);
		return (char *) "";
	}
	return (char *) &obj[HEADER_WORDS];
}

// Debugging

void memDumpObj(OBJ obj) {
	if ((obj < memStart) || (obj >= memEnd)) {
		printf("bad object at %ld\n", (long) obj);
		return;
	}
	int classID = CLASS(obj);
	int wordCount = WORDS(obj);
	printf("%x: %d words, classID %d\n", (int) obj, wordCount, classID);
	printf("Header: %x\n", (int) obj[0]);
	for (int i = 0; i < wordCount; i++) printf("	0x%x,\n", obj[HEADER_WORDS + i]);
}
