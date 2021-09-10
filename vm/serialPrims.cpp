/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2021 John Maloney, Bernat Romagosa, and Jens Mönig

// serialPrims.c - Secondary serial port primitives for boards that support it
// John Maloney, September 2021

#include <Arduino.h>

#include "mem.h"
#include "interp.h"

#define TX_BUF_SIZE 128
static int isOpen = false;

#if defined(NRF51) // not implemented (has only one UART)

static void serialOpen(int baudRate) { fail(primitiveNotImplemented); }
static void serialClose() { fail(primitiveNotImplemented); }
static int serialAvailable() { return -1; }
static void serialReadBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); }
static int serialWriteBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); return 0; }

#elif defined(ARDUINO_BBC_MICROBIT_V2) // use UART directly

// Note: Due to a bug or misfeature in the nRF52 UARTE hardware, the RXD.AMOUNT is
// not updated correctly. As a work around (hack!), we fill the receive buffer with
// 255's and detect the number of bytes by finding the last non-255 value. This
// implementation could miss an actual 255 data byte if it happens to the be last
// byte received when a read operation is performed. However, that should not be an
// problem in most real applications since 255 bytes are rare in string data, and
// this work around avoids using a hardware counter, interrupts, or PPI entries.

#define PIN_RX 0
#define PIN_TX 1

#define RX_BUF_SIZE 256
uint8 rxBufA[RX_BUF_SIZE];
uint8 rxBufB[RX_BUF_SIZE];

#define INACTIVE_RX_BUF() ((NRF_UARTE1->RXD.PTR == (int) rxBufB) ? rxBufA : rxBufB)

uint8 txBuf[TX_BUF_SIZE];

static void serialClose() {
	NRF_UARTE1->TASKS_STOPRX = true;
	NRF_UARTE1->TASKS_STOPTX = true;
	while (!NRF_UARTE1->EVENTS_TXSTOPPED) /* wait */;
	NRF_UARTE1->ENABLE = UARTE_ENABLE_ENABLE_Disabled;
	isOpen = false;
}

static void serialOpen(int baudRate) {
	if (isOpen) serialClose();

	// set pins
	NRF_UARTE1->PSEL.RXD = g_ADigitalPinMap[PIN_RX];
	NRF_UARTE1->PSEL.TXD = g_ADigitalPinMap[PIN_TX];

	// set baud rate
	NRF_UARTE1->BAUDRATE = 268 * baudRate;

	// clear receive buffer
	memset(rxBufA, 255, RX_BUF_SIZE);

	// initialize Easy DMA pointers
	NRF_UARTE1->RXD.PTR = (uint32_t) rxBufA;
	NRF_UARTE1->RXD.MAXCNT = RX_BUF_SIZE;
	NRF_UARTE1->TXD.PTR = (uint32_t) txBuf;
	NRF_UARTE1->TXD.MAXCNT = TX_BUF_SIZE;

	// set receive shortcut (restart receive and wrap when end of buffer is reached)
	NRF_UARTE1->SHORTS = UARTE_SHORTS_ENDRX_STARTRX_Msk;

	// enable the UART
	NRF_UARTE1->ENABLE = UARTE_ENABLE_ENABLE_Enabled;

	// start rx
	NRF_UARTE1->EVENTS_RXDRDY = false;
	NRF_UARTE1->TASKS_STARTRX = true;

	// start tx by sending zero bytes
	NRF_UARTE1->TXD.MAXCNT = 0;
	NRF_UARTE1->TASKS_STARTTX = true;

	delay(5); // leave a litte time for the line level to settle
	isOpen = true;
}

static int serialAvailable() {
	if (!NRF_UARTE1->EVENTS_RXDRDY) return 0;

	// clear the idle receive buffer
	uint8* idleRxBuf = INACTIVE_RX_BUF();
	memset(idleRxBuf, 255, RX_BUF_SIZE);

	// switch receive buffers
	NRF_UARTE1->RXD.PTR = (uint32_t) idleRxBuf;
	NRF_UARTE1->RXD.MAXCNT = RX_BUF_SIZE;
	NRF_UARTE1->EVENTS_RXDRDY = false;
	NRF_UARTE1->TASKS_STARTRX = true;

	uint8* rxBuf = INACTIVE_RX_BUF();
	uint8* p = rxBuf + (RX_BUF_SIZE - 1);
	while ((255 == *p) && (p >= rxBuf)) p--; // scan from end of buffer for first non-255 byte
	return (p - rxBuf) + 1;
}

static void serialReadBytes(uint8 *buf, int byteCount) {
	uint8* rxBuf = INACTIVE_RX_BUF();
	for (int i = 0; i < byteCount; i++) {
		*buf++ = rxBuf[i];
		rxBuf[i] = 255;
	}
}

static int serialWriteBytes(uint8 *buf, int byteCount) {
	if (!NRF_UARTE1->EVENTS_ENDTX) return 0; // last transmission is still in progress
	if (byteCount > TX_BUF_SIZE) return 0; // fail if can't send the entire buffer
	for (int i = 0; i < byteCount; i++) {
		txBuf[i] = *buf++;
	}
	NRF_UARTE1->TXD.MAXCNT = byteCount;
	NRF_UARTE1->EVENTS_ENDTX = false;
	NRF_UARTE1->TASKS_STARTTX = true;
	return byteCount;
}

#else // use Serial1 or Serial2

// Use Serial2 on ESP32 board, Serial1 on others
#if defined(ESP32)
	#define SERIAL_PORT Serial2
#else
	#define SERIAL_PORT Serial1
#endif

static void serialClose() {
	isOpen = false;
	#if defined(ESP32)
		SERIAL_PORT.flush();
	#endif
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
	if (!isOpen) return 0;
	return SERIAL_PORT.write(buf, byteCount);
}

#endif

// help functions

static void serialWriteSync(uint8 *buf, int bytesToWrite) {
	// Synchronously write the given buffer to the serial port, performing multipe write
	// operations if necessary. Buffer size is limited to keep the operation from blocking
	// for too long a lower baud rates.

	if (bytesToWrite > TX_BUF_SIZE) {
		fail(serialWriteTooBig);
		return;
	}
	while (bytesToWrite > 0) {
		int written = serialWriteBytes(buf, bytesToWrite);
		if (written) {
			buf += written;
			bytesToWrite -= written;
		} else {
			#if defined(ARDUINO_BBC_MICROBIT_V2)
				updateMicrobitDisplay(); // update display while sending to avoid flicker
			#endif
			delay(1);
		}
	}
}

// primitives

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

// Empty byte array constant
static uint32 emptyByteArray = HEADER(ByteArrayType, 0);

static OBJ primSerialRead(int argCount, OBJ *args) {
	if (!isOpen) return fail(serialPortNotOpen);

	int byteCount = serialAvailable();
	if (byteCount == 0) return (OBJ) &emptyByteArray;
	if (byteCount < 0) return fail(primitiveNotImplemented);

	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (!result) return fail(insufficientMemoryError);
	serialReadBytes((uint8 *) &FIELD(result, 0), byteCount);
	setByteCountAdjust(result, byteCount);
	return result;
}

static OBJ primSerialReadInto(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	OBJ buf = args[0];
	if (!IS_TYPE(buf, ByteArrayType)) return fail(needsByteArray);

	if (!isOpen) return fail(serialPortNotOpen);

	int byteCount = serialAvailable();
	if (byteCount == 0) return zeroObj;
	if (byteCount < 0) return fail(primitiveNotImplemented);

	if (byteCount > BYTES(buf)) byteCount = BYTES(buf);
	serialReadBytes((uint8 *) &FIELD(buf, 0), byteCount);
	return int2obj(byteCount);
}

static OBJ primSerialWrite(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!isOpen) return fail(serialPortNotOpen);
	OBJ arg = args[0];

	if (isInt(arg)) { // single byte
		uint8 oneByte = obj2int(arg) & 255;
		serialWriteSync(&oneByte, 1);
	} else if (IS_TYPE(arg, StringType)) { // string
		char *s = obj2str(arg);
		serialWriteSync((uint8 *) s, strlen(s));
	} else if (IS_TYPE(arg, ByteArrayType)) { // byte array
		serialWriteSync((uint8 *) &FIELD(arg, 0), BYTES(arg));
	} else if (IS_TYPE(arg, ListType)) { // list of bytes
		uint8 buf[TX_BUF_SIZE]; // buffer for list contents
		int listSize = obj2int(FIELD(arg, 0));
		if (listSize > (int) sizeof(buf)) return fail(serialWriteTooBig);
		int byteCount = 0;
		uint8 *dst = buf;
		for (int i = 1; i <= listSize; i++) {
			OBJ item = FIELD(arg, i);
			if (isInt(item)) {
				*dst++ = obj2int(item) & 255;
				byteCount++;
			}
		}
		serialWriteSync(buf, byteCount);
	}
	return falseObj;
}

// Primitives

static PrimEntry entries[] = {
	{"open", primSerialOpen},
	{"close", primSerialClose},
	{"read", primSerialRead},
	{"readInto", primSerialReadInto},
	{"write", primSerialWrite},
};

void addSerialPrims() {
	addPrimitiveSet("serial", sizeof(entries) / sizeof(PrimEntry), entries);
}
