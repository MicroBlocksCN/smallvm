// runtime.c - Runtime for uBlocks, including code chunk storage and task management
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// VM Version

#define VM_VERSION "v008"

// Forward Reference Declarations

static void sendMessage(int msgType, int chunkIndex, int dataSize, char *data);

// Printf Support

#ifdef ARDUINO
	char printfBuffer[100]; // used by printf macro in mem.h
#endif

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

// Store Ops

static void storeCodeChunk(uint8 chunkIndex, int byteCount, uint8 *data) {
	if (chunkIndex >= MAX_CHUNKS) return;
	int chunkType = data[0]; // first byte is the chunk type
	int *persistenChunk = appendPersistentRecord(chunkCode, chunkIndex, chunkType, byteCount - 1, &data[1]);
	chunks[chunkIndex].code = persistenChunk;
	chunks[chunkIndex].chunkType = chunkType;
}

void storeChunkPosition(uint8 chunkIndex, int byteCount, uint8 *data) {
	if ((chunkIndex >= MAX_CHUNKS) || (byteCount != 4)) return;
	appendPersistentRecord(chunkPosition, chunkIndex, 0, byteCount, &data);
}

void storeChunkAttribute(uint8 chunkIndex, int byteCount, uint8 *data) {
	unsigned char attributeID = data[0];
	if ((chunkIndex >= MAX_CHUNKS) || (attributeID >= ATTRIBUTE_COUNT)) return;
	appendPersistentRecord(chunkAttribute, chunkIndex, attributeID, byteCount - 1, &data[1]);
}

void storeVarName(uint8 varIndex, int byteCount, uint8 *data) {
	appendPersistentRecord(varName, varIndex, 0, byteCount, data);
}

void storeComment(uint8 commentIndex, int byteCount, uint8 *data) {
	appendPersistentRecord(comment, commentIndex, 0, byteCount, data);
}

void storeCommentPosition(uint8 commentIndex, int byteCount, uint8 *data) {
	if (byteCount != 4) return;
	appendPersistentRecord(commentPosition, commentIndex, 0, byteCount, data);
}

// Delete Ops

static void deleteCodeChunk(uint8 chunkIndex) {
	if (chunkIndex >= MAX_CHUNKS) return;
	stopTaskForChunk(chunkIndex);
	chunks[chunkIndex].code = nilObj;
	chunks[chunkIndex].chunkType = unusedChunk;
	appendPersistentRecord(chunkDeleted, chunkIndex, 0, 0, NULL);
}

static void deleteAllChunks() {
	stopAllTasks();
	for (int chunkIndex = 0; chunkIndex < MAX_CHUNKS; chunkIndex++) {
		appendPersistentRecord(chunkDeleted, chunkIndex, 0, 0, NULL);
	}
	memset(chunks, 0, sizeof(chunks));
}

static void deleteVar(uint8 varIndex) {
	if (varIndex >= MAX_VARS) return;
	vars[varIndex] = int2obj(0);
	appendPersistentRecord(varDeleted, varIndex, 0, 0, NULL);
}

static void deleteComment(uint8 commentIndex) {
	appendPersistentRecord(commentDeleted, commentIndex, 0, 0, NULL);
}

// Sending Messages to IDE

// Circular output buffer
#define OUTBUF_SIZE 1024 // must be a power of 2!
#define OUTBUF_MASK (OUTBUF_SIZE - 1)
static uint8 outBuf[OUTBUF_SIZE];
static int outBufStart = 0;
static int outBufEnd = 0;

#define OUTBUF_BYTES() ((outBufEnd - outBufStart) & OUTBUF_MASK)

static inline void sendNextByte() {
	if ((outBufStart != outBufEnd) && canSendByte()) {
		sendByte(outBuf[outBufStart]);
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
		printf("  data: ");
		for (int i = 0; i < dataSize; i++) printf("%d ", data[i]);
		printf("\r\n");
	}
	return;
#endif // DEBUG

	if (!data) { // short message
		queueByte(250);
		queueByte(msgType);
		queueByte(chunkIndex);
	} else {
		int totalBytes = 5 + dataSize;
		if (totalBytes > ((OUTBUF_SIZE - 1) - OUTBUF_BYTES())) return; // no room in outBuf; should not happen
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
	// Types: 1 - integer, 2 - string

	char data[200];
	if (isInt(value)) { // 32-bit integer, little endian
		data[0] = 1; // data type (1 is integer)
		int n = obj2int(value);
		data[1] = (n & 0xFF);
		data[2] = ((n >> 8) & 0xFF);
		data[3] = ((n >> 16) & 0xFF);
		data[4] = ((n >> 24) & 0xFF);
		sendMessage(msgType, chunkOrVarIndex, 5, data);
	} else if (IS_CLASS(value, StringClass)) { // string
		data[0] = 2; // data type (2 is string)
		char *s = obj2str(value);
		int byteCount = strlen(s);
		if (byteCount > (int) (sizeof(data) - 1)) byteCount = sizeof(data) - 1;
		for (int i = 0; i < byteCount; i++) {
			data[i + 1] = s[i];
		}
		sendMessage(msgType, chunkOrVarIndex, (byteCount + 1), data);
	} else if ((value == trueObj) || (value == falseObj)) { // boolean
		data[0] = 3; // data type (3 is boolean)
		data[1] = (value == trueObj) ? 1 : 0;
		sendMessage(msgType, chunkOrVarIndex, 2, data);
	}
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
	sendMessage(outputValueMsg, 0, (byteCount + 1), data);
}

void outputValue(OBJ value, int chunkIndex) {
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

void sendVariableValue(int varID) {
	if ((varID >= 0) && (varID < MAX_VARS)) {
		sendValueMessage(argValueMsg, varID, vars[varID]);
	}
}

void sendVersionString() {
	char s[100];
	snprintf(s, sizeof(s), " %s %s", VM_VERSION, boardType());
	s[0] = 2; // data type (2 is string)
	sendMessage(versionMsg, 0, strlen(s), s);
}

void sendAllCode() {
	// xxx to be done
}

// Receiving Messages from IDE

#define RCVBUF_SIZE 1024
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
		outputString("All tasks stopped");
		break;
	case getVarMsg:
		sendVariableValue(chunkIndex);
		break;
	case deleteVarMsg:
		deleteVar(chunkIndex);
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
		systemReset();
		break;
	}
	skipToStartByteAfter(3);
}

static void processLongMessage() {
	int msgLength = (rcvBuf[4] << 8) | rcvBuf[3];
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
	case storeChunkMsg:
		storeCodeChunk(chunkIndex, bodyBytes, &rcvBuf[5]);
		break;
	case chunkPositionMsg:
		storeChunkPosition(chunkIndex, bodyBytes, &rcvBuf[5]);
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

static void busyWaitMicrosecs(int usecs) {
	uint32 start = microsecs();
	while ((microsecs() - start) < (uint32) usecs) /* wait */;
}

void processMessage() {
	// Process a message from the client.

	sendNextByte();

	int bytesRead = readBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
	rcvByteCount += bytesRead;
	if (!rcvByteCount) return;

	while (bytesRead > 0) {
		// wait time: on microBit, 35 seems to work, 25 fails
		// on Arduino Primo, 100 sometimes fails; use 150 to be safe (character time is ~90 usecs)
//		busyWaitMicrosecs(150); // needed when built on mbed to avoid dropped bytes
		bytesRead = readBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
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
