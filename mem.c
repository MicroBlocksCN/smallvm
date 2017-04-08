// Object memory for 32-bit object pointers.
// Just an allocator for now; no garbage collector.

#include "mem.h"
#include <stdio.h>
#include <stdlib.h>

static OBJ memStart;
static OBJ freeStart;
static OBJ memEnd;

void memInit(int wordCount) {
	if (sizeof(int) != sizeof(int*)) {
		debug("GP must be compiled in 32-bit mode (e.g. gcc -m32 ...)");
		exit(-1);
	}
	if (sizeof(int) != sizeof(float)) {
		debug("GP expects floats and ints to be the same size");
		exit(-1);
	}
	memStart = (OBJ) malloc(wordCount * sizeof(int));
	if (memStart == NULL) {
		debug("memInit failed");
		exit(-1);
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

void memDump() {
	printf("----- Memory (%d) -----\n", (int) memStart);
	for (int *ptr = memStart; ptr < freeStart; ptr++) {
		printf("%d: %d\n", ((int) ptr) - ((int) memStart), *ptr);
	}
	printf("-----\n");
}

void memPrintStatus() {
	printf("%d words used out of %d\n", freeStart - memStart, memEnd - memStart);
}

OBJ newObj(int classID, int wordCount, OBJ fill) {
	OBJ obj = freeStart;
	freeStart += ((HEADER_WORDS + wordCount) / 4);
	if (freeStart >= memEnd) {
		memPrintStatus();
		debug("Out of memory!");
		exit(-1);
	}
	for (OBJ p = obj; p < freeStart; ) *p++ = (int) fill;
	obj[0] = classID;
	obj[1] = wordCount;
	obj[2] = 888888;
	return obj;
}

void dumpObj(OBJ obj) {
	if ((obj < memStart) || (obj >= memEnd)) {
		printf("bad object at %ld\n", (long) obj);
		return;
	}
	int classID = obj[0];
	int wordCount = obj[1];
	printf("obj %d class %d size %d\n", (int) obj, classID, wordCount);
	for (int i = 0; i < wordCount; i++) printf("  %d: %d\n", i, obj[HEADER_WORDS + i]);
}

// String Primitives

OBJ newString(char *s, int byteCount) {
	// Create a new string object with the contents of s.
	// Round up to an even number of words and pad with nulls.
	byteCount++; // leave room for null terminator
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
