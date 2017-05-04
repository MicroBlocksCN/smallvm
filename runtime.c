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

static void initChunks() {
	memset(chunks, 0, sizeof(chunks));
}

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

static void writeMsgHeader(int msgType, int id, int byteCount) {
	msgBuffer[0] = msgType;
	msgBuffer[1] = id;
	msgBuffer[2] = byteCount & 0xFF;
	msgBuffer[3] = (byteCount >> 8) & 0xFF;
}

static void sendOkay() {
return; // xxx
	writeMsgHeader(okayReply, 0, 0);
	writeBytes(msgBuffer, 4);
}

static void sendError() {
printf("Error!\r\n"); // xxx
return;
	writeMsgHeader(errorReply, 0, 0);
	writeBytes(msgBuffer, 4);
}

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

static void sendTaskStatus() {
	// Send a task status message containing a task status byte for each chunk.
	// Chunks that have never been run will have a status of 'unknown'.

	writeMsgHeader(getTaskStatusReply, 0, MAX_CHUNKS);
	for (int i = 0; i < MAX_CHUNKS; i++) {
		msgBuffer[4 + i] = chunks[i].taskStatus;
	}
	writeBytes(msgBuffer, (4 + MAX_CHUNKS));
}

static void sendOutput() {
	// Send the last output string. If there is none, send a zero-length string.

	if (printBufferByteCount == 0) return; // no output

// xxx for testing
// 	writeMsgHeader(getOutputReply, 0, printBufferByteCount);
// 	for (int i = 0; i < printBufferByteCount; i++) {
// 		msgBuffer[4 + i] = printBuffer[i];
// 	}
// 	writeBytes(msgBuffer, (4 + printBufferByteCount));
printf("%s", printBuffer);

	printBufferByteCount = 0;

	// make runnable any tasks that were waiting to print
	for (int i = 0; i < MAX_TASKS; i++) {
		if (waiting_print == tasks[i].status) {
			tasks[i].status = running;
		}
	}
}

static void sendReturnValue(uint8 chunkID) {
	// Send the return value for the task running the given chunk. Assume
	// that the task status is done_Value. If it isn't, send an errorReply.

	if ((chunkID >= MAX_CHUNKS) || (done_Value != chunks[chunkID].taskStatus)) {
		sendError();
		return;
	}
	OBJ returnValue = chunks[chunkID].returnValueOrErrorIP;
	if (isInt(returnValue)) { // 32-bit integer, little endian
		int n = obj2int(returnValue);
		writeMsgHeader(getOutputReply, 0, 5); // id is type (0 is integer)
		msgBuffer[4] = (n & 0xFF);
		msgBuffer[5] = ((n >> 8) & 0xFF);
		msgBuffer[6] = ((n >> 16) & 0xFF);
		msgBuffer[7] = ((n >> 24) & 0xFF);
	} else if (IS_CLASS(returnValue, StringClass)) { // string
		char *s = obj2str(returnValue);
		int byteCount = strlen(s);
		writeMsgHeader(getOutputReply, 1, byteCount); // id is type (1 is string)
		for (int i = 0; i < MAX_CHUNKS; i++) {
			msgBuffer[4 + i] = s[i];
		}
	} else { // floats support will be be added later
		sendError();
		return;
	}
	writeBytes(msgBuffer, (4 + MAX_CHUNKS));
}

static void sendErrorIP(uint8 chunkID) {
	// Send the error IP for task that was running the given chunk. Assume
	// that the task status is done_Error. If it isn't, send an errorReply.

	if ((chunkID >= MAX_CHUNKS) || (done_Error != chunks[chunkID].taskStatus)) {
		sendError();
		return;
	}
	writeMsgHeader(getErrorIPReply, 0, 4);
	int n = obj2int(chunks[chunkID].returnValueOrErrorIP);
	writeMsgHeader(getErrorIPReply, 0, 5); // id is type (0 is integer)
	msgBuffer[4] = (n & 0xFF);
	msgBuffer[5] = ((n >> 8) & 0xFF);
	msgBuffer[6] = ((n >> 16) & 0xFF);
	msgBuffer[7] = ((n >> 24) & 0xFF);
	writeBytes(msgBuffer, (4 + MAX_CHUNKS));
}

void showChunks() {
	updateChunkTaskStatus();
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
			if (chunk->errorMsg) printf("  errorMsg: %s\r\n", chunk->errorMsg);
		}
	}
	if (0 == usedChunkCount) printf("No chunks\r\n");

}

void showTasks() {
	printf("%d Tasks:\r\n", taskCount);
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

void processMessage() {
	// Process a message from the client.

	msgByteCount += readBytes(&msgBuffer[msgByteCount], MAX_MSG - msgByteCount);
	if (msgByteCount < 4) return; // incomplete message header

	int bodyBytes = (msgBuffer[3] << 8) + msgBuffer[2]; // little endian
	if (msgByteCount < (bodyBytes + 4)) return; // message body incomplete

	uint8 msgType = msgBuffer[0];
	uint8 chunkID = msgBuffer[1];
	msgByteCount = 0; // clear the message buffer

	switch (msgType) {
	case storeChunkMsg:
		// body is: <chunkType (1 byte)> <instruction data>
		storeCodeChunk(chunkID, msgBuffer[4], (bodyBytes - 1), &msgBuffer[5]);
		break;
	case deleteChunkMsg:
		deleteCodeChunk(chunkID);
		break;
	case startAllMsg:
		startAll();
		break;
	case stopAllMsg:
		stopAllTasks();
		break;
	case startChunkMsg:
		startTaskForChunk(chunkID);
		break;
	case stopChunkMsg:
		stopTaskForChunk(chunkID);
		break;
	case getTaskStatusMsg:
		sendTaskStatus();
		return;
	case getOutputMsg:
		sendOutput();
		return;
	case getReturnValueMsg:
		sendReturnValue(chunkID);
		return;
	case getErrorIPMsg:
		sendErrorIP(chunkID);
		return;

	// The following are for debugging
	case showChunksMsg:
		showChunks();
		return;
	case showTasksMsg:
		showTasks();
		return;
	}
	sendOkay();
	msgByteCount = 0; // clear the message buffer
}
