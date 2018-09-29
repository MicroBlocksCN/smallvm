// Object memory for 32-bit mode.
// John Maloney, October 2013

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mem.h"
#include "interp.h"

// amount of working memory to reserve for the garbage collector itself
#define GC_MARGIN (100000)

gp_boolean cpuIsBigEndian;

uint32 memStart;
uint32 freeStart;
uint32 memEnd;
unsigned char *baseAddress;

int allocationsSinceLastGC = 0;
int bytesAllocatedSinceLastGC = 0;
int gcCount = 0;
int gcThreshold; // request GC when free space falls below gcThreshold
gp_boolean gcNeeded = false;

#ifdef DEBUG
ADDR a(OBJ oop) {
  return ((ADDR)(((unsigned long)(oop)) + (unsigned long)baseAddress));
}
OBJ o(ADDR addr) {
  return ((OBJ)((unsigned long)addr) - (unsigned long)baseAddress);
}
OBJ atat(OBJ oop, int index) {
  return FIELD(oop, index);
}
#endif

void memInit(uint32 mbytes) {
	cpuIsBigEndian = true;
	if (((char *) &cpuIsBigEndian)[0]) cpuIsBigEndian = false;

	uint32 byteCount = mbytes * 1000000;
	baseAddress = (unsigned char*) malloc(byteCount);
	memStart = A2O(baseAddress) + 8; // reserve oop constants for nil, true, and false (oops 0, 2, 4)

	freeStart = memStart;
	memEnd = memStart + byteCount;

	allocationsSinceLastGC = 0;
	bytesAllocatedSinceLastGC = 0;
	gcThreshold = (memEnd - freeStart) / 10;
}

gp_boolean canAllocate(int wordCount) {
	uint32 byteCount = (HEADER_WORDS + wordCount) * sizeof(OBJ);
	return ((freeStart + byteCount + GC_MARGIN) < memEnd);
}

OBJ newObj(int classID, int wordCount, OBJ fill) {
	OBJ obj = freeStart;
	uint32 byteCount = (HEADER_WORDS + wordCount) * sizeof(OBJ);
	freeStart += byteCount;
	if (freeStart >= memEnd) {
		printf("Out of memory!\n");
		printf("Attempting to create class ID: %d, wordCount: %d\n", classID, wordCount);
		printf("%d words used out of %d\n", freeStart - memStart, memEnd - memStart);
		exit(1);
	}
	allocationsSinceLastGC += 1;
	bytesAllocatedSinceLastGC += byteCount;
	int freeSpace = memEnd - freeStart;
	if (freeSpace < gcThreshold) gcNeeded = true;

	ObjHeaderPtr header = (ObjHeaderPtr)O2A(obj);
	header->formatAndClass = HAS_OBJECTS_BIT | classID;
	header->wordCount = wordCount;
	header->prim = 0;
	header->hash = 0;

	ADDR end = O2A(freeStart);
	for (ADDR p = BODY(obj); p < end; p++) {
		*p = fill;
	}
	return obj;
}

OBJ copyObj(OBJ srcObj, int newSize, int srcIndex) {
	// Note: srcIndex is one-based.

	if (newSize < 0) newSize = 0;
	if (srcIndex < 1) srcIndex = 1;
	int srcSize = objWords(srcObj);
	OBJ result = newObj(CLASS(srcObj), newSize, nilObj);

	ADDR srcStart = BODY(srcObj);
	ADDR srcEnd = srcStart + srcSize - 1;
	ADDR srcPtr = srcStart + srcIndex - 1;
	ADDR dstPtr = BODY(result);
	ADDR dstEnd = dstPtr + newSize;
	while (dstPtr < dstEnd) {
		*dstPtr++ = (((srcPtr >= srcStart) && (srcPtr <= srcEnd)) ? *srcPtr : nilObj);
		srcPtr++;
	}
	return result;
}

OBJ newArray(int wordCount) {
	if (!wordCount) return emptyArray;
	return newObj(ArrayClass, wordCount, nilObj);
}

OBJ newBinaryData(int byteCount) {
	// Return a new BinaryData object with the given number of bytes, or nil if out of memory.
	// Note: Size is in bytes, not words.

	int wordCount = (byteCount + 3) / 4;
	int extraBytes = (4 * wordCount) - byteCount;
	if (!canAllocate(wordCount)) return nilObj;

	OBJ result = newObj(BinaryDataClass, wordCount, 0);
	ADDR a = O2A(result);
	a[0] = BinaryDataClass & CLASS_MASK; // clear HAS_OBJECTS_BIT
	a[0] |= extraBytes << EXTRA_BYTES_SHIFT; // set the extraBytes field
	return result;
}

OBJ newBinaryObj(int classID, int wordCount) {
	OBJ obj = newObj(classID, wordCount, 0);
	ADDR a = O2A(obj);
	a[0] = classID & CLASS_MASK; // clear HAS_OBJECTS_BIT
	return obj;
}

OBJ newFloat(double f) {
	OBJ obj = newObj(FloatClass, 2, nilObj);
	ADDR a = O2A(obj);
	a[0] = FloatClass & CLASS_MASK; // clear HAS_OBJECTS_BIT
	*((align4_double *)BODY(obj)) = f;
	return obj;
}

OBJ cloneObj(OBJ obj) {
	if (isInt(obj) || (obj <= falseObj)) return obj;
	OBJ result = newObj(CLASS(obj), WORDS(obj), nilObj);
	ADDR a = O2A(result);
	a[0] = O2A(obj)[0]; // copy format and class header from original object
	ADDR src = BODY(obj);
	//ADDR end = BODY(obj) + WORDS(obj);
	ADDR dst = BODY(result);
	memcpy(dst, src, WORDS(obj) * sizeof(OBJ));
	//while (src < end) { *dst++ = *src++; } // copy contents
	return result;
}

// Debugging Support

void dumpObj(OBJ obj) {
	ADDR a = O2A(obj);
	const int maxClass = 50; // just a rough sanity check on the class index range

	if ((obj < memStart) || (obj >= freeStart)) {
		printf("bad object %d\n", obj);
		return;
	}
	int gcAndFormat = (a[0] >> 24) & 0xFF;
	int classID = CLASS(obj);
	int wordCount = WORDS(obj);
	printf("%d	(%d words) ", obj - memStart, wordCount);

	if (!classID) printf("FREE\n");
	else if (classID == StringClass) printf("fmt %d '%s'", gcAndFormat, obj2str(obj));
	else if (classID == ArrayClass) printf("fmt %d Array", gcAndFormat);
	else printf("fmt %d classID: %d", gcAndFormat, classID);

	if ((classID < 1) || (classID > maxClass)) printf("Bad class?");
	printf("\n");

	if (HAS_OBJECTS(obj)) {
		for (int i = 0; i < wordCount; i++) {
			OBJ v = FIELD(obj, i);
			if (isInt(v)) printf("	int: %d\n", obj2int(v));
			else if (v == nilObj) printf("	nil\n");
			else if (v == falseObj) printf("	false\n");
			else if (v == trueObj) printf("	true\n");
			else {
				printf("	%d", v - memStart);
				if ((v < memStart) || (v>= freeStart)||
					(CLASS(v) < 1) || (CLASS(v) > maxClass)) {
						printf(" - BAD OOP?");
				}
				printf("\n");
			}
		}
	}
}

void memDumpWords() {
	printf("----- Memory (%u) -----\n", memStart);
	for (ADDR ptr = O2A(memStart); ptr < O2A(freeStart); ptr++) {
		printf("%p: %d\n", ptr - memStart, *ptr);
	}
	printf("-----\n");
}

void memDumpObjects() {
	printf("----- Object Memory (%d) -----\n", (int) memStart);
	OBJ ptr = memStart;
	while (ptr < freeStart) {
		dumpObj(ptr);
		ptr = nextChunk(ptr);
	}
	printf("-----\n");
}

// String Primitives

OBJ newString(char *s) {
	// Create a new string object with the contents of s.
	// Round up to an even number of words and pad with nulls.
	int byteCount = strlen(s) + 1; // including null terminator
	int wordCount = (byteCount + 3) / 4;
	OBJ result = newBinaryObj(StringClass, wordCount);
	char *dst = (char *)BODY(result);
	strcpy(dst, s);
	return result;
}

OBJ allocateString(int byteCount) {
	// Allocate an empty String object of byteCount bytes. Leave room for at least
	// one null terminator (a zero byte). Contents is initialized to null bytes.
	if (byteCount < 0) byteCount = 0;
	byteCount++; // leave room for null terminator
	int wordCount = (byteCount + 3) / 4;
	return newBinaryObj(StringClass, wordCount);
}

int stringBytes(OBJ stringObj) {
	// Return the number of bytes in the given String object, not including the null terminator.
	// Assumes stringObj is a String object.
	int words = objWords(stringObj);
	int len = 4 * (words - 1);

	// count the bytes in final word
	char *end = (char *)(BODY(stringObj) + words - 1);
	for (int i = 0; i < 4; i++) {
		if (*end++) len++; else break;
	}
	return len;
}

char* obj2str(OBJ obj) {
	if (NOT_CLASS(obj, StringClass)) {
		// VM implementation bug: caller should be sure object is a string before calling obj2str()
		printf("Non-string passed to obj2str()\n");
		stop();
		return "";
	}
	return (char *)BODY(obj);
}

gp_boolean strEQ(char *s, OBJ obj) { return strcmp(s, obj2str(obj)) == 0; }

gp_boolean isBadUTF8(char *s) {
	// Return true if s is not a valid UTF8 string.
	// Adapted from sample code in http://en.wikipedia.org/wiki/UTF-8

	int byte1, byte2, byte3, byte4;
	unsigned char *src = (unsigned char *)s;
	while ((byte1 = *src++) != 0) {
		if (byte1 < 0x80) {
			// 1-byte sequence
			continue;
		} else if (byte1 < 0xC2) {
			return true; // continuation or overlong 2-byte sequence
		} else if (byte1 < 0xE0) {
			// 2-byte sequence
			byte2 = *src++;
			if ((byte2 & 0xC0) != 0x80) return true; // bad continuation byte
			continue;
		} else if (byte1 < 0xF0) {
			// 3-byte sequence
			byte2 = *src++;
			if ((byte2 & 0xC0) != 0x80) return true; // bad continuation byte
			if ((byte1 == 0xE0) && (byte2 < 0xA0)) return true; // overlong
			byte3 = *src++;
			if ((byte3 & 0xC0) != 0x80) return true; // bad continuation byte
			continue;
		} else if (byte1 < 0xF5) {
			// 4-byte sequence
			byte2 = *src++;
			if ((byte2 & 0xC0) != 0x80) return true; // bad continuation byte
			if ((byte1 == 0xF0) && (byte2 < 0x90)) return true; // overlong
			if ((byte1 == 0xF4) && (byte2 >= 0x90)) return true; // > U+10FFFF
			byte3 = *src++;
			if ((byte3 & 0xC0) != 0x80) return true; // bad continuation byte
			byte4 = *src++;
			if ((byte4 & 0xC0) != 0x80) return true; // bad continuation byte
			continue;
		} else {
			return true; // > U+10FFFF
		}
	}
	return false;
}

// Object Enumeration

OBJ objectAfter(OBJ prevObj, int classID) {
	// Return the object in memory following prevObj or nil if prevObj was
	// the last object. If classID is non-zero, only enumberate instances of
	// that class. If it is zero, enumberate all objects. To start the
	// enumeration, pass nil as the previous object. This only enumerates
	// object in memory; calling it with an integer or boolean returns nil.

	if (prevObj == nilObj) {
		prevObj = memStart;
		if (!classID || (classID == CLASS(prevObj))) return prevObj;
	}
	if (isInt(prevObj) || (prevObj <= falseObj)) return nilObj;

	OBJ next = prevObj;
	while (true) {
		next = nextChunk(next);
		if (next >= freeStart) return nilObj;
		int nextClass = CLASS(next);
		if (!nextClass) continue; // skip free chunk
		if ((!classID) || (classID == nextClass)) return next;
	}
}

OBJ referencesToObject(OBJ target) {
	// Return an Array containing all the objects that contain a reference
	// to the target object.

	OBJ result = newArray(100);
	int resultSize = WORDS(result);
	int nextIndex = 0;

	OBJ obj = memStart;
	while (obj < result) {
		if (CLASS(obj) && HAS_OBJECTS(obj)) {
			int fieldCount = WORDS(obj);
			for (int i = 0; i < fieldCount; i++) {
				if (target == FIELD(obj, i)) {
					FIELD(result, nextIndex) = obj;
					if (++nextIndex >= resultSize) {
						resultSize = 2 * resultSize;
						result = copyObj(result, resultSize, 1);
					}
					break;
				}
			}
		}
		obj = nextChunk(obj);
	}
	return copyObj(result, nextIndex, 1);
}

void replaceObjects(OBJ srcArray, OBJ dstArray) {
	// Replace all references to each object in the first array with
	// the corresponding object in the second array. The arrays
	// must be the same size.

	int srcCount = WORDS(srcArray);
	if (WORDS(dstArray) != srcCount) return;

	OBJ obj = memStart;
	while (obj < freeStart) {
		if (CLASS(obj) && HAS_OBJECTS(obj)) {
			int fieldCount = WORDS(obj);
			for (int i = 0; i < fieldCount; i++) {
				OBJ field = FIELD(obj, i);
				for (int j = 0; j < srcCount; j++) {
					if (field == FIELD(srcArray, j)) {
						FIELD(obj, i) = FIELD(dstArray, j);
						break;
					}
				}
			}
		}
		obj = nextChunk(obj);
	}
}
