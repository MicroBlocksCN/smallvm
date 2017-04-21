// mem.c - object memory
// Just an allocator for now; no garbage collector.
// John Maloney, April 2017

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"

#ifdef ARDUINO
	char printfBuffer[100]; // used by printf macro in mem.h
#endif

static OBJ memStart;
static OBJ freeStart;
static OBJ memEnd;

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
	printf("wordCount %d memStart %d\n", wordCount, (int) memStart);
	if ((unsigned) memStart <= 8) {
		// Reserve object references 0, 4, and 8 for constants nil, true, and false
		// Details: In the unlikely case that memStart <= 8, increment it by 12
		// and reduce wordCount by 3 words.
		memStart = (OBJ) ((unsigned) memStart + 12);
		wordCount -= 3;
	}
	freeStart = memStart;
	memEnd = memStart + wordCount;
}

void memClear() {
	freeStart = memStart;
}

OBJ newObj(int classID, int wordCount, OBJ fill) {
	OBJ obj = freeStart;
	freeStart += HEADER_WORDS + wordCount;
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

void panic(char *errorMessage) {
	// Called when VM encounters a fatal error. Print the panic message and exit.

	printf("\r\n%s\r\n", errorMessage);
	exit(-1);
}

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
	printf("%x: %d words, classID %d\n", (int) obj, wordCount, classID);
	printf("Header: %x\n", (int) obj[0]);
	for (int i = 0; i < wordCount; i++) printf("	0x%x,\n", obj[HEADER_WORDS + i]);
}
