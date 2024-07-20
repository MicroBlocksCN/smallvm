/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// runtime.c - Runtime for uBlocks, including code chunk storage and task management
// John Maloney, April 2017

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <string.h>

#if defined(GNUBLOCKS) && !defined(EMSCRIPTEN)
#include "../linux+pi/linux.h"
#endif

#include "mem.h"
#include "interp.h"
#include "persist.h"
#include "version.h"

// Forward Reference Declarations

void delay(unsigned long); // Arduino delay function

static void softReset(int clearMemoryFlag);
static void sendMessage(int msgType, int chunkIndex, int dataSize, char *data);
static void sendChunkCRC(int chunkID);
static void sendData();
static void deferIDEDisconnect();

// debugging

#ifdef DEBUG_BEEP

static void debugBeep(int count) {
	// Useful for audio debugging communication issues.

	const int speakerPin = 27;
	pinMode(speakerPin, 1); // output pin
	for (int i = 0; i < 10; i++) {
		digitalWrite(speakerPin, true);
		delay(count);
		digitalWrite(speakerPin, false);
		delay(count);
	}
	delay(20);
}

#endif

// Named Primitive Support

typedef struct {
	const char *setName;
	int entryCount;
	PrimEntry *entries;
} PrimitiveSet;

PrimitiveSet primSets[PrimitiveSetCount];

void addPrimitiveSet(PrimitiveSetIndex primSetIndex, const char *setName, int entryCount, PrimEntry *entries) {
	primSets[primSetIndex].setName = setName;
	primSets[primSetIndex].entryCount = entryCount;
	primSets[primSetIndex].entries = entries;
}

PrimitiveFunction findPrimitive(char *primName) {
	// Return the address of the named primitive with the given name or NULL if not found.
	// The primitive name is a string of the form: [primSet:primName].

	int len = strlen(primName);
	if (len < 2) return NULL;
	if (('[' != primName[0]) || (']' != primName[len - 1])) return NULL;
	char *colon = strchr(primName + 1, ':');
	if (!colon) return NULL;

	char setName[100];
	char opName[100];

	// extract primitive set name
	int count = colon - (primName + 1);
	if (count < 1) return NULL;
	strncpy(setName, primName + 1, count);
	setName[count] = 0;

	// extract primitive  name
	count = (primName + len - 1) - (colon + 1);
	if (count < 1) return NULL;
	strncpy(opName, colon + 1, count);
	opName[count] = 0;

	for (int i = 0; i < PrimitiveSetCount; i++) {
		if (0 == strcmp(primSets[i].setName, setName)) {
			PrimEntry *entries = primSets[i].entries;
			int entryCount = primSets[i].entryCount;
			for (int j = 0; j < entryCount; j++) {
				if (0 == strcmp(entries[j].primName, opName)) {
					return entries[j].primFunc;
				}
			}
		}
	}
	return NULL;
}

OBJ newPrimitiveCall(PrimitiveSetIndex setIndex, const char *primName, int argCount, OBJ *args) {
	// Call a named primitive with the given primitive set index and name.

	PrimEntry *entries = primSets[setIndex].entries;
	int entryCount = primSets[setIndex].entryCount;
	for (int i = 0; i < entryCount; i++) {
		if (0 == strcmp(entries[i].primName, primName)) {
			OBJ result = (entries[i].primFunc)(argCount, args); // call the primitive
			tempGCRoot = NULL; // clear tempGCRoot in case it was used
			return result;
		}
	}

	char s[200];
	snprintf(s, sizeof(s), "Unknown primitive [%s:%s]", primSets[setIndex].setName, primName);
	outputString(s);
	return fail(primitiveNotImplemented);

	return falseObj;
}

OBJ callPrimitive(int argCount, OBJ *args) {
	// Call a named primitive. The first two arguments are the primitive set name
	// and the primitive name, followed by the arguments to the primitive itself.
	//
	// Note: The overhead of named primitives on BBC micro:bit is 43 to 150 usecs or more.
	// In contrast, the overhead for a primitive built into the interpreter dispatch loop
	// (with one argument) ia about 17 usecs. So, named primitives should not be used for
	// operations that may need to be done really fast (e.g. toggling a pin in a loop)
	// but are fine for slower operations (e.g. updating the micro:bit display).

	if (argCount < 2) return fail(primitiveNotImplemented);
	char *setName = IS_TYPE(args[0], StringType) ? obj2str(args[0]) : (char *) "";
	char *primName = IS_TYPE(args[1], StringType) ? obj2str(args[1]) : (char *) "";

	for (int i = 0; i < PrimitiveSetCount; i++) {
		if (0 == strcmp(primSets[i].setName, setName)) {
			PrimEntry *entries = primSets[i].entries;
			int entryCount = primSets[i].entryCount;
			for (int j = 0; j < entryCount; j++) {
				if (0 == strcmp(entries[j].primName, primName)) {
					OBJ result = (entries[j].primFunc)(argCount - 2, args + 2); // call primitive
					tempGCRoot = NULL; // clear tempGCRoot in case it was used
					return result;
				}
			}
		}
	}
	char s[200];
	snprintf(s, sizeof(s), "Unknown primitive [%s:%s]", setName, primName);
	outputString(s);
	return fail(primitiveNotImplemented);
}

void primsInit() {
	// Called at startup to call functions to add named primitive sets.

	addDataPrims();
	addDisplayPrims();
	addFilePrims();
	addIOPrims();
	addMiscPrims();
	addNetPrims();
	addBLEPrims();
	addRadioPrims();
	addSensorPrims();
	addSerialPrims();
	addTFTPrims();
	addVarPrims();
	addHIDPrims();
	addOneWirePrims();
	addCameraPrims();
}

// Task Ops

void initTasks() {
	memset(tasks, 0, sizeof(tasks));
	taskCount = 0;
}

void startTaskForChunk(uint8 chunkIndex) {
	// Start a task for the given chunk, if there is not one already.

	int i;
	for (i = 0; i < taskCount; i++) {
		if ((chunkIndex == tasks[i].taskChunkIndex) && tasks[i].status) {
			return; // already running
		}
	}
	for (i = 0; i < MAX_TASKS; i++) {
		if (unusedTask == tasks[i].status) break;
	}
	if (i >= MAX_TASKS) {
		outputString("No free task entries");
		return;
	}

	memset(&tasks[i], 0, sizeof(Task));
	tasks[i].status = running;
	tasks[i].taskChunkIndex = chunkIndex;
	tasks[i].currentChunkIndex = chunkIndex;
	tasks[i].code = chunks[chunkIndex].code;
	tasks[i].ip = PERSISTENT_HEADER_WORDS; // relative to start of code
	tasks[i].sp = 0; // relative to start of stack
	tasks[i].fp = 0; // 0 means "not in a function call"
	if (i >= taskCount) taskCount = i + 1;
	sendMessage(taskStartedMsg, chunkIndex, 0, NULL);
}

static void stopTaskForChunk(uint8 chunkIndex) {
	// Stop the task for the given chunk, if any.

	int i;
	for (i = 0; i < MAX_TASKS; i++) {
		if (chunkIndex == tasks[i].taskChunkIndex) break;
	}
	if (i >= MAX_TASKS) return; // no task for chunkIndex
	memset(&tasks[i], 0, sizeof(Task)); // clear task
	if (i == (taskCount - 1)) taskCount--;
	sendMessage(taskDoneMsg, chunkIndex, 0, NULL);
}

static void stopAllTasks() {
	// Stop all tasks.

	for (int t = 0; t < taskCount; t++) {
		if (tasks[t].status) {
			sendMessage(taskDoneMsg, tasks[t].taskChunkIndex, 0, NULL);
		}
	}
	initTasks();
}

void startAll() {
	// Start tasks for all start and 'when' hat blocks.

	// stop running tasks, reset, and clear memory
	stopAllTasks();
	softReset(true);
	resetTimer();

	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 chunkType = chunks[i].chunkType;
		if ((startHat == chunkType) || (whenConditionHat == chunkType)) {
			startTaskForChunk(i);
		}
	}
}

void stopAllTasksButThis(Task *thisTask) {
	// Stop all tasks except the given one.

	for (int i = 0; i < MAX_TASKS; i++) {
		Task *task = &tasks[i];
		if ((task != thisTask) && task->status) {
			sendMessage(taskDoneMsg, task->taskChunkIndex, 0, NULL);
			memset(task, 0, sizeof(Task)); // clear task
		}
		if (task == thisTask) { taskCount = i + 1; }
	}
}

// Selected Opcodes (see MicroBlocksCompiler.gp for complete set)

#define pushLiteral 4
#define recvBroadcast 25
#define initLocals 28

int broadcastMatches(uint8 chunkIndex, char *msg, int byteCount) {
	uint32 *code = (uint32 *) chunks[chunkIndex].code + PERSISTENT_HEADER_WORDS;
	// First three instructions of a broadcast hat should be:
	//	initLocals
	//	pushLiteral
	//	recvBroadcast
	// A function with zero arguments can be also launched via a broadcast.
	if ((initLocals != CMD(code[0])) ||
		(pushLiteral != CMD(code[1])) ||
		(recvBroadcast != CMD(code[2])))
			return false;

	code++; // skip initLocals
	char *s = obj2str((OBJ) code + ARG(*code) + 1);
	if (strlen(s) == 0) return true; // empty parameter in the receiver means "any message"
	if (strlen(s) != byteCount) return false;
	for (int i = 0; i < byteCount; i++) {
		if (s[i] != msg[i]) return false;
	}
	return true;
}

extern OBJ lastBroadcast;

void startReceiversOfBroadcast(char *msg, int byteCount) {
	// Start tasks for chunks with hat blocks matching the given broadcast if not already running.

	lastBroadcast = newStringFromBytes(msg, byteCount);
	for (int i = 0; i < MAX_CHUNKS; i++) {
		int chunkType = chunks[i].chunkType;
		if (((broadcastHat == chunkType) || (functionHat == chunkType)) && (broadcastMatches(i, msg, byteCount))) {
			startTaskForChunk(i); // only starts a new task if if chunk is not already running
		}
	}
}

// Button Hat Support

#define BUTTON_CHECK_INTERVAL 10000 // microseconds
#define BUTTON_CLICK_TIME 50 // milliseconds

static uint32 lastCheck = 0;
static uint32 buttonADownTime = 0;
static uint32 buttonBDownTime = 0;
static char buttonAHandled = false;
static char buttonBHandled = false;

static void startButtonHats(int hatType) {
	for (int i = 0; i < MAX_CHUNKS; i++) {
		if (hatType == chunks[i].chunkType) {
			startTaskForChunk(i); // only starts a new task if if chunk is not already running
		}
	}
}

static int mustPollButtons() {
	// Return true if there is at least one "when button _ pressed" script.
	// Always return true on ED1 because we need to poll the touch sensor buttons.

	#ifdef ARDUINO_CITILAB_ED1
		return true;
	#endif

	for (int i = 0; i < MAX_CHUNKS; i++) {
		int hatType = chunks[i].chunkType;
		if ((buttonAHat <= hatType) && (hatType <= buttonsAandBHat)) {
			return true;
		}
	}
	return false;
}

void checkButtons() {
	// If button A, button B, or both are pressed, start tasks for all of the relevant
	// hat blocks (if they are not already running). This check is done at most once
	// every BUTTON_CHECK_INTERVAL microseconds.

	uint32 now = microsecs();
	if (now < lastCheck) lastCheck = 0; // clock wrap
	if ((now - lastCheck) < BUTTON_CHECK_INTERVAL) return; // not time yet
	lastCheck = now;

	if (!mustPollButtons()) return; // no need to poll buttons (allows button pins to be used for output)

	now = millisecs(); // use milliseconds for button timeouts
	if (!now) now = 1; // the value is reserved to mean button is not down

	int buttonAIsDown = (int) primButtonA(NULL);
	int buttonBIsDown = (int) primButtonB(NULL);

	if (buttonAIsDown && !buttonADownTime) { // button A up -> down
		buttonADownTime = now;
		if (buttonBDownTime) {
			if (!buttonBHandled) {
				startButtonHats(buttonsAandBHat);
				buttonAHandled = true;
				buttonBHandled = true;
			} else {
				startButtonHats(buttonAHat);
				buttonAHandled = true;
			}
		}
	}
	if (buttonBIsDown && !buttonBDownTime) { // button B up -> down
		buttonBDownTime = now;
		if (buttonADownTime) {
			if (!buttonAHandled) {
				startButtonHats(buttonsAandBHat);
				buttonAHandled = true;
				buttonBHandled = true;
			} else {
				startButtonHats(buttonBHat);
				buttonBHandled = true;
			}
		}
	}

	if (buttonADownTime && !buttonAHandled) {
		if (now < buttonADownTime) buttonADownTime = now; // clock wrap
		if ((now - buttonADownTime) >= BUTTON_CLICK_TIME) { // button A held for click time
			startButtonHats(buttonAHat);
			buttonAHandled = true;
		}
	}
	if (buttonBDownTime && !buttonBHandled) {
		if (now < buttonBDownTime) buttonBDownTime = now; // clock wrap
		if ((now - buttonBDownTime) >= BUTTON_CLICK_TIME) { // button B held for click time
			startButtonHats(buttonBHat);
			buttonBHandled = true;
		}
	}

	if (buttonADownTime && !buttonAIsDown) { // button A down -> up
		if (!buttonAHandled) startButtonHats(buttonAHat); // fast click (< BUTTON_CLICK_TIME)
		buttonADownTime = 0;
		buttonAHandled = false;
	}
	if (buttonBDownTime && !buttonBIsDown) { // button B down -> up
		if (!buttonBHandled) startButtonHats(buttonBHat); // fast click (< BUTTON_CLICK_TIME)
		buttonBDownTime = 0;
		buttonBHandled = false;
	}
}

// Store Ops

static void storeCodeChunk(uint8 chunkIndex, int byteCount, uint8 *data) {
	if (chunkIndex >= MAX_CHUNKS) return;
	stopTaskForChunk(chunkIndex);
	int chunkType = data[0]; // first byte is the chunk type
	int *persistenChunk = appendPersistentRecord(chunkCode, chunkIndex, chunkType, byteCount - 1, &data[1]);
	chunks[chunkIndex].code = persistenChunk;
	chunks[chunkIndex].chunkType = chunkType;
}

static void storeVarName(uint8 varIndex, int byteCount, uint8 *data) {
	uint8 buf[100];
	if (byteCount > 99) byteCount = 99;
	uint8 *dst = buf;
	for (int i = 0; i < byteCount; i++) *dst++ = data[i];
	*dst = 0; // null terminate
	appendPersistentRecord(varName, varIndex, 0, (byteCount + 1), buf);
}

// Delete Ops

static void deleteCodeChunk(uint8 chunkIndex) {
	if (chunkIndex >= MAX_CHUNKS) return;
	stopTaskForChunk(chunkIndex);
	chunks[chunkIndex].code = NULL;
	chunks[chunkIndex].chunkType = unusedChunk;
	appendPersistentRecord(chunkDeleted, chunkIndex, 0, 0, NULL);
}

static void deleteAllChunks() {
	stopAllTasks();
	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(GNUBLOCKS) || defined(RP2040_PHILHOWER)
		clearPersistentMemory();
		clearCodeFile(0);
	#else
		appendPersistentRecord(deleteAll, 0, 0, 0, NULL);
	#endif
	memset(chunks, 0, sizeof(chunks));
}

static void clearAllVariables() {
	// Clear variable name records (but don't clear the variable values).
	appendPersistentRecord(varsClearAll, 0, 0, 0, NULL);
}

// Extended Messages

static void processExtendedMessage(uint8 msgID, int byteCount, uint8 *data) {
	switch (msgID) {
	case 1: // set extraByteDelay
		if (byteCount < 1) break;
		int arg = *data;
		if (arg < 1) arg = 1;
		if (arg > 50) arg = 50;
		extraByteDelay = arg * 100; // 100 to 5000 microseconds per character
		break;
	case 2: // suspend saving to the code file on file-based boards while loading a project or library
		suspendCodeFileUpdates();
		break;
	case 3: // save the entire RAM code store to the code file and resume incremental saving
		resumeCodeFileUpdates();
		break;
	}
}

// Soft Reset

static void softReset(int clearMemoryFlag) {
	// Reset the hardware and, optionally, clear memory.
	// Do not reload scripts from persistent memory.
	// This is not a full hardware reset/reboot, but close.

	stopAllTasks();
	resumeCodeFileUpdates();

	OBJ off = falseObj;
	if (!useTFT) primSetUserLED(&off);
	#if defined(OLED_128_64)
		if (!useTFT) tftInit();
	#endif

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_BBC_MICROBIT_V2) || \
	defined(ARDUINO_CALLIOPE_MINI) || defined(CALLIOPE_V3)
		OBJ enable = trueObj;
		primMBEnableDisplay(1, &enable);
		primMBDisplayOff(0, NULL);
		updateMicrobitDisplay();
#endif

	resetRadio();
	stopPWM();
	stopServos();
	stopTone();
	#if !defined(DATABOT)
		turnOffInternalNeoPixels();
	#endif
	turnOffPins();
	if (clearMemoryFlag) {
		memClear();
		outputString("Memory cleared");
	}
}

// Sending Messages to IDE

// Circular output buffer
#define OUTBUF_SIZE 1024 // must be a power of 2!
#define OUTBUF_MASK (OUTBUF_SIZE - 1)
static uint8 outBuf[OUTBUF_SIZE];
static int outBufStart = 0;
static int outBufEnd = 0;

#define OUTBUF_BYTES() ((outBufEnd - outBufStart) & OUTBUF_MASK)

static void sendData() {
#ifdef EMSCRIPTEN
	// xxx can this special case for EMSCRIPTEN be removed? try it and test w/ boardie.
	if (outBufStart > outBufEnd) {
		if (sendBytes(outBuf, outBufStart, OUTBUF_SIZE)) {
			outBufStart = 0;
		}
	}
	if (outBufStart != outBufEnd) {
		if (sendBytes(outBuf, outBufStart, outBufEnd)) {
			outBufStart = outBufEnd & OUTBUF_MASK;
		}
	}
#else
	int byteCount = 0;

	if (outBufStart > outBufEnd) {
		byteCount = sendBytes(outBuf, outBufStart, OUTBUF_SIZE);
		outBufStart = (outBufStart + byteCount) & OUTBUF_MASK;
	}
	if (outBufStart < outBufEnd) {
		byteCount = sendBytes(outBuf, outBufStart, outBufEnd);
		outBufStart = (outBufStart + byteCount) & OUTBUF_MASK;
	}
#endif
}

static inline void queueByte(uint8 aByte) {
	outBuf[outBufEnd] = aByte;
	outBufEnd = (outBufEnd + 1) & OUTBUF_MASK;
}

static void sendMessage(int msgType, int chunkIndex, int dataSize, char *data) {
	if (!data) { // short message
		if (!hasOutputSpace(3)) return; // no space; drop message
		queueByte(250);
		queueByte(msgType);
		queueByte(chunkIndex);
	} else {
		int totalBytes = 5 + dataSize;
		if (!hasOutputSpace(totalBytes)) return; // no space; drop message
		queueByte(251);
		queueByte(msgType);
		queueByte(chunkIndex);
		queueByte(dataSize & 0xFF); // low byte of size
		queueByte((dataSize >> 8) & 0xFF); // high byte of size
		for (int i = 0; i < dataSize; i++) {
			queueByte(data[i]);
		}
	}
}

int hasOutputSpace(int byteCount) { return ((OUTBUF_MASK - OUTBUF_BYTES()) > byteCount); }

static void waitForOutbufBytes(int bytesNeeded) {
	// Wait until there is room for the given number of bytes in the output buffer.

	while (bytesNeeded > (OUTBUF_MASK - OUTBUF_BYTES())) {
		sendData(); // should eventually create enough room for bytesNeeded
	}
}

void waitAndSendMessage(int msgType, int chunkIndex, int dataSize, char *data) {
	// Wait for space, then send the given message.

	waitForOutbufBytes(dataSize + 5);
	sendMessage(msgType, chunkIndex, dataSize, data);
}

static void sendValueMessage(uint8 msgType, uint8 chunkOrVarIndex, OBJ value) {
	// Send a value message of the given type for the given chunkOrVarIndex.
	// Data is: <type (1 byte)><...data...>
	// Types: 1 - integer, 2 - string, 3 - boolean, 4 - list, 5 - bytearray

	char data[801];

	if (isInt(value)) { // 32-bit integer, little endian
		data[0] = 1;  // data type (1 is integer)
		int n = obj2int(value);
		data[1] = (n & 0xFF);
		data[2] = ((n >> 8) & 0xFF);
		data[3] = ((n >> 16) & 0xFF);
		data[4] = ((n >> 24) & 0xFF);
		sendMessage(msgType, chunkOrVarIndex, 5, data);
	} else if (IS_TYPE(value, StringType)) {
		data[0] = 2; // data type (2 is string)
		char *s = obj2str(value);
		int len = strlen(s);
		int sendCount = (len > 800) ? 800 : len;
		for (int i = 0; i < sendCount; i++) {
			data[i + 1] = s[i];
		}
		if (len > 800) {
			memcpy(&data[798], "...", 3); // string was truncated; add ellipses
		}
		sendMessage(msgType, chunkOrVarIndex, (sendCount + 1), data);
	} else if ((value == trueObj) || (value == falseObj)) {
		data[0] = 3; // data type (3 is boolean)
		data[1] = (trueObj == value) ? 1 : 0;
		sendMessage(msgType, chunkOrVarIndex, 2, data);
	} else if (IS_TYPE(value, ListType)) {
		data[0] = 4; // data type (4 is list)
		// Note: xxx Does not handle sublists.
		char *dst = &data[1];
		// total items in list (16-bit, little endian)
		int itemCount = obj2int(FIELD(value, 0));
		*dst++ = itemCount & 0xFF;
		*dst++ = (itemCount >> 8) & 0xFF;
		int sendCount = 32; // send up to this many items
		if (itemCount < sendCount) sendCount = itemCount;
		*dst++ = sendCount;
		for (int i = 0; i < sendCount; i++) {
			OBJ item = FIELD(value, i + 1);
			int type = objType(item);
			if (IntegerType == type) { // integer (32-bit signed, little-endian)
				*dst++ = 1; // item type (1 is integer)
				int n = obj2int(item);
				*dst++ = (n & 0xFF);
				*dst++ = ((n >> 8) & 0xFF);
				*dst++ = ((n >> 16) & 0xFF);
				*dst++ = ((n >> 24) & 0xFF);
			} else if (StringType == type) {
				*dst++ = 2; // item type (2 is string)
				int maxStringItem = 20;
				char *s = obj2str(item);
				int len = strlen(s);
				if (len <= maxStringItem) {
					*dst++ = len;
					for (int i = 0; i < len; i++) *dst++ = s[i];
				} else {
					*dst++ = maxStringItem; // send (maxStringItem - 3) bytes, then '...'
					for (int i = 0; i < (maxStringItem - 3); i++) *dst++ = s[i];
					for (int i = 0; i < 3; i++) *dst++ = '.';
				}
			} else if (BooleanType == type) {
				*dst++ = 3; // item type (3 is boolean)
				*dst++ = (trueObj == item) ? 1 : 0;
			} else if (ListType == type) { // sublist within a list; send item count only
				*dst++ = 4; // item type (4 is list)
				int n = obj2int(FIELD(item, 0)); // item count of sublist
				*dst++ = n & 0xFF;
				*dst++ = (n >> 8) & 0xFF;
				*dst++ = 0; // send zero items of sublists
			} else if (ByteArrayType == type) { // bytearray within a list; send bytecount only
				*dst++ = 5; // item type (5 is bytearray)
				int n = BYTES(item); // bytecount item
				*dst++ = n & 0xFF;
				*dst++ = (n >> 8) & 0xFF;
				*dst++ = 0; // send zero bytes
			} else {
				*dst++ = 0; // item type (0 is unknown)
			}
		}
		sendMessage(msgType, chunkOrVarIndex, (dst - data), data);
	} else if (IS_TYPE(value, ByteArrayType)) {
		data[0] = 5; // data type (5 is bytearray)
		char *dst = &data[1];
		// total bytecount
		int byteCount = BYTES(value);
		*dst++ = byteCount & 0xFF;
		*dst++ = (byteCount >> 8) & 0xFF;
		uint8 *bytes = (uint8 *) &FIELD(value, 0);
		int sendCount = (byteCount < 100) ? byteCount : 100; // send up to 100 bytes
		*dst++ = sendCount;
		for (int i = 0; i < sendCount; i++) {
			*dst++ = bytes[i];
		}
		sendMessage(msgType, chunkOrVarIndex, (sendCount + 4), data);
	}
}

void logData(char *s) {
	// Log data (the former 'print' command). Use chunkID 254.

	char data[200];
	data[0] = 2; // data type (2 is string)
	int byteCount = strlen(s);
	if (byteCount > (int) (sizeof(data) - 1)) byteCount = sizeof(data) - 1;
	for (int i = 0; i < byteCount; i++) {
		data[i + 1] = s[i];
	}
	sendMessage(outputValueMsg, 254, (byteCount + 1), data);
}

void outputString(const char *s) {
	// Sending a debug string. Use chunkID 255.

	if (!ideConnected()) return; // serial port not open; do nothing

	char data[200];
	data[0] = 2; // data type (2 is string)
	int byteCount = strlen(s);
	if (byteCount > (int) (sizeof(data) - 1)) byteCount = sizeof(data) - 1;
	for (int i = 0; i < byteCount; i++) {
		data[i + 1] = s[i];
	}

	waitForOutbufBytes(byteCount + 50);
	sendMessage(outputValueMsg, 255, (byteCount + 1), data);

	// when debugging VM crashes, it can be helpful to uncomment the following:
	// while (outBufStart != outBufEnd) sendData(); // wait for string to be sent
}

void sendTaskDone(uint8 chunkIndex) {
	sendMessage(taskDoneMsg, chunkIndex, 0, NULL);
}

void sendTaskError(uint8 chunkIndex, uint8 errorCode, int where) {
	// Send a task error message: one-byte error code + 4-byte location.
	// Location is

	char data[5];
	data[0] = (errorCode & 0xFF); // one byte error code
	data[1] = (where & 0xFF);
	data[2] = ((where >> 8) & 0xFF);
	data[3] = ((where >> 16) & 0xFF);
	data[4] = ((where >> 24) & 0xFF);
	sendMessage(taskErrorMsg, chunkIndex, sizeof(data), data);
}

void sendTaskReturnValue(uint8 chunkIndex, OBJ returnValue) {
	// Send the value returned by the task for the given chunk.

	sendValueMessage(taskReturnedValueMsg, chunkIndex, returnValue);
}

static void sendVariableValue(int varID) {
	if ((varID >= 0) && (varID < MAX_VARS)) {
		sendValueMessage(varValueMsg, varID, vars[varID]);
	}
}

static void sendValueOfVariableNamed(uint8 chunkIndex, int byteCount, uint8 *data) {
	char varName[100];
	if (byteCount > 99) return; // variable name too long; ignore request
	memcpy(varName, &data[0], byteCount);
	varName[byteCount] = 0; // null terminate
	int varID = indexOfVarNamed(varName);
	if (varID >= 0) sendValueMessage(varValueMsg, chunkIndex, vars[varID]);
}

static void setVariableValue(int varID, int byteCount, uint8 *data) {
	if ((varID >= 0) && (varID < MAX_VARS)) {
		int type = data[0];
		switch (type) {
		case 1: // integer
			vars[varID] = int2obj((data[4] << 24) | (data[3] << 16) | (data[2] << 8) | data[1]);
			break;
		case 2: // string
			if (byteCount >= 1) {
				vars[varID] = newStringFromBytes((char *) &data[1], byteCount - 1);
			}
			break;
		case 3: // boolean
			vars[varID] = data[1] ? trueObj : falseObj;
			break;
		}
	}
}

static void sendVersionString() {
	char s[100];
	snprintf(s, sizeof(s), " %s %s", VM_VERSION, boardType());
	s[0] = 2; // data type (2 is string)
	sendMessage(versionMsg, 0, strlen(s), s);
}

void sendBroadcastToIDE(char *s, int len) {
	int spaceNeeded = len + 50; // leave room for header and a few other messages
	if (!hasOutputSpace(spaceNeeded)) {
		if (!ideConnected()) {
			return; // apparently not connected to IDE
		} else {
			waitForOutbufBytes(spaceNeeded);
		}
	}
	sendMessage(broadcastMsg, 0, len, s);
}

void sendSayForChunk(char *s, int len, uint8 chunkIndex) {
	// Used by the "say" primitive. The buffer s includes the string value type byte.
	sendMessage(outputValueMsg, chunkIndex, len, s);
}

// Code chunk error checking (CRC-32)

const uint32_t crcTable[] = {
       0x0, 0x77073096, 0xEE0E612C, 0x990951BA,  0x76DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
 0xEDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,  0x9B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
0x76DC4190,  0x1DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589,  0x6B6B51F, 0x9FBFE4A5, 0xE8B8D433,
0x7807C9A2,  0xF00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB,  0x86D3D2D, 0x91646C97, 0xE6635C01,
0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
0xEDB88320, 0x9ABFB3B6,  0x3B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF,  0x4DB2615, 0x73DC1683,
0xE3630B12, 0x94643B84,  0xD6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D,  0xA00AE27, 0x7D079EB1,
0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
0x9B64C2B0, 0xEC63F226, 0x756AA39C,  0x26D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785,  0x5005713,
0x95BF4A82, 0xE2B87A14, 0x7BB12BAE,  0xCB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7,  0xBDBDF21,
0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D};

uint32_t crc32(uint8_t *buf, int byteCount) {
	uint32_t crc = ~0;
	uint8_t *end = buf + byteCount;
	for (uint8_t *p = buf; p < end; p++) {
		crc = (crc >> 8) ^ crcTable[(crc & 0xff) ^ *p];
	}
	return ~crc;
}

static void sendChunkCRC(int chunkID) {
	// Send the 4-byte CRC-32 for the given chunk. Do nothing if the chunk is not in use.

	if ((chunkID < 0) || (chunkID >= MAX_CHUNKS)) return;
	OBJ code = chunks[chunkID].code;
	if (code) {
		int wordCount = *(code + 1); // size is the second word in the persistent store record
		uint8_t *chunkData = (uint8_t *) (code + PERSISTENT_HEADER_WORDS);
		uint32_t crc = crc32(chunkData, (4 * wordCount));
		waitForOutbufBytes(9);
		sendMessage(chunkCRCMsg, chunkID, 4, (char *) &crc);
		sendData();
	}
}

void sendAllCRCs() {
	// count chunks
	int chunkCount = 0;
	for (int i = 0; i < MAX_CHUNKS; i++) {
		if (chunks[i].code) chunkCount++;
	}

	// send message header
	int dataSize = 5 * chunkCount;
	waitForOutbufBytes(10);
	queueByte(251);
	queueByte(allCRCsMsg);
	queueByte(0);
	queueByte(dataSize & 0xFF); // low byte of size
	queueByte((dataSize >> 8) & 0xFF); // high byte of size

	// send CRC records for chunks in use
	// each record is 5 bytes: chunkID (one byte) + the CRC for that chunk (four bytes)
	int delayPerCRC = extraByteDelay / 250;  // msec delay for 4 bytes (extraByteDelay is in usecs)
	for (int i = 0; i < MAX_CHUNKS; i++) {
		if (chunks[i].code) {
			OBJ code = chunks[i].code;
			int wordCount = *(code + 1); // size is the second word in the persistent store record
			uint8_t *chunkData = (uint8_t *) (code + PERSISTENT_HEADER_WORDS);
			uint32_t crc = crc32(chunkData, (4 * wordCount));
			char *crcBytes = (char *) &crc;
			waitForOutbufBytes(5);
			queueByte(i);
			queueByte(crcBytes[0]);
			queueByte(crcBytes[1]);
			queueByte(crcBytes[2]);
			queueByte(crcBytes[3]);
			delay(delayPerCRC);
		}
	}
	deferIDEDisconnect();
}

// Retrieving source code

static void sendCodeChunk(int chunkID, int chunkType, int chunkBytes, char *chunkData) {
	int msgSize = 1 + chunkBytes;
	waitForOutbufBytes(5 + msgSize);
	queueByte(251);
	queueByte(chunkCodeMsg);
	queueByte(chunkID);
	queueByte(msgSize & 0xFF); // low byte of size
	queueByte((msgSize >> 8) & 0xFF); // high byte of size
	queueByte(chunkType); // first byte of msg body is the chunk type
	char *end = chunkData + chunkBytes;
	for (char *p = chunkData; p < end; p++) {
		queueByte(*p);
	}
}

static void sendAllCode() {
	// Send the code for all chunks to the IDE.

	int delayPerWord = extraByteDelay / 250; // derive from extraByteDelay
	for (int chunkID = 0; chunkID < MAX_CHUNKS; chunkID++) {
		OBJ code = chunks[chunkID].code;
		if (NULL == code) continue; // skip unused chunk entry

		int chunkType = chunks[chunkID].chunkType;
		int chunkWords = *(code + 1); // chunk word count is second word of persistent store record
		char *chunkData = (char *) (code + PERSISTENT_HEADER_WORDS);
		sendCodeChunk(chunkID, chunkType, (4 * chunkWords), chunkData);
		sendData();
		delay(delayPerWord * chunkWords); // 2 fails on Johns Chromebook; 3 works; 5 is conservative
		sendData();
	}
	deferIDEDisconnect();
}

// Variable support

static void sendVarNameMessage(int varID, int *persistentRecord) {
	if (!persistentRecord) return; // NULL persistentRecord; do nothing

	char *varName = (char *) (persistentRecord + 2);
	int bodyBytes = strlen(varName);
	waitForOutbufBytes(5 + bodyBytes);

	queueByte(251);
	queueByte(varNameMsg);
	queueByte(varID);
	queueByte(bodyBytes & 0xFF); // low byte of size
	queueByte((bodyBytes >> 8) & 0xFF); // high byte of size
	char *src = varName;
	for (int i = 0; i < bodyBytes; i++) {
		queueByte(*src++);
	}
}

static int* varsStart() {
	int *p = scanStart();

	// find the last varsClearAll record
	int *result = p;
	while (p) {
		if (varsClearAll == ((*p >> 16) & 0xFF)) result = p;
		p = recordAfter(p);
	}
	return result;
}

static void sendVarNames() {
	// Send the names of all variables.

	int *p = varsStart();
	while (p) {
		int recType = (*p >> 16) & 0xFF;
		int varID = (*p >> 8) & 0xFF;
		if (recType == varName) sendVarNameMessage(varID, p);
		p = recordAfter(p);
	}
	deferIDEDisconnect();
}

int indexOfVarNamed(const char *s) {
	// Return the index of the given variable or -1 if not found.

	int result = -1; // default is not found
	int *p = varsStart();
	while (p) {
		int recType = (*p >> 16) & 0xFF;
		int id = (*p >> 8) & 0xFF;
		if (recType == varName) {
			if (0 == strcmp(s, (char *) (p + 2))) result = id;
		} else if (recType == varsClearAll) {
			result = -1;
		}
		p = recordAfter(p);
	}
	return result;
}

// Receiving Messages from IDE

#define RCVBUF_SIZE 1024
#define MAX_MSG_SIZE (RCVBUF_SIZE - 10) // 5 header + 1 terminator bytes plus a few extra
static uint8 rcvBuf[RCVBUF_SIZE];
static int rcvByteCount = 0;
uint32 lastRcvTime = 0;

static void skipToStartByteAfter(int startIndex) {
	int i, nextStart = -1;
	for (i = startIndex; i < rcvByteCount; i++) {
		int b = rcvBuf[i];
		if ((0xFA == b) || (0xFB == b)) {
			if ((i + 1) < rcvByteCount) {
				b = rcvBuf[i + 1];
                if ((b == 0) || ((b > LAST_MSG) && (b < 200))) continue; // illegal msg type; keep scanning			}
			}
			nextStart = i;
			break;
		}
	}
	if (-1 == nextStart) { // no start byte found; clear the entire buffer
		rcvByteCount = 0;
		return;
	}
	uint8 *dst = &rcvBuf[0];
	for (i = nextStart; i < rcvByteCount; i++) {
		*dst++ = rcvBuf[i];
	}
	rcvByteCount -= nextStart;
}

static int receiveTimeout() {
	// Check for receive timeout. This allows recovery from bad length or incomplete message.

	uint32 usecs = microsecs();
	if (usecs < lastRcvTime) lastRcvTime = 0; // clock wrap
	return (usecs - lastRcvTime) > 20000;
}

#if !defined(GNUBLOCKS) || defined(EMSCRIPTEN)

int ideConnected() {
	// Return true if the board is connected to the MicroBlocks IDE
	// (i.e. if it has received a message from the IDE in the past 3 seconds).

	if (0 == lastRcvTime) return false; // startup - no IDE messages yet

	uint32 now = microsecs();
	uint32 elapsed = (lastRcvTime > now) ? now : (now - lastRcvTime);
	return elapsed < 3 * 1000000; // an ide msg was received in the past N seconds
}

#endif

static void deferIDEDisconnect() {
	lastRcvTime = microsecs();
}

static void sendPingNow(int chunkIndex) {
	// Used to acknowledge receipt of a command that may take time, such as sending all CRC's.
	sendMessage(pingMsg, chunkIndex, 0, NULL); // send a ping to acknowledge receipt
	sendData();
}

static void processShortMessage() {
	if (rcvByteCount < 3) { // message is not complete
		if (receiveTimeout()) {
			skipToStartByteAfter(1);
		}
		return; // message incomplete
	}
	int cmd = rcvBuf[1];
	int chunkIndex = rcvBuf[2];
	switch (cmd) {
	case deleteChunkMsg:
		deleteCodeChunk(chunkIndex);
		break;
	case startChunkMsg:
		startTaskForChunk(chunkIndex);
		sendPingNow(chunkIndex); // send a ping to acknowledge
		break;
	case stopChunkMsg:
		stopTaskForChunk(chunkIndex);
		sendPingNow(chunkIndex); // send a ping to acknowledge
		break;
	case startAllMsg:
		startAll();
		break;
	case stopAllMsg:
		stopAllTasks();
		softReset(false);
		outputString("All tasks stopped");
		break;
	case getVarMsg:
		sendVariableValue(chunkIndex);
		break;
	case getVarNamesMsg:
		sendVarNames();
		break;
	case clearVarsMsg:
		clearAllVariables();
		memClear();
		break;
	case getChunkCRCMsg:
		sendChunkCRC(chunkIndex);
		break;
	case getAllCRCsMsg:
		sendPingNow(chunkIndex); // send a ping to acknowledge receipt
		sendAllCRCs();
		break;
	case getVersionMsg:
		sendVersionString();
		break;
	case getAllCodeMsg:
		sendPingNow(chunkIndex); // send a ping to acknowledge receipt
		sendAllCode();
		break;
	case deleteAllCodeMsg:
		deleteAllChunks();
		memClear();
		primMBDisplayOff(0, NULL);
		break;
	case systemResetMsg:
		// non-zero chunkIndex is used for debugging operations
		if (1 == chunkIndex) { outputRecordHeaders(); break; }
		if (2 == chunkIndex) { compactCodeStore(); break; }
		if (3 == chunkIndex) { primMBDisplayOff(0, NULL); } // used by Boardie reset
		softReset(true);
		break;
	case pingMsg:
		sendPingNow(chunkIndex);
		break;
	case enableBLEMsg:
		BLE_setEnabled(chunkIndex);
		break;
	default:
		if ((200 <= cmd) && (cmd <= 205)) {
			processFileMessage(cmd, 0, NULL);
			sendData();
		}
	}
	skipToStartByteAfter(3);
}

static void processLongMessage() {
	int msgLength = (rcvBuf[4] << 8) | rcvBuf[3];
	if ((rcvByteCount >= 5) && (msgLength > MAX_MSG_SIZE)) { // message too large for buffer
		skipToStartByteAfter(1);
		return;
	}
	if ((rcvByteCount < 5) || (rcvByteCount < (5 + msgLength))) { // message is not complete
		if (receiveTimeout()) {
			skipToStartByteAfter(1);
		}
		return; // message incomplete
	}
	if (0xFE != rcvBuf[5 + msgLength - 1]) { // chunk does not end with a terminator byte
		skipToStartByteAfter(1);
		return;
	}
	int cmd = rcvBuf[1];
	int chunkIndex = rcvBuf[2];
	int bodyBytes = msgLength - 1; // subtract terminator byte
	switch (cmd) {
	case chunkCodeMsg:
		sendPingNow(chunkIndex); // send a ping to acknowledge receipt
		storeCodeChunk(chunkIndex, bodyBytes, &rcvBuf[5]);
		sendChunkCRC(chunkIndex);
		break;
	case setVarMsg:
		setVariableValue(rcvBuf[2], bodyBytes, &rcvBuf[5]);
		break;
	case getVarMsg:
		sendValueOfVariableNamed(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	case broadcastMsg:
		startReceiversOfBroadcast((char *) &rcvBuf[5], bodyBytes);
		break;
	case varNameMsg:
		storeVarName(chunkIndex, bodyBytes, &rcvBuf[5]);
		sendPingNow(chunkIndex); // send a ping to acknowledge save
		break;
	case extendedMsg:
		processExtendedMessage(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	default:
		if ((200 <= cmd) && (cmd <= 205)) {
			processFileMessage(cmd, bodyBytes, (char *) &rcvBuf[5]);
			sendData();
		}
	}
	skipToStartByteAfter(5 + msgLength);
}

// Uncomment when building on mbed:
// static void busyWaitMicrosecs(int usecs) {
//	uint32 start = microsecs();
//	while ((microsecs() - start) < (uint32) usecs) /* wait */;
// }

void captureIncomingBytes() {
	int bytesRead = recvBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
	rcvByteCount += bytesRead;
	// uncomment to check for serial buffer overruns:
	// if (bytesRead > 49) reportNum("bytesRead", bytesRead);
}

void processMessage() {
	// Process a message from the client.
	sendData();

	int bytesRead = recvBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
	// uncomment to check for serial buffer overruns:
	// if (bytesRead > 49) reportNum("bytesRead", bytesRead);
	rcvByteCount += bytesRead;
	if (!rcvByteCount) return;

	// the following is needed when built on mbed to avoid dropped bytes
// 	while (bytesRead > 0) {
// 		// on Arduino Primo, 100 sometimes fails; use 150 to be safe (character time is ~90 usecs)
// 		busyWaitMicrosecs(150);
// 		bytesRead = recvBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
// 		rcvByteCount += bytesRead;
// 	}

	lastRcvTime = microsecs();
	int firstByte = rcvBuf[0];
	if (0xFA == firstByte) {
		processShortMessage();
	} else if (0xFB == firstByte) {
		processLongMessage();
	} else {
		skipToStartByteAfter(1); // bad message, probably due to dropped bytes
	}
}
