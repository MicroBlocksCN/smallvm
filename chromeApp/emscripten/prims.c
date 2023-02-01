// prims.c
// John Maloney, September, 2013

#include <dirent.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <zlib.h>

#include "sha1.h"
#include "sha2.h"

#include "mem.h"
#include "cache.h"
#include "dict.h"
#include "embeddedFS.h"
#include "interp.h"
#include "oop.h"
#include "parse.h"

#ifdef EMSCRIPTEN
#include <emscripten.h>
#endif

#ifdef MAC
#include <Carbon/Carbon.h>
#endif

#ifdef IOS
#include "iosOps.h"
#endif

#ifdef _WIN32
#include <windows.h>
#include <direct.h>		// used by makeDirectory (for _wmkdir)
#include <Shlobj.h>		// used by userHomePath (for SHGetFolderPathW)
#include <process.h>
#else
#include <sys/wait.h>
#endif

// ***** Version Date and Time *****

static char *versionNum = "v272";
static char *versionDate = __DATE__;
static char *versionTime = __TIME__;

// ***** Command Line Arguments *****

static char** commandLineValues = NULL;
static int commandLineCount = 0;

// ***** Primitive Failure *****

OBJ primFailed(char *reason) {
	// Print a message and stop the interpreter.
	failure(reason);
	stop();
	return nilObj;
}

OBJ notEnoughArgsFailure() { return primFailed("Not enough arguments"); }
OBJ outOfMemoryFailure() { return primFailed("Insufficient memory"); }

// ***** Helper *****

static inline int evalInt(OBJ obj) {
	// Covert the given object to a integer. Assumes the object is an Integer.
	if (isInt(obj)) return obj2int(obj);
	primFailed("Expected integer");
	return 0;
}

unsigned char* largeIntBody(OBJ obj) {
	if (!IS_CLASS(obj, LargeIntegerClass)) {
		primFailed("Expect Large Integer");
		return NULL;
	}
	OBJ bytes = FIELD(obj, 0);
	if (!IS_CLASS(bytes, BinaryDataClass)) {
		primFailed("malformed Large Integer object found");
		return NULL;
	}
	return (unsigned char*)(&FIELD(bytes, 0));
}

double largeIntToDouble(OBJ obj) {
	double result = 0.0;
	int sign;
	unsigned char *bytes = largeIntBody(obj);
	if (!bytes) {return 0.0;}

	sign = (FIELD(obj, 1) == trueObj) ? -1 : 1;
	unsigned byteCount = objBytes(FIELD(obj, 0));
	for (int i = 0; i < byteCount; i++) {
		result *= 256.0;
		result += bytes[i];
	}
	return result * sign;
}

uint32 uint32Value(OBJ obj) {
	if (isInt(obj)) {
		if (((int)obj) < 0) {
			primFailed("negative integer");
			return 0;
		}
		return obj2int(obj);
	}
	if (!IS_CLASS(obj, LargeIntegerClass)) {
		primFailed("Expect Large Integer");
		return 0;
	}
	if (FIELD(obj, 1) == trueObj) {
		primFailed("negative integer");
	}
	OBJ bytes = FIELD(obj, 0);
	unsigned int byteCount = objBytes(bytes);
	unsigned int result = 0;
	unsigned char *body = (unsigned char*)(&FIELD(bytes, 0));
	for (int i = 0; i < (4 < byteCount ? 4 : byteCount); i++) {
		result <<= 8;
		result += body[i];
	}
	return result;
}

OBJ uint32Obj(unsigned int val) {
	if (val <= 0x3FFFFFFF) {
		return int2obj(val);
	}
	if (!canAllocate(10)) return outOfMemoryFailure(); // enough for LargeInteger + its data object

	OBJ result = newObj(LargeIntegerClass, 2, nilObj);
	OBJ bytes = newBinaryData(4);
	unsigned char *body = (unsigned char*)(&FIELD(bytes, 0));
	body[0] = (val >> 24) & 255;
	body[1] = (val >> 16) & 255;
	body[2] = (val >> 8) & 255;
	body[3] = val & 255;
	FIELD(result, 0) = bytes;
	return result;
}

// ***** Printing *****

static inline double obj2double(OBJ obj) {
	return *((align4_double *)BODY(obj));
}

void printObj(OBJ obj, int arrayDepth) {
	if (isInt(obj)) printf("%d", obj2int(obj));
	else if (obj == nilObj) printf("nil");
	else if (obj == trueObj) printf("true");
	else if (obj == falseObj) printf("false");
	else if (IS_CLASS(obj, StringClass)) printf("%s", obj2str(obj));
	else if (IS_CLASS(obj, FloatClass)) {
		double n = obj2double(obj);
		if (n == (int) n) printf("%.1f", n); // print trailing ".0"
		else printf("%g", n);
	}
	else printf("<%s>", getClassName(obj));
}

void printlnObj(OBJ obj) {
	printObj(obj, 0);
	printf("\n");
}

OBJ primLog(int nargs, OBJ args[]) {
	for (int i = 0; i < nargs; i++) {
		printObj(args[i], 0);
		printf(" ");
	}
	printf("\n");
	fflush(stdout);
	return nilObj;
}

// ***** Array Primitives *****

OBJ sizeFailure() { return primFailed("Size must be a non-negative integer"); }
OBJ arrayClassFailure() { return primFailed("Must be an Array"); }
OBJ indexClassFailure() { return primFailed("Index must be an integer"); }
OBJ outOfRangeFailure() { return primFailed("Index out of range"); }
OBJ notBinaryDataFailure() { return primFailed("First argument must be a BinaryData"); }
OBJ notStringOrBinaryFailure() { return primFailed("First argument must be a String or BinaryData"); }

OBJ primNewArray(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	int count = obj2int(args[0]);
	OBJ fillObj = (nargs > 1) ? args[1] : nilObj;
	if (!isInt(args[0]) || (count < 0)) return sizeFailure();
	if (!count) return emptyArray;
	if (!canAllocate(count)) return outOfMemoryFailure();
	return newObj(ArrayClass, count, fillObj);
}

OBJ primArrayAt(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ array = args[0];
	if (!(IS_CLASS(array, ArrayClass) || IS_CLASS(array, TaskClass))) return arrayClassFailure();
	int count = WORDS(array);
	int i = obj2int(args[1]);
	if (!isInt(args[1])) return indexClassFailure();
	if ((i < 1) || (i > count)) return outOfRangeFailure();

	return BODY(array)[i - 1];
}

OBJ primArray(int nargs, OBJ args[]) {
	if (!canAllocate(nargs)) return outOfMemoryFailure();
	OBJ result = newArray(nargs);
	for (int i = 0; i < nargs; i++) FIELD(result, i) = args[i];
	return result;
}

static int utf8_count(unsigned char *s);

OBJ primCount(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ arg = args[0];
	int class = objClass(arg);
	if (StringClass == class) return int2obj(utf8_count((unsigned char *) obj2str(args[0])));
	if (ArrayClass == class) return int2obj(objWords(arg));
	return int2obj(objWords(arg));
}

OBJ primArrayAtPut(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ array = args[0];
	if (!(IS_CLASS(array, ArrayClass) || IS_CLASS(array, TaskClass) || IS_CLASS(array, WeakArrayClass))) return arrayClassFailure();
	int count = WORDS(array);
	int i = obj2int(args[1]);
	if (!isInt(args[1])) return indexClassFailure();
	if ((i < 1) || (i > count)) return outOfRangeFailure();
	BODY(array)[i - 1] = args[2];
	return nilObj;
}

OBJ primFillArray(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	int arraySize = objWords(array);
	OBJ value = args[1];
	int first = intArg(2, 1, nargs, args);
	int last = intArg(3, arraySize, nargs, args);

	ADDR dst = BODY(array) + clip(first, 1, arraySize) - 1;
	ADDR end = BODY(array) + clip(last, 1, arraySize) - 1;
	while (dst <= end) *dst++ = value;
	return nilObj;
}

OBJ primReplaceArrayRange(int nargs, OBJ args[]) {
	// dst first last src srcStartIndex
	if (nargs < 4) return notEnoughArgsFailure();
	OBJ dstArray = args[0];
	int first = intArg(1, -1, nargs, args);
	int last = intArg(2, -1, nargs, args);
	OBJ srcArray = args[3];
	int srcFirst = intArg(4, 1, nargs, args); // optional; default to 1

	if (NOT_CLASS(dstArray, ArrayClass)) return arrayClassFailure();
	if (NOT_CLASS(srcArray, ArrayClass)) return arrayClassFailure();

	int dstSize = objWords(dstArray);
	if (last < first) {
		return nilObj;
	}
	if ((first < 1) || (first > dstSize) ||
		(last < 1) || (last > dstSize)) {
			return outOfRangeFailure();
	}
	int srcSize = objWords(srcArray);
	if ((srcFirst < 1) || ((srcFirst + (last - first)) > srcSize)) {
		return outOfRangeFailure();
	}
	if ((dstArray == srcArray) && (srcFirst < first)) {
		// moving subrange up in same array; use decrementating index loop
		ADDR src = BODY(srcArray) + srcFirst + (last - first) - 1;
		ADDR dst = BODY(dstArray) + last - 1;
		ADDR end = BODY(dstArray) + first - 1;
		while (dst >= end) *dst-- = *src--;
	} else {
		ADDR src = BODY(srcArray) + srcFirst - 1;
		ADDR dst = BODY(dstArray) + first - 1;
		ADDR end = BODY(dstArray) + last - 1;
		while (dst <= end) *dst++ = *src++;
	}
	return nilObj;
}

OBJ primCopyArray(int nargs, OBJ args[]) {
	OBJ srcArray = args[0];
	if (NOT_CLASS(srcArray, ArrayClass)) return arrayClassFailure();
	int srcSize = objWords(srcArray);
	int newSize = intArg(1, srcSize, nargs, args); // new array size; default = srcArray size
	int srcIndex = intArg(2, 1, nargs, args); // start index in srcArray; default = 1
	if (newSize < 0) return sizeFailure();
	if (!canAllocate(newSize)) return outOfMemoryFailure();
	return copyObj(srcArray, newSize, srcIndex);
}

OBJ primIntAt(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ data = args[0];
	int byteIndex = evalInt(args[1]); // 1-based
	int bigEndian = ((nargs > 2) && (args[2] == trueObj));

	if (!IS_CLASS(data, BinaryDataClass)) return notBinaryDataFailure();
	if (!isInt(args[1])) return indexClassFailure();

	int byteCount = objBytes(data);
	if ((byteIndex < 1) || (byteIndex > (byteCount - 3))) return outOfRangeFailure();

	unsigned char *ptr = ((unsigned char*) &FIELD(data, 0)) + byteIndex - 1;
	int buf;
	unsigned char *bufP = (unsigned char*) &buf;

	if (bigEndian == cpuIsBigEndian) {
		bufP[0] = *ptr++; bufP[1] = *ptr++; bufP[2] = *ptr++; bufP[3] = *ptr++;
	} else {
		bufP[3] = *ptr++; bufP[2] = *ptr++; bufP[1] = *ptr++; bufP[0] = *ptr++;
	}
	return int2obj(buf);
}

OBJ primIntAtPut(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ data = args[0];
	int byteIndex = evalInt(args[1]); // 1-based
	int bigEndian = ((nargs > 3) && (args[3] == trueObj));

	if (!IS_CLASS(data, BinaryDataClass)) return notBinaryDataFailure();
	if (!isInt(args[1])) return indexClassFailure();
	if (!isInt(args[2])) return primFailed("Value must be an integer");

	int byteCount = objBytes(data);
	if ((byteIndex < 1) || (byteIndex > (byteCount - 3))) return outOfRangeFailure();

	unsigned char *ptr = ((unsigned char*) &FIELD(data, 0)) + byteIndex - 1;
	int buf = obj2int(args[2]);
	unsigned char *bufP = (unsigned char*) &buf;

	if (bigEndian == cpuIsBigEndian) {
		*ptr++ = bufP[0]; *ptr++ = bufP[1]; *ptr++ = bufP[2]; *ptr++ = bufP[3];
	} else {
		*ptr++ = bufP[3]; *ptr++ = bufP[2]; *ptr++ = bufP[1]; *ptr++ = bufP[0];
	}
	return args[2];
}

OBJ primUInt32At(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ data = args[0];
	int byteIndex = evalInt(args[1]); // 1-based
	int bigEndian = ((nargs > 2) && (args[2] == trueObj));

	if (!IS_CLASS(data, BinaryDataClass)) return notBinaryDataFailure();
	if (!isInt(args[1])) return indexClassFailure();

	int byteCount = objBytes(data);
	if ((byteIndex < 1) || (byteIndex > (byteCount - 3))) return outOfRangeFailure();

	unsigned char *ptr = ((unsigned char*) &FIELD(data, 0)) + byteIndex - 1;
	uint32 buf;
	unsigned char *bufP = (unsigned char*) &buf;

	if (bigEndian == cpuIsBigEndian) {
		bufP[0] = *ptr++; bufP[1] = *ptr++; bufP[2] = *ptr++; bufP[3] = *ptr++;
	} else {
		bufP[3] = *ptr++; bufP[2] = *ptr++; bufP[1] = *ptr++; bufP[0] = *ptr++;
	}
	return uint32Obj(buf);
}

OBJ primUInt32AtPut(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ data = args[0];
	int byteIndex = evalInt(args[1]); // 1-based
	int bigEndian = ((nargs > 3) && (args[3] == trueObj));

	if (!IS_CLASS(data, BinaryDataClass)) return notBinaryDataFailure();
	if (!isInt(args[1])) return indexClassFailure();

	int byteCount = objBytes(data);
	if ((byteIndex < 1) || (byteIndex > (byteCount - 3))) return outOfRangeFailure();

	unsigned char *ptr = ((unsigned char*) &FIELD(data, 0)) + byteIndex - 1;
	uint32 buf = uint32Value(args[2]);
	unsigned char *bufP = (unsigned char*) &buf;

	if (bigEndian == cpuIsBigEndian) {
		*ptr++ = bufP[0]; *ptr++ = bufP[1]; *ptr++ = bufP[2]; *ptr++ = bufP[3];
	} else {
		*ptr++ = bufP[3]; *ptr++ = bufP[2]; *ptr++ = bufP[1]; *ptr++ = bufP[0];
	}
	return args[2];
}

OBJ primFloat32At(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ data = args[0];
	int byteIndex = evalInt(args[1]); // 1-based
	int bigEndian = ((nargs > 2) && (args[2] == trueObj));

	if (!IS_CLASS(data, BinaryDataClass)) return notBinaryDataFailure();
	if (!isInt(args[1])) return indexClassFailure();

	int byteCount = objBytes(data);
	if ((byteIndex < 1) || (byteIndex > (byteCount - 3))) return outOfRangeFailure();

	unsigned char *ptr = ((unsigned char*) &FIELD(data, 0)) + byteIndex - 1;
	unsigned char buf[4];

	if (bigEndian == cpuIsBigEndian) {
		buf[0] = *ptr++; buf[1] = *ptr++; buf[2] = *ptr++; buf[3] = *ptr++;
	} else {
		buf[3] = *ptr++; buf[2] = *ptr++; buf[1] = *ptr++; buf[0] = *ptr++;
	}
	return newFloat(((float *) &buf)[0]);
}

OBJ primFloat32AtPut(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ data = args[0];
	int byteIndex = evalInt(args[1]); // 1-based
	int bigEndian = ((nargs > 3) && (args[3] == trueObj));

	if (!IS_CLASS(data, BinaryDataClass)) return notBinaryDataFailure();
	if (!isInt(args[1])) return indexClassFailure();

	int byteCount = objBytes(data);
	if ((byteIndex < 1) || (byteIndex > (byteCount - 3))) return outOfRangeFailure();

	unsigned char *ptr = ((unsigned char*) &FIELD(data, 0)) + byteIndex - 1;
	unsigned char buf[4];
	((float *) &buf)[0] = evalFloat(args[2]);

	if (bigEndian == cpuIsBigEndian) {
		*ptr++ = buf[0]; *ptr++ = buf[1]; *ptr++ = buf[2]; *ptr++ = buf[3];
	} else {
		*ptr++ = buf[3]; *ptr++ = buf[2]; *ptr++ = buf[1]; *ptr++ = buf[0];
	}
	return args[2];
}

// ***** Strings *****

static OBJ firstArgMustBeString() { return primFailed("First argument must be a string"); }
static OBJ needsArrayOfStrings() { return primFailed("joinStringArray expects an array of strings"); }

OBJ primJoinStringArray(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();

	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return needsArrayOfStrings();
	int arrayLength = objWords(array);
	if (arrayLength == 0) return newString("");

	OBJ delimiter = nilObj;
	if (nargs > 1) {
		delimiter = args[1];
		if (delimiter != nilObj) {
			if (NOT_CLASS(delimiter, StringClass)) {
				return primFailed("Optional second arg must be a string or nil");
			}
			if (stringBytes(delimiter) == 0) delimiter = nilObj;
		}
	}

	int startIndex = intArg(2, 1, nargs, args);
	int stopIndex = intArg(3, arrayLength, nargs, args);
	if (startIndex > stopIndex) return newString("");
	if ((startIndex < 1) || (startIndex > arrayLength) ||
		(stopIndex < 1) || (stopIndex > arrayLength)) {
			return primFailed("Bad start or stop index");
	}
	int count = (stopIndex - startIndex) + 1;
	ADDR strings = BODY(array) + startIndex - 1;

	// compute total number of bytes and allocate the result string
	OBJ s;
	int i, byteCount = 0;
	for (i = 0; i < count; i++) {
		s = strings[i];
		if (NOT_CLASS(s, StringClass)) return needsArrayOfStrings();
		byteCount += stringBytes(s);
	}
	if (delimiter) byteCount += (count - 1) * stringBytes(delimiter);
	if (!canAllocate(byteCount / 4)) return outOfMemoryFailure();
	OBJ result = allocateString(byteCount);

	// concatenate the strings into the result
	char *dst = (char *)BODY(result);
	for (i = 0; i < count; i++) {
		char *src = (char*)BODY(strings[i]);
		while (*src) *dst++ = *src++;
		if (delimiter && (i < (count - 1))) {
			src = (char*)BODY(delimiter);
			while (*src) *dst++ = *src++;
		}
	}
	*dst++ = '\0'; // null terminator
	return result;
}

static OBJ copyByteRange(char *start, char *stop) {
	// Create a new string with the byte index range from start up to but not including stop.
	int byteCount = stop - start;
	if (!canAllocate(byteCount / 4)) return outOfMemoryFailure();
	OBJ result = allocateString(byteCount);
	char *dst = (char *)BODY(result);
	for (char *s = start; s < stop; ) *dst++ = *s++; // faster than strncpy
	return result;
}

static int splitLines(char *s, OBJ array, int arrayLength) {
	// Return the number of lines in the given string.
	// If array is not nil, fill it with the lines, discarding line endings.
	// Support CR, LF, or CR-LF line endings.

	int count = 0;
	char *src = s;
	char *start = src;
	while (true) {
		uint32 ch = *src++;
		if ((ch == 0) || (ch == 10) || (ch == 13)) {
			count++;
			if (count <= arrayLength) {
				OBJ line = copyByteRange(start, src - 1);
				FIELD(array, count - 1) = line;
			}
			if ((ch == 13) && (*src == 10)) src++; // line ended in cr-lf
			if ((ch == 10) && (*src == 13)) src++; // line ended in lf-cr
			if (ch == 0) break;
			start = src;
		}
	}
	return count;
}

OBJ primLines(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	char *s = obj2str(args[0]);

	int lineCount = splitLines(s, nilObj, 0); // count lines
	int wordsNeeded = (lineCount * (HEADER_WORDS + 1)) + objWords(args[0]); // estimate
	if (!canAllocate(wordsNeeded)) return outOfMemoryFailure();
	OBJ result = newArray(lineCount);
	splitLines(s, result, lineCount); // collect lines

	return result;
}

static int splitWords(char *s, OBJ array, int arrayLength) {
	if (*s == 0) return 0; // empty string

	int count = 0;
	char *src = s;
	while (true) {
		uint32 ch = *src;
		while (ch && (ch <= 32)) ch = *(++src); // skip whitespace

		if (!ch) break; // end of string

		char *start = src;
		while (ch && (ch > 32)) ch = *(++src); // find end of word
		count++;
		if (count <= arrayLength) {
			OBJ word = copyByteRange(start, src);
			FIELD(array, count - 1) = word;
		}
	}
	return count;
}

OBJ primWords(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	char *s = obj2str(args[0]);

	int wordCount = splitWords(s, nilObj, 0); // count words
	int wordsNeeded = (wordCount * (HEADER_WORDS + 1)) + objWords(args[0]); // estimate
	if (!canAllocate(wordsNeeded)) return outOfMemoryFailure();
	OBJ result = newArray(wordCount);
	splitWords(s, result, wordCount); // collect words

	return result;
}

OBJ primByteCount(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	if (IS_CLASS(obj, BinaryDataClass)) return int2obj(objBytes(obj));
	if (IS_CLASS(obj, StringClass)) return int2obj(stringBytes(obj));
	return notStringOrBinaryFailure();
}

OBJ primByteAt(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ obj = args[0];
	int index = obj2int(args[1]);
	if (!isInt(args[1])) return indexClassFailure();

	unsigned char *bytes;
	int byteCount;
	if (IS_CLASS(obj, BinaryDataClass)) {
		bytes = (unsigned char *) BODY(obj);
		byteCount = objBytes(obj);
	} else if (IS_CLASS(obj, StringClass)) {
		bytes = (unsigned char *)obj2str(obj);
		byteCount = stringBytes(obj);
	} else {
		return notStringOrBinaryFailure();
	}
	if ((index < 1) || (index > byteCount)) return outOfRangeFailure();
	return int2obj(bytes[index - 1]);
}

OBJ primByteAtPut(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ obj = args[0];
	int index = obj2int(args[1]);
	int value = obj2int(args[2]);

	if (NOT_CLASS(obj, BinaryDataClass)) return primFailed("First argument of byteAtPut must be a BinaryData");
	if (!isInt(args[1])) return indexClassFailure();
	if (!isInt(args[2]) || (value < 0) || (value > 255)) {
		return primFailed("Value stored by byteAtPut must be an integer in the range 0-255");
	}

	unsigned char *bytes = (unsigned char *)BODY(obj);
	int byteCount = objBytes(obj);

	if ((index < 1) || (index > byteCount)) return outOfRangeFailure();
	bytes[index - 1] = value;
	return nilObj;
}

OBJ primReplaceByteRange(int nargs, OBJ args[]) {
	// Arguments: dstBinaryData first last srcBinaryData [srcStartIndex]
	if (nargs < 4) return notEnoughArgsFailure();
	OBJ dstObj = args[0];
	int first = intArg(1, -1, nargs, args);
	int last = intArg(2, -1, nargs, args);
	OBJ srcObj = args[3];
	int srcFirst = intArg(4, 1, nargs, args); // optional; default to 1

	int srcIsString = IS_CLASS(srcObj, StringClass);
	if (NOT_CLASS(dstObj, BinaryDataClass)) return primFailed("First argument must be a BinaryData");
	if (!(srcIsString || IS_CLASS(srcObj, BinaryDataClass))) return primFailed("Source must be a String or BinaryData");

	int dstByteCount = objBytes(dstObj);
	if (last < first) return nilObj;

	if ((first < 1) || (first > dstByteCount) ||
		(last < 1) || (last > dstByteCount)) {
			return outOfRangeFailure();
	}
	int srcByteCount = srcIsString ? stringBytes(srcObj) : objBytes(srcObj);
	if ((srcFirst < 1) || ((srcFirst + (last - first)) > srcByteCount)) {
		return outOfRangeFailure();
	}
	if ((srcObj == dstObj) && (srcFirst < first)) {
		// moving subrange up in same BinaryData; use decrementating index loop
		char *src = ((char *)BODY(srcObj)) + srcFirst + (last - first) - 1;
		char *dst = ((char *)BODY(dstObj)) + last - 1;
		char *end = ((char *)BODY(dstObj)) + first - 1;
		while (dst >= end) *dst-- = *src--;
	} else {
		char *src = ((char *)BODY(srcObj)) + srcFirst - 1;
		char *dst = ((char *)BODY(dstObj)) + first - 1;
		char *end = ((char *)BODY(dstObj)) + last - 1;
		while (dst <= end) *dst++ = *src++;
	}
	return nilObj;
}

OBJ primStringFromByteRange(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ srcObj = args[0];
	int first = intArg(1, -1, nargs, args);
	int last = intArg(2, -1, nargs, args);

	int byteCount = 0;
	if (IS_CLASS(srcObj, StringClass)) {
		byteCount = stringBytes(srcObj);
	} else if (IS_CLASS(srcObj, BinaryDataClass)) {
		byteCount = objBytes(srcObj);
	} else {
		return primFailed("Source must be a String or BinaryData");
	}

	if (last < first) return newString("");

	if ((first < 1) || (first > byteCount) || (last > byteCount)) {
		return outOfRangeFailure();
	}

	unsigned char *s = (unsigned char *) BODY(srcObj);
	// It perhaps should test that the destination is String or not and make sure it does not end up with having bunch of NULs
	return copyByteRange((char *) s + first - 1, (char *) s + last);
}

OBJ primString(int nargs, OBJ args[]) {
	if (!canAllocate(nargs / 4)) return outOfMemoryFailure();
	OBJ result = allocateString(nargs);
	unsigned char *s = (unsigned char *) obj2str(result);
	for (unsigned int i = 0; i < nargs; i++) {
		s[i] = obj2int(args[i]);
	}
	s[nargs] = '\0';
	if (isBadUTF8((char *) s)) return primFailed("Invalid UTF8 string");
	return result;
}

OBJ primParse(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();

	char *s = obj2str(args[0]);
	parser p;
	parse_setSourceString(&p, "<parse>", s, strlen(s));
	gp_boolean isCmdList = ('{' == parse_firstChar(&p));

	OBJ result = newArray(20);
	int i = 0;
	while (true) {
		OBJ expr = parse_nextScript(&p, false);
		if (IS_CLASS(expr, CmdClass) && (FIELD(expr, 5) == nilObj) && !isCmdList) {
			// if nextBlock is nil, convert expr to a reporter (helps with blockify)
			SETCLASS(expr, ReporterClass);
		}
		if (nilObj == expr) break;
		if (i >= objWords(result)) { // grow result
			result = copyObj(result, 2 * objWords(result), 1);
		}
		FIELD(result, i++) = expr;
	}
	result = copyObj(result, i, 1);
	return result;
}

// ***** UTF-8 Strings *****

#define REPLACEMENT_CHAR 0xFFFD;

static int utf8_next(unsigned char *s, int *byteIndex) {
	// Return the next UTF-8 code point starting at the given byteIndex,
	// or zero if there are no more code points. If utf8 is not well-formed
	// read at least one byte and return REPLACEMENT_CHAR.

	int result = 0;
	unsigned char *src = s + *byteIndex;
	unsigned char firstByte = *src++;
	if (!firstByte) return 0; // end of string

	if (firstByte < 128) { // common case
		(*byteIndex)++;
		return firstByte;
	}
	if ((firstByte & 0xC0) == 0x80) {
		goto error; // unexpected continuation byte
	} else if ((firstByte & 0xE0) == 0xC0) {
		result = ((firstByte & 0x1F) << 6);
		if ((*src & 0xC0) != 0x80) goto error;
		result |= *src++ & 0x3F;
	} else if ((firstByte & 0xF0) == 0xE0) {
		result = ((firstByte & 0x0F) << 12);
		if ((*src & 0xC0) != 0x80) goto error;
		result |= (*src++ & 0x3F) << 6;
		if ((*src & 0xC0) != 0x80) goto error;
		result |= *src++ & 0x3F;
	} else if ((firstByte & 0xF8) == 0xF0) {
		result = ((firstByte & 0x07) << 18);
		if ((*src & 0xC0) != 0x80) goto error;
		result |= (*src++ & 0x3F) << 12;
		if ((*src & 0xC0) != 0x80) goto error;
		result |= (*src++ & 0x3F) << 6;
		if ((*src & 0xC0) != 0x80) goto error;
		result |= *src++ & 0x3F;
	}
	if (result > 0x10FFFF) goto error;
	*byteIndex = src - s;
	return result;
error:
	*byteIndex = src - s;
	return REPLACEMENT_CHAR;
}

inline static int utf8_isCombining(int ch) {
	// Return true if the given Unicode codepoint is a combining character.

	if (ch < 0x300) return false;
	if (ch <= 0x36F) return true;

	if (ch < 0x1DC0) return false;
	if (ch <= 0x1DFF) return true;

	if (ch < 0x20D0) return false;
	if (ch <= 0x20FF) return true;

	if (ch < 0xFE20) return false;
	if (ch <= 0xFE2F) return true;

	return false;
}

static int utf8_skip(unsigned char *s, int *byteIndex) {
	// Skip the UTF-8 'letter' starting at the given byte index.
	// A letter may consist of multiple code points: a base
	// letter followed by several combining characters.
	// Return false when the end of the string is reached.

	uint32 ch1 = s[*byteIndex];
	if (ch1 < 128) (*byteIndex)++; // optimization: if ch1 is 7-bit, just increment *byteIndex
	else ch1 = utf8_next(s, byteIndex);
	if (ch1 == 0) return false; // end of string

	if (s[*byteIndex] < 128) return true; // next char is 7-bit; can't be a combining char

	// skip any following combining characters
	int peekIndex = *byteIndex;
	while (utf8_isCombining(utf8_next(s, &peekIndex))) *byteIndex = peekIndex;

	return true;
}

static int utf8_count(unsigned char *s) {
	// Count the 'letters' in the given UTF-8 string, where a
	// letter may actually a substring consisting of one or two
	// base letter plus several combining characters.

	int count = 0;
	int byteIndex = 0;
	while (true) {
		// optimization for 7-bit ascii:
		int ch = s[byteIndex];
		while (ch && (ch < 128)) {
			if (s[byteIndex + 1] >= 128) break; // following char might be combining
			count++;
			ch = s[++byteIndex];
		}
		// end optimization
		if (utf8_skip(s, &byteIndex)) count++;
		else break;
	}
	return count;
}

OBJ primSubstring(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	unsigned char *s = (unsigned char *) obj2str(args[0]);

	int start = intArg(1, 1, nargs, args);
	if (start < 1) start = 1;
	int end = intArg(2, 0x3FFFFFFF, nargs, args);
	int len = stringBytes(args[0]);
	if (end > len) end = len;
	if (start > end) return newString("");

	// find starting byte index
	int i = 1;
	int byteIndex = 0;
	while (i++ < start) {
		if (!utf8_skip(s, &byteIndex)) return newString(""); // start past end of string
	}
	int startIndex = byteIndex;

	// find ending byte index
	while (i++ <= (end + 1)) {
		if (!utf8_skip(s, &byteIndex)) break; // reached end of string
	}

	return copyByteRange((char *) s + startIndex, (char *) s + byteIndex);
}

OBJ primLetters(int nargs, OBJ args[]) {
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	unsigned char *s = (unsigned char *) obj2str(args[0]);

	int letterCount = utf8_count(s);
	int wordsNeeded = (letterCount * (HEADER_WORDS + 1)) + objWords(args[0]); // estimate
	if (!canAllocate(wordsNeeded)) return outOfMemoryFailure();
	OBJ array = newArray(letterCount);

	int startIndex = 0;
	int byteIndex = 0;
	for (int i = 0; i < letterCount; i++) {
		if (!utf8_skip((unsigned char *) s, &byteIndex)) return outOfRangeFailure(); // should not happen if utf8_count() is correct

		// create a UTF-8 string for the potentially multibyte 'letter' at the given index
		int byteCount = byteIndex - startIndex;
		OBJ charStr = newBinaryObj(StringClass, ((byteCount / 4) + 1));
		char *src = (char *)(s + startIndex);
		char *dst = (char *)BODY(charStr);
		char *stop = src + byteCount;
		for (char *s = src; s < stop; ) *dst++ = *s++; // faster than strncpy
		FIELD(array, i) = charStr; // add char to array
		startIndex = byteIndex;
	}
	return array;
}

OBJ primNextMatchIn(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	if (NOT_CLASS(args[1], StringClass)) return primFailed("Second argument must be a string");

	char *sought = obj2str(args[0]);
	char *stringToSearch = obj2str(args[1]);
	int i = intArg(0, 1, nargs, args);

	int soughtBytes = strlen(sought);
	int searchBytes = 4 * objWords(args[1]); // approximate; includes 1 to 4 terminator bytes
	if ((i < 1) || (i > (searchBytes - soughtBytes))) return nilObj;
	char *match = strstr(&stringToSearch[i - 1], sought);
	return match ? int2obj((match - stringToSearch) + 1) : nilObj;
}

// ***** Files *****

#ifdef _WIN32
// Functions used to convert between UTF8 and UTF16 ("wide" strings) on Windows.
// These functions should only be used translate file paths, not arbitrarily long strings.
// The maximum file path is 260 wide characters, so these buffers should be more than enough.

#define MAX_WIDE_COUNT 500
#define MAX_UTF8_COUNT 2000

WCHAR wideStringBuf[MAX_WIDE_COUNT];
char utf8StringBuf[MAX_UTF8_COUNT];

static char *wide2utf8(WCHAR *ws) {
	utf8StringBuf[0] = 0; // null terminate in case of failure
	WideCharToMultiByte(CP_UTF8, 0, ws, -1, utf8StringBuf, MAX_UTF8_COUNT, NULL, NULL);
	return utf8StringBuf;
}

static WCHAR *utf82wide(char *s) {
	wideStringBuf[0] = 0; // null terminate in case of failure
	MultiByteToWideChar(CP_UTF8, 0, s, -1, wideStringBuf, MAX_WIDE_COUNT);
	return wideStringBuf;
}
#endif

OBJ primReadFile(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	int isBinary = (nargs > 1) && (args[1] == trueObj);
#ifdef IOS
	char fileName[5000];
	ios_fullPath(obj2str(args[0]), fileName, 5000);
#else
	char *fileName = obj2str(args[0]);
#endif

#ifdef _WIN32
	FILE *f = _wfopen(utf82wide(fileName), L"rb"); // 'b' needed to avoid premature EOF on Windows
#else
	FILE *f = fopen(fileName, "rb"); // 'b' needed to avoid premature EOF on Windows
#endif
	if (!f) return nilObj; // file doesn't exist

	fseek(f, 0L, SEEK_END);
	long n = ftell(f); // get file size
	fseek(f, 0L, SEEK_SET);

	if (!canAllocate(n / 4)) return outOfMemoryFailure();
	OBJ result = isBinary ? newBinaryData(n) : allocateString(n);
	int count = fread(&FIELD(result, 0), sizeof(char), n, f);
	fclose(f);
	if (count < n) return primFailed("File read error");

	return result;
}

OBJ primWriteFile(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	OBJ data = args[1];
	if (!(IS_CLASS(data, StringClass) || IS_CLASS(data, BinaryDataClass))) {
		return primFailed("Can only write a String or BinaryData to a file");
	}
#ifdef IOS
	char fileName[5000];
	ios_fullPath(obj2str(args[0]), fileName, 5000);
#else
	char *fileName = obj2str(args[0]);
#endif
	int isBinary = IS_CLASS(data, BinaryDataClass);
	int byteCount = isBinary ? objBytes(data) : stringBytes(data);

#ifdef EMSCRIPTEN
	EM_ASM_({
		var fileName = UTF8ToString($0);
		fileName = fileName.slice(fileName.lastIndexOf('/') + 1);
		var src = $1;
		var isBinary = $2;
		var byteCount = $3;
		var mimeType = isBinary ? 'application/octet-stream' : 'text/plain;charset=utf-8';
		var buf = new Uint8Array(byteCount);
		for (var i = 0; i < byteCount; i++) {
			buf[i] = Module.HEAPU8[src++];
		}
		var blob = new Blob([buf], {type: mimeType});
		saveAs(blob, fileName);
	}, fileName, &FIELD(data, 0), isBinary, byteCount);
#else
  #ifdef _WIN32
	FILE *f = _wfopen(utf82wide(fileName), L"wb");
  #else
	FILE *f = fopen(fileName, "wb");
  #endif

	if (!f) {
		char err[1000];
		sprintf(err, "Could not open file for writing: %s", fileName);
		return primFailed(err);
	}
	int result = fwrite(&FIELD(data, 0), 1, byteCount, f);
	if (result < byteCount) return primFailed("cannot write the file");
	fclose(f);
#endif // EMSCRIPTEN

	return nilObj;
}

OBJ primDeleteFile(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
#ifdef IOS
	char fileName[5000];
	ios_fullPath(obj2str(args[0]), fileName, 5000);
#else
	char *fileName = obj2str(args[0]);
#endif

#ifdef _WIN32
	int err = _wremove(utf82wide(fileName));
#else
	int err = remove(fileName);
#endif
	if (err) primFailed("Delete failed");
	return nilObj;
}

OBJ primRenameFile(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass) || NOT_CLASS(args[1], StringClass) ) return primFailed("Both arguments must be strings");
#ifdef IOS
	char oldName[5000];
	char newName[5000];
	ios_fullPath(obj2str(args[0]), oldName, 5000);
	ios_fullPath(obj2str(args[1]), newName, 5000);
#else
	char *oldName = obj2str(args[0]);
	char *newName = obj2str(args[1]);
#endif

#ifdef _WIN32
	WCHAR newNameWide[500];
	newNameWide[0] = 0; // null terminate
	MultiByteToWideChar(CP_UTF8, 0, newName, -1, newNameWide, 500);
	int err = _wrename(utf82wide(oldName), newNameWide);
#else
	int err = rename(oldName, newName);
#endif
	if (err) primFailed("Rename failed");
	return nilObj;
}

OBJ primSetFileMode(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	if (!isInt(args[1])) return primFailed("Second argument (file mode) must be an integer");
#ifdef IOS
	char fileName[5000];
	ios_fullPath(obj2str(args[0]), fileName, 5000);
#else
	char *fileName = obj2str(args[0]);
#endif

#ifdef _WIN32
	// NOTE: Windows only supports two flags: read = 256 and write = 128
	// There is no execute flag. Files are aways readable, so only the presence
	// or absence of the write flag makes any difference.
	_wchmod(utf82wide(fileName), obj2int(args[1]));
#else
	chmod(fileName, obj2int(args[1]));
#endif
	return nilObj;
}

OBJ directoryContents(char *dirName, int listDirectories) {
#ifdef IOS
	return ios_directoryContents(dirName, listDirectories);
#elif defined(_WIN32)
	OBJ result = newArray(100);
	int i = 0;
	WCHAR pathWithWildcard[500];
	WIN32_FIND_DATAW info;

	if (0 == strcmp(dirName, "/")) {
		// enumerate drive names
		uint32 driveBits = GetLogicalDrives();
		char driveName[4];
		strcpy(driveName, "_:"); // template for drive name
		for (int j = 0; j < 25; j++) {
			if (driveBits & 1) {
				driveName[0] = 65 + j; // drive letter
				FIELD(result, i++) = newString(driveName);
			}
			driveBits = driveBits >> 1;
		}
	} else {
		pathWithWildcard[0] = 0; // null terminate
		if (strlen(dirName)) {
			// if dirName is not empty, append "/*" to it
			wcscpy(pathWithWildcard, utf82wide(dirName));
			wcscat(pathWithWildcard, L"\\*");
		} else {
			// otherwise use "*" as the search string
			wcscpy(pathWithWildcard, L"*");
		}
		HANDLE hFind = FindFirstFileW(pathWithWildcard, &info);
		if (INVALID_HANDLE_VALUE != hFind) {
			do {
				int isDir = (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
				if (isDir != listDirectories) continue; // skip
				if ((wcscmp(info.cFileName, L".") == 0) || (wcscmp(info.cFileName, L"..") == 0)) {
					continue; // don't include "." and ".." in directory list
				}
				if (info.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN) {
					continue; // don't include hidden files and folders
				}
				if (i >= objWords(result)) { // grow result
					result = copyObj(result, 2 * objWords(result), 1);
				}
				FIELD(result, i++) = newString(wide2utf8(info.cFileName));
			} while (FindNextFileW(hFind, &info) != 0);
		}
		FindClose(hFind);
	}
	result = copyObj(result, i, 1);
	return result;
#else
	if (dirName[0] == 0) dirName = ".";
	OBJ result = newArray(100);
	int i = 0;

	DIR *dir = opendir(dirName);
	if (dir) {
		struct dirent *ep;
		while ((ep = readdir(dir))) {
			if (!listDirectories || (DT_DIR == ep->d_type)) {
				if ((strcmp(ep->d_name, ".") == 0) || (strcmp(ep->d_name, "..") == 0)) {
					continue; // don't include "." and ".." in results
				}
				if (strcmp(ep->d_name, ".DS_Store") == 0) {
					continue; // don't include ".DS_Store" in results
				}
				if ((DT_DIR == ep->d_type) && !listDirectories) {
					continue; // don't include directories when listing files
				}
				if (i >= objWords(result)) { // grow result
					result = copyObj(result, 2 * objWords(result), 1);
				}
				FIELD(result, i++) = newString(ep->d_name);
			}
		}
		closedir(dir);
	}
	result = copyObj(result, i, 1);
	return result;
#endif
}

OBJ primListFiles(int nargs, OBJ args[]) {
	char *dir = ".";
	if (nargs > 0) {
		if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
		dir = obj2str(args[0]);
	}
	return directoryContents(dir, false);
}

OBJ primListDirectories(int nargs, OBJ args[]) {
	char *dir = ".";
	if (nargs > 0) {
		if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
		dir = obj2str(args[0]);
	}
	return directoryContents(dir, true);
}

OBJ primMakeDirectory(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
#ifdef IOS
	char dirName[5000];
	ios_fullPath(obj2str(args[0]), dirName, 5000);
#else
	char *dirName = obj2str(args[0]);
#endif

#ifdef _WIN32
	_wmkdir(utf82wide(dirName));
#else
	mkdir(dirName, 0755);
#endif
	return nilObj;
}

OBJ primAbsolutePath(int nargs, OBJ args[]) {
	char absolutePath[5001]; // max path is 4096 on many Linux systems
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();

	absolutePath[0] = 0; // empty string in case of failure
#ifdef _WIN32
	#define ABS_PATH_SIZE 500
	WCHAR wideResult[ABS_PATH_SIZE];
	int len = GetFullPathNameW(utf82wide(obj2str(args[0])), 500, wideResult, NULL);
	if ((len == 0) || (len >= ABS_PATH_SIZE)) {
		return newString("");  // ignore error and return empty string
	}
	char *result = wide2utf8(wideResult);

	// replace backslashes with GP-standard forward slashes
	len = strlen(result);
	for (int i = 0; i < len; i++) {
	  int ch = result[i];
	  if ('\\' == ch) result[i] = '/';
	  if (ch == 0) break;
	}
	return newString(result);
#elif defined(EMSCRIPTEN)
	return args[0];  // EMSCRIPTEN doesn't support realpath(); return the original path
#elif defined(IOS)
	return ios_absolutePath(obj2str(args[0]));
#else
	if (!realpath(obj2str(args[0]), absolutePath)) {
		/* ignore error and return empty string */;
	}
#endif
	absolutePath[5000] = 0; // ensure null termination
	return newString(absolutePath);
}

OBJ primAppPath(int nargs, OBJ args[]) {
#ifdef IOS
	return newString("/GP");
#else
	return appPath();
#endif
}

OBJ primUserHomePath(int nargs, OBJ args[]) {
#ifdef IOS
	// No prefix; this is the root of the iTunes-visible app folder in IOS
	return newString("");
#elif defined(_WIN32)
	if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PROFILE, NULL, 0, wideStringBuf))) {
		return newString(wide2utf8(wideStringBuf));
	}
#else
	char *homePath = getenv("HOME");
	if (homePath) return newString(homePath);
#endif
	return newString("");
}

OBJ primListEmbeddedFiles(int nargs, OBJ args[]) {
	#ifdef EMSCRIPTEN
		// Optional args: directoryToList, listDirsFlag
		char *path = ((nargs > 0) && IS_CLASS(args[0], StringClass)) ? obj2str(args[0]) : "";
		int dirsFlag = ((nargs > 1) && (trueObj == args[1]));
		return directoryContents(path, dirsFlag);
	#endif

	FILE *f = openAppFile();
	if (!f) return nilObj;

	OBJ result = embeddedFileList(f);
	fclose(f);
	return result;
}

OBJ primReadEmbeddedFile(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return firstArgMustBeString();
	int isBinary = (nargs > 1) && (args[1] == trueObj);

	#ifdef EMSCRIPTEN
		return primReadFile(nargs, args);
	#endif

	FILE *f = openAppFile();
	if (!f) return nilObj;

	OBJ result = extractEmbeddedFile(f, obj2str(args[0]), isBinary);
	fclose(f);
	return result;
}

// ***** File Streams *****

static FILE* obj2file(OBJ refObj);

static void finalizeFileStream(OBJ refObj) {
	FILE *file = obj2file(refObj);
	if (!file) return; // invalid refObj or already closed

	fclose(file);
	ADDR *a = (ADDR*)BODY(refObj);
	a[0] = NULL;
}

static FILE* obj2file(OBJ refObj) {
	// Return the file handle from the given external reference or NULL if refObj is not valid.

	if (isInt(refObj) || (refObj <= falseObj)) return NULL;

	ADDR *a = (ADDR*)BODY(refObj);
	if (NOT_CLASS(refObj, ExternalReferenceClass) ||
		(objWords(refObj) < ExternalReferenceWords) ||
		(a[1] != (ADDR) finalizeFileStream)) {
			primFailed("Invalid file stream");
			return NULL;
	}
	return (FILE *) a[0];
}

OBJ primOpenFilestream(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("File name must be a string");

	FILE *file = fopen(obj2str(args[0]), "r"); // open for reading
	if (!file) return primFailed("Could not open file.");

	OBJ result = newBinaryObj(ExternalReferenceClass, ExternalReferenceWords);
	ADDR *a = (ADDR*)BODY(result);
	a[0] = (ADDR) ((long) file);
	a[1] = (ADDR) finalizeFileStream;
	return result;
}

OBJ primFilestreamReadByte(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	FILE *file = obj2file(args[0]);
	if (!file) return primFailed("Needs an open file stream");

	int byte = fgetc(file);
	return (EOF == byte) ? nilObj : int2obj(byte); // return nil on end of file
}

OBJ primFilestreamReadLine(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	FILE *file = obj2file(args[0]);
	if (!file) return primFailed("Needs an open file stream");

	char lineBuf[1001];
	int i = 0;
	while (true) {
		int byte = fgetc(file);
		if (EOF == byte) {
			if (0 == i) return nilObj; // nothing in buffer; return nil to indicate end of file
			break; // return final line
		}
		if ((10 == byte) || (13 == byte)) {
			int nextByte = fgetc(file);
			if ((10 == byte) && (13 != nextByte)) ungetc(nextByte, file);
			if ((13 == byte) && (10 != nextByte)) ungetc(nextByte, file);
			break;
		}
		lineBuf[i++] = byte;
		if (1000 == i) break;
	}
	lineBuf[i] = 0; // null terminate
	return newString(lineBuf);
}

OBJ primCloseFilestream(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	finalizeFileStream(args[0]);
	return nilObj;
}

// ***** Time *****

OBJ primMSecsSinceStart(int nargs, OBJ args[]) {
	struct timeval now;
	gettimeofday(&now, NULL);
	int secs = now.tv_sec - startTime.tv_sec;
	int usecs = now.tv_usec - startTime.tv_usec;
	return int2obj(((1000 * secs) + (usecs / 1000)) & 0x3FFFFFFF);
}

OBJ primTime(int nargs, OBJ args[]) {
	const long gpEpoch = 946684800; // Midnight, Jan 1, 2000
	struct timeval now;
	struct timezone tz;
	gettimeofday(&now, &tz);
	long minutesWest = 0;
	int isDST = false;

#ifdef _WIN32
	TIME_ZONE_INFORMATION timeZoneInfo;
	DWORD zoneResult = GetTimeZoneInformation(&timeZoneInfo);
	isDST = (zoneResult == TIME_ZONE_ID_DAYLIGHT);
	minutesWest = timeZoneInfo.Bias;
#else
	minutesWest = tz.tz_minuteswest;
	isDST = (localtime(&now.tv_sec))->tm_isdst;
#endif

	OBJ result = newArray(4);
	FIELD(result, 0) = int2obj(now.tv_sec - gpEpoch);
	FIELD(result, 1) = int2obj(now.tv_usec);
	FIELD(result, 2) = int2obj(60 * minutesWest);
	FIELD(result, 3) = isDST ? trueObj : falseObj;
	return result;
}

OBJ primSleep(int nargs, OBJ args[]) {
	int msecs = intArg(0, 0, nargs, args);
	if (IS_CLASS(args[0], FloatClass)) {
		msecs = (int) evalFloat(args[0]);
	}
	if (msecs <= 0) return nilObj;
#ifdef _WIN32
	_sleep(msecs); // from mingw; deprecated, but still works
#elif defined(EMSCRIPTEN)
	usleep(msecs * 1000);
#else
	struct timespec sleepTime;
	sleepTime.tv_sec = msecs / 1000;
	sleepTime.tv_nsec = 1000000 * (msecs % 1000);
	while ((nanosleep(&sleepTime, &sleepTime) == -1) && (errno == EINTR)) /* restart if interrupted */;
#endif
	return nilObj;
}

// ***** Functions *****

static OBJ primDefineFunction(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();

	OBJ functionName = args[0];
	if (NOT_CLASS(functionName, StringClass)) return primFailed("Function name must be a String");

	// collect argument names
	OBJ argNames = newArray(nargs - 2);
	for (int i = 1; i < nargs - 1; i++) {
		FIELD(argNames, i - 1) = args[i];
	}
	OBJ cmdList = args[nargs - 1];
	return addMethod(nilObj, functionName, argNames, currentModule, cmdList, true);
}

OBJ primNewFunction(int nargs, OBJ args[]) {
	// Return a new anonymous function.
	if (nargs < 1) return notEnoughArgsFailure();

	// collect argument names
	OBJ argNames = newArray(nargs - 1);
	for (int i = 0; i < nargs - 1; i++) {
		FIELD(argNames, i) = args[i];
	}
	OBJ cmdList = args[nargs - 1];
	return addMethod(nilObj, nilObj, argNames, currentModule, cmdList, false);
}

OBJ primPrimitiveNames(int nargs, OBJ args[]) {
	OBJ primitiveNames(); // forward reference
	return primitiveNames();
}

OBJ primGlobalFuncs(int nargs, OBJ args[]) {
	return FIELD(topLevelModule, Module_Functions);
}

// ***** Objects *****

OBJ classNameMustBeString() { return primFailed("Class name must be a string"); }
OBJ badFieldIndexFailure() { return primFailed("Object has no field with that name or index or contains binary data"); }

OBJ primDefineClass(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return classNameMustBeString();
	OBJ module = currentModule;
	if (!module) module = topLevelModule; // a hack until we go into parser
	OBJ classObj = defineClass(args[0], module);
	for (int i = 1; i < nargs; i++) {
		OBJ fieldName = args[i];
		if (NOT_CLASS(fieldName, StringClass)) return primFailed("Expected string arguments");
		addField(classObj, fieldName);
	}
	return classObj;
}

OBJ primAddClassComment(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return classNameMustBeString();
	if (NOT_CLASS(args[1], StringClass)) return primFailed("Class comment must be a string");
	OBJ classObj = classFromNameInModule(args[0], currentModule);
	if (!classObj) {
		char err[1000];
		sprintf(err, "Unknown class '%s'", obj2str(args[0]));
		return primFailed(err);
	}
	OBJ comments = FIELD(classObj, 4);
	if (IS_CLASS(comments, ArrayClass)) {
		comments = copyArrayWith(comments, args[1]);
	} else {
		comments = newArray(1);
		FIELD(comments, 0) = args[1];
	}
	FIELD(classObj, 4) = comments;
	return nilObj;
}

OBJ primClasses(int nargs, OBJ args[]) {
	// Note: Copy into Array rather than returning a WeakArray.
	// This also protects the class table from inadvertent corruption.
	int count = objWords(classes);
	OBJ result = newArray(count);
	int dst = 0;
	for (int i = 0; i < count; i++) {
		OBJ class = FIELD(classes, i);
		if (class) FIELD(result, dst++) = class;
	}
	if (dst < count) {
		// remove unused slots from result
		result = copyObj(result, dst, 1);
	}
	return result;
}

OBJ primClass(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (isInt(args[0])) {
		int i = obj2int(args[0]);
		if ((i < 1) || (i > objWords(classes))) return primFailed("Class index out of range");
		return FIELD(classes, i - 1);
	}
	if (NOT_CLASS(args[0], StringClass)) return classNameMustBeString();
	return classFromNameInModule(args[0], currentModule);
}

static OBJ primAddClass(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ classObj = args[0];
	if (NOT_CLASS(classObj, ClassClass)) return primFailed("Argument must be a class.");
	int classesSize = objWords(classes);
	for (int i = 0; i < classesSize; i++) {
		if (FIELD(classes, i) == classObj) return nilObj; // already in classes array
	}
	addClass(classObj);
	return nilObj;
}

OBJ primClassOf(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	return classFromIndex(objClass(args[0]));
}

OBJ primIsClass(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ objCls = classFromIndex(objClass(args[0]));
	if (NOT_CLASS(args[1], StringClass)) {
		if (IS_CLASS(args[1], ClassClass)) return ((objCls == args[1]) ? trueObj : falseObj);
		return primFailed("Second argument must be a string or a class");
	}
	OBJ objModule = FIELD(objCls, 6);
	OBJ clsName = FIELD(objCls, 0);
	// There are several cases if we are to avoid linear scan (especially in the top-level module):
	// (1) The most common case: objModule and currentModule are both top-level. Then, the class names must match.
	// (2) Neither objModule nor currentModule is top-level
	//     The modules have to be the same and the names should match
	// (3) objModule is top-level but currentModule is not
	//     The class name is resolved in currentModule first.
	//     If the class exists, objModule must be equal to currentModule and the names must match.
	//     If the class name does not exist in currentModule, it is resolved in top-level.
	// (4) objModule is not top-level but currentModule is
	//     Result is false
	// printf("isClass: %s, %s\n", obj2str(clsName), obj2str(args[1]));
	if (objModule == currentModule) {
		return bool2obj(strcmp(obj2str(clsName), obj2str(args[1])) == 0); // case (1) and (2)
	}
	if (objModule == topLevelModule) { // case (3)
		OBJ cls = classFromNameInModuleNoDelegate(args[1], currentModule);
		if (cls) {
			return falseObj; // like, a call (isClass 42 'MyClass') in the module of MyClass
		}
		// like, a call (isClass 'foo' 'String') in a user module
		return bool2obj(strcmp(obj2str(clsName), obj2str(args[1])) == 0);
	}
	return falseObj; // case (4);
}

static OBJ primAddMethod(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ methodName = args[0];
	if (NOT_CLASS(methodName, StringClass)) return primFailed("Method name must be a String");

	OBJ module = currentModule;
	if (!module) module = topLevelModule; // a hack until we go into parser

	OBJ classObj = nilObj;
	if (IS_CLASS(args[1], StringClass)) {
		classObj = classFromNameInModuleNoDelegate(args[1], module);
	} else if (IS_CLASS(args[1], ClassClass)) {
		classObj = args[1];
	} else {
		return primFailed("Class must be a string or a class");
	}

	if (!classObj) {
		char err[1000];
		sprintf(err, "Missing class '%s' for method '%s'", obj2str(args[1]), obj2str(args[0]));
		return primFailed(err);
	}

	// collect argument names
	OBJ argNames = newArray(nargs - 2);
	FIELD(argNames, 0) = newString("this"); // the first arg of a method is always "this"
	for (int i = 2; i < nargs - 1; i++) {
		FIELD(argNames, i - 1) = args[i];
	}
	OBJ cmdList = args[nargs - 1];
	return addMethod(classObj, methodName, argNames, module, cmdList, true);
}

OBJ primNew(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ result = newInstance(args[0], 0);
	if (!result) return nilObj;
	int initialValues = (nargs - 1);
	if (objWords(result) < initialValues) initialValues = objWords(result);
	for (int i = 0; i < initialValues; i++) FIELD(result, i) = args[i + 1];
	return result;
}

OBJ primNewIndexable(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	int indexableFields = intArg(1, 0, nargs, args);
	OBJ result = newInstance(args[0], indexableFields);
	if (!result) return nilObj;
	int initialValues = (nargs - 2);
	if (objWords(result) < initialValues) initialValues = objWords(result);
	for (int i = 0; i < initialValues; i++) FIELD(result, i) = args[i + 2];
	return result;
}

OBJ primNewBinaryData(int nargs, OBJ args[]) {
	int byteCount = intArg(0, 0, nargs, args);
	if (byteCount < 0) return sizeFailure();
	if (!canAllocate(byteCount / 4)) return outOfMemoryFailure();
	OBJ result = newBinaryData(byteCount);
	if (!result) return outOfMemoryFailure();
	return result;
}

OBJ primClone(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!canAllocate(objWords(args[0]))) return outOfMemoryFailure();
	return cloneObj(args[0]);
}

OBJ primGetField(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ obj = args[0];
	for (int i = 1; i < nargs; i++) {
		int fieldIndex = getFieldIndex(obj, args[i]);
		if (fieldIndex < 0) return badFieldIndexFailure();
		obj = FIELD(obj, fieldIndex);
	}
	return obj;
}

OBJ primSetField(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ obj = args[0];
	for (int i = 1; i < nargs - 2; i++) {
		if (!HAS_OBJECTS(obj)) return primFailed("Binary object in setField path");
		int fieldIndex = getFieldIndex(obj, args[i]);
		if (fieldIndex < 0) return badFieldIndexFailure();
		obj = FIELD(obj, fieldIndex);
	}
	int fieldIndex = getFieldIndex(obj, args[nargs - 2]);
	if (fieldIndex < 0) return badFieldIndexFailure();
	OBJ newValue = args[nargs - 1];
	if (HAS_OBJECTS(obj)) {
		FIELD(obj, fieldIndex) = newValue;
	} else {
		return primFailed("Cannot use setField on an immutable object or an object containing binary data such as a string");
	}
	return nilObj;
}

OBJ primToString(int nargs, OBJ args[]) {
	char s[1000];
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	int precision = clip(intArg(1, 6, nargs, args), 1, 16);

	if (isInt(obj)) {
		sprintf(s, "%d", obj2int(obj));
		return newString(s);
	}
	if (IS_CLASS(obj, StringClass)) return obj;
	if (IS_CLASS(obj, FloatClass)) {
		double n = obj2double(obj);
		if (n == (int) n) sprintf(s, "%.1f", n); // print trailing ".0"
		else sprintf(s, "%.*g", precision, n);
		// if s doesn't contain a decimal point or 'e', add ".0" to indicate that it is a float
		if (!strchr(s, '.') && !strchr(s, 'e')) strncat(s, ".0", 999);
		return newString(s);
	}
	if (nilObj == obj) return newString("nil");
	if (trueObj == obj) return newString("true");
	if (falseObj == obj) return newString("false");
	sprintf(s, "<%s>", getClassName(obj));
	return newString(s);
}

// ***** Data Compression *****

// Raw deflate/inflate mode: no header or checksum
#define Z_RAW -15

OBJ zlibError(int err) {
	char msg[100];
	sprintf(msg, "Zlib error %d", err);
	primFailed(msg);
	return nilObj;
}

OBJ primZlibDeflate(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (!(IS_CLASS(data, StringClass) || IS_CLASS(data, BinaryDataClass))) {
		return primFailed("Argument must be a String or BinaryData");
	}

	int compression = clip(intArg(1, Z_DEFAULT_COMPRESSION, nargs, args), -1, 9);
	int strategy = clip(intArg(2, Z_DEFAULT_STRATEGY, nargs, args), 0, 4);

	int rc;
	z_stream strm;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;

	rc = deflateInit2(&strm, compression, Z_DEFLATED, Z_RAW, 8, strategy);
	if (rc < 0) return zlibError(rc);

	int originalSize = IS_CLASS(data, StringClass) ? stringBytes(data) : objBytes(data);
	int bufSize = deflateBound(&strm, originalSize);
	OBJ buf = newBinaryData(bufSize);
	if (!buf) return outOfMemoryFailure();

	strm.next_out = (unsigned char *) &FIELD(buf, 0);
	strm.avail_out = bufSize;
	strm.next_in = (unsigned char *) &FIELD(data, 0);
	strm.avail_in = originalSize;

	rc = deflate(&strm, Z_FINISH);
	deflateEnd (&strm);
	if (rc < 0) return zlibError(rc);

	int compressedSize = bufSize - strm.avail_out;
	if (!canAllocate(compressedSize / 4)) return outOfMemoryFailure();
	OBJ result = newBinaryData(compressedSize);
	if (!result) return outOfMemoryFailure();

	OBJ *src = &FIELD(buf, 0);
	OBJ *dst = &FIELD(result, 0);
	OBJ *end = dst + objWords(result);
	while (dst < end) { *dst++ = *src++; }

	return result;
}

OBJ primZlibInflate(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (NOT_CLASS(data, BinaryDataClass)) return primFailed("First argument must be a BinaryData");

	int isString = (nargs > 1) && (args[1] == trueObj);

	int rc;
	z_stream strm;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;

	rc = inflateInit2(&strm, Z_RAW);
	if (rc < 0) return zlibError(rc);

	int compressedSize = objBytes(data);
	int bufWords = compressedSize / 2;
	if (bufWords < 10000) bufWords = 10000;

	strm.next_in = (unsigned char *) &FIELD(data, 0);
	strm.avail_in = compressedSize;

	OBJ buffers = newArray(0);
	int bufCount = 0;
	int resultSize = 0;
	int lastBufSize = 0;
	OBJ buf;
	while (true) {
		bufCount++;
		buf = newBinaryObj(BinaryDataClass, bufWords);
		buffers = copyArrayWith(buffers, buf);
		strm.next_out = (unsigned char *) &FIELD(buf, 0);
		strm.avail_out = bufWords * 4;
		rc = inflate(&strm, Z_NO_FLUSH);
		if (rc < 0) {
			inflateEnd(&strm);
			return zlibError(rc);
		}
		lastBufSize = ((bufWords * 4) - strm.avail_out);
		resultSize += lastBufSize;
		if (strm.avail_out > 0) break; // done!
	}
	inflateEnd(&strm);

	if (!canAllocate(resultSize / 4)) return outOfMemoryFailure();
	OBJ result = isString ? allocateString(resultSize) : newBinaryData(resultSize);

	// copy all buffers into result
	OBJ *dst = &FIELD(result, 0);
	for (int i = 0; i < bufCount; i++) {
		buf = FIELD(buffers, i);
		OBJ *src = &FIELD(buf, 0);
		OBJ *end = src + objWords(buf);
		if (i == (bufCount - 1)) { end = src + ((lastBufSize + 3) / 4); }
		while (src < end) { *dst++ = *src++; }
	}
	return result;
}

OBJ primZlibCRC(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (!(IS_CLASS(data, StringClass) || IS_CLASS(data, BinaryDataClass))) {
		return primFailed("First argument must be a String or BinaryData");
	}
	int addlerFlag = (nargs > 1) && (args[1] == trueObj);

	unsigned char *buf = (unsigned char *) &FIELD(data, 0);
	unsigned int byteCount = IS_CLASS(data, StringClass) ? stringBytes(data) : objBytes(data);

	unsigned int checksum = addlerFlag ? adler32(0, Z_NULL, 0) : crc32(0, Z_NULL, 0);
	if (nargs > 2) {
		OBJ arg2 = args[2];
		if (isInt(arg2) || IS_CLASS(arg2, LargeIntegerClass)) {
			checksum = uint32Value(arg2);
		}
	}
	checksum = addlerFlag ? adler32(checksum, buf, byteCount) : crc32(checksum, buf, byteCount);
	return uint32Obj(checksum);
}

OBJ primSHA256(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (!(IS_CLASS(data, StringClass) || IS_CLASS(data, BinaryDataClass))) {
		return primFailed("First argument must be a String or BinaryData");
	}
	unsigned char *buf = (unsigned char *)BODY(data);
	unsigned int byteCount = IS_CLASS(data, StringClass) ? stringBytes(data) : objBytes(data);

	char result[SHA256_DIGEST_STRING_LENGTH];

	SHA256_Data(buf, byteCount, result);
	return newString(result);
}

OBJ primSHA1(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (!(IS_CLASS(data, StringClass) || IS_CLASS(data, BinaryDataClass))) {
		return primFailed("First argument must be a String or BinaryData");
	}
	unsigned char *buf = (unsigned char *)BODY(data);
	unsigned int byteCount = IS_CLASS(data, StringClass) ? stringBytes(data) : objBytes(data);
	char hash[21];

	SHA1(hash, (const char *) buf, byteCount);

	// copy the hash into BinaryData object
	OBJ result = newBinaryData(20);
	if (!result) return outOfMemoryFailure();
	char *dst = (char *) &FIELD(result, 0);
	for (int i = 0; i < 20; i++) {
		*dst++ = hash[i];
	}
	return result;
}

// ***** Pixel Manipulation *****

static OBJ failedBadPixelData() { return primFailed("PixelData must be BinaryData"); }
static OBJ failedBadPixelOffset() { return primFailed("Bad pixel offset"); }

static int isBitmap(OBJ bitmap) {
	return
	(objWords(bitmap) >= 3) &&
	isInt(FIELD(bitmap, 0)) && isInt(FIELD(bitmap, 1)) &&
	IS_CLASS(FIELD(bitmap, 2), BinaryDataClass);
}

OBJ primGetPixelAlpha(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (NOT_CLASS(data, BinaryDataClass)) return failedBadPixelData();
	int offset = intArg(1, -1, nargs, args) - 1; // convert to zero-based offset
	if ((offset < 0) || (offset >= objWords(data))) return failedBadPixelOffset();
	int pixel = (int) FIELD(data, offset);
	return int2obj((pixel >> 24) & 0xFF);
}

OBJ primGetPixelRGB(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (NOT_CLASS(data, BinaryDataClass)) return failedBadPixelData();
	int offset = intArg(1, -1, nargs, args) - 1; // convert to zero-based offset
	if ((offset < 0) || (offset >= objWords(data))) return failedBadPixelOffset();
	int pixel = (int) FIELD(data, offset);
	return int2obj(pixel & 0xFFFFFF);
}

OBJ primSetPixelRGBA(int nargs, OBJ args[]) {
	// Set the given pixel color at the given offset in a BinaryData object.
	// Arguments: binaryData pixelOffset [red green blue alpha]
	// If the optional alpha argument is omitted it is taken to be 255 (opaque).

	if (nargs < 2) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (NOT_CLASS(data, BinaryDataClass)) return failedBadPixelData();
	int offset = intArg(1, -1, nargs, args) - 1; // convert to zero-based offset
	if ((offset < 0) || (offset >= objWords(data))) return failedBadPixelOffset();

	int red = intArg(2, 0, nargs, args) & 255;
	int green = intArg(3, 0, nargs, args) & 255;
	int blue = intArg(4, 0, nargs, args) & 255;
	int alpha = intArg(5, 255, nargs, args) & 255;

	FIELD(data, offset) = ((alpha << 24) | (red << 16) | (green << 8) | blue); // okay to store raw integer in BinaryData
	return nilObj;
}

OBJ primFillPixels(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();

	OBJ data = args[0];
	if (NOT_CLASS(data, BinaryDataClass)) return failedBadPixelData();

	int red = intArg(1, 0, nargs, args) & 255;
	int green = intArg(2, 0, nargs, args) & 255;
	int blue = intArg(3, 0, nargs, args) & 255;
	int alpha = intArg(4, 255, nargs, args) & 255;
	uint32 pixel = ((alpha << 24) | (red << 16) | (green << 8) | blue);

	ADDR dst = BODY(data);
	ADDR end = BODY(data) + objWords(data) - 1;
	while (dst <= end) *dst++ = pixel;

	return nilObj;
}

// ***** Graphics Operations *****

OBJ primApplyMask(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ dstBM = args[0];
	OBJ maskBM = args[1];
	int reverse = ((nargs > 2) && (args[2] == trueObj));

	if (!isBitmap(dstBM)) return primFailed("First argument must be a Bitmap");
	if (!isBitmap(maskBM)) return primFailed("Second argument must be a Bitmap");
	if ((FIELD(dstBM, 0) != FIELD(maskBM, 0)) ||
		(FIELD(dstBM, 1) != FIELD(maskBM, 1))) {
			return primFailed("Target and mask bitmaps must have the same dimensions");
	}
	int pixelCount = objWords(FIELD(dstBM, 2));
	int *maskPixels = (int *) &FIELD(FIELD(maskBM, 2), 0);
	int *dstPixels = (int *) &FIELD(FIELD(dstBM, 2), 0);
	int *end = dstPixels + pixelCount;

	if (reverse) {
		while (dstPixels < end) {
			int maskAlpha = (((*maskPixels++) >> 24) & 255);
			if (maskAlpha > 0) { *dstPixels = 0; }
			dstPixels++;
		}
	} else {
		while (dstPixels < end) {
			int maskAlpha = (((*maskPixels++) >> 24) & 255);
			if (maskAlpha < 250) { *dstPixels = 0; } // using 250 allows for rounding errors in alpha blending
			dstPixels++;
		}
	}
	return nilObj;
}

static int isColor(OBJ color) {
	return
		(objWords(color) >= 4) &&
		isInt(FIELD(color, 0)) && isInt(FIELD(color, 1)) &&
		isInt(FIELD(color, 2)) && isInt(FIELD(color, 3));
}

OBJ primFloodFill(int nargs, OBJ args[]) {
	if (nargs < 4) return notEnoughArgsFailure();
	OBJ bitmap = args[0];
	int seedX = intOrFloatArg(1, 0, nargs, args);
	int seedY = intOrFloatArg(2, 0, nargs, args);
	OBJ fillColor = args[3];
	int threshold = intOrFloatArg(4, 0, nargs, args);

	if (!isColor(fillColor)) return primFailed("Bad color");
	int newR = obj2int(FIELD(fillColor, 0)) & 255;
	int newG = obj2int(FIELD(fillColor, 1)) & 255;
	int newB = obj2int(FIELD(fillColor, 2)) & 255;
	int newA = obj2int(FIELD(fillColor, 3)) & 255;
	uint32 newColor = (newA << 24) | (newR << 16) | (newG << 8) | newB;

	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	uint32 *pixels = &(FIELD(FIELD(bitmap, 2), 0));

	// create a mask with zeros for RGB bits to ignore
	if (threshold < 0) threshold = 0;
	if (threshold > 7) threshold = 7;
	int mask = ((255 << threshold) & 255);
	mask = (mask << 16) | (mask << 8) | mask;

	if ((seedX < 0) || (seedX >= w) || (seedY < 0) || (seedY >= h)) {
//		printf("Flood fill seed point (%d, %d) is outside of bitmap (%d x %d)\n", seedX, seedY, w, h);
		return nilObj;
	}
	int matchRGB = pixels[(seedY * w) + seedX] & mask;

	// flags to mark processed pixels; processed[i] is set to 1 when pixel i is processed
	OBJ processedObj = newBinaryData(w * h);
	if (!processedObj) return nilObj;
	char *processed = (char *) &FIELD(processedObj, 0); // initially all zero (false)

	// stack used to keep track of x,y values to be processed
	int todoStack[10000];
	int todoIndex = 0;
	int todoLimit = (sizeof(todoStack) / sizeof(int)) - 2;
	todoStack[todoIndex++] = seedX;
	todoStack[todoIndex++] = seedY;

	while (todoIndex > 0) {
		int y = todoStack[--todoIndex];
		int x = todoStack[--todoIndex];
		int lineStart = y * w;
		int lineEnd = lineStart + w - 1;
		int left = lineStart + x;
		int right = left;
		int i;

		// find and process span of matching pixels within the current line
		while ((left > lineStart) && ((pixels[left - 1] & mask) == matchRGB)) left -= 1;
		while ((right < lineEnd) && ((pixels[right + 1] & mask) == matchRGB)) right += 1;
		for (i = left; i <= right; i++) {
			pixels[i] = newColor;
			processed[i] = true;
		}

		// propagate to adjacent lines
		for (int offset = -1; offset <= 1; offset += 2) {
			int adjacentY = y + offset;
			if ((adjacentY < 0) || (adjacentY >= h)) continue; // adjacentY out of range
			lineStart = adjacentY * w;
			int run = false;
			for (i = (left + (offset * w)); i <= (right  + (offset * w)); i++) {
				if (!processed[i] && ((pixels[i] & mask) == matchRGB)) {
					if (!run) { // start of a new run of matching pixels
						// push a new x,y on the todo list
						if (todoIndex < todoLimit) {
							todoStack[todoIndex++] = i - lineStart;
							todoStack[todoIndex++] = adjacentY;
						}
						run = true;
					}
				} else {
					run = false; // no longer in a run
				}
				processed[i] = true;
			}
		}
	}
	return nilObj;
}

OBJ primQuadraticBezier(int nargs, OBJ args[]) {
	if (nargs < 8) return notEnoughArgsFailure();
	double x0 = evalFloat(args[0]);
	double y0 = evalFloat(args[1]);
	double x1 = evalFloat(args[2]);
	double y1 = evalFloat(args[3]);
	double cx = evalFloat(args[4]);
	double cy = evalFloat(args[5]);
	double step = evalFloat(args[6]);
	double stepCount = evalFloat(args[7]);

	double t = step / stepCount;
	double invT = 1.0 - t;
	double a = invT * invT;
	double b = 2 * (t * invT);
	double c = t * t;
	OBJ result = newArray(2);
	FIELD(result, 0) = int2obj((int) round((a * x0) + (b * cx) + (c * x1)));
	FIELD(result, 1) = int2obj((int) round((a * y0) + (b * cy) + (c * y1)));
	return result;
}

OBJ primUnmultiplyAlpha(int nargs, OBJ args[]) {
	// Undo pre-multiplied alpha in edge pixels.

	if (nargs < 1) return notEnoughArgsFailure();
	OBJ bitmap = args[0];
	if (!isBitmap(bitmap)) return nilObj; // do nothing if not a bitmap

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ pixels = FIELD(bitmap, 2);
	if (objWords(pixels) != (w * h)) return primFailed("Bad bitmap");

	uint32 *ptr = &FIELD(pixels, 0);
	uint32 *end = ptr + (w * h);
 	while (ptr < end) {
 		uint32 pix = *ptr;
		int a = (pix >> 24) & 255;
		if ((a > 0) && (a < 255)) {
			if (a < 10) {
				*ptr = 0; // make fully transparent
			} else {
				// restore original color before premulitplying alpha
				int r = (pix >> 16) & 255;
				int g = (pix >> 8) & 255;
				int b =  pix & 255;
				r = (255 * r) / a;
				g = (255 * g) / a;
				b = (255 * b) / a;
				r = (r > 255) ? 255 : r;
				g = (g > 255) ? 255 : g;
				b = (b > 255) ? 255 : b;
				*ptr = (a << 24) | (r << 16) | (g << 8) | b;
			}
		}
		ptr++;
 	}
 	return nilObj;
}

static inline uint32 iterpolatePixel(uint32 c1, uint32 c2, uint32 frac) {
	uint32 invFrac = 1024 - frac; // fixed point: 0-1024
	uint32 a = ((frac * ((c2 >> 24) & 255)) + (invFrac * ((c1 >> 24) & 255))) / 1024;
	uint32 r = ((frac * ((c2 >> 16) & 255)) + (invFrac * ((c1 >> 16) & 255))) / 1024;
	uint32 g = ((frac * ((c2 >> 8) & 255)) + (invFrac * ((c1 >> 8) & 255))) / 1024;
	uint32 b = ((frac * (c2 & 255)) + (invFrac * (c1 & 255))) / 1024;
	return (a << 24) | (r << 16) | (g << 8) | b;
}

OBJ primInterpolatedPixel(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ bitmap = args[0];
	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");
	uint32 w = obj2int(FIELD(bitmap, 0));
	uint32 h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return primFailed("Bad bitmap size");

	double xFloat = evalFloat(args[1]);
	double yFloat = evalFloat(args[2]);
	OBJ colorObj;
	if (nargs > 3) {
		colorObj = args[3];
		if (objWords(colorObj) < 4) return primFailed("Bad color object");
	} else {
		colorObj = newArray(4);
	}

	uint32 x = (uint32) xFloat;
	uint32 y = (uint32) yFloat;
	double xFrac = (uint32) (1024 * (xFloat - x)); // normalized to 0-1024
	double yFrac = (uint32) (1024 * (yFloat - y)); // normalized to 0-1024

	uint32 *pixels = &FIELD(data, 0);
	uint32 result = 0;
	if ((x <= w) && (y <= h)) {
		// Note: x and y are 1-based indices
		result = pixels[(w * (y - 1)) + (x - 1)];
		if ((x < w) && (xFrac > 0)) result = iterpolatePixel(result, pixels[(w * (y - 1)) + x], xFrac);
		if ((y < h) && (yFrac > 0)) {
			uint32 nextLine = pixels[(w * y) + (x - 1)];
			if ((x < w) && (xFrac > 0)) nextLine = iterpolatePixel(nextLine, pixels[(w * y) + x], xFrac);
			result = iterpolatePixel(result, nextLine, yFrac);
		}
	}
	FIELD(colorObj, 0) = int2obj((result >> 16) & 255);
	FIELD(colorObj, 1) = int2obj((result >> 8) & 255);
	FIELD(colorObj, 2) = int2obj(result & 255);
	FIELD(colorObj, 3) = int2obj((result >> 24) & 255);
	return colorObj;
}

OBJ primBitmapsTouch(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ bitmap1 = args[0];
	OBJ bitmap2 = args[1];
	int alphaThresh = intOrFloatArg(2, 10, nargs, args);
	alphaThresh = clip(alphaThresh, 0, 255);

	if (!isBitmap(bitmap1) || !isBitmap(bitmap2)) return primFailed("Bad bitmap");
	if ((obj2int(FIELD(bitmap1, 0)) != obj2int(FIELD(bitmap2, 0))) ||
		(obj2int(FIELD(bitmap1, 1)) != obj2int(FIELD(bitmap2, 1)))) {
			return primFailed("Bitmaps must have the same dimensions");
	}
	OBJ data1 = FIELD(bitmap1, 2);
	OBJ data2 = FIELD(bitmap2, 2);
	uint32 *pixels1 = &FIELD(data1, 0);
	uint32 *pixels2 = &FIELD(data2, 0);
	uint32 *end = pixels1 + objWords(data1);
	while (pixels1 < end) {
		int a1 = ((*pixels1++) >> 24) & 255;
		if (a1 > alphaThresh) {
			int a2 = ((*pixels2) >> 24) & 255;
			if (a2 > alphaThresh) return trueObj; // both alphas are above threshold
		}
		pixels2++;
	}
	return falseObj;
}

OBJ primRectanglesTouch(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ r1 = args[0];
	OBJ r2 = args[1];
	if ((objWords(r1) < 4) || (objWords(r2) < 4)) return primFailed("Bad rectangle object");

	double left1 = evalFloat(FIELD(r1, 0));
	double right1 = left1 + evalFloat(FIELD(r1, 2));
	double left2 = evalFloat(FIELD(r2, 0));
	double right2 = left2 + evalFloat(FIELD(r2, 2));
	if ((right1 < left2) || (right2 < left1)) return falseObj; // no horizontal overlap

	double top1 = evalFloat(FIELD(r1, 1));
	double bottom1 = top1 + evalFloat(FIELD(r1, 3));
	double top2 = evalFloat(FIELD(r2, 1));
	double bottom2 = top2 + evalFloat(FIELD(r2, 3));
	if ((bottom1 < top2) || (bottom2 < top1)) return falseObj; // no vertical overlap

	return trueObj;
}

// ***** Math Operators *****

OBJ primAdd(int nargs, OBJ args[]) {
	OBJ arg1 = args[0];
	OBJ arg2 = args[1];
	if ((nargs == 2) && bothInts(arg1, arg2)) {
		return int2obj(obj2int(arg1) + obj2int(arg2)); // common case: 2 int args
	}
	if (nargs == 0) return int2obj(0);

	int hasFloatArg = false;
	for (int i = 0; i < nargs; i++) {
		if (!isInt(args[i])) {
			if (IS_CLASS(args[i], FloatClass)) hasFloatArg = true;
			else return primFailed("All arguments must be integers or floats");
		}
	}

	if (hasFloatArg) {
		double result = evalFloat(arg1);
		for (int i = 1; i < nargs; i++) result += evalFloat(args[i]);
		return newFloat(result);
	} else {
		int result = obj2int(arg1);
		for (int i = 1; i < nargs; i++) result += obj2int(args[i]);
		return int2obj(result);
	}
}

OBJ primSub(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ arg1 = args[0];
	OBJ arg2 = args[1];
	if (nargs == 2) { // binary minus
		if (bothInts(arg1, arg2)) return int2obj(obj2int(arg1) - obj2int(arg2));
		if ((isInt(arg1) || IS_CLASS(arg1, FloatClass)) &&
			(isInt(arg2) || IS_CLASS(arg2, FloatClass))) {
			return newFloat(evalFloat(arg1) - evalFloat(arg2));
		}
		return primFailed("All arguments must be integers or floats");
	}
	if (nargs == 1) { // unary minus
		if (isInt(arg1)) return int2obj(-(obj2int(arg1)));
		if (IS_CLASS(arg1, FloatClass)) return newFloat(-evalFloat(arg1));
		return primFailed("Argument must be an integer or float");
	}
	return primFailed("Too many arguments");
}

OBJ primMul(int nargs, OBJ args[]) {
	OBJ arg1 = args[0];
	OBJ arg2 = args[1];
	if ((nargs == 2) && bothInts(arg1, arg2)) {
		return int2obj(obj2int(arg1) * obj2int(arg2)); // common case: 2 int args
	}
	if (nargs == 0) return int2obj(1);

	int hasFloatArg = false;
	for (int i = 0; i < nargs; i++) {
		if (!isInt(args[i])) {
			if (IS_CLASS(args[i], FloatClass)) hasFloatArg = true;
			else return primFailed("All arguments must be integers or floats");
		}
	}

	if (hasFloatArg) {
		double result = evalFloat(arg1);
		for (int i = 1; i < nargs; i++) result *= evalFloat(args[i]);
		return newFloat(result);
	} else {
		int result = obj2int(arg1);
		for (int i = 1; i < nargs; i++) result *= obj2int(args[i]);
		return int2obj(result);
	}
}

OBJ primDiv(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ arg1 = args[0];
	OBJ arg2 = args[1];
	if (bothInts(arg1, arg2)) {
		int denom = evalInt(arg2);
		if (denom == 0) return primFailed("Cannot divide by zero");
		int numerator = evalInt(arg1);
		if ((numerator % denom) == 0) { // numerator is integer multiple of denom
			return int2obj(numerator / denom);
		}
	}
	double denom = evalFloat(arg2);
	if (denom == 0.0) return primFailed("Cannot divide by zero");
	return newFloat(evalFloat(arg1) / denom);
}

OBJ primMod(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ arg1 = args[0];
	OBJ arg2 = args[1];
	if (bothInts(arg1, arg2)) {
		int denom = evalInt(arg2);
		if (denom == 0) return primFailed("Cannot use zero as modulus");
		return int2obj(evalInt(arg1) % denom);
	}
	double denom = evalFloat(arg2);
	if (denom == 0.0) return primFailed("Cannot use zero as modulus");
	return newFloat(fmod(evalFloat(arg1), denom));
}

OBJ primAbs(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ arg = args[0];
	if (isInt(arg)) return int2obj(abs(obj2int(arg)));
	return newFloat(fabs(evalFloat(arg)));
}

OBJ primRand(int nargs, OBJ args[]) {
	int useFloats = ((nargs > 0) && (IS_CLASS(args[0], FloatClass)));
	if (!useFloats && (nargs > 1) && (IS_CLASS(args[1], FloatClass))) useFloats = true;
	if (useFloats) {
		// if either argument is a Float, compute a random float
		double lowF = evalFloat(args[0]);
		double highF = (nargs > 1) ? evalFloat(args[1]) : lowF;
		if (nargs == 1) lowF = 0; // if only one argument, the range is 0.0 to the argument
		return newFloat(lowF + (((highF - lowF) * rand()) / RAND_MAX));
	}
	int low = intArg(0, 1, nargs, args);
	int high = intArg(1, 100, nargs, args);
	if (nargs == 1) {
		high = low;
		low = 1;
	}
	if (low >= high) return int2obj(high);
	int range = high + 1 - low;
	return int2obj(low + (rand() % range));
}

OBJ primSin(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	double radians = (M_PI * fmod(evalFloat(args[0]), 360.0)) / 180.0;
	return newFloat(sin(radians));
}

OBJ primCos(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	double radians = (M_PI * fmod(evalFloat(args[0]), 360.0)) / 180.0;
	return newFloat(cos(radians));
}

OBJ primTan(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	double radians = (M_PI * fmod(evalFloat(args[0]), 360.0)) / 180.0;
	return newFloat(tan(radians));
}

OBJ primAtan(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	double radians = atan2(evalFloat(args[0]), evalFloat(args[1]));
	double degrees = (180.0 * radians) / M_PI;
	if (degrees < 0.0) degrees += 360.0;
	return newFloat(degrees);
}

OBJ primSqrt(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	double n = evalFloat(args[0]);
	if (n < 0) return primFailed("You cannot take the square root of a negative number");
	return newFloat(sqrt(n));
}

OBJ primExp(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	return newFloat(exp(evalFloat(args[0])));
}

OBJ primLn(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	double n = evalFloat(args[0]);
	if (n < 0) return primFailed("You cannot take the logarithm of a negative number");
	return newFloat(log(n));
}

OBJ primToFloat(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (IS_CLASS(args[0], FloatClass)) return args[0];
	return newFloat(evalInt(args[0]));
}

OBJ primTruncate(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ arg = args[0];
	if (isInt(arg)) return arg;
	return int2obj((int) evalFloat(arg));
}

// ***** Comparison Operations *****

#define isNum(obj) (isInt(obj) || IS_CLASS(obj, FloatClass) || IS_CLASS(obj, LargeIntegerClass))

static inline int compare(OBJ a, OBJ b, int incomparableFlag) {
	// Compare two ints or strings and return:
	//	-1 if a < b
	//	 0 if a == b or a === b
	//	 1 if a > b
	//	 incomparableFlag if a and b are incomparable

	if (a == b) return 0; // identical objects or equal ints
	if (bothInts(a, b)) return (obj2int(a) < obj2int(b)) ? -1 : 1; // both ints, not equal
	if (isNum(a) && isNum(b)) {
		double n1 = evalFloat(a);
		double n2 = evalFloat(b);
		if (n1 == n2) return 0; // exactly equal (e.g. -0.0 == 0.0)
		// Check for "almost equal"
		const unsigned long long mask = 0xFFFFFFFFFFFFF000; // ignore last 12 bits of mantissa
		long long n1bits = *((long long *) &n1) & mask;
		long long n2bits = *((long long *) &n2) & mask;
		if (n1bits == n2bits) return 0; // nearly equal; consider them equal
		return (n1 < n2) ? -1 : 1; // not equal
	}
	if (IS_CLASS(a, StringClass) && IS_CLASS(b, StringClass)) {
		int cmp = strcmp(obj2str(a), obj2str(b));
		return (cmp == 0) ? 0 : ((cmp > 0) ? 1 : -1);
	}
	return incomparableFlag;
}

OBJ primLess(int nargs, OBJ args[])			{ return (compare(args[0], args[1], 2) == -1) ? trueObj : falseObj; }
OBJ primLessEqual(int nargs, OBJ args[])	{ return (compare(args[0], args[1], 2) <= 0) ? trueObj : falseObj; }
OBJ primEqual(int nargs, OBJ args[])		{ return (compare(args[0], args[1], 2) == 0) ? trueObj : falseObj; }
OBJ primNotEqual(int nargs, OBJ args[])		{ return (compare(args[0], args[1], 2) != 0) ? trueObj : falseObj; }
OBJ primGreaterEqual(int nargs, OBJ args[]) { return (compare(args[0], args[1], -2) >= 0) ? trueObj : falseObj; }
OBJ primGreater(int nargs, OBJ args[])		{ return (compare(args[0], args[1], -2) == 1) ? trueObj : falseObj; }
OBJ primIdentical(int nargs, OBJ args[])	{ return (args[0] == args[1]) ? trueObj : falseObj; }

OBJ primCompareFloats(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	double n1 = evalFloat(args[0]);
	double n2 = evalFloat(args[1]);
	int result = (n1 == n2) ? 0 : ((n1 < n2) ? -1 : 1);
	return int2obj(result);
}

// ***** Bitwise Operations *****

OBJ primBitAnd(int nargs, OBJ args[])		{ return int2obj(evalInt(args[0]) & evalInt(args[1])); }
OBJ primBitOr(int nargs, OBJ args[])		{ return int2obj(evalInt(args[0]) | evalInt(args[1])); }
OBJ primBitXor(int nargs, OBJ args[])		{ return int2obj(evalInt(args[0]) ^ evalInt(args[1])); }
OBJ primBitShiftL(int nargs, OBJ args[])	{ return int2obj(evalInt(args[0]) << evalInt(args[1])); }
OBJ primBitShiftR(int nargs, OBJ args[])	{ return int2obj(evalInt(args[0]) >> evalInt(args[1])); }
OBJ primBitUShiftR(int nargs, OBJ args[])	{ return int2obj((unsigned) evalInt(args[0]) >> evalInt(args[1])); }

OBJ extendedPrimBitOr(int nargs, OBJ args[]) {
	OBJ arg1 = args[0];
	OBJ arg2 = args[1];
	if ((nargs == 2) && bothInts(arg1, arg2)) {
		return ((unsigned int)arg1) | ((unsigned int)arg2); // common case: 2 int args
	}
	if (nargs == 0) return int2obj(0);

	int smallArgs = true;
	int smallResult = 0;

	int maxCount = 4;
	OBJ result = nilObj;
	OBJ bytes;
	unsigned char *body = NULL;

	for (int i = 0; i < nargs; i++) {
		OBJ other = args[i];
		if (isInt(other)) {
			unsigned int value = obj2int(other);
			if (smallArgs) {
				smallResult |= value;
			} else {
				for (int j = 0; j < 4; j++) {
					int ind = maxCount - j - 1;
					body[ind] |= ((value >> (j * 8)) & 255);
				}
			}
		} else if (IS_CLASS(other, LargeIntegerClass)) {
			unsigned char *otherBytes = largeIntBody(other);
			if (otherBytes) {
				int otherCount = objBytes(FIELD(other, 0));
				if (smallArgs) {
					smallArgs = false;
					for (int j = i; j < nargs; j++) {
						maxCount = maxCount > otherCount ? maxCount : otherCount;
					}
					result = newObj(LargeIntegerClass, 2, nilObj);
					if (!canAllocate(maxCount / 4)) return outOfMemoryFailure();
					bytes = newBinaryData(maxCount);
					FIELD(result, 0) = bytes;
					body = largeIntBody(result);
					for (int j = 0; j < 4; j++) {
						int ind = maxCount - j - 1;
						body[ind] |= ((obj2int(smallResult) >> (j * 8)) & 255);
					}
					for (int j = 0; j < otherCount; j++) {
						int ind = maxCount - j - 1;
						body[ind] |= otherBytes[otherCount - j - 1];
					}
				} else {
					for (int j = 0; j < otherCount; j++) {
						int ind = maxCount - j - 1;
						body[ind] |= otherBytes[otherCount - j - 1];
					}
				}
			} else {
				primFailed("malformed large integer detected");
				return 0;
			}
		}
	}
	if (smallArgs) {return uint32Obj(smallResult);}
	return result;
}

// ***** Logical Operations *****

OBJ notBooleanFailure() { primFailed("Expected a boolean (true or false)"); return nilObj; }

OBJ primLogicalAnd(int nargs, OBJ args[]) {
	for (int i = 0; i < nargs; i++) {
		if (falseObj == args[i]) return falseObj;
		if (trueObj != args[i]) return notBooleanFailure();
	}
	return trueObj;
}

OBJ primLogicalOr(int nargs, OBJ args[]) {
	for (int i = 0; i < nargs; i++) {
		if (trueObj == args[i]) return trueObj;
		if (falseObj != args[i]) return notBooleanFailure();
	}
	return falseObj;
}

OBJ primLogicalNot(int nargs, OBJ args[]) {
	if (trueObj == args[0]) return falseObj;
	if (falseObj == args[0]) return trueObj;
	return notBooleanFailure();
}

// ***** Module Variables *****

static OBJ getModuleVar(OBJ varName, OBJ module) {
	if (NOT_CLASS(varName, StringClass)) return nilObj;
	if (NOT_CLASS(module, ModuleClass)) return nilObj;

	OBJ moduleVarNames = FIELD(module, Module_VariableNames);
	OBJ moduleVariables = FIELD(module, Module_Variables);
	int i = indexOfString(varName, moduleVarNames);
	if (i < 0) return nilObj;
	return FIELD(moduleVariables, i);
}

static void setModuleVar(OBJ varName, OBJ newValue, OBJ module) {
	if (NOT_CLASS(varName, StringClass)) return;
	if (NOT_CLASS(module, ModuleClass)) return;

	OBJ moduleVarNames = FIELD(module, Module_VariableNames);
	OBJ moduleVariables = FIELD(module, Module_Variables);
	int i = indexOfString(varName, moduleVarNames);
	if (i < 0) { // add new variable
		addModuleVariable(module, varName, newValue);
	} else { // update existing variable
		FIELD(moduleVariables, i) = newValue;
	}
}

OBJ primGetGlobal(int nargs, OBJ args[]) {
	// Globals are stored in the sessionModule. Optional second argument is default value.
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ varName = args[0];
	if (NOT_CLASS(varName, StringClass)) return firstArgMustBeString();

	OBJ result = getModuleVar(varName, sessionModule);
	if (!result && (nargs > 1)) return args[1]; // return default value
	return result;
}

OBJ primSetGlobal(int nargs, OBJ args[]) {
	// Globals are stored in the sessionModule.
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ varName = args[0];
	OBJ newValue = args[1];
	if (NOT_CLASS(varName, StringClass)) return firstArgMustBeString();

	setModuleVar(varName, newValue, sessionModule);
	return newValue;
}

OBJ primGetShared(int nargs, OBJ args[]) {
	// Return a shared variable. Optional second argument is the target module.
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ varName = args[0];
	if (NOT_CLASS(varName, StringClass)) return firstArgMustBeString();

	OBJ module = currentModule;
	if (nargs > 1) {
		module = args[1];
		if (NOT_CLASS(module, ModuleClass)) return primFailed("Second argument must be a module");
	}
	return getModuleVar(varName, module);
}

OBJ primSetShared(int nargs, OBJ args[]) {
	// Set a shared variable to a value. Optional third argument is the target module.
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ varName = args[0];
	OBJ newValue = args[1];
	if (NOT_CLASS(varName, StringClass)) return firstArgMustBeString();

	OBJ module = currentModule;
	if (nargs > 2) {
		module = args[2];
		if (NOT_CLASS(module, ModuleClass)) return primFailed("Third argument must be a module");
	}
	setModuleVar(varName, newValue, module);
	return nilObj;
}

OBJ primIncreaseShared(int nargs, OBJ args[]) {
	// Increase a shared variable by the given amount. Optional third argument is the target module.
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ varName = args[0];
	OBJ delta = args[1];
	if (NOT_CLASS(varName, StringClass)) return firstArgMustBeString();

	OBJ module = currentModule;
	if (nargs > 2) {
		module = args[2];
		if (NOT_CLASS(module, ModuleClass)) return primFailed("Third argument must be a module");
	}

	OBJ value = getModuleVar(varName, module);
	OBJ newValue = nilObj;
	if (bothInts(value, delta)) {
		newValue = int2obj(obj2int(value) + obj2int(delta)); // common case: 2 int args
	} else {
		if (!isNum(value)) return primFailed("Shared variable value is not a number");
		if (!isNum(delta)) return primFailed("Amount to increase is not a number");
		newValue = newFloat(evalFloat(value) + evalFloat(delta));
	}
	setModuleVar(varName, newValue, module);
	return nilObj;
}

// ***** Miscellaneous *****

OBJ primBeep(int nargs, OBJ args[]) { printf("\007"); return nilObj; }
OBJ primExit() { printf("Goodbye!\n\n"); exit(0); return nilObj; }
OBJ primHalt(int nargs, OBJ args[]) { failure("Halted"); return nilObj; }
OBJ primHelp(int nargs, OBJ args[]); // forward reference
OBJ primNoop(int nargs, OBJ args[]) { return nilObj; }

OBJ primVersion(int nargs, OBJ args[]) {
	char s[100];
	sprintf(s, "GP Virtual Machine %s (%s, %s)", versionNum, versionDate, versionTime);

	OBJ result = newArray(4);
	FIELD(result, 0) = newString(s); // full version string
	FIELD(result, 1) = newString(versionNum);
	FIELD(result, 2) = newString(versionDate);
	FIELD(result, 3) = newString(versionTime);
	return result;
}

int recordCommandLine(int argc, char *argv[]) {
	commandLineValues = argv;
	commandLineCount = argc;
	return argc;
}

OBJ primCommandLine(int nargs, OBJ args[]) {
	if (!canAllocate(commandLineCount * 30)) return outOfMemoryFailure(); // estimate
	OBJ result = newArray(commandLineCount);
	for (int i = 0; i < commandLineCount; i++) {
		FIELD(result, i) = newString(commandLineValues[i]);
	}
	return result;
}

OBJ primPlatform(int nargs, OBJ args[]) {
 #if defined(__ANDROID__)
	return newString("Android");
 #elif defined(EMSCRIPTEN)
	return newString("Browser");
 #elif defined(IOS)
	return newString("iOS");
 #elif defined(__linux__)
	return newString("Linux");
 #elif defined(MAC)
	return newString("Mac");
 #elif defined(_WIN32) || defined(_WIN64)
	return newString("Win");
 #else
	return newString("Unknown");
 #endif
}

// ***** System Execute Support *****

#ifdef _WIN32
	#define WIN_PROC_HANDLES 10
	HANDLE winProcHandle[WIN_PROC_HANDLES + 1];

	static int winEmptyProcSlot() {
		// Return an unused process handle slot. The index of this slot is
		// used as the Windows equivalent of Unix process ID. The slot is released
		// when the client requests the status of a completed process.

		for (int i = 1; i <= WIN_PROC_HANDLES; i++) {
			if (!winProcHandle[i]) return i;
		}
		return -1;
	}
#endif

OBJ primExec(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	char *argList[32];
	int argCount = (nargs <= 31) ? nargs : 31;

	for (int i = 0; i < argCount; i++) {
		OBJ arg = args[i];
		if (!IS_CLASS(arg, StringClass)) return nilObj; // all args must be strings
		argList[i] = obj2str(args[i]);
	}
	argList[argCount] = NULL;
	int pid = 0;

#if defined(EMSCRIPTEN)
	return nilObj;
#elif defined(_WIN32)
	pid = winEmptyProcSlot();
	if (-1 == pid) return nilObj;
	char *cmd = argList[0];
	HANDLE procHndl = (HANDLE) _spawnvp(_P_NOWAIT, (const char *) cmd, (const char **) argList);
	winProcHandle[pid] = procHndl;
#else
	pid = fork();
	char *cmd = argList[0];
	if (pid == 0) {
		execvp(cmd, (char * const *) argList);
		exit(0);
		return nilObj;
	}
#endif
	return int2obj(pid);
}

OBJ primExecStatus(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return nilObj;

#if defined(EMSCRIPTEN)
	return nilObj;
#elif defined(_WIN32)
	int pid = obj2int(args[0]);
	if ((pid < 1) || (pid > WIN_PROC_HANDLES)) return nilObj;
	HANDLE procHndl = winProcHandle[pid];
	if (!procHndl) return nilObj;
	unsigned long status = 0;
	GetExitCodeProcess(procHndl, &status);
	if (STILL_ACTIVE == status) return nilObj;
	winProcHandle[pid] = NULL;  // process has completed, so recycle the winProcHandle slot
	return int2obj(status);
#else
	int pid = obj2int(args[0]);
	int status;
	int rc = waitpid(pid, &status, WNOHANG);
	if ((rc <= 0) || (!WIFEXITED(status))) return nilObj; // process not completed or does not exist
	return int2obj(WEXITSTATUS(status));
#endif
	return nilObj;
}

OBJ primOpenURL(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!IS_CLASS(args[0], StringClass)) return primFailed("First argument must be a string");
	char *url = obj2str(args[0]);
	#if defined(EMSCRIPTEN)
		EM_ASM_({
			var url = UTF8ToString($0);
			var newTab = window.open(url, '_blank');
			if (newTab != null) { newTab.focus(); }
		}, url);
	#elif defined(_WIN32) || defined(_WIN64)
		ShellExecute(NULL, TEXT("open"), url, NULL, NULL, SW_SHOWNORMAL);
	#elif defined(MAC)
		CFStringRef urlString = CFStringCreateWithCString(kCFAllocatorDefault, url, kCFStringEncodingUTF8);
		CFURLRef urlRef = CFURLCreateWithString(kCFAllocatorDefault, urlString, NULL);
		if (urlRef != NULL) {
			LSOpenCFURLRef(urlRef, NULL);
			CFRelease (urlRef);
		}
		CFRelease(urlString);
	#elif defined(__linux__)
		char *argList[3] = {"xdg-open", url, NULL};
		char *cmd = argList[0];
		int pid = fork();
		if (pid == 0) {
			execvp(cmd, (char * const *) argList);
			exit(0);
			return nilObj;
		}
	#endif
	return nilObj;
}

// ***** Debugger/Process Hooks *****

OBJ primDebugeeTask(int nargs, OBJ args[]) { return debugeeTask; }
OBJ primYield(int nargs, OBJ args[]) { yield(); return nilObj; }

// ***** Memory Primitives *****

OBJ primMemStats(int nargs, OBJ args[]) {
	OBJ result = newArray(5);
	FIELD(result, 0) = int2obj(freeStart - memStart); // bytes used
	FIELD(result, 1) = int2obj(memEnd - memStart); // bytes free
	FIELD(result, 2) = int2obj(allocationsSinceLastGC);
	FIELD(result, 3) = int2obj(bytesAllocatedSinceLastGC);
	FIELD(result, 4) = int2obj(gcCount);
	return result;
}

OBJ primObjectAfter(int nargs, OBJ args[]) {
	OBJ prevObj = (nargs) ? args[0] : nilObj;
	int classID = 0; // all objects
	if (nargs > 1) {
	  if (!isInt(args[1])) return primFailed("Second argument (class index) must be an integer");
	  classID = obj2int(args[1]);
	}
	return objectAfter(prevObj, classID);
}

OBJ primObjectReferences(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	return referencesToObject(args[0]);
}

OBJ primReplaceObjects(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ srcArray = args[0];
	OBJ dstArray = args[1];
	if (NOT_CLASS(srcArray, ArrayClass) || NOT_CLASS(dstArray, ArrayClass)) return primFailed("Both arguments must be arrays");
	if (WORDS(srcArray) != WORDS(dstArray)) return primFailed("Argument arrays must be the same size");
	replaceObjects(srcArray, dstArray);
	return nilObj;
}

OBJ primFindGarbage(int nargs, OBJ args[]) {
	initGarbageCollector();
	markLoop();
	return nilObj;
}

OBJ primIsGarbage(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	if (isInt(obj) || (obj <= falseObj)) return falseObj;
	return isMarked(obj) ? falseObj : trueObj;
}

OBJ primObjAddr(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	if (isInt(obj) || (obj <= falseObj)) return int2obj(0); // ints, nil, booleans -> 0
	return int2obj(obj - memStart); // word address of object
}

OBJ primObjWords(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	if (isInt(obj) || (obj <= falseObj)) return int2obj(0); // ints, nil, booleans -> 0
	return int2obj(objWords(obj));
}

OBJ primMemDumpWords(int nargs, OBJ args[]) {
	memDumpWords();
	return nilObj;
}

OBJ primMemDumpObjects(int nargs, OBJ args[]) {
	memDumpObjects();
	return nilObj;
}

OBJ primObjData(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	if (isInt(obj) || (obj <= falseObj)) return nilObj; // ints, nil, booleans -> nil
	int byteCount = 4 * objWords(obj);
	OBJ result = newArray(byteCount);
	unsigned char *src = (void *) &FIELD(obj, 0);
	for (int i = 0; i < byteCount; i++) {
		FIELD(result, i) = int2obj(*src++);
	}
	return result;
}

// ***** Profiling *****

#if !defined(_WIN32) && !defined(EMSCRIPTEN)

#include <pthread.h>

// 425 usecs/tick yields about 2000 interrupts/sec on MacBook Pro
#define PROFILE_TICK_USECS 425

static pthread_t mainThread;
static pthread_t timerThread;

static int timerActive = false;

static void handleProfileTick(int sig, siginfo_t *info, void *uap) {
	profileTick += 1;
}

static void * timerLoop(void *ignore) {
	timerActive = true;
	while (timerActive) {
		struct timespec sleepTime = { 0, PROFILE_TICK_USECS * 1000 };
		while ((nanosleep(&sleepTime, &sleepTime) == -1) && (errno == EINTR)) /* restart if interrupted */;
		pthread_kill(mainThread, SIGPROF); // signal the main thread
	}
	return NULL;
}

static void stopTimerThread() { timerActive = false; }

static void startTimerThread() {
	int timerThreadPolicy;
	struct sched_param timerThreadPriority;

	mainThread = pthread_self();
	int err = pthread_getschedparam(mainThread, &timerThreadPolicy, &timerThreadPriority);
	if (err) return;

	// add 2 to priority to the current thread:
	timerThreadPriority.sched_priority += 2;

	if (sched_get_priority_max(timerThreadPolicy) < timerThreadPriority.sched_priority) {
		// if the priority isn't appropriate for the policy, then change policy:
		timerThreadPolicy = SCHED_FIFO;
	}

	struct sigaction action;
	action.sa_sigaction = handleProfileTick;
	action.sa_flags = SA_NODEFER | SA_SIGINFO;
	sigemptyset(&action.sa_mask);
	sigaction(SIGPROF, &action, 0);

	err = pthread_create(&timerThread, NULL, timerLoop, NULL);
	if (err) return;

	err = pthread_setschedparam(timerThread, timerThreadPolicy, &timerThreadPriority);
}

#else

// stubs
static void startTimerThread() {}
static void stopTimerThread() {}

#endif // Profiling

OBJ primStartProfileClock(int nargs, OBJ args[]) {
	startTimerThread();
	return nilObj;
}

OBJ primStopProfileClock(int nargs, OBJ args[]) {
	stopTimerThread();
	return nilObj;
}

// ***** Hashing *****

uint32 murmurHash3(uint32 *data, int wordCount) {
	// A fast string hash function with low collisions and good statistical properties.
	// MurmurHash3 was written by Austin Appleby and placed in the publicn domain.
	// See: https://code.google.com/p/smhasher/

	const uint32 c1 = 0xcc9e2d51;
	const uint32 c2 = 0x1b873593;
	uint32 hash = 0;

	uint32 *ptr;
	uint32 *end = data + wordCount;
	for (ptr = data; ptr < end; ptr++) {
		uint32 w = *ptr;
		w *= c1;
		w = (w << 15) | (w >> 17);
		w *= c2;
		hash ^= w;
		hash = (hash << 13) | (hash >> 19);
		hash = (hash * 5) + 0xe6546b64;
	}
	hash ^= (4 * wordCount); // include string size in the hash

	// force all bits of a hash block to avalanche:
	hash ^= hash >> 16;
	hash *= 0x85ebca6b;
	hash ^= hash >> 13;
	hash *= 0xc2b2ae35;
	hash ^= hash >> 16;

	return hash;
}

static unsigned long seed = 123456;

static int nextHash() {
	// Compute a random integer using the Park-Miller pseudo-random number generator.
	// See http://en.wikipedia.org/wiki/Lehmer_random_number_generator
	seed = (16807 * seed) & 0x7FFFFFF;
	return seed;
}

OBJ primHash(int nargs, OBJ args[]) {
	// Every object has an immutable hash that is computed the first time it is needed.
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ obj = args[0];
	// ints hash to 3 * obj value masked to be positive (multiplier spreads out sequential values)
	if (isInt(obj)) return (7 * obj) & 0x7FFFFFFF; // ints hash to 7 * themselves, masked to be positive. Or should be 0x3FFFFFFF?
	if (obj <= falseObj) return int2obj(obj); // nil, true, false hash to 0, 2, 4
	if (!HASH(obj)) {
		if (IS_CLASS(obj, StringClass)) {
			// String hash is computed from the string contents (strings are immutable)
			HASH(obj) = (uint32)int2obj(murmurHash3(BODY(obj), objWords(obj)) & 0x3FFFFFFF);
		} else if (IS_CLASS(obj, FloatClass)) {
			// Float hash is the 30 most significant bits of the mantissa
			long long floatBits = *((long long *) BODY(obj));
			HASH(obj) = (uint32) int2obj((floatBits >> 22 & 0x3FFFFFFF));
		} else {
			// Hash for a non-string object is a random positive integer assigned on first use
			HASH(obj) = (uint32)int2obj(nextHash() & 0x3FFFFFFF);
		}
	}
	return HASH(obj);
}

// ***** Module Support *****

static OBJ primSessionModule(int nargs, OBJ args[]) {
	return sessionModule;
}

static OBJ primThisModule(int nargs, OBJ args[]) {
	return currentModule;
}

static OBJ primTopLevelModule(int nargs, OBJ args[]) {
	return topLevelModule;
}

static OBJ primConsoleModule(int nargs, OBJ args[]) {
	return consoleModule;
}

static OBJ primSetSessionModule(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], ModuleClass)) return primFailed("The argument has to be a module");
	currentModule = sessionModule = consoleModule = args[0];
	return nilObj;
}

static OBJ primSetConsoleModule(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], ModuleClass)) return primFailed("The argument has to be a module");
	currentModule = consoleModule = args[0];
	return nilObj;
}

static OBJ primModule(int nargs, OBJ args[]) {
	// may need to support all Module loading logic but for now this would be only used by the initial top-level module loading.
	return topLevelModule;
}

// ***** Method Cache *****

static OBJ primClearMethodCache(int nargs, OBJ args[]) {
	if ((nargs > 0) && (IS_CLASS(args[0], StringClass))) {
		methodCacheClearEntry(args[0]); // clear entry for the given method/function name
	} else {
		methodCacheClear(); // clear the entire cache
	}
	return nilObj;
}

static OBJ primMethodCacheStats(int nargs, OBJ args[]) {
	return methodCacheStats();
}

static OBJ primDrawPatches(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ patches = args[0];
	OBJ pixels = args[1];
	int rgb = intArg(2, 0, nargs, args) & 0xFFFFFF; // low 24 bits
	int scale = intArg(3, 0, nargs, args); // optional - if zero us exponential scaling

	if (NOT_CLASS(patches, ArrayClass)) return primFailed("First argument must be an Array");
	if (NOT_CLASS(pixels, BinaryDataClass)) return primFailed("Second argument must be a BinaryData");

	int count = objWords(patches);
	if (objWords(pixels) < count) count = objWords(pixels);
	for (int i = 0; i < count; i++) {
		int a;
		if (scale) {
			a = (int) (scale * evalFloat(FIELD(patches, i)));
		} else {
			a = (int) (8.0 * (log2(evalFloat(FIELD(patches, i))) + 22.0));
		}
		if (a < 0) a = 0;
		if (a > 255) a = 255;
		FIELD(pixels, i) = (a << 24) | rgb;
	}

	return nilObj;
}

static OBJ primDiffuse1(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ patches = args[0];
	int w = intArg(1, 0, nargs, args);
	int h = objWords(patches) / w;

	if (NOT_CLASS(patches, ArrayClass)) return primFailed("First argument must be an Array");
	if (objWords(patches) != (w * h)) return primFailed("Bad array size");

	int right = w - 1;
	int bottom = h - 1;
	OBJ old = cloneObj(patches);
	for (int r = 0; r < h; r++) {
		for (int c = 0; c < w; c++) {
			int i = (w * r) + c;
			double sum = evalFloat(FIELD(old, i));
			if (c > 0) sum += evalFloat(FIELD(old, i - 1));
			if (c < right) sum += evalFloat(FIELD(old, i + 1));
			if (r > 0) {
				int prevRow = i - w;
				sum += evalFloat(FIELD(old, prevRow));
				if (c > 0) sum += evalFloat(FIELD(old, prevRow - 1));
				if (c < right) sum += evalFloat(FIELD(old, prevRow + 1));
			}
			if (r < bottom) {
				int nextRow = i + w;
				sum += evalFloat(FIELD(old, nextRow));
				if (c > 0) sum += evalFloat(FIELD(old, nextRow - 1));
				if (c < right) sum += evalFloat(FIELD(old, nextRow + 1));
			}
			FIELD(patches, i) = newFloat(sum / 9);
		}
	}
	return nilObj;
}

static OBJ primDiffuse2(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	OBJ patches = args[0];
	int w = intArg(1, 0, nargs, args);
 	int h = objWords(patches) / w;
	double factor = evalFloat(args[2]);

	if (NOT_CLASS(patches, ArrayClass)) return primFailed("First argument must be an Array");
	if (objWords(patches) != (w * h)) return primFailed("Bad array size");

	OBJ old = cloneObj(patches);
	for (int r = 1; r < (h - 1); r++) {
		for (int c = 1; c < (w - 1); c++) {
			int i = (w * r) + c;
			int prevRow = i - w;
			int nextRow = i + w;
			double centerVal = evalFloat(FIELD(patches, i));
			double neighborSum = (
				(evalFloat(FIELD(old, prevRow)) - centerVal) +
				(evalFloat(FIELD(old, i - 1)) - centerVal) +
				(evalFloat(FIELD(old, i + 1)) - centerVal) +
				(evalFloat(FIELD(old, nextRow)) - centerVal));
 			double sum = centerVal + (factor * neighborSum);
 			FIELD(patches, i) = newFloat(sum);
		}
	}
	return nilObj;
}

// ***** Core Primitives *****

PrimEntry corePrimList[] = {
	{"-----", NULL, "Basics"},
	{"help",		primHelp,			"Get list of commands or help on a particular command. Ex. help newArray"},
	{"log",			primLog,			"Print to the console operation for low-level debugging. Print all arguments. Ex. log 'hello!' 1 true"},
	{"exit",		primExit,			"Quit from GP."},

	{"-----", NULL, "Control Structures"},
	{"if",			(void*) IF,			"Do statements if first argument is true. Ex. if true { print 'yes!' }"},
	{"repeat",		(void*) REPEAT,		"Repeat some statements the given number of times. Ex. repeat 10 { print 'hello' }"},
	{"while",		(void*) WHILE,		"Repeat some statements as long the condition is is true. Ex. { x = 1; while (x <= 10) { print x; x += 1 }}"},
	{"for",			(void*) FOR,		"Repeat some statements with the given variable having a range of values. Ex. for x 10 { print x }"},
	{"animate",		(void*) ANIMATE,	"Repeat some statements indefinitely. When running in a task, wait at the end of the loop for the next display cycle."},
	{"waitUntil",	(void*) WAIT_UNTIL,	"Wait for a condition to become true. When running in a task, wait for the next display cycle."},

	{"-----", NULL, "Variables"},
	{"v",			(void*) GETVAR,		""}, // internal; the parser converts variable names to (v 'varName')
	{"=",			(void*) SETVAR,		"Set the value of a variable. Ex. score = 0"},
	{"+=",			(void*) CHANGEBY,	"Change the value of a variable. Ex. score += 100"},
	{"my",			(void*) GETVAR,		"Return the value of an instance variable."},
	{"setMy",		(void*) SETVAR,		"Set the value of an instance variable."},
	{"increaseMy",	(void*) CHANGEBY,	"Change the value of an instance variable."},
	{"local",		(void*) LOCALVAR,	"Used to declare and initialize a local variable."},
	{"global",		primGetGlobal,		"Return the value of the given global variable. Ex. (global 'scale')"},
	{"setGlobal",	primSetGlobal,		"Set the value of the given global variable. Ex. setGlobal 'scale' 2"},
	{"shared",		primGetShared,		"Return the value of the given shared (module) variable. Ex. (shared 'scale')"},
	{"setShared",	primSetShared,		"Set the value of the given shared (module) variable. Ex. setShared 'scale' 2"},
	{"increaseShared", primIncreaseShared, "Increase the value of the given shared (module) variable by the given amount."},

	{"-----", NULL, "Math"},
	{"+",			(void*) ADD,		"Ex. (3 + 4) -> 7"},
	{"-",			(void*) SUB,		"Ex. (3 - 4) -> -1"},
	{"*",			primMul,			"Ex. (3 * 4) -> 12"},
	{"/",			primDiv,			"Ex. (12 / 4) -> 3"},
	{"%",			primMod,			"Ex. (11 % 4) -> 3"},

	{"abs",			primAbs,			"Return the absolute value of an integer. Ex. (abs -7) -> 7"},
	{"rand",		primRand,			"Return a random integer. Optionally takes two arguments to specify range. Ex. (rand 0 1)"},
	{"toFloat",		primToFloat,		"Convert an integer value to a Float. Ex. (toFloat 2)"},
	{"truncate",	primTruncate,		"Truncate a float value to an integr. Ex. (truncate 2.9) -> 2"},
	{"sqrt",		primSqrt,			"The square root of a number. Ex. (sqrt 2)"},
	{"sin",			primSin,			"The sine of a number. Ex. (sin 0)"},
	{"cos",			primCos,			"The cosine of a number. Ex. (cos 0)"},
	{"tan",			primTan,			"The tangent of a number. Ex. (tan 1)"},
	{"atan",		primAtan,			"The the angle made by a right triangle with the given opposite and adjacent side lengths. Ex. (atan 1 1)"},
	{"exp",			primExp,			"Return e raised to the given power. Ex. (exp 1)"},
	{"ln",			primLn,				"Return the natural logarithm (base e) of a number. Ex. (log 10)"},

	{"-----", NULL, "Comparisons"},
	{"<",			(void*) LESS,		"Ex. (3 < 4) -> true"},
	{"<=",			primLessEqual,		"Ex. (3 <= 3) -> true"},
	{"==",			primEqual,			"Ex. (3 == 4) -> false"},
	{"!=",			primNotEqual,		"Ex. (3 != 4) -> true"},
	{">=",			primGreaterEqual,	"Ex. (3 >= 4) -> false"},
	{">",			primGreater,		"Ex. (3 > 3) -> false"},
	{"===",			primIdentical,		"Identity test. Return true if the two arguments are the exact same object. Ex. ((array) === (array)) -> false"},
	{"compareFloats", primCompareFloats, "Compare two numbers, a and b, as floats using all bits of the mantissa (normal comparisons ignore some of the least significant bits). Return -1 if a < b, 0 if a == b, and 1 if a > b. Eg. (compareFloats  (13 * (1 / 1000)) (13 / 1000))"},
	{"isNil",		(void*) IS_NIL,		"Return true if the argument is nil. Ex. (isNil nil)"},
	{"notNil",		(void*) NOT_NIL,	"Return true if the argument is not nil. Ex. (notNil nil)"},

	{"-----", NULL, "Logical Operations"},
	{"and",			primLogicalAnd,		"Logical AND. Return true only if both arguments are true. Ex. (and true false) -> false"},
	{"or",			primLogicalOr,		"Logical OR. Return true if either argument is true. Ex. (or true false) -> true"},
	{"not",			primLogicalNot,		"Logical NOT. Return true if argument is false and return false if argument is true. Ex. (not true) -> false"},

	{"-----", NULL, "Bitwise Operations"},
	{"&",			primBitAnd,			"Bitwise AND of two integers. Ex. (2 & 3) -> 2"},
	{"|",			primBitOr,			"Bitwise OR of two integers. Ex. (3 | 4) -> 7"},
	{"^",			primBitXor,			"Bitwise XOR of two integers. Ex. (2 ^ 3) -> 1"},
	{"<<",			primBitShiftL,		"Left shift. Ex. (1 << 3) -> 8"},
	{">>",			primBitShiftR,		"Arithmetic (signed) right shift. Ex. (-100 >> 2) -> -25"},
	{">>>",			primBitUShiftR,		"Logical (unsigned) right shift. Ex. (-100 >>> 2) -> 1073741799"},

	{"-----", NULL, "Arrays"},
	{"newArray",	primNewArray,		"Return a new array of a given size. Arguments: size [fillValue] Ex. myArray = (newArray 10)"},
	{"array",		primArray,			"Return a new array containing the arguments. Ex. print (array 1 2 3 'go')"},
	{"count",		primCount,			"Return the number of elements in an array or string. Ex. (count (array 'apple' 'orange' 'grapefruit'))"},
	{"at",			primArrayAt,		"Return the Nth element of an array (the first index is 1). Ex. (at myArray 1)"},
	{"atPut",		primArrayAtPut,		"Set the Nth element of an array (the first index is 1). Ex. atPut myArray 1 'First element'"},
	{"copyArray",	primCopyArray,		"Copy all or part of the given array into a new array. Arguments: array newSize startIndex Ex. copyArray myArray 2 1"},
	{"fillArray",	primFillArray,		"Fill the array (or part of it) with the given value. Arguments: array fillValue [startIndex endIndex]. Ex. fillArray myArray 0"},
	{"replaceArrayRange", primReplaceArrayRange, "Replace a subrange of an array with data from another (or the same) array. Arguments: array startIndex endIndex sourceArray [sourceStartIndex]. Ex. replaceArrayRange myArray 1 2 (array 3 4)"},

	{"-----", NULL, "Strings"},
	{"substring",	primSubstring,		"Return a string containing the letters from start through end of the given string. If end is omitted, copy from start through the end of the string. Arguments: string start [end] Ex. substring 'smiles' 2 5"},
	{"joinStringArray",	primJoinStringArray, "Return a new string that joins (concatenates) the strings in an array. Arguments: array [firstStringIndex lastStringIndex]"},
	{"lines",		primLines,			"Split a string into an array of lines."},
	{"words",		primWords,			"Split a string into an array of words. Ex. words 'The owl and the pussycat went to sea'"},
	{"letters",		primLetters,		"Split a string into an array of letters. A letter is a string containing the base letter plus zero or more modifiers (e.g. accent marks)."},
	{"string",		primString,			"Return a new string containing the arguments as raw bytes. Ex. myString = (string 71 80 32 105 115 32 70 117 110 33)"},
	{"nextMatchIn",	primNextMatchIn,	"Return the index of the next match of the first argument string in second argument string or nil if not found. Arguments: soughtString stringToSearch [startIndex] Ex. (nextMatchIn 'mile' 'smile')"},

	{"-----", NULL, "Files"},
	{"readFile",	primReadFile,		"Return a String or BinaryData with the contents of a file. Return nil if the file does not exist. Arguments: fileName [binaryFlag]"},
	{"writeFile",	primWriteFile,		"Write a String or BinaryData to a file, overwriting any previous contents. Arguments: fileName stringOrBinaryData"},
	{"deleteFile",	primDeleteFile,		"Delete a file or an empty directory. Arguments: fileOrDirectoryName"},
	{"renameFile",	primRenameFile,		"Rename a file or directory. Arguments: oldName newName"},
	{"setFileMode",	primSetFileMode,	"Set the file mode (i.e. permission bits). Arguments: filename mode"},
	{"listFiles",	primListFiles,		"List the files in the given directory. Arguments: [directoryName]"},
	{"listDirectories",	primListDirectories, "List the subdirectories in the given directory. Arguments: [directoryName]"},
	{"makeDirectory",	primMakeDirectory,	"Create a directory with the given path. Arguments: directoryPath"},
	{"absolutePath",	primAbsolutePath,	"Return the absolute path for the given relative path. Ex. (absolutePath '.')"},
	{"appPath",			primAppPath,		"Return the absolute path for application. Ex. (appPath)"},
	{"userHomePath",	primUserHomePath,	"Return the path to the user's home folder."},
	{"listEmbeddedFiles",	primListEmbeddedFiles,	"Return an array of names for embedded files."},
	{"readEmbeddedFile",	primReadEmbeddedFile,	"Return a String or BinaryData with the contents of the given embedded file. Return nil if the file does not exist. Arguments: fileName [binaryFlag]"},

	{"-----", NULL, "File Streams"},
	{"openFilestream",		primOpenFilestream,		"Open a new filestream. Arguments: fileName"},
	{"filestreamReadByte",	primFilestreamReadByte,	"Get the next byte from the given filestream. Arguments: aFileStream"},
	{"filestreamReadLine",	primFilestreamReadLine,	"Get the next line from the given filestream, assumed to be a UTF-8 encoded text file. If no line break is found within 1000 bytes, return that 1000 bytes. Arguments: aFileStream"},
	{"closeFilestream",		primCloseFilestream,	"Close a filestream. Arguments: aFileStream"},

	{"-----", NULL, "Functions"},
	{"to",			primDefineFunction,	"Define a function for all objects. Ex. to sayHello name { print 'Hello,' name }"},
	{"method",		primAddMethod,		"Define a method on objects of a certain class. Arguments: method name, class name, arg names, body."},
	{"return",		(void*) RETURN,		"Exit from a function, optionally returning a value. Ex. to lifeTheUnivereAndEverything { return 42 }"},
	{"argCount",	(void*) ARG_COUNT,	"Return the number of arguments to a function. Ex. to countArgs { print (argCount) }"},
	{"arg",			(void*) GETARG,		"Return the Nth argument of a function. Ex. to say { print (arg 1) }"},
	{"lastReceiver", (void*) LAST_RECEIVER, "Return the receiver of the most recent method call or nil if there were no method calls."},
	{"call",		(void*) APPLY,		"Call a function. The first argument is either the function name or a function object. Ex. (call '+' 1 2)"},
	{"callWith",	(void*) APPLY_TO_ARRAY,	"Call a function with an array of arguments. Ex. (call '+' (array 1 2))"},
	{"function",	primNewFunction,	"Return a new function object. Arguments: arg names, body. Ex. function arg1 { print 'Hello,' arg1 }"},
	{"parse",		primParse,			"Parse a string as GP code. Ex. parse 'print 42'"},
	{"primitives",	primPrimitiveNames,	"Return a list of primitives built into the virtual machine."},
	{"comment",		primNoop,			"Does nothing. Used to add comments to functions/methods. The argument is a string containing the comment."},
	{"globalFuncs",	primGlobalFuncs,	"Return the dictionary of global functions (functions defined with 'to'). Ex. (globalFuncs)"},

	{"-----", NULL, "Objects"},
	{"new",			primNew,			"Return a new instance of a class. First arg is class name, remaining (optional) args are initial field values. Ex. inspect (new 'Class')"},
	{"newIndexable", primNewIndexable,	"Return a new instance of a class with indexable fields. First arg is class name, second is indexable field count. Optional additional args are initial field values. Ex. inspect (newIndexable 'Array' 3)"},
	{"clone",		primClone,			"Return a shallow copy of the given object."},
	{"getField",	primGetField,		"Return the value an object field, by name or index. Ex. (getField p 'x')"},
	{"setField",	primSetField,		"Set the value an object field, by name or index. Ex. setField p 'x' 42"},
	{"toString",	primToString,		"Return a string representing the object. Ex. (17 toString) -> '17'"},
	{"isClass",		primIsClass,		"Return true if the first parameter is of the given class. The second argument may be either a class name or a class object. Ex. (isClass 123 'Integer')"},
	{"classOf",		primClassOf,		"Return the class of an object. Ex. inspect (classOf 'hello')"},
	{"hash",		primHash,			"Return a non-negative, immutable hash value for this object. Ex. hash 'hello'"},

	{"-----", NULL, "Binary Data"},
	{"newBinaryData", primNewBinaryData, "Return a new BinaryData with the given number of bytes. Arguments: [byteCount]"},
	{"byteCount",	primByteCount,		"Return the number of bytes in a BinaryData or string. For a string, this is the number bytes in its UTF-8 representation, not the number of letters. Ex. byteCount 'ö'"},
	{"byteAt",		primByteAt,			"Return the byte at the given byte index in a BinaryData or string. Arguments: string byteIndex"},
	{"byteAtPut",	primByteAtPut,		"Set the byte value (0-255) at the given byte index in a BinaryData. Arguments: binaryData byteIndex byteValue"},
	{"replaceByteRange", primReplaceByteRange, "Replace a subrange of a BinaryData with data from another (or the same) BinaryData or a String. Arguments: binaryData startIndex endIndex sourceBinaryData [sourceStartIndex]."},
	{"stringFromByteRange", primStringFromByteRange, "Return a string containing the given byte range of a BinaryData. Arguments: binaryData startIndex endIndex"},
	{"intAt",		primIntAt,			"Return the integer value at the given byte index in a BinaryData. Arguments: binaryData index [bigEndianFlag]"},
	{"intAtPut",	primIntAtPut,		"Set the integer value at the given byte index in a BinaryData. Arguments: binaryData index int [bigEndianFlag]"},
	{"uint32At",	primUInt32At,		"Return the 32-bit unsigned integer value at the given byte index in a BinaryData. Arguments: binaryData index [bigEndianFlag]"},
	{"uint32AtPut", primUInt32AtPut,	"Set the 32-bit unsigned integer value at the given byte index in a BinaryData. Arguments: binaryData index largeInteger [bigEndianFlag]"},
	{"float32At",	primFloat32At,		"Return the float value at the given byte index in a BinaryData. Arguments: binaryData index [bigEndianFlag]"},
	{"float32AtPut", primFloat32AtPut,	"Set the float value at the given byte index in a BinaryData. Arguments: binaryData index float [bigEndianFlag]"},

	{"deflate",		primZlibDeflate,	"Compress a String or BinaryData using the Deflate algorithm and return the result. Arguments: data"},
	{"inflate",		primZlibInflate,	"Decompress data using the Inflate algorithm and return the result. If stringFlag is true, return the result as a String. Arguments: compressedData [stringFlag]"},
	{"crc",			primZlibCRC,		"Return the CRC-32 (or Adler-32, if adlerFlag is true) checksum for the given String or BinaryData. lastCRC can be provided to combine CRCs. Arguments: data [adlerFlag lastCRC]"},
	{"sha256",		primSHA256,			"Return the digest of the SHA 256 hash value for the given String or BinaryData. Arguments: data"},
	{"sha1",		primSHA1,			"Return the 20-byte SHA-1 hash for the given String or BinaryData. Arguments: data"},

	{"-----", NULL, "Graphics: Pixel Manipulation"},
	{"getPixelAlpha",	primGetPixelAlpha,			"Return the alpha value of a pixel. Arguments: pixelData offset."},
	{"getPixelRGB",		primGetPixelRGB,			"Return the RGB value of a pixel (a 24 bit integer). Arguments: pixelData offset."},
	{"setPixelRGBA",	primSetPixelRGBA,			"Set the color of a pixel. Arguments: pixelData offset [red green blue alpha]."},
	{"fillPixelsRGBA",	primFillPixels,				"Fill a bitmap with a color. Arguments: pixelData [red green blue alpha]."},

	{"-----", NULL, "Graphics: Utilities"},
	{"applyMask",		primApplyMask,				"Erase (i.e. make transparent) portions of a bitmap using a mask bitmap. If the optional reverse flag is true, the mask is used to cut a hole. Otherwise, it is used as a stencil. Arguments: dstBitmap maskBitmap [reverseFlag]."},
	{"floodFill",		primFloodFill,				"Change the color of the solid-colored portion of a bitmap containing the seed point to a new color. The optional threshold argument is an integer from 0 to 7 (0 if omitted) that controls how precisely pixels must match the color at the seed point to be included in the region. 0 means 'exact match' and 7 is the most forgiving. Arguments: dstBitmap seedX seedY color [threshold]"},
	{"quadaticBezier",	primQuadraticBezier,		"Compute a point on the quadratic Bezier curve from p0 to p1 with control point c. Arguments: x0 y0 x1 y1 cx cy step totalSteps"},
	{"unmultiplyAlpha",	primUnmultiplyAlpha,		"Unmultiply pre-multiplied alpha in the given bitmap. Arguments: bitmap"},
	{"interpolatedPixel", primInterpolatedPixel,	"Return the interpolated color at the given location. x and y are 1-based. Store the result in the given color object, if provided. Arguments: bitmap x y [color]"},
	{"bitmapsTouch",	primBitmapsTouch,			"Return true if any corresponding pixels in the two bitmaps are not transparent (alpha < alphaThreshold). Arguments: bitmap1 bitmap2 [alphaThreshold]"},
	{"rectanglesTouch",	primRectanglesTouch,			"Return true if two Rectangles overlap."},

	{"-----", NULL, "Classes"},
	{"defineClass",	primDefineClass,	"Define or update a class. First arg is class name, remaining args are field names. Ex. defineClass Point x y"},
	{"classComment", primAddClassComment, "Add a comment to a class. A class can have multiple comments. First arg is class name, second is the comment string."},
	{"classes",		primClasses,		"Return an array of all defined classes."},
	{"class",		primClass,			"Return the class with the given name or index."},
	{"addClass",	primAddClass,		"Low-level. Add a class object to the class table."},

	{"-----", NULL, "System"},
	{"version",		primVersion,		"Return the GP version string."},
	{"msecsSinceStart", primMSecsSinceStart, "Return the number of millseconds since GP started. This wraps around roughly every 12 days."},
	{"time",		primTime,			"Return an array containing the GMT seconds and microseconds since midnight, January 1, 2000, the local time offset from GMT (seconds west), and the daylight savings flag."},
	{"sleep",		primSleep,			"Sleep (i.e. pause) for the given number of milliseconds. Ex. sleep 1000"},
	{"commandLine",	primCommandLine,	"Return an array containing the command and arguments used to launch GP."},
	{"platform",	primPlatform,		"Return a string describing the platform (e.g. 'iOS')."},
	{"exec",		primExec,			"Ask the OS to execute a command (a string) with zero or more argument strings. Return the pid of the exec-ed process"},
	{"execStatus",	primExecStatus,		"Return the status of an exec-ed process. Return nil if the project is still running. Argument: the process ID returned by exec."},
	{"openURL",		primOpenURL,		"Open the given URL in the default system browser. Argument: URL string"},

	{"-----", NULL, "Debugging"},
	{"error",		primHalt,			"Stop the script due to an error. By convention, the first argument is an error message."},
	{"halt",		primHalt,			"Stop the script. Does the same thing as error, but used debugging."},
	{"beep",		primBeep,			"Play the default system beep."},
	{"debugeeTask",	primDebugeeTask,	"Return the task that most recently stopped to an error or halt, or nil."},
	{"currentTask",	(void*) CURRENT_TASK, "Return the currently running task."},
	{"yield",		primYield,			"Yield execution of the current task."},
	{"resume",		(void*) RESUME,		"Resume execution of the given task."},
	{"uninterruptedly", (void*) UNINTERRUPTEDLY, "Do statements without allowing other tasks to run."},
	{"noop",		(void*) NOOP,		"Does nothing. Can take any number of arguments, which are ignored."},
	{"noopPrim",	primNoop,			""}, // internal, for testing

	{"-----", NULL, "Profiling"},
	{"startProfileClock",	primStartProfileClock,	"Start the profiling clock."},
	{"stopProfileClock",	primStopProfileClock,	"Stop the profiling clock."},

	{"-----", NULL, "Memory"},
	{"memStats",	primMemStats,		"Return an array with memory statistics: bytes used, total bytes, plus the object allocations and bytes allocated since the last garbage collection."},
	{"objectAfter",	primObjectAfter,	"Return the next object in memory, optionally filtered by classID. Used to enumerate objects. Pass nil to get the first object. Returns nil when there are no more objects. Arguments: previousObject [classID] Ex. objectAfter nil 4"},
	{"objectReferences", primObjectReferences,	"Return an array containing all objects that contain a reference to the argument."},
	{"replaceObjects", primReplaceObjects,		"Replace all references to each object in the first argument array with the corresponding object in the second argument array."},
	{"gc",			(void*) GC,			"Garbage collect memory. Reclaim discarded objects and compact the remaining objects."},
	{"findGarbage",	primFindGarbage,	"Find garbage objects but don't reclaim them. Used to analyze object memory."},
	{"isGarbage",	primIsGarbage,		"Return true if the given object was identified as garbage by findGarbage. Used to analyze object memory."},
	{"objAddr",		primObjAddr,		"Return the current word address of the given object. Used to analyze object memory."},
	{"objWords",	primObjWords,		"Return the number of words used by the given object. Used to analyze object memory."},
	{"memDumpWords", primMemDumpWords,	""}, // word-level memory dump; internal, for debugging
	{"memDumpObjects",	primMemDumpObjects,	""}, // object-level memory demp; internal, for debugging
	{"objData",		primObjData,		""}, // return object bytes, for debugging

	{"-----", NULL, "Module Support"},
	{"module",			primModule,		"Start a new module"},
	{"sessionModule",		primSessionModule,	"Return the module object for the current session."},
	{"consoleModule",		primConsoleModule,	"Return the module object for the current console."},
	{"thisModule",			primThisModule,		"Return the module that the current function or method is defined, or returns the session module."},
	{"topLevelModule",		primTopLevelModule,	"Return the top-level module."},
	{"setSessionModule",	primSetSessionModule,	"Set the sessionModule and currentModule VM variables to the given module. (Internal)"},
	{"setConsoleModule",	primSetConsoleModule,	"Set the consoleModule to the given module."},

	{"-----", NULL, "Method Cache"},
	{"clearMethodCache",	primClearMethodCache,	"Clear the method cache. If a string argument is supplied, clear only the entry for that method/function name."},
	{"methodCacheStats",	primMethodCacheStats,	"Return an array with the method cache size, hits, and misses."},

	{"-----", NULL, "StarLogo Support"},
	{"starLogoDrawPatches",		primDrawPatches,	"Arguments: patchData, pixelData, rgb"},
	{"starLogoDiffuse1",		primDiffuse1,		"Arguments: patchData, width"},
	{"starLogoDiffuse2",		primDiffuse2,		"Arguments: patchData, width, factor"},
};

PrimEntry* corePrimitives(int *primCount) {
	*primCount = sizeof(corePrimList) / sizeof(PrimEntry);
	return corePrimList;
}

// ***** Primitive Table *****

typedef struct {
	PrimEntry *primEntries;
	int count;
} PrimitiveSet;

#define MAX_PRIM_SETS 100
PrimitiveSet primSets[MAX_PRIM_SETS];
int primSetCount = 0;

void addPrimitiveSet(PrimEntry *primEntries, int primCount) {
	// Install the given set of primitive entries.
	if (primSetCount >= MAX_PRIM_SETS) {
		primFailed("Too many primitive sets");
		return;
	}
	primSets[primSetCount].primEntries = primEntries;
	primSets[primSetCount].count = primCount;
	primSetCount++;
}

#ifdef NO_GRAPHICS
#define NO_SDL
#endif

#ifndef NO_SDL

#include "SDL_loadso.h"

void loadPrimitivePlugins() {
	// Load primitive sets from the 'plugins' directory.

	char pluginPrefix[] = "plugins/";
	char pluginFileName[1000];

	OBJ pluginNames = directoryContents(pluginPrefix, false);
	int count = objWords(pluginNames);
	for (int i = 0; i < count; i++) {
		PrimEntry* (*primListFnc)(int *);
		strncpy(pluginFileName, pluginPrefix, 999);
		strncat(pluginFileName, obj2str(FIELD(pluginNames, i)), 999);

		void *sharedObjectFile = SDL_LoadObject(pluginFileName);
		if (!sharedObjectFile) continue; // couldn't open shared library
		primListFnc = SDL_LoadFunction(sharedObjectFile, "primList");
		if (!primListFnc) {
			printf("Plugin library %s does not export primList() function\n", pluginFileName);
			continue;
		}
		int entryCount;
		PrimEntry* entries = primListFnc(&entryCount);
		addPrimitiveSet(entries, entryCount);
	}
}

#else

void loadPrimitivePlugins() { } // stub; primitive loading requires SDL

#endif

void initPrimitiveDictionary() {
	primitiveDictionary = newDict(500);

	for (int i = 0; primSets[i].count > 0; i++) {
		PrimEntry *entries = primSets[i].primEntries;
		int n = primSets[i].count;
		for (int j = 0; j < n; j++) {
			char *primName = entries[j].primName;
			if (strcmp("-----", primName) != 0) {
				OBJ primRef = newBinaryObj(ExternalReferenceClass, ExternalReferenceWords);
				ADDR *a = (ADDR*) BODY(primRef);
				a[0] = (ADDR) entries[j].primFunc;
				dictAtPut(primitiveDictionary, newString(primName), primRef);
			}
		}
	}
}

void initPrimitiveTable() {
	// The primitive table is collection of PrimEntry arrays, one
	// array for each set of primitives (core, graphics, sound, etc.)
	// To add a new set of primtives, declare a function to return the
	// primitive set and call it here.

	memset(primSets, 0, sizeof(primSets));
	primSetCount = 0;

	int count;
	PrimEntry *entries = corePrimitives(&count);
	addPrimitiveSet(entries, count);

#ifndef NO_GRAPHICS
	PrimEntry* graphicsPrimitives(int *count);
	entries = graphicsPrimitives(&count);
	addPrimitiveSet(entries, count);

	#ifndef NO_CAIRO
		PrimEntry* vectorPrimitives(int *count);
		entries = vectorPrimitives(&count);
		addPrimitiveSet(entries, count);

		PrimEntry* pathPrimitives(int *count);
		entries = pathPrimitives(&count);
		addPrimitiveSet(entries, count);
	#endif // NO_CAIRO

	#ifndef NO_JPEG
		PrimEntry* jpegPrimitives(int *count);
		entries = jpegPrimitives(&count);
		addPrimitiveSet(entries, count);
	#endif // NO_JPEG

	#ifndef NO_TEXT
		PrimEntry* textAndFontPrimitives(int *count);
		entries = textAndFontPrimitives(&count);
		addPrimitiveSet(entries, count);
	#endif // NO_TEXT

#endif // NO_GRAPHICS

#ifndef NO_SOCKETS
	PrimEntry* socketPrimitives(int *count);
	entries = socketPrimitives(&count);
	addPrimitiveSet(entries, count);
#endif // NO_SOCKETS

#ifndef NO_SOUND
	PrimEntry* soundPrimitives(int *count);
	entries = soundPrimitives(&count);
	addPrimitiveSet(entries, count);
#endif // NO_SOUND

// The camera primitives are currently implemented only on MacOS and iOS:
#if !(defined(MAC) || defined(IOS))
#define NO_CAMERA 1
#endif

#ifndef NO_CAMERA
	PrimEntry* cameraPrimitives(int *count);
	entries = cameraPrimitives(&count);
	addPrimitiveSet(entries, count);
#endif // NO_CAMERA

#ifndef NO_SERIAL_PORTS
	PrimEntry* serialPortPrimitives(int *count);
	entries = serialPortPrimitives(&count);
	addPrimitiveSet(entries, count);
#endif // NO_SERIAL_PORTS

#ifdef EMSCRIPTEN
	PrimEntry* browserPrimitives(int *count);
	entries = browserPrimitives(&count);
	addPrimitiveSet(entries, count);
#endif // EMSCRIPTEN

#ifndef NO_HTTP
    PrimEntry* httpPrimitives(int *count);
    entries = httpPrimitives(&count);
    addPrimitiveSet(entries, count);
#endif // NO_HTTP

	initPrimitiveDictionary();
}

PrimEntry* primLookup(char *primName) {
	for (int i = 0; primSets[i].count > 0; i++) {
		PrimEntry *entries = primSets[i].primEntries;
		int n = primSets[i].count;
		for (int j = 0; j < n; j++) {
			if (strcmp(primName, entries[j].primName) == 0) return &entries[j];
		}
	}
	return NULL;
}

#define MAX_PRIM_NAMES 2000

OBJ primitiveNames() {
	char *primNames[MAX_PRIM_NAMES];
	int primCount = 0;
	for (int i = 0; primSets[i].count > 0; i++) {
		PrimEntry *entries = primSets[i].primEntries;
		int n = primSets[i].count;
		for (int j = 0; j < n; j++) {
			char *primName = entries[j].primName;
			if ((strcmp("-----", primName) != 0) && (primCount < MAX_PRIM_NAMES)) {
				primNames[primCount++] = primName;
			}
		}
	}
	OBJ result = newArray(primCount);
	for (int i = 0; i < primCount; i++) {
		FIELD(result, i) = newString(primNames[i]);
	}
	return result;
}

// ***** Help *****

#define HELPSTRING_MAX 10000

OBJ primHelp(int nargs, OBJ args[]) {
	char helpString[HELPSTRING_MAX + 1];
	int helpStringSize = 0;
	char s[200];

	if (nargs && IS_CLASS(args[0], StringClass)) {
		char *arg = obj2str(args[0]);
		PrimEntry *entry = primLookup(arg);
		if (entry) sprintf(helpString, "%s", entry->help);
		else sprintf(helpString, "Unknown command: %s", arg);
	} else {
		helpString[0] = 0;
		for (int i = 0; primSets[i].count > 0; i++) {
			PrimEntry *entries = primSets[i].primEntries;
			int n = primSets[i].count;
			for (int j = 0; j < n; j++) {
				s[0] = 0;
				PrimEntry *entry = &entries[j];
				if (strcmp("-----", entry->primName) == 0) {
					sprintf(s, "\n-- %s --\n", entry->help); // category
				} else {
					if (entry->help[0] != '\0') sprintf(s, "   %s\n", entry->primName); // primitive
				}
				int n = strlen(s);
				if (n && ((helpStringSize + n) < HELPSTRING_MAX)) {
					strcat(helpString, s);
					helpStringSize += n;
				}
			}
		}
	}
	return newString(helpString);
}
