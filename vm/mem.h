/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// mem.h - Object memory definitions using 32-bit object references
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Unsigned integer types

typedef unsigned char uint8;
typedef unsigned short uint16;
typedef unsigned int uint32;

// Boolean constants for readability

#define true 1
#define false 0

// Object reference type (32-bits)

typedef int * OBJ;

// Class IDs

#define BooleanClass 1
#define IntegerClass 2
#define FloatClass 3 // not yet supported
#define StringClass 4
#define ByteArrayClass 5 // objects with class ID's <= 5 do not contain pointers
#define ArrayClass 6

// OBJ constants for false and true
// Note: These are constants, not pointers to objects in memory.

#define falseObj ((OBJ) 0)
#define trueObj ((OBJ) 4)

// Integers

// Integers are encoded in object references; they have no memory object.
// They have a 1 in their lowest bit and a signed value in their top 31 bits.

#define isInt(obj) (((int) (obj)) & 1)
#define int2obj(n) ((OBJ) (((n) << 1) | 1))
#define obj2int(obj) ((int)(obj) >> 1)
#define zeroObj ((OBJ) 1)

// Memory Objects
//
// Even-valued object references (except nil, true, and false) point to an object in memory.
// Memory objects start with one or more header words.

#define HEADER_WORDS 1
#define HEADER(classID, wordCount) ((wordCount << 4) | (classID & 0xF))
#define CLASS(obj) (*((unsigned*) (obj)) & 0xF)
#define WORDS(obj) (*((unsigned*) (obj)) >> 4)

static inline int objWords(OBJ obj) {
	if (isInt(obj) || (obj <= trueObj)) return 0;
	return WORDS(obj);
}

static inline int objClass(OBJ obj) {
	if (isInt(obj)) return IntegerClass;
	if (obj <= trueObj) return BooleanClass;
	return CLASS(obj);
}

// FIELD() can be used either to get or set an object field

#define FIELD(obj, i) (((OBJ *) obj)[HEADER_WORDS + (i)])

// Class check for classes with memory instances
// (Note: there are faster tests for small integers and booleans)

#define IS_CLASS(obj, classID) (((((int) obj) & 3) == 0) && ((obj) > trueObj) && (CLASS(obj) == classID))

// Object Memory Operations

void memInit(int wordCount);
void memClear();
OBJ newObj(int classID, int wordCount, OBJ fill);
OBJ newStringFromBytes(uint8 *bytes, int byteCount);
char* obj2str(OBJ obj);

#ifdef __cplusplus
}
#endif
