/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// runtime.c - Runtime for uBlocks, including code chunk storage and task management
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// VM Version

#define VM_VERSION "v047"

// Forward Reference Declarations

static void sendMessage(int msgType, int chunkIndex, int dataSize, char *data);

// Printf Support

#ifdef ARDUINO
	char printfBuffer[100]; // used by printf macro in mem.h
#endif

// Named Primitive Support

typedef struct {
	char *setName;
	int entryCount;
	PrimEntry *entries;
} PrimitiveSet;

#define MAX_PRIM_SETS 5
PrimitiveSet primSets[MAX_PRIM_SETS];
int primSetCount = 0;

void addPrimitiveSet(char *setName, int entryCount, PrimEntry *entries) {
	if (primSetCount < MAX_PRIM_SETS) {
		primSets[primSetCount].setName = setName;
		primSets[primSetCount].entryCount = entryCount;
		primSets[primSetCount].entries = entries;
		primSetCount++;
	}
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
	char *setName = IS_CLASS(args[0], StringClass) ? obj2str(args[0]) : "";
	char *primName = IS_CLASS(args[1], StringClass) ? obj2str(args[1]) : "";

	for (int i = 0; i < primSetCount; i++) {
		if (0 == strcmp(primSets[i].setName, setName)) {
			PrimEntry *entries = primSets[i].entries;
			int entryCount = primSets[i].entryCount;
			for (int j = 0; j < entryCount; j++) {
				if (0 == strcmp(entries[j].primName, primName)) {
					return (entries[j].primFunc)(argCount - 2, args + 2); // call primitive
				}
			}
		}
	}
	return fail(primitiveNotImplemented);
}

void primsInit() {
	// Called at startup to call functions to add named primitive sets.

	addDisplayPrims();
	addIOPrims();
	addNetPrims();
	#ifdef ARDUINO_CITILAB_ED1
		addTFTPrims();
	#endif
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

void startAll() {
	// Start tasks for all start and 'when' hat blocks.

	stopAllTasks(); // stop any running tasks
	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 chunkType = chunks[i].chunkType;
		if ((startHat == chunkType) || (whenConditionHat == chunkType)) {
			startTaskForChunk(i);
		}
	}
}

void stopAllTasks() {
	// Stop all tasks.

	for (int t = 0; t < taskCount; t++) {
		if (tasks[t].status) {
			sendMessage(taskDoneMsg, tasks[t].taskChunkIndex, 0, NULL);
		}
	}
	initTasks();
}

// Selected Opcodes (see MicroBlocksCompiler.gp for complete set)

#define pushLiteral 4
#define recvBroadcast 25
#define initLocals 28

static int broadcastMatches(uint8 chunkIndex, char *msg, int byteCount) {
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
	if (strlen(s) != byteCount) return false;
	for (int i = 0; i < byteCount; i++) {
		if (s[i] != msg[i]) return false;
	}
	return true;
}

void startReceiversOfBroadcast(char *msg, int byteCount) {
	// Start tasks for chunks with hat blocks matching the given broadcast if not already running.

	for (int i = 0; i < MAX_CHUNKS; i++) {
		int chunkType = chunks[i].chunkType;
		if (((broadcastHat == chunkType) || (functionHat == chunkType)) && (broadcastMatches(i, msg, byteCount))) {
			startTaskForChunk(i); // only starts a new task if if chunk is not already running
		}
	}
}

// Button Hat Support

#define BUTTON_CHECK_INTERVAL 10000 // microseconds

static uint32 lastCheck = 0;

void checkButtons() {
	// If either button A or button B is pressed, start tasks for all of that button's
	// hat blocks if they are not already running. This check is done at most once
	// every BUTTON_CHECK_INTERVAL microseconds.

	uint32 now = microsecs();
	if (now < lastCheck) lastCheck = 0; // clock wrap
	if ((now - lastCheck) < BUTTON_CHECK_INTERVAL) return; // not time yet
	lastCheck = now;

	int chunkTypeA = (primButtonA(NULL)) ? buttonAHat : -1;
	int chunkTypeB = (primButtonB(NULL)) ? buttonBHat : -1;
	if ((chunkTypeA < 0) && (chunkTypeB < 0)) return; // neither button pressed

	for (int i = 0; i < MAX_CHUNKS; i++) {
		int chunkType = chunks[i].chunkType;
		if ((chunkTypeA == chunkType) || (chunkTypeB == chunkType)) {
			startTaskForChunk(i); // only starts a new task if if chunk is not already running
		}
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

static void storeChunkAttribute(uint8 chunkIndex, int byteCount, uint8 *data) {
	unsigned char attributeID = data[0];
	if ((chunkIndex >= MAX_CHUNKS) || (attributeID >= ATTRIBUTE_COUNT)) return;
	appendPersistentRecord(chunkAttribute, chunkIndex, attributeID, byteCount - 1, &data[1]);
}

static void storeVarName(uint8 varIndex, int byteCount, uint8 *data) {
	uint8 buf[100];
	if (byteCount > 99) byteCount = 99;
	uint8 *dst = buf;
	for (int i = 0; i < byteCount; i++) *dst++ = data[i];
	*dst = 0; // null terminate
	appendPersistentRecord(varName, varIndex, 0, (byteCount + 1), buf);
}

static void storeComment(uint8 commentIndex, int byteCount, uint8 *data) {
	appendPersistentRecord(comment, commentIndex, 0, byteCount, data);
}

static void storeCommentPosition(uint8 commentIndex, int byteCount, uint8 *data) {
	if (byteCount != 4) return;
	appendPersistentRecord(commentPosition, commentIndex, 0, byteCount, data);
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
	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(GNUBLOCKS)
		clearCodeFile();
	#else
		for (int chunkIndex = 0; chunkIndex < MAX_CHUNKS; chunkIndex++) {
			appendPersistentRecord(chunkDeleted, chunkIndex, 0, 0, NULL);
		}
	#endif
	memset(chunks, 0, sizeof(chunks));
}

static void clearAllVariables() {
	// Clear variable name records (but don't clear the variable values).
	appendPersistentRecord(varsClearAll, 0, 0, 0, NULL);
}

static void deleteComment(uint8 commentIndex) {
	appendPersistentRecord(commentDeleted, commentIndex, 0, 0, NULL);
}

// Soft Reset

static void softReset(int clearMemoryFlag) {
	// Reset the hardware and, optionally, clear memory.
	// Do not reload scripts from persistent memory.
	// This is not a full hardware reset/reboot, but close.

	stopAllTasks();

	OBJ off = falseObj;
	primSetUserLED(&off);
#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE_MINI)
	primMBDisplayOff(NULL);
	updateMicrobitDisplay();
#endif

	resetServos();
	stopTone();
	turnOffInternalNeoPixels();
	turnOffPins();
	outputString("Welcome to MicroBlocks!");
	if (clearMemoryFlag) {
		memClear();
		outputString("Memory cleared.");
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

static inline void sendData() {
	while (outBufStart != outBufEnd) {
		if (!sendByte(outBuf[outBufStart])) break;
		outBufStart = (outBufStart + 1) & OUTBUF_MASK;
	}
}

static inline void queueByte(char aByte) {
	outBuf[outBufEnd] = aByte;
	outBufEnd = (outBufEnd + 1) & OUTBUF_MASK;
}

static void sendMessage(int msgType, int chunkIndex, int dataSize, char *data) {
#define DEBUG false
#if DEBUG
	return; // comment out this line to display the messages being sent

	printf("sendMessage %d %d %d \r\n", msgType, chunkIndex, dataSize);
	if (data) {
		printf(" data: ");
		for (int i = 0; i < dataSize; i++) printf("%d ", data[i]);
		printf("\r\n");
	}
	return;
#endif // DEBUG

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

static void sendValueMessage(uint8 msgType, uint8 chunkOrVarIndex, OBJ value) {
	// Send a value message of the given type for the given chunkOrVarIndex.
	// Data is: <type byte><...data...>
	// Types: 1 - integer, 2 - string, 3 - boolean, 4 - bytearray, 5 - array

	char data[504]; // big enough for an array of 100 integers
	int maxBytes = (int) sizeof(data) - 1; // leave room for type bytes

	if (isInt(value)) { // 32-bit integer, little endian
		data[0] = 1; // data type (1 is integer)
		int n = obj2int(value);
		data[1] = (n & 0xFF);
		data[2] = ((n >> 8) & 0xFF);
		data[3] = ((n >> 16) & 0xFF);
		data[4] = ((n >> 24) & 0xFF);
		sendMessage(msgType, chunkOrVarIndex, 5, data);
	} else if (IS_CLASS(value, StringClass)) {
		data[0] = 2; // data type (2 is string)
		char *s = obj2str(value);
		int byteCount = strlen(s);
		if (byteCount > maxBytes) byteCount = maxBytes;
		for (int i = 0; i < byteCount; i++) {
			data[i + 1] = s[i];
		}
		sendMessage(msgType, chunkOrVarIndex, (byteCount + 1), data);
	} else if ((value == trueObj) || (value == falseObj)) { // boolean
		data[0] = 3; // data type (3 is boolean)
		data[1] = (value == trueObj) ? 1 : 0;
		sendMessage(msgType, chunkOrVarIndex, 2, data);
	} else if (IS_CLASS(value, ByteArrayClass)) {
		int byteCount = 4 * objWords(value);
		data[0] = 4; // data type (4 is bytearray)
		if (byteCount > maxBytes) byteCount = maxBytes;
		char *src = (char *) (&FIELD(value, 0));
		for (int i = 0; i < byteCount; i++) {
			data[i + 1] = *src++;
		}
		sendMessage(msgType, chunkOrVarIndex, (byteCount + 1), data);
	} else if (IS_CLASS(value, ArrayClass)) {
		// Note: xxx Incomplete! Currently only handles arrays of integers.
		int itemCount = objWords(value);
		int byteCount = 5 * objWords(value); // assume ints; include a type byte for each item
		if (byteCount > maxBytes) return; // too much data to send!
		data[0] = 5; // data type (5 is array)
		char *dst = &data[1];
		for (int i = 0; i < itemCount; i++) {
			OBJ item = FIELD(value, i);
			int n = isInt(item) ? obj2int(item) : -999; // map non-integers to special value
			*dst++ = 1; // item data type (1 is integer)
			*dst++ = (n & 0xFF);
			*dst++ = ((n >> 8) & 0xFF);
			*dst++ = ((n >> 16) & 0xFF);
			*dst++ = ((n >> 24) & 0xFF);
		}
		sendMessage(msgType, chunkOrVarIndex, (byteCount + 1), data);
	}
	// xxx to do: support arrays (containing various data types including other arrays)
}

void outputString(char *s) {
	// Special case for sending a debug string.

	char data[200];
	data[0] = 2; // data type (2 is string)
	int byteCount = strlen(s);
	if (byteCount > (int) (sizeof(data) - 1)) byteCount = sizeof(data) - 1;
	for (int i = 0; i < byteCount; i++) {
		data[i + 1] = s[i];
	}
	sendMessage(outputValueMsg, 255, (byteCount + 1), data);
}

void outputValue(OBJ value, uint8 chunkIndex) {
	sendValueMessage(outputValueMsg, chunkIndex, value);
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

static void setVariableValue(int varID, int byteCount, uint8 *data) {
	if ((varID >= 0) && (varID < MAX_VARS)) {
		int type = data[0];
		switch (type) {
		case 1: // integer
			vars[varID] = int2obj((data[4] << 24) | (data[3] << 16) | (data[2] << 8) | data[1]);
			break;
		case 2: // string
			if (byteCount >= 1) {
				vars[varID] = newStringFromBytes(&data[1], byteCount - 1);
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

static void waitForOutbufBytes(int bytesNeeded) {
	// Wait until there is room for the given number of bytes in the output buffer.

	while (bytesNeeded > (OUTBUF_MASK - OUTBUF_BYTES())) {
		sendData(); // should eventually create enough room for bytesNeeded
	}
}

void sendBroadcastToIDE(char *s, int len) {
	waitForOutbufBytes(len + 50); // leave a little room for other messages
	sendMessage(broadcastMsg, 0, len, s);
}

void sendSayForChunk(char *s, int len, uint8 chunkIndex) {
	// Used by the "say" primitive. The buffer s includes the string value type byte.
	sendMessage(outputValueMsg, chunkIndex, len, s);
}

// Retrieving source code and attributes

static void sendAttributeMessage(int chunkIndex, int attributeID, int *persistentRecord) {
	if (!persistentRecord) return; // NULL persistentRecord; do nothing

	int wordCount = *(persistentRecord + 1);
	int bodyBytes = 1 + (4 * wordCount);
	waitForOutbufBytes(5 + bodyBytes);

	queueByte(251);
	queueByte(chunkAttributeMsg);
	queueByte(chunkIndex);
	queueByte(bodyBytes & 0xFF); // low byte of size
	queueByte((bodyBytes >> 8) & 0xFF); // high byte of size
	queueByte(attributeID);
	int *src = persistentRecord + 2;
	for (int i = 0; i < wordCount; i++) {
		int w = *src++;
		queueByte(w & 0xFF);
		queueByte((w >> 8) & 0xFF);
		queueByte((w >> 16) & 0xFF);
		queueByte((w >> 24) & 0xFF);
	}
}

static void sendAllCode() {
	// Send the code and attributes for all chunks to the IDE.

	for (int chunkID = 0; chunkID < MAX_CHUNKS; chunkID++) {
		OBJ code = chunks[chunkID].code;
		if (NULL == code) continue; // skip unused chunk entry

		// send the binary code
		int words = *(code + 1); // size is the second word in the persistent store record
		int *data = code + PERSISTENT_HEADER_WORDS;
		waitForOutbufBytes(5 + (4 * words));
		sendMessage(chunkCodeMsg, chunkID, (4 * words), (char *) data);

		int *position = NULL;
		int *snapSource = NULL;
		int *gpSource = NULL;

		int *p = recordAfter(NULL);
		while (p) {
			int recID = (*p >> 8) & 0xFF;
			if (recID == chunkID) {
				int recType = (*p >> 16) & 0xFF;
				if (chunkAttribute == recType) {
					int attrType = *p & 0xFF;
					if (sourcePosition == attrType) position = p;
					if (snapSourceString == attrType) snapSource = p;
					if (gpSourceString == attrType) gpSource = p;
				}
				if (chunkDeleted == recType) {
					position = snapSource = gpSource = NULL;
				}
			}
			p = recordAfter(p);
		}
		if (snapSource) sendAttributeMessage(chunkID, snapSourceString, snapSource);
		if (gpSource) sendAttributeMessage(chunkID, gpSourceString, gpSource);
		if (position) sendAttributeMessage(chunkID, sourcePosition, position);
	}
}

// Variable support

int * varNameRecordFor(int varID) {
	int *result = NULL;
	int *p = recordAfter(NULL);
	while (p) {
		int recType = (*p >> 16) & 0xFF;
		int id = (*p >> 8) & 0xFF;
		if ((recType == varName) && (id == varID)) result = p;
		if (recType == varsClearAll) result = NULL;
		p = recordAfter(p);
	}
	return result;
}

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

static void sendVarNames() {
	// Send the names of all variables.

	for (int varID = 0; varID < MAX_VARS; varID++) {
		int *rec = varNameRecordFor(varID);
		if (rec) sendVarNameMessage(varID, rec);
	}
}

int indexOfVarNamed(char *varName) {
	// Return the index of the given variable or -1 if not found.

	for (int i = 0; i < MAX_VARS; i++) {
		int *rec = varNameRecordFor(i);
		if (rec) {
			char *thisVarName = (char *) (rec + 2);
			if (0 == strcmp(varName, thisVarName)) return i;
		}
	}
	return -1; // not found
}

// Receiving Messages from IDE

#define RCVBUF_SIZE 1024
#define MAX_MSG_SIZE (RCVBUF_SIZE - 10) // 5 header + 1 terminator bytes plus a few extra
static uint8 rcvBuf[RCVBUF_SIZE];
static int rcvByteCount = 0;
static uint32 lastRcvTime = 0;

static void skipToStartByteAfter(int startIndex) {
	int i, nextStart = -1;
	for (i = startIndex; i < rcvByteCount; i++) {
		int b = rcvBuf[i];
		if ((0xFA == b) || (0xFB == b)) {
			if ((i + 1) < rcvByteCount) {
				b = rcvBuf[i + 1];
				if ((b < 0x01) || (b > 0x20)) continue; // illegal msg type; keep scanning
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
		break;
	case stopChunkMsg:
		stopTaskForChunk(chunkIndex);
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
		break;
	case deleteCommentMsg:
		deleteComment(chunkIndex);
		break;
	case getVersionMsg:
		sendVersionString();
		break;
	case getAllCodeMsg:
		sendAllCode();
		break;
	case deleteAllCodeMsg:
		deleteAllChunks();
		break;
	case systemResetMsg:
		softReset(true);
		break;
	case pingMsg:
		sendMessage(pingMsg, chunkIndex, 0, NULL);
		break;
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
		storeCodeChunk(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	case setVarMsg:
		setVariableValue(rcvBuf[2], bodyBytes, &rcvBuf[5]);
		break;
	case broadcastMsg:
		startReceiversOfBroadcast((char *) &rcvBuf[5], bodyBytes);
		break;
	case chunkAttributeMsg:
		storeChunkAttribute(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	case varNameMsg:
		storeVarName(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	case commentMsg:
		storeComment(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	case commentPositionMsg:
		storeCommentPosition(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	}
	skipToStartByteAfter(5 + msgLength);
}

// Uncomment when building on mbed:
// static void busyWaitMicrosecs(int usecs) {
//	uint32 start = microsecs();
//	while ((microsecs() - start) < (uint32) usecs) /* wait */;
// }

void processMessage() {
	// Process a message from the client.

	sendData();

	int bytesRead = recvBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
	rcvByteCount += bytesRead;
	if (!rcvByteCount) return;

	while (bytesRead > 0) {
		// wait time: on microBit, 35 seems to work, 25 fails
		// on Arduino Primo, 100 sometimes fails; use 150 to be safe (character time is ~90 usecs)
//		busyWaitMicrosecs(150); // needed when built on mbed to avoid dropped bytes
		bytesRead = recvBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
		rcvByteCount += bytesRead;
		lastRcvTime = microsecs();
	}
	int firstByte = rcvBuf[0];
	if (0xFA == firstByte) {
		processShortMessage();
	} else if (0xFB == firstByte) {
		processLongMessage();
	} else {
		skipToStartByteAfter(1); // bad message, probably due to dropped bytes
	}
}
