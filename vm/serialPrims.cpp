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

// Use Serial2 on ESP32 board, Serial1 on others
#if defined(ESP32)
	#define SERIAL_PORT Serial2
#else
	#define SERIAL_PORT Serial1
#endif

static int isOpen = false;

#if defined(NRF51) // not implemented (has only one UART)

static void serialOpen(int baudRate) { fail(primitiveNotImplemented); }
static void serialClose() { fail(primitiveNotImplemented); }
static int serialAvailable() { return -1; }
static void serialReadBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); }
static int serialWriteBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); return 0; }

#elif defined(ARDUINO_BBC_MICROBIT_V2) // use UART directly

#define PIN_RX 0
#define PIN_TX 1

#define BUF_SIZE 128
uint8 rxBuf[BUF_SIZE];
uint8 txBuf[BUF_SIZE];

int rxReadIndex = 0;

static void serialClose() {
	NRF_UARTE1->TASKS_STOPRX = true;
	NRF_UARTE1->TASKS_STOPTX = true;
	while (!NRF_UARTE1->EVENTS_TXSTOPPED) /* wait */;
	NRF_UARTE1->ENABLE = UARTE_ENABLE_ENABLE_Disabled;
	isOpen = false;
}

static void serialOpen(int baudRate) {
	if (isOpen) serialClose();

	// set DMA pointers
	NRF_UARTE1->RXD.PTR = (uint32_t) &rxBuf[0];
	NRF_UARTE1->RXD.MAXCNT = BUF_SIZE;
	NRF_UARTE1->TXD.PTR = (uint32_t) &txBuf[0];
	NRF_UARTE1->TXD.MAXCNT = BUF_SIZE;

	// set pins
	NRF_UARTE1->PSEL.RXD = g_ADigitalPinMap[PIN_RX];
	NRF_UARTE1->PSEL.TXD = g_ADigitalPinMap[PIN_TX];

	// set baud rate
	NRF_UARTE1->BAUDRATE = 268 * baudRate;

	// set receive shortcut (restart receive and wrap when end of buffer is reached)
	NRF_UARTE1->SHORTS = (1 << 5); // Shortcut between event ENDRX and task STARTRX

	// enable and start rx and tx
	NRF_UARTE1->ENABLE = UARTE_ENABLE_ENABLE_Enabled;
	NRF_UARTE1->TASKS_STARTRX = true;
	while (!NRF_UARTE1->EVENTS_RXSTARTED) /* wait */;
	NRF_UARTE1->TASKS_STARTTX = true;
	while (!NRF_UARTE1->EVENTS_TXSTARTED) /* wait */;

	NRF_UARTE1->EVENTS_ENDTX = true; // ready to transmit

	isOpen = true;
}

static int serialAvailable() {
	int byteCount = NRF_UARTE1->RXD.AMOUNT - rxReadIndex;
	if (byteCount < 0) byteCount += BUF_SIZE;
	return byteCount;
}

static void serialReadBytes(uint8 *buf, int byteCount) {
	int srcIndex = rxReadIndex;
	for (int i = 0; i < byteCount; i++) {
		*buf++ = rxBuf[srcIndex++];
		if (srcIndex >= BUF_SIZE) srcIndex = 0;
	}
	rxReadIndex = srcIndex;
}

static int serialWriteBytes(uint8 *buf, int byteCount) {
	if (!NRF_UARTE1->EVENTS_ENDTX) return 0; // last transmission is still in progress
	if (byteCount > BUF_SIZE) byteCount = BUF_SIZE;
	for (int i = 0; i < byteCount; i++) {
		txBuf[i++] = *buf++;
	}
	NRF_UARTE1->TXD.MAXCNT = byteCount;
	NRF_UARTE1->EVENTS_ENDTX = false;
	NRF_UARTE1->TASKS_STARTTX = true;
	return byteCount;
}

#else // use Serial1 or Serial2

static void serialClose() {
	isOpen = false;
	SERIAL_PORT.flush();
	SERIAL_PORT.end();
}

static void serialOpen(int baudRate) {
	if (isOpen) serialClose();
	SERIAL_PORT.begin(baudRate);
	isOpen = true;
}

static int serialAvailable() {
	return isOpen ? SERIAL_PORT.available() : 0;
}

static void serialReadBytes(uint8 *buf, int byteCount) {
	if (isOpen) SERIAL_PORT.readBytes(buf, byteCount);
}

static int serialWriteBytes(uint8 *buf, int byteCount) {
	return isOpen ? SERIAL_PORT.write(buf, byteCount) : 0;
}

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
	{"open", primSerialOpen},
	{"close", primSerialClose},
	{"read", primSerialRead},
	{"write", primSerialWrite},
};

void addSerialPrims() {
	addPrimitiveSet("serial", sizeof(entries) / sizeof(PrimEntry), entries);
}
