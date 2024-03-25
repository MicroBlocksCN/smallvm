/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// oneWirePrims.cpp - OneWire primitives (https://www.pjrc.com/teensy/td_libs_OneWire.html).
// John Maloney, March 2023

#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

#if defined(ARDUINO_ARCH_ESP32)

#include <OneWire.h>

OneWire oneWire(0);

static OBJ primInitOneWire(int argCount, OBJ *args) {
	int pinNum = (argCount > 0) ? obj2int(args[0]) : 0;
	oneWire.begin(pinNum);
	return falseObj;
}

static OBJ primScanStart(int argCount, OBJ *args) {
	oneWire.reset_search(); // caller should wait 250 msecs after this call
	return falseObj;
}

static OBJ primScanNext(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], ByteArrayType)) return falseObj;
	OBJ arg0 = args[0];
	if (BYTES(arg0) < 8) return falseObj;

	uint8 addr[8];
	if (!oneWire.search(addr)) return falseObj;
	if (OneWire::crc8(addr, 7) != addr[7]) {
		outputString("Bad OneWire CRC in scan");
		return falseObj;
	}

	uint8 *dst = (uint8 *) &FIELD(arg0, 0);
	for (int i = 0; i < 8; i++) dst[i] = addr[i];
	return trueObj;
}

static OBJ primSelect(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], ByteArrayType)) return falseObj;
	OBJ arg0 = args[0];
	if (BYTES(arg0) < 8) return falseObj;
	uint8 *addr = (uint8 *) &FIELD(arg0, 0);

	oneWire.reset();
	oneWire.select(addr);
	return falseObj;
}

static OBJ primSelectAll(int argCount, OBJ *args) {
	oneWire.reset();
	oneWire.skip();
	return falseObj;
}

static OBJ primWriteByte(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	uint8 byteToWrite = obj2int(args[0]) & 255;
	int powerFlag = (argCount > 1) && (trueObj == args[1]); // optional bus power flag

	oneWire.write(byteToWrite, powerFlag);
	return falseObj;
}

static OBJ primReadByte(int argCount, OBJ *args) {
	return int2obj(oneWire.read());
}

static OBJ primCRC8(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], ByteArrayType)) return zeroObj;
	OBJ arg0 = args[0];
	int byteCount = BYTES(arg0);
	if ((argCount > 1) && isInt(args[1])) {
		int arg1 = obj2int(args[1]);
		if ((arg1 >= 0) && (arg1 < byteCount)) byteCount = arg1;
	}

	uint8 *data = (uint8 *) &FIELD(arg0, 0);
	int crc = OneWire::crc8(data, byteCount);
	return int2obj(crc);
}

static OBJ primCRC16(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], ByteArrayType)) return zeroObj;
	OBJ arg0 = args[0];
	int byteCount = BYTES(arg0);
	if ((argCount > 1) && isInt(args[1])) {
		int arg1 = obj2int(args[1]);
		if ((arg1 >= 0) && (arg1 < byteCount)) byteCount = arg1;
	}

	uint8 *data = (uint8 *) &FIELD(arg0, 0);
	int crc = OneWire::crc16(data, byteCount);
	return int2obj(crc);
}

#else //stubs

static OBJ primInitOneWire(int argCount, OBJ *args) { return falseObj; }
static OBJ primScanStart(int argCount, OBJ *args) { return falseObj; }
static OBJ primScanNext(int argCount, OBJ *args) { return falseObj; }
static OBJ primSelect(int argCount, OBJ *args) { return falseObj; }
static OBJ primSelectAll(int argCount, OBJ *args) { return falseObj; }
static OBJ primWriteByte(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadByte(int argCount, OBJ *args) { return zeroObj; }
static OBJ primCRC8(int argCount, OBJ *args) { return zeroObj; }
static OBJ primCRC16(int argCount, OBJ *args) { return zeroObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	{"init", primInitOneWire},
	{"scanStart", primScanStart},
	{"scanNext", primScanNext},
	{"select", primSelect},
	{"selectAll", primSelectAll},
	{"writeByte", primWriteByte},
	{"readByte", primReadByte},
	{"crc8", primCRC8},
	{"crc16", primCRC16},
};

void addOneWirePrims() {
	addPrimitiveSet(OneWirePrims, "1wire", sizeof(entries) / sizeof(PrimEntry), entries);
}
