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

static void sendMsg(uint8 *buf, int count) {
#define SHOW_BYTES false
#if SHOW_BYTES
	printf("[");
	for (int i = 0; i < count; i++) {
		printf("%d ", buf[i]);
	}
	printf("]\r\n");
#else
	writeBytes(buf, count);
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
	printBuffer[0] = 0;  // null terminate
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

// Client Interaction

// Note: msgBuffer is used for both incoming messages and their replies

#define MAX_MSG 512
uint8 msgBuffer[MAX_MSG];
int msgByteCount = 0;

static void setMsgHeader(int msgType, int msgID, int chunkIndex, int byteCount) {
	msgBuffer[0] = msgType;
	msgBuffer[1] = msgID;
	msgBuffer[2] = chunkIndex;
	msgBuffer[3] = byteCount & 0xFF; // low byte
	msgBuffer[4] = (byteCount >> 8) & 0xFF; // high byte
}

static void sendOkay(uint8 msgID) {
#if DEBUG
	printf("Okay\r\n");
#else
	setMsgHeader(okayReply, msgID, 0, 0);
	sendMsg(msgBuffer, 5);
#endif
}

static void sendError(uint8 msgID, uint8 errorCode) {
	// Send a protocol error message (e.g. badChunkIndexError).
	// The error code is stored in the third byte of the message,
	// where the chunkIndex often appears.
#if DEBUG
	printf("Error: %d\r\n", errorCode);
#else
	setMsgHeader(errorReply, msgID, errorCode, 0);
	sendMsg(msgBuffer, 5);
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
	setMsgHeader(getTaskStatusReply, msgID, 0, MAX_CHUNKS);
	for (int i = 0; i < MAX_CHUNKS; i++) {
		msgBuffer[5 + i] = chunks[i].taskStatus;
	}
	sendMsg(msgBuffer, (5 + MAX_CHUNKS));
#endif
}

static void sendOutput(uint8 msgID) {
	// Send the last output string. If there is none, do nothing.

	if (!printBufferByteCount) return; // no output to send

#if DEBUG
	if (printBufferByteCount) printf("Output: %s", printBuffer);
#else
	setMsgHeader(getOutputReply, msgID, 0, printBufferByteCount);
	for (int i = 0; i < printBufferByteCount; i++) {
		msgBuffer[5 + i] = printBuffer[i];
	}
	sendMsg(msgBuffer, (5 + printBufferByteCount));
#endif

	// clear the buffer and make runnable any tasks that were waiting to print
	printBufferByteCount = 0;
	printBuffer[0] = 0;  // null terminate
	for (int i = 0; i < MAX_TASKS; i++) {
		if (waiting_print == tasks[i].status) {
			tasks[i].status = running;
		}
	}
}

static void sendReturnValue(uint8 msgID, uint8 chunkIndex) {
	// Send the return value for the task running the given chunk. Assume
	// that the task status is done_Value. If it isn't, send an errorReply.
	// Data is: <type byte><...data...>

	if ((chunkIndex >= MAX_CHUNKS) || (done_Value != chunks[chunkIndex].taskStatus)) {
		sendError(msgID, badChunkIndexError);
		return;
	}
	OBJ returnValue = chunks[chunkIndex].returnValueOrErrorIP;
	if (isInt(returnValue)) { // 32-bit integer, little endian
		int n = obj2int(returnValue);
		setMsgHeader(getReturnValueReply, msgID, chunkIndex, 5);
		msgBuffer[5] = 1; // result value type (0 is integer)
		msgBuffer[6] = (n & 0xFF);
		msgBuffer[7] = ((n >> 8) & 0xFF);
		msgBuffer[8] = ((n >> 16) & 0xFF);
		msgBuffer[9] = ((n >> 24) & 0xFF);
		sendMsg(msgBuffer, 10);
	} else if (IS_CLASS(returnValue, StringClass)) { // string
		char *s = obj2str(returnValue);
		int byteCount = strlen(s);
		setMsgHeader(getReturnValueReply, msgID, chunkIndex, (byteCount + 1));
		msgBuffer[5] = 1; // result value type (1 is string)
		for (int i = 0; i < MAX_CHUNKS; i++) {
			msgBuffer[6 + i] = s[i];
		}
		sendMsg(msgBuffer, (5 + (byteCount + 1)));
	} else { // floats support will be be added later
		sendError(msgID, unspecifiedError);
	}

	// reset chunk entry (triggers highlight removal by IDE)
	chunks[chunkIndex].taskStatus = done;
	chunks[chunkIndex].taskErrorCode = 0;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
}

static void sendTaskErrorInfo(uint8 msgID, uint8 chunkIndex) {
	// Send the error code and IP for the task that was running the given chunk.
	// Assume that the task status is done_Error. If it isn't, send an errorReply.

	if ((chunkIndex >= MAX_CHUNKS) || (done_Error != chunks[chunkIndex].taskStatus)) {
		sendError(msgID, badChunkIndexError);
		return;
	}
	setMsgHeader(getTaskErrorInfoReply, msgID, 0, 5);
	int n = obj2int(chunks[chunkIndex].returnValueOrErrorIP);
	msgBuffer[5] = (n & 0xFF);
	msgBuffer[6] = ((n >> 8) & 0xFF);
	msgBuffer[7] = ((n >> 16) & 0xFF);
	msgBuffer[8] = ((n >> 24) & 0xFF);
	sendMsg(msgBuffer, 9);

	// reset chunk entry (triggers highlight removal by IDE)
	chunks[chunkIndex].taskStatus = done;
	chunks[chunkIndex].taskErrorCode = 0;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
}

void processMessage() {
	// Process a message from the client.

	msgByteCount += readBytes(&msgBuffer[msgByteCount], MAX_MSG - msgByteCount);
	if (msgByteCount < 5) return; // incomplete message header

	int bodyBytes = (msgBuffer[4] << 8) + msgBuffer[3]; // little endian
	if (msgByteCount < (bodyBytes + 5)) return; // incomplete message body

	uint8 msgType = msgBuffer[0];
	uint8 msgID = msgBuffer[1];
	uint8 chunkIndex = msgBuffer[2];

//xxx
// printf("msg %d id %d chunk %d [", msgType, msgID, chunkIndex);
// for (int i = 5; i < msgByteCount; i++) printf("%d ", msgBuffer[i]);
// printf("]\r\n");

	msgByteCount = 0; // clear the message buffer

	switch (msgType) {
	case storeChunkMsg:
		// body is: <chunkType (1 byte)> <instruction data>
		storeCodeChunk(chunkIndex, msgBuffer[5], (bodyBytes - 1), &msgBuffer[6]);
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
}
