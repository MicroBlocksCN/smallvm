/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.cpp - Persistent file/non-volatile storage operations

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "persist.h"

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(RP2040_PHILHOWER)

#include "fileSys.h"

#define FILE_NAME "/ublockscode"

static File codeFile;

static void closeAndOpenCodeFile() {
	if (codeFile) codeFile.close();
	codeFile = myFS.open(FILE_NAME, "a+");
	codeFile.seek(0, SeekEnd);
}

extern "C" void initFileSystem() {
	// Initialize the file system.

	#if defined(ARDUINO_ARCH_ESP32)
		myFS.begin(true);
	#else
		myFS.begin();
	#endif
}

extern "C" int initCodeFile(uint8 *flash, int flashByteCount) {
	// Called at startup on boards that store code in the file system.
	// Initialize the file system, read the code file, and return

	initFileSystem();
	codeFile = myFS.open(FILE_NAME, "r");
	if (!codeFile) clearCodeFile(0);
	// read code file into simulated Flash:
	int bytesRead = codeFile.readBytes((char*) flash, flashByteCount);
	closeAndOpenCodeFile();
	return bytesRead;
}

extern "C" void writeCodeFile(uint8 *code, int byteCount) {
	if (codeFile) codeFile.write(code, byteCount);
	closeAndOpenCodeFile();
}

extern "C" void writeCodeFileWord(int word) {
	if (codeFile) codeFile.write((uint8 *) &word, 4);
}

extern "C" void clearCodeFile(int cycleCount) {
	if (codeFile) codeFile.close();
	codeFile = myFS.open(FILE_NAME, "w"); // truncate file to zero length
	int headerWord = ('S' << 24) | cycleCount; // Header record, version 1
	writeCodeFileWord(headerWord);
	closeAndOpenCodeFile();
}

// File operations for storing system state

extern "C" void createFile(const char *fileName) {
	File file = myFS.open(fileName, "w");
	file.close();
}

extern "C" void deleteFile(const char *fileName) {
	if (fileExists(fileName)) {
		myFS.remove(fileName);
	}
}

extern "C" int fileExists(const char *fileName) {
	File file = myFS.open(fileName, "r");
	if (!file) return false;
	file.close();
	return true;
}

#endif
