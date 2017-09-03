// runtime.c - Runtime for uBlocks, including code chunk storage and task management
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

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
	if (i >= MAX_TASKS) panic("No free task entries");

	memset(&tasks[i], 0, sizeof(Task));
	tasks[i].status = running;
	tasks[i].taskChunkIndex = chunkIndex;
	tasks[i].currentChunkIndex = chunkIndex;
	tasks[i].code = chunks[chunkIndex].code;
	tasks[i].ip = HEADER_WORDS; // relative to start of code
	tasks[i].sp = 0; // relative to start of stack
	tasks[i].fp = 0; // 0 means "not in a function call"
	if (i >= taskCount) taskCount = i + 1;
	sendMessage(taskStarted, 0, chunkIndex, 0, NULL);
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
	sendMessage(taskDone, 0, chunkIndex, 0, NULL);
}

static void startAll() {
	// Start tasks for all start and 'when' hat blocks.

	stopAllTasks(); // stop any running tasks
	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 chunkType = chunks[i].chunkType;
		if ((startHat == chunkType) || (whenConditionHat == chunkType)) {
			startTaskForChunk(i);
		}
	}
}

static void clearOutputQueue(void); // forward reference

void stopAllTasks() {
	// Stop all tasks.

	clearOutputQueue();
	for (int t = 0; t < taskCount; t++) {
		if (tasks[t].status) {
			sendMessage(taskDone, 0, tasks[t].taskChunkIndex, 0, NULL);
		}
	}
	initTasks();
	printStartMessage("All tasks stopped");
}

// Code Chunk Ops

void storeCodeChunk(uint8 chunkIndex, uint8 chunkType, int byteCount, uint8 *data) {
	if (chunkIndex >= MAX_CHUNKS) return;
	int wordCount = (byteCount + 3) / 4;
	OBJ newChunk = newObj(CodeChunkClass, wordCount, 0);
	uint8 *src = data;
	uint8 *end = data + byteCount;
	uint8 *dst = (uint8 *) &FIELD(newChunk, 0);
	while (src < end) *dst++ = *src++;

	chunks[chunkIndex].code = newChunk;
	chunks[chunkIndex].chunkType = chunkType;
}

static void deleteCodeChunk(uint8 chunkIndex) {
	if (chunkIndex >= MAX_CHUNKS) return;
	stopTaskForChunk(chunkIndex);
	chunks[chunkIndex].code = nilObj;
	chunks[chunkIndex].chunkType = unusedChunk;
}

// Sending Messages to IDE

// Circular output buffer
#define OUTBUF_SIZE 1024 // must be a power of 2!
#define OUTBUF_MASK (OUTBUF_SIZE - 1)
static uint8 outBuf[OUTBUF_SIZE];
static int outBufStart = 0;
static int outBufEnd = 0;

#define OUTBUF_BYTES() ((outBufEnd - outBufStart) & 0x1FF)

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

static void clearOutputQueue() { outBufStart = outBufEnd = 0; }

void sendMessage(int msgType, int msgID, int chunkIndex, int dataSize, char *data) {
#define DEBUG false
#if DEBUG
	return; // do nothing; comment out this line to see messages being sent

	printf("sendMessage %d %d %d %d \r\n", msgType, msgID, chunkIndex, dataSize);
	if (dataSize) {
		printf("  data: ");
		for (int i = 0; i < dataSize; i++) printf("%d ", data[i]);
		printf("\r\n");
	}
	return;
#endif // DEBUG

	int totalBytes = 5 + dataSize;
	if (totalBytes > ((OUTBUF_SIZE - 1) - OUTBUF_BYTES())) return; // no room in outBuf; should not happen
	queueByte(msgType);
	queueByte(msgID);
	queueByte(chunkIndex);
	queueByte(dataSize & 0xFF); // low byte of size
	queueByte((dataSize >> 8) & 0xFF); // high byte of size
	for (int i = 0; i < dataSize; i++) {
		queueByte(data[i]);
	}
}

int hasOutputSpace(int byteCount) { return ((OUTBUF_MASK - OUTBUF_BYTES()) > byteCount); }

void sendOutputMessage(char *s, int byteCount) {
	sendMessage(getOutputReply, 0, 0, byteCount, s);
}

void sendTaskReturnValue(uint8 chunkIndex, OBJ returnValue) {
	// Send the value returned by the task for the given chunk.
	// Data is: <type byte><...data...>
	// Types: 1 - integer, 2 - string

	char data[100];
	if (isInt(returnValue)) { // 32-bit integer, little endian
		data[0] = 1; // data type (1 is integer)
		int n = obj2int(returnValue);
		data[1] = (n & 0xFF);
		data[2] = ((n >> 8) & 0xFF);
		data[3] = ((n >> 16) & 0xFF);
		data[4] = ((n >> 24) & 0xFF);
		sendMessage(getReturnValueReply, 0, chunkIndex, 5, data);
	} else if (IS_CLASS(returnValue, StringClass)) { // string
		data[0] = 2; // data type (2 is string)
		char *s = obj2str(returnValue);
		int byteCount = strlen(s);
		if (byteCount > (int) (sizeof(data) - 1)) byteCount = sizeof(data) - 1;
		for (int i = 0; i < byteCount; i++) {
			data[i + 1] = s[i];
		}
		sendMessage(getReturnValueReply, 0, chunkIndex, (byteCount + 1), data);
	} else if ((returnValue == trueObj) || (returnValue == falseObj)) { // boolean
		data[0] = 3; // data type (3 is boolean)
		data[1] = (returnValue == trueObj) ? 1 : 0;
		sendMessage(getReturnValueReply, 0, chunkIndex, 2, data);
	}
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
	sendMessage(getTaskErrorInfoReply, 0, chunkIndex, sizeof(data), data);
}

// Receiving Messages from IDE

#define RCVBUF_SIZE 1024
static uint8 rcvBuf[RCVBUF_SIZE];
static int rcvByteCount = 0;

static void busyWaitMicrosecs(unsigned int usecs) {
	unsigned long start = TICKS();
	while ((TICKS() - start) < usecs) /* wait */;
}

unsigned long lastRcvTime = 0;

void processMessage() {
	// Process a message from the client.

	sendNextByte();

	int bytesRead = readBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
	rcvByteCount += bytesRead;
	if (!rcvByteCount) return;

	while (bytesRead > 0) {
		// wait time: on microBit, 35 seems to work, 25 fails
		// on Arduino Primo, 100 sometimes fails; use 150 to be safe (character time is ~90 usecs)
		busyWaitMicrosecs(150);
		bytesRead = readBytes(&rcvBuf[rcvByteCount], RCVBUF_SIZE - rcvByteCount);
		rcvByteCount += bytesRead;
		lastRcvTime = TICKS();
	}

	if (rcvByteCount < 5) return; // incomplete message header

	int bodyBytes = (rcvBuf[4] << 8) + rcvBuf[3]; // little endian
	if (rcvByteCount < (bodyBytes + 5)) { // incomplete message body
		int usecsSinceLastRcv = TICKS() - lastRcvTime;
		if (usecsSinceLastRcv < 0) { // clock wrap
			lastRcvTime = 0;
			usecsSinceLastRcv = 0;
		}
		if (usecsSinceLastRcv > 20000) rcvByteCount = 0; // timeout: discard message
		return;
	}

	uint8 msgType = rcvBuf[0];
	uint8 chunkIndex = rcvBuf[2];

	switch (msgType) {
	case storeChunkMsg:
		// body is: <chunkType (1 byte)> <instruction data>
		storeCodeChunk(chunkIndex, rcvBuf[5], (bodyBytes - 1), &rcvBuf[6]);
		break;
	case deleteChunkMsg:
		deleteCodeChunk(chunkIndex);
		break;
	case startAllMsg:
		startAll();
		break;
	case stopAllMsg:
		stopAllTasks();
		break;
	case startChunkMsg:
		startTaskForChunk(chunkIndex);
		break;
	case stopChunkMsg:
		stopTaskForChunk(chunkIndex);
		break;
	}

	// consume the message just processed
	if (rcvByteCount > (bodyBytes + 5)) {
		// slide message bytes following this message to the start of rcvBuf
		int extra = rcvByteCount - (bodyBytes + 5);
		uint8 *dst = &rcvBuf[0];
		uint8 *src = &rcvBuf[bodyBytes + 5];
		for (int i = 0; i < extra; i++) *dst++ = *src++;
		rcvByteCount = extra;
	} else {
		// this was the only message in the buffer; clear rcvByteCount
		rcvByteCount = 0; // clear the message buffer
	}
}
