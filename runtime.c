// runtime.c - Runtime for uBlocks, including CodeChunk and Task management
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "runtime.h"

// Code Chunk Table

#define MAX_CHUNKS 32
CodeChunkRecord chunks[MAX_CHUNKS];

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

void deleteCodeChunk(uint8 chunkIndex) {
	if (chunkIndex >= MAX_CHUNKS) return;
	chunks[chunkIndex].code = nilObj;
	chunks[chunkIndex].chunkType = unusedChunk;
	chunks[chunkIndex].taskStatus = unknown;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
}

// Task List

Task tasks[MAX_TASKS];
int taskCount = 0;

// Task Ops

void initTasks() {
	memset(tasks, 0, sizeof(tasks));
	taskCount = 0;
}

OBJ taskReturnValueOrErrorIP(uint8 chunkIndex) {
	return (chunkIndex < MAX_CHUNKS) ? chunks[chunkIndex].returnValueOrErrorIP : int2obj(0);
}

uint8 taskStatus(uint8 chunkIndex) {
	return (chunkIndex < MAX_CHUNKS) ? chunks[chunkIndex].taskStatus : unknown;
}

int getStatusForAllTasks(uint8 *buf, int bufSize) {
	int end = (bufSize < MAX_CHUNKS) ? bufSize : MAX_CHUNKS;
	for (int i = 0; i < end; i++) buf[i] = chunks[i].taskStatus;
	return MAX_CHUNKS;
}

void startTaskForChunk(uint8 chunkIndex) {
	// Start a task for the given chunk, if there is not one already.

	int i;
	for (i = 0; i < MAX_TASKS; i++) {
		if (unusedTask == tasks[i].status) break;
		if (chunkIndex == tasks[i].codeChunkIndex) return; // already running
	}
	if (i >= MAX_TASKS) panic("No free task entries");
	memset(&tasks[i], 0, sizeof(Task));
	tasks[i].status = running;
	tasks[i].code = chunks[chunkIndex].code;
	tasks[i].sp = 0; // relative to start of stack
	tasks[i].ip = HEADER_WORDS; // relative to start of code
	taskCount++;
}

void stopChunkTask(uint8 chunkIndex) {
	// Stop the task for the given chunk, if any.

	int i;
	for (i = 0; i < MAX_TASKS; i++) {
		if (chunkIndex == tasks[i].codeChunkIndex) break;
	}
	if (i >= MAX_TASKS) return; // no task for chunkIndex
	memset(&tasks[i], 0, sizeof(Task)); // clear task
	chunks[chunkIndex].taskStatus = unknown;
	chunks[chunkIndex].returnValueOrErrorIP = nilObj;
	if (i == (taskCount - 1)) taskCount--;
}

void startAll() {
	// Start tasks for all start and 'when' hat blocks.

	stopAll(); // stop any running tasks
	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 chunkType = chunks[i].chunkType;
		if ((startHat == chunkType) || (whenConditionHat == chunkType)) {
			startTaskForChunk(i);
		}
	}
}

void stopAll() {
	// Stop all tasks.

	taskCount = 0;
	for (int i = 0; i < MAX_CHUNKS; i++) {
		uint8 status = chunks[i].taskStatus;
		if (status >= waiting) {
			chunks[i].taskStatus = unknown;
			chunks[i].returnValueOrErrorIP = nilObj;
		}
	}
	initTasks();
}
