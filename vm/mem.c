// mem.c - object memory
// Just an allocator for now; no garbage collector.
// John Maloney, April 2017

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

static OBJ memStart;
static OBJ freeStart;
static OBJ memEnd;

void memInit(int wordCount) {
	if (sizeof(int) != sizeof(int*)) {
		vmPanic("MicroBlocks must be compiled in 32-bit mode (e.g. gcc -m32 ...)");
	}
	if (sizeof(int) != sizeof(float)) {
		vmPanic("MicroBlocks expects float and int to be the same size");
	}

	memStart = (OBJ) malloc(wordCount * sizeof(int));
	uint32 stackBytes; // address of this local variable approximates the current C stack pointer
	stackBytes = ((uint32) &stackBytes) - ((uint32) (memStart + wordCount));
	if ((memStart == NULL) || (stackBytes < 256)) {
		vmPanic("Insufficient memory to start MicroBlocks");
	}
	if ((unsigned) memStart <= 8) {
		// Reserve object references 0, 4, and 8 for constants nil, true, and false
		// Details: In the unlikely case that memStart <= 8, increment it by 12
		// and reduce wordCount by 3 words.
		memStart = (OBJ) ((unsigned) memStart + 12);
		wordCount -= 3;
	}
	freeStart = memStart;
	memEnd = memStart + wordCount;

	// initialize all global variables to zero
	for (int i = 0; i < MAX_VARS; i++) vars[i] = int2obj(0);
}

void vmPanic(char *errorMessage) {
	// Called when VM encounters a fatal error. Output the given message and loop forever.
	// NOTE: This call never returns!

	char s[100];
	sprintf(s, "\r\nVM Panic: %s\r\n", errorMessage);
	printf(s);
	outputString(s);
	while (true) processMessage(); // there's no way to recover; loop forever!
}

void memClear() {
	freeStart = memStart;
}

OBJ newObj(int classID, int wordCount, OBJ fill) {
	if ((freeStart + HEADER_WORDS + wordCount) >= memEnd) {
		return fail(insufficientMemoryError);
	}
	OBJ obj = freeStart;
	freeStart += HEADER_WORDS + wordCount;
	for (OBJ p = obj; p < freeStart; ) *p++ = (int) fill;
	unsigned header = HEADER(classID, wordCount);
	obj[0] = header;
	return obj;
}

// String Primitives

OBJ newString(char *s) {
	// Create a new string object with the contents of s.
	// Round up to an even number of words and pad with nulls.

	int byteCount = strlen(s) + 1; // leave room for null terminator
	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(StringClass, wordCount, 0);
	char *dst = (char *) &result[HEADER_WORDS];
	for (int i = 0; i < byteCount; i++) *dst++ = *s++;
	*dst = 0; // null terminator byte
	return result;
}

char* obj2str(OBJ obj) {
	if (NOT_CLASS(obj, StringClass)) {
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
