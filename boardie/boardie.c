/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardie.c - Boardie - A Simulated MicroBlocks Board for Web Browsers
// John Maloney and Bernat Romagosa, October 2022

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Timing Functions

static int startSecs = 0;

static void initTimers() {
	struct timeval now;
	gettimeofday(&now, NULL);
	startSecs = now.tv_sec;
}

uint32 microsecs() {
	struct timeval now;
	gettimeofday(&now, NULL);

	return (1000000 * (now.tv_sec - startSecs)) + now.tv_usec;
}

uint32 millisecs() {
	struct timeval now;
	gettimeofday(&now, NULL);

	return (1000 * (now.tv_sec - startSecs)) + (now.tv_usec / 1000);
}

// Communication/System Functions

void initMessageService() {
	EM_ASM_({
		window.recvBuffer = [];
		window.addEventListener('message', function (event) {
			window.recvBuffer.push(...event.data);
		}, false);
	}, NULL);
}

int nextByte() {
	return EM_ASM_INT({
		// Returns first byte in the buffer, and removes it from the buffer.
		// Returns undefined if buffer is empty, which will be cast to 0, so it
		// needs to be paired with pendingByteCount to make sure we're not
		// reading zeroes that aren't there.
		return window.recvBuffer.splice(0, 1)[0];
	}, NULL);
}

int canReadByte() {
	return EM_ASM_INT({
		if (!window.recvBuffer) { window.recvBuffer = []; }
		return window.recvBuffer.length > 0;
	}, NULL);
}

int recvBytes(uint8 *buf, int count) {
	int total = 0;
	while (canReadByte() && total <= count) {
		buf[total] = nextByte();
		total++;
	}
	return total;
}

int sendByte(char aByte) {
	EM_ASM_({
		window.parent.postMessage([$0]);
	}, aByte);
	return 1;
}

// System Functions

const char * boardType() {
	return "Boardie (MicroBlocks Virtual Board)";
}

// Stubs for functions not used by Boardie

void addFilePrims() {}
void addNetPrims() {}
void addSensorPrims() {}
void addSerialPrims() {}
void delay(int msecs) {}
void processFileMessage(int msgType, int dataSize, char *data) {}

// Stubs for code file (persistence) not used by Boardie

void initCodeFile(uint8 *flash, int flashByteCount) {}
void writeCodeFile(uint8 *code, int byteCount) { }
void writeCodeFileWord(int word) { }
void clearCodeFile(int ignore) { }

// Stubs for primitives not used by Boardie

OBJ primI2cGet(OBJ *args) { return int2obj(0); }
OBJ primI2cSet(OBJ *args) { return int2obj(0); }
OBJ primSPISend(OBJ *args) { return int2obj(0); }
OBJ primSPIRecv(OBJ *args) { return int2obj(0); }
OBJ primSPIExchange(int argCount, OBJ *args) { return falseObj; }
OBJ primSPISetup(int argCount, OBJ *args) { return falseObj; }

OBJ primMBTemp(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltX(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltY(int argCount, OBJ *args) { return int2obj(0); }
OBJ primMBTiltZ(int argCount, OBJ *args) { return int2obj(0); }

// Main loop

int main(int argc, char *argv[]) {
	printf("Starting Boardie\n");

	initMessageService();
	initTimers();
	memInit();
	primsInit();
	restoreScripts();
	startAll();

	printf("Boardie started, starting interpreter\n");
	emscripten_set_main_loop(interpretStep, 0, true); // callback, fps, loopFlag
}
