// runtime.c - Runtime for uBlocks, including CodeChunk storage and Task management
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
	for (i = 0; i < MAX_TASKS; i++) {
		if (unusedTask == tasks[i].status) break;
		if (chunkIndex == tasks[i].chunkIndex) return; // already running
	}
	if (i >= MAX_TASKS) panic("No free task entries");
	memset(&tasks[i], 0, sizeof(Task));
	tasks[i].status = running;
	tasks[i].code = chunks[chunkIndex].code;
	tasks[i].sp = 0; // relative to start of stack
	tasks[i].ip = HEADER_WORDS; // relative to start of code
	taskCount++;
}

static void stopTaskForChunk(uint8 chunkIndex) {
	// Stop the task for the given chunk, if any.

	int i;
	for (i = 0; i < MAX_TASKS; i++) {
		if (chunkIndex == tasks[i].chunkIndex) break;
	}
	if (i >= MAX_TASKS) return; // no task for chunkIndex
	memset(&tasks[i], 0, sizeof(Task)); // clear task
	chunks[chunkIndex].taskStatus = unknown;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
	if (i == (taskCount - 1)) taskCount--;
}

static void stopAll() {
	// Stop all tasks.

	taskCount = 0;
	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 status = chunks[i].taskStatus;
		if (status >= waiting_micros) {
			chunks[i].taskStatus = unknown;
			chunks[i].returnValueOrErrorIP = nilObj;
		}
	}
	initTasks();
}

static void startAll() {
	// Start tasks for all start and 'when' hat blocks.

	stopAll(); // stop any running tasks
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

static void writeMsgHeader(int msgType, int id, int byteCount) {
	msgBuffer[0] = msgType;
	msgBuffer[1] = id;
	msgBuffer[2] = byteCount & 0xFF;
	msgBuffer[3] = (byteCount >> 8) & 0xFF;
}

static void sendOkay() {
	writeMsgHeader(okayReply, 0, 0);
	writeBytes(msgBuffer, 4);
}

static void sendError() {
	writeMsgHeader(errorReply, 0, 0);
	writeBytes(msgBuffer, 4);
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

	writeMsgHeader(getOutputReply, 0, printBufferByteCount);
	for (int i = 0; i < printBufferByteCount; i++) {
		msgBuffer[4 + i] = printBuffer[i];
	}
	writeBytes(msgBuffer, (4 + printBufferByteCount));
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

void processMessage() {
	// Process a message from the client.

	msgByteCount += readBytes(&msgBuffer[msgByteCount], MAX_MSG - msgByteCount);
	if (msgByteCount < 4) return; // incomplete message header

	int bodyByteCount = (msgBuffer[2] << 8) + msgBuffer[3];
	if (msgByteCount < (bodyByteCount + 4)) return; // message body incomplete

	uint8 msgType = msgBuffer[0];
	uint8 chunkID = msgBuffer[1];
	msgByteCount = 0; // clear the message buffer

	switch (msgType) {
	case storeChunkMsg:
		storeCodeChunk(chunkID, 0, bodyByteCount, &msgBuffer[4]);
		break;
	case deleteChunkMsg:
		deleteCodeChunk(chunkID);
		break;
	case startAllMsg:
		startAll();
		break;
	case stopAllMsg:
		stopAll();
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
	}
	sendOkay();
	msgByteCount = 0; // clear the message buffer
}
