/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// dataPrims.cpp - Microblocks list and string primitives
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

static void printIntegerOrBooleanInto(OBJ obj, char *buf) {
	// Helper for primJoin. Write a representation of obj into the given string.
	// Assume buf has space for at least 20 characters.

	*buf = 0; // null terminator
	if (isInt(obj)) sprintf(buf, "%d", obj2int(obj));
	else if (obj == falseObj) strcat(buf, "false");
	else if (obj == trueObj) strcat(buf, "true");
	else if (IS_TYPE(obj, StringType)) sprintf(buf, "%.15s...", obj2str(obj));
}

static inline int matches(const char *s, OBJ obj) {
	// Return true if the given object is a string that matches s.

	return IS_TYPE(obj, StringType) && (0 == strcmp(s, obj2str(obj)));
}

static inline char * nextUTF8(char *s) {
	// Return a pointer to the start of the UTF8 character following the given one.
	// If s points to a null byte (i.e. end of the string) return it unchanged.

	if (!*s) return s; // end of string
	if (*s < 128) return s + 1; // single-byte character
	if (0xC0 == (*s & 0xC0)) s++; // start of multi-byte character
	while (0x80 == (*s & 0xC0)) s++; // skip continuation bytes
	return s;
}

static int countUTF8(char *s) {
	int count = 0;
	while (*s) {
		s = nextUTF8(s);
		count++;
	}
	return count;
}

static int bytesForUnicode(int unicode) {
	if (unicode < 0x80) return 1; // 7 bits, one byte
	if (unicode < 0x800) return 2; // 11 bits, two bytes
	if (unicode < 0x10000) return 3; // 16 bits, three bytes
	if (unicode < 0x11000) return 4; // 21 bits, four bytes
	return 0; // invalid unicode value; skip
}

static uint8 * appendUTF8(uint8 *s, int unicode) {
	// Append the UTF-8 bytes for the given Unicode character to the given string and
	// return a pointer to the following byte.

	if (unicode < 0x80) { // 7 bits, one byte
		*s++ = unicode;
	} else if (unicode < 0x800) { // 11 bits, two bytes
		*s++ = 0xC0 | ((unicode >> 6) & 0x1F);
		*s++ = 0x80 | (unicode & 0x3F);
	} else if (unicode < 0x10000) { // 16 bits, three bytes
		*s++ = 0xE0 | ((unicode >> 12) & 0x0F);
		*s++ = 0x80 | ((unicode >>  6) & 0x3F);
		*s++ = 0x80 | (unicode & 0x3F);
	} else if (unicode < 0x11000) { // 21 bits, four bytes
		*s++ = 0xF0 | ((unicode >> 18) & 0x07);
		*s++ = 0x80 | ((unicode >> 12) & 0x3F);
		*s++ = 0x80 | ((unicode >>  6) & 0x3F);
		*s++ = 0x80 | (unicode & 0x3F);
	}
	return s;
}

// Growable Lists:
// First field is the item count (N). Items are stored in fields 2..N.
// Fields N+1..end are available for adding additional items without growing.

OBJ primNewList(int argCount, OBJ *args) {
	// Return a new List filled with zeros. Optional argument specifies size.

	int count = ((argCount > 0) && isInt(args[0])) ? obj2int(args[0]) : 0;
	if (count < 0) count = 0;
	OBJ result = newObj(ListType, count + 1, int2obj(0)); // filled with zeros
	if (result) FIELD(result, 0) = int2obj(count);
	return result;
}

OBJ primFillList(int argCount, OBJ *args) {
	OBJ obj = args[0];
	OBJ value = args[1];

	if (IS_TYPE(obj, ListType)) {
		int count = obj2int(FIELD(obj, 0));
		if (count >= WORDS(obj))count = WORDS(obj) - 1;
		for (int i = 0; i < count; i++) FIELD(obj, i + 1) = value;
		int end = WORDS(obj) + HEADER_WORDS;
		for (int i = HEADER_WORDS + 1; i < end; i++) ((OBJ *) obj)[i] = value;
	} else if (IS_TYPE(obj, ByteArrayType)) {
		if (!isInt(value)) return fail(byteArrayStoreError);
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return fail(byteArrayStoreError);
		uint8 *dst = (uint8 *) &FIELD(obj, 0);
		uint8 *end = dst + (4 * WORDS(obj));
		while (dst < end) *dst++ = byteValue;
	} else {
		fail(needsListError);
	}
	return falseObj;
}

OBJ primAt(int argCount, OBJ *args) {
	OBJ obj = args[1];
	int i, count = 0;

	if (IS_TYPE(obj, ListType)) {
		count = obj2int(FIELD(obj, 0));
		if (count >= WORDS(obj)) count = WORDS(obj) - 1;
	} else if (IS_TYPE(obj, StringType)) {
		count = stringSize(obj);
	} else if (IS_TYPE(obj, ByteArrayType)) {
		count = 4 * WORDS(obj);
	}
	if (isInt(args[0])) {
		i = obj2int(args[0]);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else if (matches("random", args[0])) {
		i = (rand() % count) + 1;
	} else if (matches("last", args[0])) {
		i = count;
	} else {
		return fail(needsIntegerIndexError);
	}
	if (IS_TYPE(obj, ListType)) {
		return FIELD(obj, i);
	} else if (IS_TYPE(obj, StringType)) {
		char *start = obj2str(obj);
		if (i > countUTF8(start)) return fail(indexOutOfRangeError);
		while (i-- > 1) start = nextUTF8(start);
		int startOffset = start - obj2str(obj);
		int byteCount = nextUTF8(start) - start;
		OBJ result = newString(byteCount);
		if (result) {
			memcpy(obj2str(result), obj2str(args[1]) + startOffset, byteCount);
		}
		return result;
	} else if (IS_TYPE(obj, ByteArrayType)) {
		uint8 *bytes = (uint8 *) &FIELD(obj, 0);
		return int2obj(bytes[i - 1]);
	}
	return fail(needsListError);
}

OBJ primAtPut(int argCount, OBJ *args) {
	OBJ obj = args[1];
	OBJ value = args[2];
	int count, i;
	uint32 byteValue = 0;

	if (IS_TYPE(obj, ListType)) {
		count = obj2int(FIELD(obj, 0));
		if (count >= WORDS(obj)) count = WORDS(obj) - 1;
	} else if (IS_TYPE(obj, ByteArrayType)) {
		count = 4 * WORDS(obj);
		if (!isInt(value)) return fail(byteArrayStoreError);
		byteValue = obj2int(value);
		if (byteValue > 255) return fail(byteArrayStoreError);
	} else {
		return fail(needsListError);
	}

	if (matches("all", args[0])) {
		if (IS_TYPE(obj, ListType)) {
			for (i = 1; i <= count; i++) {
				FIELD(obj, i) = value;
			}
		} else if (IS_TYPE(obj, ByteArrayType)) {
			for (i = 1; i <= count; i++) {
				((uint8 *) &FIELD(obj, 0))[i - 1] = byteValue;
			}
		}
		return falseObj;
	}

	if (isInt(args[0])) {
		i = obj2int(args[0]);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else if (matches("last", args[0])) {
		i = count;
	} else {
		return fail(needsIntegerIndexError);
	}

	if (IS_TYPE(obj, ListType)) {
		FIELD(obj, i) = value;
	} else if (IS_TYPE(obj, ByteArrayType)) {
		((uint8 *) &FIELD(obj, 0))[i - 1] = byteValue;
	}
	return falseObj;
}

OBJ primLength(int argCount, OBJ *args) {
	OBJ obj = args[0];

	if (IS_TYPE(obj, ListType)) {
		return FIELD(obj, 0); // actual count stored in first field
	} else if (IS_TYPE(obj, ByteArrayType)) {
		return int2obj(4 * WORDS(obj));
	} else if (IS_TYPE(obj, StringType)) {
		return int2obj(countUTF8(obj2str(obj)));
	}
	return fail(needsListError);
}

// Named primitives

OBJ primMakeList(int argCount, OBJ *args) {
	OBJ result = newObj(ListType, argCount + 1, falseObj);
	if (!result) return result; // allocation failed

	FIELD(result, 0) = int2obj(argCount);
	for (int i = 0; i < argCount; i++) FIELD(result, i + 1) = args[i];
	return result;
}

OBJ primListAddLast(int argCount, OBJ *args) {
	// Add the given item to the end of the List. Grow if necessary.

	OBJ list = args[1];
	if (!IS_TYPE(list, ListType)) return fail(needsListError);

	int count = obj2int(FIELD(list, 0));
	if (count >= (WORDS(list) - 1)) { // no more capacity; try to grow
		int growBy = count / 3;
		if (growBy < 4) growBy = 3;
		if (growBy > 100) growBy = 100;

		list = resizeObj(list, WORDS(list) + growBy);
	}
	if (count < (WORDS(list) - 1)) { // append item if there's room
		count++;
		FIELD(list, count) = args[0];
		FIELD(list, 0) = int2obj(count);
	}
	return falseObj;
}

OBJ primListDelete(int argCount, OBJ *args) {
	// Delete item(s) from the given List.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[1], ListType)) return fail(needsListError);
	OBJ list = args[1];
	int count = obj2int(FIELD(list, 0));
	if (count >= WORDS(list)) count = WORDS(list) - 1;

	if (matches("all", args[0])) {
		for (int i = 0; i <= count; i++) FIELD(list, i) = zeroObj;
		return falseObj;
	}
	if (matches("last", args[0])) {
		if (count) {
			FIELD(list, count) = zeroObj;
			FIELD(list, 0) = int2obj(count - 1);
		}
		return falseObj;
	}

	if (!isInt(args[0])) return fail(needsIntegerError);
	int i = obj2int(args[0]);
	if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);

	while (i < count) {
		FIELD(list, i) = FIELD(list, i + 1);
		i++;
	}
	FIELD(list, count) = zeroObj; // clear final field
	FIELD(list, 0) = int2obj(count - 1);
	return falseObj;
}

OBJ primCopyFromTo(int argCount, OBJ *args) {
	// Return a copy of the first argument (a string or list) between the indices give by the
	// second and third arguments. If the optional third argument is not supplied it is taken
	// to be the last index.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[1])) return fail(needsIntegerError);
	int startIndex = obj2int(args[1]);
	if (startIndex < 1) startIndex = 1;
	if ((argCount > 2) && !isInt(args[2])) return fail(needsIntegerError);

	OBJ src = args[0];
	if (IS_TYPE(src, ListType)) {
		int srcLen = obj2int(FIELD(src, 0));
		int endIndex = (argCount > 2) ? obj2int(args[2]) : srcLen;
		if (endIndex > srcLen) endIndex = srcLen;
		int resultLen = (endIndex - startIndex) + 1;
		if (resultLen < 0) resultLen = 0;
		OBJ result = newObj(ListType, resultLen + 1, int2obj(0));
		if (result) {
			src = args[0]; // update src after possible GC
			FIELD(result, 0) = int2obj(resultLen);
			OBJ *dst = &FIELD(result, 1);
			for (int i = startIndex; i <= endIndex; i++) *dst++ = FIELD(src, i);
		}
		return result;
	} else if (IS_TYPE(src, StringType)) {
		int srcLen = countUTF8(obj2str(src));
		int endIndex = (argCount > 2) ? obj2int(args[2]) : srcLen;
		if (endIndex > srcLen) endIndex = srcLen;
		if (startIndex > endIndex) return newString(0);

		char *start = obj2str(src);
		for (int i = 1; i < startIndex; i++) start = nextUTF8(start);
		int startOffset = start - obj2str(src);
		char *end = start;
		for (int i = startIndex; i <= endIndex; i++) end = nextUTF8(end);
		int byteCount = end - start;

		OBJ result = newString(byteCount);
		if (result) {
			memcpy(obj2str(result), obj2str(args[0]) + startOffset, byteCount);
		}
		return result;
	}
	return fail(needsIndexable);
}

OBJ primJoin(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	char buf[50];
	int count, resultCount = 0;
	OBJ arg, arg1 = args[0];
	OBJ result = falseObj;

	if (IS_TYPE(arg1, ListType)) {
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (!IS_TYPE(arg, ListType)) return fail(joinArgsNotSameType);
			resultCount += obj2int(FIELD(arg, 0));
		}
		result = newObj(ListType, resultCount + 1, int2obj(0));
		if (!result) return result; // allocation failed
		FIELD(result, 0) = int2obj(resultCount);
		OBJ *dst = &FIELD(result, 1);
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			count = obj2int(FIELD(arg, 0));
			if (count >= WORDS(arg)) count = WORDS(arg) - 1;
			for (int j = 0; j < count; j++) *dst++ = FIELD(arg, j + 1);
		}
	} else if (IS_TYPE(arg1, StringType)) {
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (IS_TYPE(arg, StringType)) {
				resultCount += stringSize(arg);
			} else if (isInt(arg) || isBoolean(arg)) {
				printIntegerOrBooleanInto(arg, buf);
				resultCount += strlen(buf);
			} else {
				return fail(joinArgsNotSameType);
			}
		}
		result = newString(resultCount);
		if (!result) return result; // allocation failed
		char *dst = (char *) &FIELD(result, 0);
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (IS_TYPE(arg, StringType)) {
				count = stringSize(arg);
				memcpy(dst, obj2str(arg), count);
				dst += count;
			} else if (isInt(arg) || isBoolean(arg)) {
				printIntegerOrBooleanInto(arg, buf);
				count = strlen(buf);
				memcpy(dst, buf, count);
				dst += count;
			}
		}
		*dst = 0; // null terminator
	} else {
		fail(needsIndexable);
	}
	return result;
}

OBJ primJoinStrings(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], ListType)) return fail(needsListError);

	OBJ stringList = args[0];
	int count = obj2int(FIELD(stringList, 0));
	if (count <= 0) return newString(0);

	char *separator = ((argCount > 1) && IS_TYPE(args[1], StringType)) ? obj2str(args[1]) : "";
	int separatorLen = strlen(separator);
	char buf[50];

	int resultBytes = (count - 1) * separatorLen;
	for (int i = 0; i < count; i++) {
		OBJ item = FIELD(stringList, i + 1);
		if (IS_TYPE(item, StringType)) {
			resultBytes += stringSize(item);
		} else if (isInt(item) || isBoolean(item)) {
			printIntegerOrBooleanInto(item, buf);
			resultBytes += strlen(buf);
		} else {
			resultBytes += strlen(obj2str(item));
		}
	}
	OBJ result = newString(resultBytes);
	if (!result) return result; // allocation failed

	// update temps after possible GC triggered by newString()
	stringList = args[0];
	if (separatorLen) separator = obj2str(args[1]);

	char *dst = obj2str(result);
	for (int i = 0; i < count; i++) {
		OBJ item = FIELD(stringList, i + 1);
		char *s = obj2str(item);
		if (isInt(item) || isBoolean(item)) {
			printIntegerOrBooleanInto(item, buf);
			s = buf;
		}
		int n = strlen(s);
		memcpy(dst, s, n);
		dst += n;
		if (separatorLen && (i < (count - 1))) {
			memcpy(dst, separator, separatorLen);
			dst += separatorLen;
		}
	}
	return result;
}

OBJ primFind(int argCount, OBJ *args) {
	// If both arguments are strings, return the index of next instance the second string
	// in the first or -1 if not found. If the second argument is a list, return the index
	// of the first argument in the list or -1 if not found.
	// An optional third argument can be used to specify the starting point for the search.

	if (argCount < 2) return fail(notEnoughArguments);
	OBJ arg0 = args[0];
	OBJ arg1 = args[1];
	int startOffset = ((argCount > 2) && isInt(args[2])) ? obj2int(args[2]) : 1;
	if (startOffset < 1) startOffset = 1;

	if (IS_TYPE(arg1, StringType)) { // search for substring in a string
		if (!(IS_TYPE(arg0, StringType))) return fail(needsStringError);
		if (startOffset && (startOffset > stringSize(arg1))) return int2obj(-1); // not found
		char *s = obj2str(arg1);
		char *sought = obj2str(arg0);
		char *match = strstr(s + startOffset - 1, sought);
		return int2obj(match ? (match - s) + 1 : -1);
	} else if (IS_TYPE(arg1, ListType)) { // search in a list
		int listCount = obj2int(FIELD(arg1, 0));
		if (startOffset > listCount) return int2obj(-1); // not found
		if (IS_TYPE(arg0, StringType)) { // search for a string in a list
			char *sought = obj2str(arg0);
			for (int i = startOffset; i <= listCount; i++) {
				OBJ item = FIELD(arg1, i);
				if (item == arg0) return int2obj(i); // identical
				if (IS_TYPE(item, StringType) && (0 == strcmp(sought, obj2str(item)))) {
					return int2obj(i); // string match
				}
			}
		} else { // search for an integer, boolean, or other object in a list
			for (int i = startOffset; i <= listCount; i++) {
				if (FIELD(arg1, i) == arg0) return int2obj(i); // identical
			}
		}
		return int2obj(-1);
	}
	return fail(needsIndexable);
}

OBJ primUnicodeAt(int argCount, OBJ *args) {
	// Return the Unicode value (an integer) for the given character of a string.
	// Return -1 if the given character is not a valid UTF-8 Unicode character.

	if (argCount < 2) return fail(notEnoughArguments);

	if (!isInt(args[0])) return fail(needsIntegerIndexError);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	int i = obj2int(args[0]);
	char *s = obj2str(args[1]);
	if ((i < 1) || (i > countUTF8(s))) return fail(indexOutOfRangeError);

	for (; i > 1; i--) s = nextUTF8(s); // find first byte of desired Unicode character
	int result = -1;
	int firstByte = *s;
	if (firstByte < 128) {
		result = firstByte; // 7-bit ASCII
	} else if (firstByte < 0xE0) {
		result = ((firstByte & 0x1F) << 6) | (*(s + 1) & 0x3F);
	} else if (firstByte < 0xF0) {
		result = ((firstByte & 0xF) << 12) | ((*(s + 1) & 0x3F) << 6) | (*(s + 2) & 0x3F);
	} else if (firstByte < 0xF8) {
		result = ((firstByte & 0x7) << 18) |
			((*(s + 1) & 0x3F) << 12) |
			((*(s + 2) & 0x3F) << 6) |
			 (*(s + 3) & 0x3F);
	}
	return int2obj(result);
}

OBJ primUnicodeString(int argCount, OBJ *args) {
	// Return a string containing the given Unicode character(s).

	if (argCount < 1) return fail(notEnoughArguments);
	OBJ arg = args[0];

	if (isInt(arg)) { // convert a single integer to a Unicode character
		uint8 buf[8]; // buffer for one UTF-8 character
		uint8 *s = appendUTF8(buf, obj2int(arg));
		int byteCount = s - buf;
		return newStringFromBytes(buf, byteCount);
	} else if (IS_TYPE(arg, ListType)) { // convert list of integers to a Unicode string
		int listCount = obj2int(FIELD(arg, 0));
		int utfByteCount = 0;
		for (int i = 1; i <= listCount; i++) {
			OBJ item = FIELD(arg, i);
			if (!isInt(item)) return fail(needsIntegerError);
			utfByteCount += bytesForUnicode(obj2int(item));
		}
		OBJ result = newString(utfByteCount);
		if (!result) return result; // allocation failed
		arg = args[0]; // update arg after possible GC
		uint8 *s = (uint8 *) obj2str(result);
		for (int i = 1; i <= listCount; i++) {
			OBJ item = FIELD(arg, i);
			if (!isInt(item)) return fail(needsIntegerError);
			s = appendUTF8(s, obj2int(item));
		}
		return result;
	}
	return fail(needsIndexable);
}

OBJ primFreeMemory(int argCount, OBJ *args) {
	return int2obj(wordsFree());
}

OBJ primTypeOf(int argCount, OBJ *args) {
	return int2obj(objType(args[0]));
}

// Primitives

static PrimEntry entries[] = {
	{"makeList", primMakeList},
	{"addLast", primListAddLast},
	{"delete", primListDelete},
	{"join", primJoin},
	{"copyFromTo", primCopyFromTo},
	{"find", primFind},
	{"joinStrings", primJoinStrings},
	{"unicodeAt", primUnicodeAt},
	{"unicodeString", primUnicodeString},
	{"freeMemory", primFreeMemory},
	{"typeOf", primTypeOf},
};

void addDataPrims() {
	addPrimitiveSet("data", sizeof(entries) / sizeof(PrimEntry), entries);
}
