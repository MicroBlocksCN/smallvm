// runtime.c - Runtime for uBlocks, including code chunk storage and task management
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Helper Functions

static void updateChunkTaskStatus() {
	for (int i = 0; i < MAX_CHUNKS; i++) {
		chunks[i].taskStatus = unknown;
	}
	for (int i = 0; i < taskCount; i++) {
		Task *task = &tasks[i];
		if ((task->status > unusedTask) && (task->taskChunkIndex < MAX_CHUNKS)) {
			chunks[task->taskChunkIndex].taskStatus = task->status;
		}
	}
}

static void resetTask(int chunkIndex) {
	// Reset the task status after getting return value or error (trigger highlight removal by IDE).

	chunks[chunkIndex].taskStatus = done;
	chunks[chunkIndex].taskErrorCode = 0;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;

	for (int i = 0; i < taskCount; i++) {
		Task *task = &tasks[i];
		if (task->taskChunkIndex == chunkIndex) {
			task->status = done;
		}
	}
}

// Debugging Support

// When DEBUG is true, respond to queries by printing human-readable strings to the teriminal
// rather than sending binary messages. DEBUG mode is useful for all debugging since debugging
// messages are simply mixed with protocol query results in the terminal output. Of course, the
// client must also be modified to simply simply to print all incoming bytes to the terminal,
// rather than expected binary protocol messages. While DEBUG mode might seem clumbsy, if you
// don't have it the VM implementor cannot use printf for debugging, since its output would
// "corrupt" the binary messages of the protocol. The root difficulty arises from the fact that
// a single serial port is used for both normal operation and debugging. One might dedicate a
// second serial port for debug output,but that would require a USB-serial cable and the use
// of a second USB connection on the host computer. DEBUG mode allows you to debug over the
// existing USB-serial connection.

#define DEBUG false

void showChunks() {
	int usedChunkCount = 0;
	for (int i = 0; i < MAX_CHUNKS; i++) {
		CodeChunkRecord* chunk = &chunks[i];
		if (chunk->chunkType != unusedChunk) {
			usedChunkCount++;
			printf("Chunk %d: type %d taskStatus %d code %u (%d words)\r\n",
				i, chunk->chunkType, chunk->taskStatus, (uint32) chunk->code, objWords(chunk->code));
			if (chunk->returnValueOrErrorIP) {
				printf("  returnValueOrErrorIP: %d\r\n", (int) chunk->returnValueOrErrorIP);
			}
			if (chunk->taskErrorCode) printf("  taskErrorCode: %d\r\n", chunk->taskErrorCode);
		}
	}
	if (0 == usedChunkCount) printf("No chunks\r\n");
}

void showTasks() {
	if (!taskCount) {
		printf("No tasks\r\n");
		return;
	}
	printf("%d tasks:\r\n", taskCount);
	for (int i = 0; i < taskCount; i++) {
		Task *task = &tasks[i];
		if (task->status > unusedTask) {
			printf("Task %d: status %d wake %u ip %d sp %d fp %d taskChunk %d ",
				i, task->status, task->wakeTime, task->ip, task->sp, task->fp, task->taskChunkIndex);
			if (task->currentChunkIndex != task->taskChunkIndex) {
				printf("currentChunk %d code %u", task->currentChunkIndex, (uint32) task->code);
			}
			printf("\r\n");
		}
	}
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
		if ((chunkIndex == tasks[i].taskChunkIndex) && (tasks[i].status >= waiting_micros)) {
			return; // already running
		}
	}

	for (i = 0; i < MAX_TASKS; i++) {
		if (tasks[i].status < waiting_micros) break;
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
	sendTaskStarted(chunkIndex);
}

static void stopTaskForChunk(uint8 chunkIndex) {
	// Stop the task for the given chunk, if any.

	int i;
	for (i = 0; i < MAX_TASKS; i++) {
		if (chunkIndex == tasks[i].taskChunkIndex) break;
	}
	if (i >= MAX_TASKS) return; // no task for chunkIndex
	memset(&tasks[i], 0, sizeof(Task)); // clear task
	chunks[chunkIndex].taskStatus = unknown;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
	if (i == (taskCount - 1)) taskCount--;
}

void stopAllTasks() {
	// Stop all tasks.

	initTasks();
	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 status = chunks[i].taskStatus;
		if (status >= waiting_micros) {
			chunks[i].taskStatus = unknown;
			chunks[i].returnValueOrErrorIP = nilObj;
		}
	}
	// Clear buffered output
	printBufferByteCount = 0;
	printBuffer[0] = 0; // null terminate
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
	chunks[chunkIndex].taskStatus = unknown;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
}

static void deleteCodeChunk(uint8 chunkIndex) {
	if (chunkIndex >= MAX_CHUNKS) return;
	stopTaskForChunk(chunkIndex);
	chunks[chunkIndex].code = nilObj;
	chunks[chunkIndex].chunkType = unusedChunk;
	chunks[chunkIndex].taskStatus = unknown;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
}

// Sending Messages to IDE

// Circular output buffer
#define OUTBUF_SIZE 512 // must be a power of 2!
#define OUTBUF_MASK (OUTBUF_SIZE - 1)
uint8 outBuf[OUTBUF_SIZE];
int outBufStart = 0;
int outBufEnd = 0;

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

static void sendMessage(int msgType, int msgID, int chunkIndex, int dataSize, char *data) {

// xxx
// printf("sendMessage %d %d %d %d \r\n", msgType, msgID, chunkIndex, dataSize);
// if (dataSize) {
//   printf("  data: ");
//   for (int i = 0; i < dataSize; i++) printf("%d ", data[i]);
//   printf("\r\n");
// }
// return; // xxx

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

void sendOutputMessage(char *s, int byteCount) {
	sendMessage(getOutputReply, 0, 0, byteCount, s);
}

static void sendOkay(uint8 msgID) {
#if DEBUG
	printf("Okay\r\n");
#else
	sendMessage(okayReply, msgID, 0, 0, NULL);
#endif
}

static void sendError(uint8 msgID, uint8 errorCode) {
	// Send a protocol error message (e.g. badChunkIndexError).
	// The error code is stored in the third byte of the message,
	// where the chunkIndex often appears.
#if DEBUG
	printf("Error: %d\r\n", errorCode);
#else
	sendMessage(errorReply, msgID, errorCode, 0, NULL);
#endif
}

static void sendTaskStatus(uint8 msgID) {
	// Send a task status message containing a task status byte for each chunk.
	// Chunks that have never been run will have a status of 'unknown'.

	updateChunkTaskStatus();
#if DEBUG
	showChunks();
	showTasks();
#else
	char statusData[MAX_CHUNKS];
	for (int i = 0; i < MAX_CHUNKS; i++) {
		statusData[i] = chunks[i].taskStatus;
	}
	sendMessage(getTaskStatusReply, msgID, 0, sizeof(statusData), statusData);
#endif
}

static void sendOutput(uint8 msgID) {
	// Send the last output string. If there is none, do nothing.

	if (!printBufferByteCount) return; // no output to send

#if DEBUG
	if (printBufferByteCount) printf("Output: %s", printBuffer);
#else
	sendMessage(getOutputReply, msgID, 0, printBufferByteCount, printBuffer);
#endif

	// clear the buffer and make runnable any tasks that were waiting to print
	printBufferByteCount = 0;
	printBuffer[0] = 0; // null terminate
	for (int i = 0; i < MAX_TASKS; i++) {
		if (waiting_print == tasks[i].status) {
			tasks[i].status = running;
		}
	}
}

void sendTaskStarted(uint8 chunkIndex) {
	// Inform the client that a task has started for the given chunk.

	sendMessage(taskStarted, 0, chunkIndex, 0, NULL);
}

void sendTaskDone(uint8 chunkIndex) {
	// Inform the client that the task for the given chunk is done.

	sendMessage(taskDone, 0, chunkIndex, 0, NULL);
	resetTask(chunkIndex);
}

void sendTaskDoneReturnValue(uint8 chunkIndex, OBJ returnValue) {
	// Send the value returned by the task for the given chunk.
	// Data is: <type byte><...data...>
	// Types: 1 - integer, 2 - string

	char buf[100];
	if (isInt(returnValue)) { // 32-bit integer, little endian
		int n = obj2int(returnValue);
		buf[0] = 1; // data type (1 is integer)
		buf[1] = (n & 0xFF);
		buf[2] = ((n >> 8) & 0xFF);
		buf[3] = ((n >> 16) & 0xFF);
		buf[4] = ((n >> 24) & 0xFF);
		sendMessage(getReturnValueReply, 0, chunkIndex, 5, buf);
	} else if (IS_CLASS(returnValue, StringClass)) { // string
		char *s = obj2str(returnValue);
		int byteCount = strlen(s);
		if (byteCount > (int) (sizeof(buf) - 1)) byteCount = sizeof(buf) - 1;
		buf[0] = 2; // data type (2 is string)
		for (int i = 0; i < byteCount; i++) {
			buf[i + 1] = s[i];
		}
		sendMessage(getReturnValueReply, 0, chunkIndex, (byteCount + 1), buf);
	} else if ((returnValue == trueObj) || (returnValue == falseObj)) { // boolean
		buf[0] = 3; // data type (3 is boolean)
		buf[1] = (returnValue == trueObj) ? 1 : 0;
		sendMessage(getReturnValueReply, 0, chunkIndex, 2, buf);
	} else { // floats support will be be added later
		sendError(0, unspecifiedError);
	}
	resetTask(chunkIndex);
}

void sendTaskError(uint8 taskChunkIndex, uint8 errorCode) {
	sendMessage(errorReply, taskChunkIndex, errorCode, 0, NULL);
}

static void sendReturnValue(uint8 msgID, uint8 chunkIndex) {
	// Send the return value for the task running the given chunk. Assume
	// that the task status is done_Value. If it isn't, send an errorReply.
	// Data is: <type byte><...data...>
	// Types: 1 - integer, 2 - string

	if ((chunkIndex >= MAX_CHUNKS) || (done_Value != chunks[chunkIndex].taskStatus)) {
		sendError(msgID, badChunkIndexError);
		return;
	}
	OBJ returnValue = chunks[chunkIndex].returnValueOrErrorIP;
	char buf[100];
	if (isInt(returnValue)) { // 32-bit integer, little endian
		int n = obj2int(returnValue);
		buf[0] = 1; // data type (1 is integer)
		buf[1] = (n & 0xFF);
		buf[2] = ((n >> 8) & 0xFF);
		buf[3] = ((n >> 16) & 0xFF);
		buf[4] = ((n >> 24) & 0xFF);
		sendMessage(getReturnValueReply, msgID, chunkIndex, 5, buf);
	} else if (IS_CLASS(returnValue, StringClass)) { // string
		char *s = obj2str(returnValue);
		int byteCount = strlen(s);
		if (byteCount > (int) (sizeof(buf) - 1)) byteCount = sizeof(buf) - 1;
		buf[0] = 2; // data type (2 is string)
		for (int i = 0; i < byteCount; i++) {
			buf[i + 1] = s[i];
		}
		sendMessage(getReturnValueReply, msgID, chunkIndex, (byteCount + 1), buf);
	} else { // floats support will be be added later
		sendError(msgID, unspecifiedError);
	}
	resetTask(chunkIndex);
}

static void sendTaskErrorInfo(uint8 msgID, uint8 chunkIndex) {
	// Send the error code and IP for the task that was running the given chunk.
	// Assume that the task status is done_Error. If it isn't, send an errorReply.

	if ((chunkIndex >= MAX_CHUNKS) || (done_Error != chunks[chunkIndex].taskStatus)) {
		sendError(msgID, badChunkIndexError);
		return;
	}
	int n = obj2int(chunks[chunkIndex].returnValueOrErrorIP);
	char errorData[4];
	errorData[0] = (n & 0xFF);
	errorData[1] = ((n >> 8) & 0xFF);
	errorData[2] = ((n >> 16) & 0xFF);
	errorData[3] = ((n >> 24) & 0xFF);
	sendMessage(getTaskErrorInfoReply, msgID, 0, sizeof(errorData), errorData);
	resetTask(chunkIndex);
}

// Receiving Messages from IDE

#define RCVBUF_SIZE 512
uint8 rcvBuf[RCVBUF_SIZE];
int rcvByteCount = 0;

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
	uint8 msgID = rcvBuf[1];
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
		sendOkay(msgID);
		break;
	case startChunkMsg:
		startTaskForChunk(chunkIndex);
		break;
	case stopChunkMsg:
		stopTaskForChunk(chunkIndex);
		break;
	case getTaskStatusMsg:
		sendTaskStatus(msgID);
		break;
	case getOutputMsg:
		sendOutput(msgID);
		break;
	case getReturnValueMsg:
		sendReturnValue(msgID, chunkIndex);
		break;
	case getTaskErrorInfoMsg:
		sendTaskErrorInfo(msgID, chunkIndex);
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
