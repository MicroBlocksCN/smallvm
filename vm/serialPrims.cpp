/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2021 John Maloney, Bernat Romagosa, and Jens Mönig

// serialPrims.c - Secondary serial port primitives for boards that support it
// John Maloney, September 2021

#include <Arduino.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#if defined(NRF51) // not implemented (has only one UART)

static void serialOpen(int baudRate) { fail(primitiveNotImplemented); }
static void serialClose() { fail(primitiveNotImplemented); }
static int serialAvailable() { return -1; }
static void serialReadBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); }
static int serialWriteBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); return 0; }

#elif defined(NRF52) // use secondary UART

static void serialOpen(int baudRate) { }
static void serialClose() { }
static int serialAvailable() { return 0; }
static void serialReadBytes(uint8 *buf, int byteCount) { }
static int serialWriteBytes(uint8 *buf, int byteCount) { }

#else // use Serial1

static void serialOpen(int baudRate) { Serial1.begin(baudRate); }
static void serialClose() { Serial1.end(); }
static int serialAvailable() { return Serial1.available(); }
static void serialReadBytes(uint8 *buf, int byteCount) { Serial1.readBytes(buf, byteCount); }
static int serialWriteBytes(uint8 *buf, int byteCount) { return Serial1.write(buf, byteCount); }

#endif

static OBJ primSerialOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	int baudRate = obj2int(args[0]);
	serialOpen(baudRate);
	return falseObj;
}

static OBJ primSerialClose(int argCount, OBJ *args) {
	serialClose();
	return falseObj;
}

static OBJ primSerialRead(int argCount, OBJ *args) {
	int byteCount = serialAvailable();
	if (byteCount < 0) return fail(primitiveNotImplemented);
	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (!result) return fail(insufficientMemoryError);
	serialReadBytes((uint8 *) &FIELD(result, 0), byteCount);
	setByteCountAdjust(result, byteCount);
	return result;
}

static OBJ primSerialWrite(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	OBJ arg = args[0];
	uint8 oneByte = 0;
	int bytesWritten = 0;

	if (isInt(arg)) { // single byte
		oneByte = obj2int(arg) & 255;
		bytesWritten = serialWriteBytes(&oneByte, 1);
	} else if (IS_TYPE(arg, StringType)) { // string
		char *s = obj2str(arg);
		bytesWritten = serialWriteBytes((uint8 *) s, strlen(s));
	} else if (IS_TYPE(arg, ByteArrayType)) { // byte array
		bytesWritten = serialWriteBytes((uint8 *) &FIELD(arg, 0), BYTES(arg));
	} else if (IS_TYPE(arg, ListType)) { // list of bytes
		int count = obj2int(FIELD(arg, 0));
		for (int i = 1; i <= count; i++) {
			OBJ item = FIELD(arg, i);
			if (isInt(item)) {
				oneByte = obj2int(item) & 255;
				if (!serialWriteBytes(&oneByte, 1)) break; // no more room
				bytesWritten++;
			}
		}
	}
	return int2obj(bytesWritten);
}

// Primitives

static PrimEntry entries[] = {
	{"serialOpen", primSerialOpen},
	{"serialClose", primSerialClose},
	{"serialRead", primSerialRead},
	{"serialWrite", primSerialWrite},
};

void addSerialPrims() {
	addPrimitiveSet("serial", sizeof(entries) / sizeof(PrimEntry), entries);
}
