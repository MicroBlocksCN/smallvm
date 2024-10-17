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
#include "persist.h"

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
	else if (obj == falseObj) strcat(buf, "0");
	else if (obj == trueObj) strcat(buf, "1");
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
	if ((uint8) *s < 128) return s + 1; // single-byte character
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

static int unicodeCodePoint(char *s) {
	// Return the Unicode code point starting at the given start byte.

	int result = -1; // bad unicode character; should not happen
	uint8 *byte = (uint8 *) s;
	int firstByte = byte[0];
	if (firstByte < 128) {
		result = firstByte; // 7-bit ASCII
	} else if (firstByte < 0xE0) {
		result = ((firstByte & 0x1F) << 6) | (byte[1] & 0x3F);
	} else if (firstByte < 0xF0) {
		result = ((firstByte & 0xF) << 12) | ((byte[1] & 0x3F) << 6) | (byte[2] & 0x3F);
	} else if (firstByte < 0xF8) {
		result = ((firstByte & 0x7) << 18) |
			((byte[1] & 0x3F) << 12) |
			((byte[2] & 0x3F) << 6) |
			 (byte[3] & 0x3F);
	}
	return result;
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
	OBJ fillValue = (argCount > 1) ? args[1] : zeroObj;

	OBJ result = newObj(ListType, count + 1, fillValue);
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
	} else if (IS_TYPE(obj, ByteArrayType)) {
		if (!isInt(value)) return fail(byteArrayStoreError);
		int byteValue = obj2int(value);
		if ((byteValue < 0) || (byteValue > 255)) return fail(byteArrayStoreError);
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
		count = BYTES(obj);
	}

	OBJ arg0 = args[0];
	if (isInt(arg0)) {
		i = obj2int(arg0);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else if (matches("random", arg0)) {
		if (count == 0) return fail(indexOutOfRangeError);
		i = (rand() % count) + 1;
	} else if (matches("last", arg0)) {
		i = count;
	} else if (IS_TYPE(arg0, StringType)) {
		i = evalInt(arg0);
		if ((0 == i) && !matches("0", arg0)) return fail(needsIntegerIndexError);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else {
		return fail(needsIntegerIndexError);
	}

	if (IS_TYPE(obj, ListType)) {
		return FIELD(obj, i);
	} else if (IS_TYPE(obj, StringType)) {
		char *start = obj2str(obj);
		while (i-- > 1) { // find start of the ith Unicode character
			if (!*start) return fail(indexOutOfRangeError); // end of string
			start = nextUTF8(start);
		}
		int byteCount = nextUTF8(start) - start;
		OBJ result = newString(byteCount);
		if (result) {
			memcpy(obj2str(result), start, byteCount);
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
		count = BYTES(obj);
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

	OBJ arg0 = args[0];
	if (isInt(arg0)) {
		i = obj2int(arg0);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else if (matches("last", arg0)) {
		i = count;
	} else if (IS_TYPE(arg0, StringType)) {
		i = evalInt(arg0);
		if ((0 == i) && !matches("0", arg0)) return fail(needsIntegerIndexError);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
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
		return int2obj(BYTES(obj));
	} else if (IS_TYPE(obj, StringType)) {
		return int2obj(countUTF8(obj2str(obj)));
	}
	return zeroObj;
}

// Named primitives

OBJ primMakeList(int argCount, OBJ *args) {
	OBJ result = newObj(ListType, argCount + 1, falseObj);
	if (!result) return result; // allocation failed

	FIELD(result, 0) = int2obj(argCount);
	for (int i = 0; i < argCount; i++) FIELD(result, i + 1) = args[i];
	return result;
}

OBJ primRange(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	int start = evalInt(args[0]);
	int end = evalInt(args[1]);
	int incr = (argCount > 2) ? evalInt(args[2]) : 1;
	if (incr < 1) return fail(needsPositiveIncrement); // increment must be >= 1

	int count;
	if (end >= start) {
		count = ((end - start) / incr) + 1;
	} else {
		count = ((start - end) / incr) + 1;
		incr = -incr; // make the increment negative
	}

	OBJ result = newObj(ListType, count + 1, falseObj);
	if (!result) return result; // allocation failed

	FIELD(result, 0) = int2obj(count);
	int n = start;
	for (int i = 0; i < count; i++) {
		FIELD(result, i + 1) = int2obj(n);
		n += incr;
	}
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

	int i;
	if (isInt(args[0])) {
		i = obj2int(args[0]);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else if (matches("all", args[0])) {
		for (int i = 0; i <= count; i++) FIELD(list, i) = zeroObj;
		return falseObj;
	} else if (matches("last", args[0])) {
		if (count) {
			FIELD(list, count) = zeroObj;
			FIELD(list, 0) = int2obj(count - 1);
		}
		return falseObj;
	} else if (IS_TYPE(args[0], StringType)) {
		i = evalInt(args[0]);
		if ((0 == i) && !matches("0", args[0])) return fail(needsIntegerIndexError);
		if ((i < 1) || (i > count)) return fail(indexOutOfRangeError);
	} else {
		return fail(needsIntegerIndexError);
	}

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
	} else if (IS_TYPE(src, ByteArrayType)) {
		int srcLen = BYTES(src);
		int endIndex = (argCount > 2) ? obj2int(args[2]) : srcLen;
		if (endIndex > srcLen) endIndex = srcLen;
		if (startIndex > endIndex) return newObj(ByteArrayType, 0, falseObj);

		char *base = (char *) (&FIELD(src, 0));
		int byteCount = (endIndex - startIndex) + 1;
		int wordCount = (byteCount + 3) / 4;
		OBJ result = newObj(ByteArrayType, wordCount, falseObj);
		if (result) {
			setByteCountAdjust(result, byteCount);
			memcpy(&FIELD(result, 0), base + startIndex - 1, byteCount);
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
	} else if (IS_TYPE(arg1, ByteArrayType)) {
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (IS_TYPE(arg, ByteArrayType)) {
				resultCount += BYTES(arg);
			} else if (IS_TYPE(arg, StringType)) {
				resultCount += stringSize(arg);
			} else {
				return fail(joinArgsNotSameType);
			}
		}
		int wordCount = (resultCount + 3) / 4;
		result = newObj(ByteArrayType, wordCount, falseObj);
		if (!result) return result; // allocation failed
		setByteCountAdjust(result, resultCount);

		char *dst = (char *) &FIELD(result, 0);
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			int byteCount = IS_TYPE(arg, ByteArrayType) ? BYTES(arg) : stringSize(arg);
			char *src = (char *) &FIELD(arg, 0);
			for (int j = 0; j < byteCount; j++) *dst++ = src[j];
		}
	} else {
		for (int i = 0; i < argCount; i++) {
			arg = args[i];
			if (IS_TYPE(arg, StringType)) {
				resultCount += stringSize(arg);
			} else if (isInt(arg) || isBoolean(arg)) {
				printIntegerOrBooleanInto(arg, buf);
				resultCount += strlen(buf);
			} else if (IS_TYPE(arg, ByteArrayType)) {
				resultCount += BYTES(arg);
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
			} else if (IS_TYPE(arg, ByteArrayType)) {
				count = BYTES(arg);
				memcpy(dst, (char *) &FIELD(arg, 0), count);
				dst += count;
			}
		}
		*dst = 0; // null terminator
	}
	return result;
}

OBJ primSplit(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *s = obj2str(args[0]);
	char *delim = obj2str(args[1]);
	int delimLen = strlen(delim);

	// count substrings for result list
	int resultCount = 0;
	if (delimLen == 0) {
		resultCount = countUTF8(s);
	} else {
		if (strstr(s, delim) == s) resultCount++; // s begins with a delimiter
		char *match = s;
		while (match) {
			resultCount++;
			match = strstr(match + delimLen, delim);
		}
	}

	// allocate result list (stored in tempGCRoot so it will be processed by garbage collector
	// if a GC happens during a later allocation)
	tempGCRoot = newObj(ListType, resultCount + 1, zeroObj);
	if (!tempGCRoot) return tempGCRoot; // allocation failed
	FIELD(tempGCRoot, 0) = int2obj(resultCount);

	// add substrings to the result list
	if (delimLen == 0) {
		// return a list containing the characters of s
		char *last = s;
		char *next = nextUTF8(last);
		for (int i = 0; i < resultCount; i++) {
			// allocate string and save in list
			int byteCount = next - last;
			OBJ item = newStringFromBytes(last, byteCount);
			if (!item) return falseObj; // allocation failed
			FIELD(tempGCRoot, i + 1) = item;
			last = next;
			next = nextUTF8(last);
		}
	} else {
		if (1 == resultCount) { // no delimiters found; return unsplit source string
			FIELD(tempGCRoot, 1) = args[0];
			return tempGCRoot;
		}
		int i = 1;
		char *last = s;
		char *next = strstr(last, delim);
		while (next && (i <= resultCount)) {
			int byteCount = next - last;
			OBJ item = newStringFromBytes(last, byteCount);
			if (!item) return falseObj; // allocation failed
			FIELD(tempGCRoot, i++) = item;
			last = next + delimLen;
			next = strstr(last, delim);
		}
		if (i <= resultCount) { //
			OBJ item = newStringFromBytes(last, strlen(last));
			if (!item) return falseObj; // allocation failed
			FIELD(tempGCRoot, i++) = item;
		}
	}
	return tempGCRoot;
}

OBJ primJoinStrings(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], ListType)) return fail(needsListError);

	OBJ stringList = args[0];
	int count = obj2int(FIELD(stringList, 0));
	if (count <= 0) return newString(0);

	char *separator = ((argCount > 1) && IS_TYPE(args[1], StringType)) ? obj2str(args[1]) : (char *) "";
	int separatorLen = strlen(separator);
	char buf[50];

	int resultBytes = (count - 1) * separatorLen;
	for (int i = 0; i < count; i++) {
		OBJ item = FIELD(stringList, i + 1);
		if (IS_TYPE(item, StringType)) {
			resultBytes += stringSize(item);
		} else if (IS_TYPE(item, ByteArrayType)) {
			resultBytes += BYTES(item);
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
		if (IS_TYPE(item, ByteArrayType)) {
			s = (char *) &FIELD(item, 0);
			n = BYTES(item);
		}
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
		if (startOffset > stringSize(arg1)) return int2obj(-1); // not found
		char *s = obj2str(arg1);
		char *sought = obj2str(arg0);
		if (0 == sought[0]) return int2obj(-1); // empty string
		char *match = strstr(s + startOffset - 1, sought);
		if (!match) return int2obj(-1);
		// count the Unicode characters up to match
		int charIndex = 1;
		while (*s && (s < match)) {
			s = nextUTF8(s);
			charIndex++;
		}
		return int2obj(charIndex);
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
	} else if (IS_TYPE(arg1, ByteArrayType)) { // search in a ByteArray
		uint8 *target = (uint8 *) &FIELD(arg1, 0);
		int targetSize = BYTES(arg1);
		if (startOffset > targetSize) return int2obj(-1); // not found
		uint8 *sought;
		int soughtSize = 0;
		if (IS_TYPE(arg0, ByteArrayType)) {
			sought = (uint8 *) &FIELD(arg0, 0);
			soughtSize = BYTES(arg0);
		} else if (IS_TYPE(arg0, StringType)) {
			sought = (uint8 *) obj2str(arg0);
			soughtSize = stringSize(arg0);
		} else if (isInt(arg0)) {
			// search for a byte in a ByteArray
			int soughtByte = obj2int(arg0);
			if ((soughtByte < 0) || (soughtByte > 255)) return fail(byteOutOfRange);
			for (int i = startOffset - 1; i <= targetSize; i++) {
				if (target[i] == soughtByte) return int2obj(i + 1);
			}
			return int2obj(-1);
		} else {
			// a ByteArray can be searched for a String or ByteArray
			return fail(nonComparableError);
		}
		int lastPotenialMatch = targetSize - soughtSize;
		uint8 *soughtEnd = sought + soughtSize;
		for (int i = startOffset - 1; i <= lastPotenialMatch; i++) {
			uint8 *p1 = target + i;
			uint8 *p2 = sought;
			while (p2 < soughtEnd) {
				if (*p1 != *p2) break;
				p1++;
				p2++;
			}
			if (p2 == soughtEnd) return int2obj(i + 1); // found a match!
		}
		return int2obj(-1);
	}
	return int2obj(-1);
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
	int result = unicodeCodePoint(s);
	return int2obj(result);
}

OBJ primUnicodeString(int argCount, OBJ *args) {
	// Return a string containing the given Unicode character(s).

	if (argCount < 1) return fail(notEnoughArguments);
	OBJ arg = args[0];

	if (isInt(arg) || IS_TYPE(arg, StringType)) { // convert a single integer to a Unicode character
		uint8 buf[8]; // buffer for one UTF-8 character
		uint8 *s = appendUTF8(buf, evalInt(arg));
		int byteCount = s - buf;
		return newStringFromBytes((char *) buf, byteCount);
	} else if (IS_TYPE(arg, ListType)) { // convert list of integers to a Unicode string
		int listCount = obj2int(FIELD(arg, 0));
		int utfByteCount = 0;
		for (int i = 1; i <= listCount; i++) {
			OBJ item = FIELD(arg, i);
			utfByteCount += bytesForUnicode(evalInt(item));
		}
		if (failure()) return fail(needsIntOrListOfInts); // evalInt failed on some list item

		OBJ result = newString(utfByteCount);
		if (!result) return result; // allocation failed
		arg = args[0]; // update arg after possible GC
		uint8 *s = (uint8 *) obj2str(result);
		for (int i = 1; i <= listCount; i++) {
			OBJ item = FIELD(arg, i);
			s = appendUTF8(s, evalInt(item));
		}
		return result;
	}
	return fail(needsIntOrListOfInts);
}

OBJ primNewByteArray(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);

	int byteCount = obj2int(args[0]);
	if (byteCount < 0) byteCount = 0;

	int fillWord = 0;
	if (argCount > 1) {
		if (!isInt(args[1])) return fail(needsIntegerError);
		int fillByte = obj2int(args[1]);
		if ((fillByte < 0) || (fillByte > 255)) return fail(byteArrayStoreError);
		fillWord = (fillByte << 24) | (fillByte << 16) | (fillByte << 8) | fillByte;
	}

	OBJ result = newObj(ByteArrayType, (byteCount + 3) / 4, (OBJ) fillWord);
	if (result) setByteCountAdjust(result, byteCount);
	return result;
}

OBJ primAsByteArray(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	OBJ arg = args[0];
	OBJ result = falseObj;
	int byteCount;

	if (isInt(arg)) {
		int byteValue = obj2int(arg);
		if ((byteValue < 0) || (byteValue > 255)) return fail(byteArrayStoreError);
		result = newObj(ByteArrayType, 1, falseObj);
		if (result) {
			setByteCountAdjust(result, 1);
			*((uint8 *) &FIELD(result, 0)) = byteValue;
		}
	} else if (IS_TYPE(arg, StringType)) {
		byteCount = stringSize(arg);
		result = newObj(ByteArrayType, (byteCount + 3) / 4, falseObj);
		if (result) {
			setByteCountAdjust(result, byteCount);
			memcpy(&FIELD(result, 0), obj2str(arg), byteCount);
		}
	} else if (IS_TYPE(arg, ListType)) {
		byteCount = obj2int(FIELD(arg, 0));
		result = newObj(ByteArrayType, (byteCount + 3) / 4, falseObj);
		if (result) {
			setByteCountAdjust(result, byteCount);
			uint8 *bytes = (uint8 *) &FIELD(result, 0);
			for (int i = 0; i < byteCount; i++) {
				OBJ item = FIELD(arg, i + 1);
				if (isInt(item)) {
					int byteValue = obj2int(item);
					if ((byteValue < 0) || (byteValue > 255)) return fail(byteArrayStoreError);
					bytes[i] = byteValue;
				}
			}
		}
	} else if (IS_TYPE(arg, ByteArrayType)) {
		result = arg;
	} else {
		return fail(byteArrayStoreError);
	}
	return result;
}

OBJ primFreeMemory(int argCount, OBJ *args) {
	return int2obj(wordsFree());
}

// Helper functions for convert primitive

static OBJ stringToList(OBJ strObj) {
	// Return a list containing the Unicode character values (codepoints) of the given string.

	int itemCount = countUTF8(obj2str(strObj));

	tempGCRoot = strObj; // record strObj in case allocation triggers GC that moves it
	OBJ result = newObj(ListType, itemCount + 1, falseObj);
	strObj = tempGCRoot; // restore strObj
	if (!result) return fail(insufficientMemoryError); // allocation failed
	FIELD(result, 0) = int2obj(itemCount);

	char *codepointPtr = obj2str(strObj);
	for (int i = 0; i < itemCount; i++) {
		FIELD(result, i + 1) = int2obj(unicodeCodePoint(codepointPtr));
		codepointPtr = nextUTF8(codepointPtr);
	}
	return result;
}

static OBJ stringToByteArray(OBJ strObj) {
	// Return a byte array containing the bytes of the given string (i.e. its utf8 encoding).

	int byteCount = strlen(obj2str(strObj));
	int wordCount = (byteCount + 3) / 4;

	tempGCRoot = strObj; // record strObj in case allocation triggers GC that moves it
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	strObj = tempGCRoot; // restore strObj
	if (!result) return fail(insufficientMemoryError); // allocation failed
	setByteCountAdjust(result, byteCount);

	char *src = obj2str(strObj);
	char *dst = (char *) &FIELD(result, 0);
	for (int i = 0; i < byteCount; i++) {
		*dst++ = src[i];
	}
	return result;
}

static OBJ listToString(OBJ listObj) {
	// Return a string the given list of Unicode characters (code points).
	// Assume the list contains only integers that represent valid Unicode characters.

	int itemCount = obj2int(FIELD(listObj, 0));
	int utfByteCount = 0;
	for (int i = 1; i <= itemCount; i++) {
		OBJ item = FIELD(listObj, i);
		utfByteCount += bytesForUnicode(evalInt(item));
	}
	if (failure()) return fail(needsIntOrListOfInts); // evalInt failed on some list item

	tempGCRoot = listObj; // record listObj in case allocation triggers GC that moves it
	OBJ result = newString(utfByteCount);
	listObj = tempGCRoot; // restore listObj
	if (!result) return result; // allocation failed

	uint8 *s = (uint8 *) obj2str(result);
	for (int i = 1; i <= itemCount; i++) {
		OBJ item = FIELD(listObj, i);
		if (!isInt(item)) return fail(needsListOfIntegers);
		int codepoint = obj2int(item);
		if ((codepoint < 0) || (codepoint > 1114111)) return fail(invalidUnicodeValue);
		s = appendUTF8(s, codepoint);
	}
	return result;
}

static OBJ listToByteArray(OBJ listObj) {
	// Return a byte array containing the contents of the given list.
	// Assume the list elements are integers between 0 and 255.

	int byteCount = obj2int(FIELD(listObj, 0));
	int wordCount = (byteCount + 3) / 4;

	tempGCRoot = listObj; // record listObj in case allocation triggers GC that moves it
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	listObj = tempGCRoot; // restore listObj
	if (!result) return fail(insufficientMemoryError); // allocation failed
	setByteCountAdjust(result, byteCount);

	OBJ *src = &FIELD(listObj, 1);
	char *dst = (char *) &FIELD(result, 0);
	for (int i = 0; i < byteCount; i++) {
		OBJ item = *src++;
		if (!isInt(item)) return fail(needsListOfIntegers);
		int byte = obj2int(item);
		if ((byte < 0) || (byte > 255)) return fail(byteArrayStoreError);
		*dst++ = byte;
	}
	return result;
}

static OBJ byteArrayToString(OBJ byteArrayObj) {
	// Return a string containing the given bytes.
	// Assume the byte array is a valid UTF8 string encoding.

	int byteCount = BYTES(byteArrayObj);
	tempGCRoot = byteArrayObj; // record byteArrayObj in case allocation triggers GC that moves it
	OBJ result = newString(byteCount);
	byteArrayObj = tempGCRoot; // restore byteArrayObj
	if (!result) return fail(insufficientMemoryError); // allocation failed

	char *src = (char *) &FIELD(byteArrayObj, 0);
	char *dst = (char *) &FIELD(result, 0);
	for (int i = 0; i < byteCount; i++) {
		*dst++ = *src++;
	}

	return result;
}

static OBJ byteArrayToList(OBJ byteArrayObj) {
	// Return a list containing the byte values of the given byte array.

	int itemCount = BYTES(byteArrayObj);
	tempGCRoot = byteArrayObj; // record byteArrayObj in case allocation triggers GC that moves it
	OBJ result = newObj(ListType, itemCount + 1, falseObj);
	byteArrayObj = tempGCRoot; // restore byteArrayObj
	if (!result) return fail(insufficientMemoryError); // allocation failed
	FIELD(result, 0) = int2obj(itemCount);

	uint8 *bytes = (uint8 *) &FIELD(byteArrayObj, 0);
	for (int i = 0; i < itemCount; i++) {
		FIELD(result, i + 1) = int2obj(bytes[i]);
	}
	return result;
}

static OBJ singletonList(OBJ anObj) {
	// Return a singleton list containing the given object.

	tempGCRoot = anObj; // record anObj in case allocation triggers GC that moves it
	OBJ result = newObj(ListType, 2, falseObj);
	anObj = tempGCRoot; // restore anObj
	if (!result) return fail(insufficientMemoryError); // allocation failed
	FIELD(result, 0) = int2obj(1);
	FIELD(result, 1) = anObj;
	return result;
}

static OBJ singletonByteArray(OBJ anObj) {
	// Return a singleton list containing the given number or boolean object.

	int byteValue = 0;
	if (isInt(anObj)) {
		byteValue = obj2int(anObj);
		if ((byteValue < 0) || (byteValue > 255)) return fail(byteArrayStoreError);
	} else {
		// Convert boolean to byte value.
		byteValue = (anObj == falseObj) ? 0 : 1;
	}

	OBJ result = newObj(ByteArrayType, 1, falseObj);
	if (!result) return fail(insufficientMemoryError); // allocation failed
	setByteCountAdjust(result, 1);
	*((uint8 *) &FIELD(result, 0)) = byteValue;
	return result;
}

OBJ primConvertType(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	OBJ srcObj = args[0];
	int srcType = objType(srcObj);
	char *dstTypeName = obj2str(args[1]);

	int dstType = -1;
	if (strcmp(dstTypeName, "boolean") == 0) dstType = BooleanType;
	if (strcmp(dstTypeName, "number") == 0) dstType = IntegerType;
	if (strcmp(dstTypeName, "string") == 0) dstType = StringType;
	if (strcmp(dstTypeName, "list") == 0) dstType = ListType;
	if (strcmp(dstTypeName, "byte array") == 0) dstType = ByteArrayType;
	if (dstType < 0) return fail(unknownDatatype);

	char s[32];
	char *srcStr;
	OBJ result = srcObj; // default used when converting object to its current type
	int srcItemCount = 0;

	switch (srcType) {
	case BooleanType:
		switch (dstType) {
		case IntegerType:
			result = int2obj((srcObj == trueObj) ? 1 : 0);
			break;
		case StringType:
			result = newStringFromBytes(((srcObj == trueObj) ? "1" : "0"), 1);
			break;
		case ListType:
			return singletonList(srcObj);
			break;
		case ByteArrayType:
			return singletonByteArray(srcObj);
			break;
		}
		break;
	case IntegerType:
		switch (dstType) {
		case BooleanType:
			// 0 is false; all other numbers are true
			result = (obj2int(srcObj) == 0) ? falseObj : trueObj;
			break;
		case StringType:
			sprintf(s, "%d", obj2int(srcObj));
			result = newStringFromBytes(s, strlen(s));
			break;
		case ListType:
			return singletonList(srcObj);
			break;
		case ByteArrayType:
			return singletonByteArray(srcObj);
			break;
		}
		break;
	case StringType:
		switch (dstType) {
		case BooleanType:
			srcStr = obj2str(srcObj);
			// "0" is false; all other strings are true
			result = (strcmp(srcStr, "0") == 0) ? falseObj : trueObj;
			break;
		case IntegerType:
			result = int2obj(evalInt(srcObj));
			break;
		case ListType:
			result = stringToList(srcObj);
			break;
		case ByteArrayType:
			result = stringToByteArray(srcObj);
			break;
		}
		break;
	case ListType:
		srcItemCount = obj2int(FIELD(srcObj, 0));
		switch (dstType) {
		case BooleanType:
			if ((srcItemCount != 1) || (objType(FIELD(srcObj, 1)) != BooleanType)) {
				 return fail(cannotConvertToBoolean);
			}
			return FIELD(srcObj, 1);
			break;
		case IntegerType:
			if ((srcItemCount != 1) || !isInt(FIELD(srcObj, 1))) {
				 return fail(cannotConvertToInteger);
			}
			return FIELD(srcObj, 1);
			break;
		case StringType:
			result = listToString(srcObj);
			break;
		case ByteArrayType:
			result = listToByteArray(srcObj);
			break;
		}
		break;
	case ByteArrayType:
		srcItemCount = BYTES(srcObj);
		switch (dstType) {
		case BooleanType:
			if (srcItemCount != 1) return fail(cannotConvertToBoolean);
			return (*((uint8 *) &FIELD(result, 0)) ? trueObj : falseObj);
			break;
		case IntegerType:
			if (srcItemCount != 1) return fail(cannotConvertToInteger);
			return int2obj(*((uint8 *) &FIELD(result, 0)));
			break;
		case StringType:
			result = byteArrayToString(srcObj);
			break;
		case ListType:
			result = byteArrayToList(srcObj);
			break;
		}
		break;
	}
	return result;
}

// Primitives

static PrimEntry entries[] = {
	{"makeList", primMakeList},
	{"range", primRange},
	{"addLast", primListAddLast},
	{"delete", primListDelete},
	{"join", primJoin},
	{"split", primSplit},
	{"copyFromTo", primCopyFromTo},
	{"find", primFind},
	{"joinStrings", primJoinStrings},
	{"unicodeAt", primUnicodeAt},
	{"unicodeString", primUnicodeString},
	{"newByteArray", primNewByteArray},
	{"asByteArray", primAsByteArray},
	{"freeMemory", primFreeMemory},
	{"convertType", primConvertType},
};

void addDataPrims() {
	addPrimitiveSet(DataPrims, "data", sizeof(entries) / sizeof(PrimEntry), entries);
}
