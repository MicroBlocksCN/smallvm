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

// Unify Arduino IDE and PlatformIO
#if defined(NRF52_SERIES) && !defined(NRF52)
  #define NRF52 1
#endif

// Define short symbols ESP32 variants
#if defined(CONFIG_IDF_TARGET_ESP32S2)
  #define ESP32_S2 1
#elif defined(CONFIG_IDF_TARGET_ESP32S3)
  #define ESP32_S3 1
#elif defined(CONFIG_IDF_TARGET_ESP32C3)
  #define ESP32_C3 1
#elif defined(CONFIG_IDF_TARGET_ESP32C6)
  #define ESP32_C6 1
#endif

#if defined(ESP32) && !(defined(ESP32_S2) || defined(ESP32_S3) || defined(ESP32_C3) || defined(ESP32_C6))
  #define ESP32_ORIGINAL 1
#endif

#if defined(ARDUINO_ARCH_RP2040) && !defined(__MBED__)
  #define RP2040_PHILHOWER 1
#endif

#if defined(BLE_IDE) || defined(BLE_KEYBOARD) || defined(BLE_UART) || defined(BLE_OCTO)
  #define USE_NIMBLE 1
#endif

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE_MINI) || defined(CALLIOPE_V3) || \
	defined(ARDUINO_BBC_MICROBIT_V2) || defined(ARDUINO_M5Atom_Matrix_ESP32) || \
	defined(GNUBLOCKS) || defined(ARDUINO_Mbits)
		#define HAS_LED_MATRIX 1
#endif

// Integer types

typedef unsigned char uint8;
typedef unsigned short uint16;
typedef unsigned int uint32;
typedef unsigned long long uint64;

typedef signed short int int16;

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
#define ByteArrayType 3
#define StringType 4
// types 5-7 reserved for future non-pointer objects
#define BinaryObjectTypes 7 // objects with type ID's <= 7 do not contain pointers
#define ArrayType 8
#define ListType 9

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
#define WORDS(obj) ((*((uint32*) (obj)) >> 4) & 0xFFFF)
#define TYPE(obj) (*((uint32*) (obj)) & 0xF)

static inline int objWords(OBJ obj) {
	if (isInt(obj) || isBoolean(obj)) return 0;
	return WORDS(obj);
}

// ByteArray Objects
//
// ByteArray objects use two bits in the object header to adjust their size in bytes so that
// they are not limited to multiples of four bytes. To get the size in bytes, this field
// is subtracted from 4 * WORDS(obj).

#define BYTECOUNT_ADJUST(obj) ((*((uint32*) (obj)) >> 29) & 0x3)
#define BYTES(obj) (4 * WORDS(obj) - BYTECOUNT_ADJUST(obj))

static inline void setByteCountAdjust(OBJ obj, int byteCount) {
	if (isInt(obj) || isBoolean(obj) || (ByteArrayType != TYPE(obj))) return;
	int delta = 4 - (byteCount & 3); // # of bytes to subtract from 4 * WORDS(obj)
	*obj = ((delta & 3) << 29) | ((*obj) & 0x9FFFFFFF);
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

// Global temporary GC root for use by primitives that do multiple allocations.

extern OBJ tempGCRoot;

// Object Memory Operations

void memInit();
void memClear();
int wordsFree();
void gc();

OBJ newObj(int typeID, int wordCount, OBJ fill);
OBJ resizeObj(OBJ obj, int wordCount);
OBJ newString(int byteCount);
OBJ newStringFromBytes(const char *bytes, int byteCount);
char* obj2str(OBJ obj);

// Debugging Support

void reportNum(const char *msg, int n);
void reportHex(const char *msg, int n);
void reportObj(const char *msg, OBJ obj);
void dumpObjectStore(void);
void memDumpObj(OBJ obj);

#ifdef __cplusplus
}
#endif

#endif // _MEM_H_
