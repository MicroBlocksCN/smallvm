/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// mem.h - Object memory definitions using 32-bit object references
// John Maloney, April 2017

#ifndef _MEM_H_
#define _MEM_H_

#ifdef __cplusplus
extern "C" {
#endif

// Unsigned integer types

typedef unsigned char uint8;
typedef unsigned int uint32;

// Boolean constants for readability (if not already defined)

#if !defined(true) || !defined(false)
	#define true 1
	#define false 0
#endif

// Object reference type (32-bits)

typedef int * OBJ;

// Type IDs

#define FREE_CHUNK 0
#define BooleanType 1
#define IntegerType 2
#define FloatType 3 // not yet supported
#define StringType 4
#define ByteArrayType 5
// types 6 and 7 reserved for future non-pointer objects
#define ArrayType 8 // objects with type ID's < 8 do not contain pointers

// Booleans
// Note: These are constants, not pointers to objects in memory.

#define falseObj ((OBJ) 0)
#define trueObj ((OBJ) 4)

#define isBoolean(obj) ((obj) <= trueObj)

// Integers

// Integers are encoded in object references; they have no memory object.
// They have a 1 in their lowest bit and a signed value in their top 31 bits.

#define isInt(obj) (((int) (obj)) & 1)
#define int2obj(n) ((OBJ) (((n) << 1) | 1))
#define obj2int(obj) ((int)(obj) >> 1)
#define zeroObj ((OBJ) 1)

// Memory Objects
//
// Even-valued object references (except true and false) point to an object in memory.
// Memory objects start with one or more header words.

#define HEADER_WORDS 1
#define HEADER(typeID, wordCount) (((wordCount) << 4) | ((typeID) & 0xF))
#define WORDS(obj) (*((uint32*) (obj)) >> 4)
#define TYPE(obj) (*((uint32*) (obj)) & 0xF)

static inline int objWords(OBJ obj) {
	if (isInt(obj) || isBoolean(obj)) return 0;
	return WORDS(obj);
}

// Types

static inline int objType(OBJ obj) {
	if (isInt(obj)) return IntegerType;
	if (isBoolean(obj)) return BooleanType;
	return TYPE(obj);
}

// Type check for non-integer/boolean objects
// (Note: Use isInt() and isBoolean() to test for integers and booleans)

#define IS_TYPE(obj, typeID) (((((int) obj) & 1) == 0) && ((obj) > trueObj) && (TYPE(obj) == typeID))

// FIELD() macro can be used either to get or set an object field (zero-based)

#define FIELD(obj, i) (((OBJ *) obj)[HEADER_WORDS + (i)])


// Object Memory Operations

void memInit();
void memClear();
OBJ newObj(int typeID, int wordCount, OBJ fill);
OBJ newStringFromBytes(uint8 *bytes, int byteCount);
char* obj2str(OBJ obj);

#ifdef __cplusplus
}
#endif

#endif // _MEM_H_
