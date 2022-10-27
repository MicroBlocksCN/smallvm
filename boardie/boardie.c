/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardie.c - Boardie - A Simulated MicroBlocks Board for Web Browsers
// John Maloney, October 2022

#include <stdio.h>
#include <stdlib.h> // still needed?
#include <sys/time.h>
#include <signal.h>

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

// Communication/System Functions (stubs for now)

int recvBytes(uint8 *buf, int count) { return 0; }
int canReadByte() { return false; }
int sendByte(char aByte) { return 1; }

// System Functions

const char * boardType() {
	return "Boardie (MicroBlocks Virtual Board";
}

// Stubs for functions not used by Boardie

void addFilePrims() {}
void addNetPrims() {}
void addSerialPrims() {}
void addSensorPrims() {}
void delay(int msecs) {}
void processFileMessage(int msgType, int dataSize, char *data) {}

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

// Persistence support

char *codeFileName = "ublockscode";
FILE *codeFile;

void initCodeFile(uint8 *flash, int flashByteCount) {
	codeFile = fopen(codeFileName, "ab+");
	fseek(codeFile, 0 , SEEK_END);
	long fileSize = ftell(codeFile);

	// read code file into simulated Flash:
	fseek(codeFile, 0L, SEEK_SET);
	long bytesRead = fread((char*) flash, 1, flashByteCount, codeFile);
	if (bytesRead != fileSize) {
		outputString("initCodeFile did not read entire file");
	}
}

void writeCodeFile(uint8 *code, int byteCount) {
	fwrite(code, 1, byteCount, codeFile);
	fflush(codeFile);
}

void writeCodeFileWord(int word) {
	fwrite(&word, 1, 4, codeFile);
	fflush(codeFile);
}

void clearCodeFile(int ignore) {
	fclose(codeFile);
	remove(codeFileName);
	codeFile = fopen(codeFileName, "ab+");
	uint32 cycleCount = ('S' << 24) | 1; // Header record, version 1
	fwrite((uint8 *) &cycleCount, 1, 4, codeFile);
}

// Messaging

void initMessageService() {
	EM_ASM_({
		window.messages = [];
		window.addEventListener('message', function (event) {
			console.log('received', event.data);
			window.messages.push(event.data);
		}, false);
	}, NULL);
}

int pendingMessages() {
	printf("checking for pending messages");
	return EM_ASM_INT({ return window.messages.length; }, NULL);
};

// Linux Main
void interpretStep();

int main(int argc, char *argv[]) {
	printf("Starting Boardie\n");

	initMessageService();
	initTimers();
	memInit();
	primsInit();
	restoreScripts();
	startAll();

	printf("Boardie started, starting interpreter :)\n");

	emscripten_set_main_loop(interpretStep, 10, true); // callback, fps, loopFlag

	printf("Main loop set up\n");

	return 0;
}
