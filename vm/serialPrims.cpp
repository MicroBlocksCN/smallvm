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

static OBJ setNRF52SerialPins(uint8 rxPin, uint8 txPin) { return fail(primitiveNotImplemented); }
static void serialOpen(int baudRate) { fail(primitiveNotImplemented); }
static void serialClose() { fail(primitiveNotImplemented); }
static int serialAvailable() { return -1; }
static void serialReadBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); }
static int serialWriteBytes(uint8 *buf, int byteCount) { fail(primitiveNotImplemented); return 0; }

#elif defined(NRF52) // use UART directly

// Note: Due to a bug or misfeature in the nRF52 UARTE hardware, the RXD.AMOUNT is
// not updated correctly. As a work around (hack!), we fill the receive buffer with
// 255's and detect the number of bytes by finding the last non-255 value. This
// implementation could miss an actual 255 data byte if it happens to the be last
// byte received when a read operation is performed. However, that should not be an
// problem in most real applications since 255 bytes are rare in string data, and
// this work around avoids using a hardware counter, interrupts, or PPI entries.

// Pin numbers for nRF52 boards. May be changed before calling serialOpen().
#if defined(CALLIOPE_V3)
	uint8 nrf52PinRx = 16;
	uint8 nrf52PinTx = 17;
#else
	uint8 nrf52PinRx = 0;
	uint8 nrf52PinTx = 1;
#endif

#define RX_BUF_SIZE 256
uint8 rxBufA[RX_BUF_SIZE];
uint8 rxBufB[RX_BUF_SIZE];

#define INACTIVE_RX_BUF() (((void *) NRF_UARTE1->RXD.PTR == rxBufB) ? rxBufA : rxBufB)

uint8 txBuf[TX_BUF_SIZE];

static OBJ setNRF52SerialPins(uint8 rxPin, uint8 txPin) {
	nrf52PinRx = rxPin;
	nrf52PinTx = txPin;
	return trueObj;
}

static void serialClose() {
	if (!NRF_UARTE1->ENABLE) return; // already stopped
	NRF_UARTE1->TASKS_STOPRX = true;
	NRF_UARTE1->TASKS_STOPTX = true;
	while (!NRF_UARTE1->EVENTS_TXSTOPPED) /* wait */;
	NRF_UARTE1->ENABLE = UARTE_ENABLE_ENABLE_Disabled;
	isOpen = false;
}

static void serialOpen(int baudRate) {
	if (isOpen) serialClose();

	// set pins
	NRF_UARTE1->PSEL.RXD = g_ADigitalPinMap[nrf52PinRx];
	NRF_UARTE1->PSEL.TXD = g_ADigitalPinMap[nrf52PinTx];

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

// Use Serial2 on ESP32 and Pico:ed boards, Serial1 on others
#if (defined(ESP32) && !defined(ESP32_S2_OR_S3) && !defined(ESP32_C3)) || defined(PICO_ED)
	#define SERIAL_PORT Serial2
#else
	#define SERIAL_PORT Serial1
#endif

static OBJ setNRF52SerialPins(uint8 rxPin, uint8 txPin) {
	return fail(primitiveNotImplemented);
}

static void serialClose() {
	isOpen = false;
	#if defined(ESP32)
		SERIAL_PORT.flush();
	#endif
	SERIAL_PORT.end();
}

static void serialOpen(int baudRate) {
	if (isOpen) serialClose();
	#if defined(ARDUINO_CITILAB_ED1)
		int txPin = mapDigitalPinNum(1);
		int rxPin = mapDigitalPinNum(2);
		SERIAL_PORT.begin(baudRate, SERIAL_8N1, rxPin, txPin);
	#elif defined(RP2040_PHILHOWER)
		#if defined(PICO_ED)
			// pico:ed edge connector pins 0-3 are analog pins 26-29
			// so use pins 4-5 for serial
			SERIAL_PORT.setTX(4);
			SERIAL_PORT.setRX(5);
		#elif defined(XRP)
			// use pins 16-17 (servo 1 & 2) for serial on XRP
			SERIAL_PORT.setTX(16);
			SERIAL_PORT.setRX(17);
		#endif
		SERIAL_PORT.setFIFOSize(1023);
		SERIAL_PORT.setTimeout(1);
		SERIAL_PORT.begin(baudRate);
		delayMicroseconds(5); // wait for garbage byte when first opening the serial port after a reset (seen at 115200 baud)
		SERIAL_PORT.begin(baudRate); // reset to discard garbage byte
	#else
		SERIAL_PORT.begin(baudRate);
	#endif
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

// helper functions

static void serialWriteSync(uint8 *buf, int bytesToWrite) {
	// Synchronously write the given buffer to the serial port, performing multipe write
	// operations if necessary. Buffer size is limited to keep the operation from blocking
	// for too long at low baud rates.

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
			// do background VM tasks
			#if defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3) || defined(GNUBLOCKS)
				updateMicrobitDisplay(); // update display while sending to avoid flicker
			#endif
			checkButtons();
			processMessage();
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
	if (isOpen) serialClose();
	isOpen = false;
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

	if (byteCount > (int) BYTES(buf)) byteCount = BYTES(buf);
	serialReadBytes((uint8 *) &FIELD(buf, 0), byteCount);
	return int2obj(byteCount);
}

static OBJ primSerialWrite(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!isOpen) return fail(serialPortNotOpen);
	OBJ arg = args[0];

	if (isInt(arg)) { // single byte
		int byteValue = obj2int(arg);
		if (byteValue > 255) return fail(byteOutOfRange);
		uint8 oneByte = byteValue;
		serialWriteSync(&oneByte, 1);
	} else if (IS_TYPE(arg, StringType)) { // string
		char *s = obj2str(arg);
		serialWriteSync((uint8 *) s, strlen(s));
	} else if (IS_TYPE(arg, ByteArrayType)) { // byte array
		serialWriteSync((uint8 *) &FIELD(arg, 0), BYTES(arg));
	} else if (IS_TYPE(arg, ListType)) { // list
		int listCount = obj2int(FIELD(arg, 0));
		for (int i = 1; i <= listCount; i++) {
			OBJ item = FIELD(arg, i);
			if (isInt(item)) {
				int byteValue = obj2int(item);
				if (byteValue > 255) return fail(byteOutOfRange);
				uint8 oneByte = byteValue;
				serialWriteSync(&oneByte, 1);
			}
		}
	}
	return falseObj;
}

static OBJ primSetPins(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0]) || !isInt(args[1])) return fail(needsIntegerIndexError);

	return setNRF52SerialPins(obj2int(args[0]), obj2int(args[1]));
}

static OBJ primSerialWriteBytes(int argCount, OBJ *args) {
	if (!isOpen) return fail(serialPortNotOpen);
	if (argCount < 2) return fail(notEnoughArguments);

	OBJ buf = args[0];
	int startIndex = obj2int(args[1]) - 1; // convert 0-based index
	if (startIndex < 0) return fail(indexOutOfRangeError);

	int bufType = objType(buf);
	if (!((bufType == StringType) || (bufType == ByteArrayType) || (bufType == ListType))) return fail(needsByteArray);
	if (!isInt(args[1])) return fail(needsIntegerIndexError);

	if (bufType == ListType) { // list
		int listCount = obj2int(FIELD(buf, 0));
		if (startIndex >= listCount) return fail(indexOutOfRangeError);
		for (int i = startIndex + 1; i <= listCount; i++) {
			OBJ item = FIELD(buf, i);
			if (isInt(item)) {
				int byteValue = obj2int(item);
				if (byteValue > 255) return fail(byteOutOfRange);
				uint8 oneByte = byteValue;
				serialWriteSync(&oneByte, 1);
			}
		}
		return int2obj((listCount - startIndex) + 1);
	}

	int srcLen = (bufType == StringType) ? strlen(obj2str(buf)) : BYTES(buf);
	if (startIndex >= srcLen) return fail(indexOutOfRangeError);

	int bytesToWrite = srcLen - startIndex;
	if (bytesToWrite > TX_BUF_SIZE) bytesToWrite = TX_BUF_SIZE;
	int bytesWritten = serialWriteBytes((uint8 *) &FIELD(buf, 0), bytesToWrite);
	return int2obj(bytesWritten);
}

// USB MIDI Primitives

#if defined(USB_MIDI) || defined(ARDUINO_ARCH_SAMD) || defined(ARDUINO_SAM_DUE)

#include "MIDIUSB.h"

static OBJ primMIDISend(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);

	midiEventPacket_t midiMsg;
	int cmd = obj2int(args[0]);
	midiMsg.header = (argCount == 1) ? cmd : ((cmd >> 4) & 0xF); // MIDI command w/o channel
	midiMsg.byte1 = cmd;
	midiMsg.byte2 = (argCount > 1) ? obj2int(args[1]) : 0;
	midiMsg.byte3 = (argCount > 2) ? obj2int(args[2]) : 0;

	MidiUSB.sendMIDI(midiMsg);
	MidiUSB.flush();

	return trueObj;
}

static OBJ primMIDIRecv(int argCount, OBJ *args) {
	// Return a MIDI message packet or false if none is available.
	// Packets are always 3-bytes. The first byte is the MIDI command bytes.
	// The following two bytes are argument bytes. The unused argument bytes
	// of 1-byte and 2-byte MIDI commands are zero.

	midiEventPacket_t midiEvent = MidiUSB.read(); // get the MIDI packet
	if (midiEvent.header == 0) return falseObj; // no data

	// allocate 3-byte byte array
	OBJ result = newObj(ByteArrayType, 1, falseObj);
	if (!result) return fail(insufficientMemoryError);
	setByteCountAdjust(result, 3);

	// read MIDI data into result
	uint8 *bytes = (uint8 *) &FIELD(result, 0);
	bytes[0] = midiEvent.byte1;
	bytes[1] = midiEvent.byte2;
	bytes[2] = midiEvent.byte3;

	return result;
}

#else // no USB_MIDI

static OBJ primMIDISend(int argCount, OBJ *args) { return falseObj; }
static OBJ primMIDIRecv(int argCount, OBJ *args) { return falseObj; }

#endif // USB_MIDI

// Primitives

static PrimEntry entries[] = {
	{"open", primSerialOpen},
	{"close", primSerialClose},
	{"read", primSerialRead},
	{"readInto", primSerialReadInto},
	{"write", primSerialWrite},
	{"setPins", primSetPins},
	{"writeBytes", primSerialWriteBytes},
	{"midiSend", primMIDISend},
	{"midiRecv", primMIDIRecv},
};

void addSerialPrims() {
	addPrimitiveSet("serial", sizeof(entries) / sizeof(PrimEntry), entries);
}
