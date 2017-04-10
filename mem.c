// mem.c - object memory
// Just an allocator for now; no garbage collector.
// John Maloney, April 2017

#include "mem.h"
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>

static OBJ memStart;
static OBJ freeStart;
static OBJ memEnd;

void panic(char *errorMessage) {
	// Called when VM encountered as fatal error. Print the error message and exit.

	debug(errorMessage);
	exit(-1);
}

void memInit(int wordCount) {
	if (sizeof(int) != sizeof(int*)) {
		panic("GP must be compiled in 32-bit mode (e.g. gcc -m32 ...)");
	}
	if (sizeof(int) != sizeof(float)) {
		panic("GP expects floats and ints to be the same size");
	}
	memStart = (OBJ) malloc(wordCount * sizeof(int));
	if (memStart == NULL) {
		panic("memInit failed; insufficient memory");
	}
	printf("wordCount %d memStart %d\r\n", wordCount, (int) memStart);
	if ((unsigned) memStart < 8) {
		// Reserve memory addresses below 8 vor special OOP values for nil, true, and false
		// Details: In the very unlikely case that memStart is under 8, increment it by 8
		// and reduce wordCount by 2 words.
		memStart = (OBJ) ((unsigned) memStart + 8);
		wordCount -= 2;
	}
	freeStart = memStart;
	memEnd = memStart + wordCount;
}

void memClear() {
	freeStart = memStart;
}

OBJ newObj(int classID, int wordCount, OBJ fill) {
	OBJ obj = freeStart;
	freeStart += ((HEADER_WORDS + wordCount) / 4);
	if (freeStart >= memEnd) {
		memPrintStatus();
		panic("Out of memory!");
	}
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
		printf("Non-string passed to obj2str()\n");
		return (char *) "";
	}
	return (char *) &obj[HEADER_WORDS];
}

// Debugging

void memPrintStatus() {
	printf("%d words used out of %d\n", freeStart - memStart, memEnd - memStart);
}

void memDumpObj(OBJ obj) {
	if ((obj < memStart) || (obj >= memEnd)) {
		printf("bad object at %ld\n", (long) obj);
		return;
	}
	int classID = CLASS(obj);
	int wordCount = WORDS(obj);
	printf("obj %d class %d size %d\n", (int) obj, classID, wordCount);
	for (int i = 0; i < wordCount; i++) printf("  %d: %x\n", i, obj[HEADER_WORDS + i]);
}

