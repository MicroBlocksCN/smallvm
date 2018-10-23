/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.cpp - Persistent file/non-volatile storage operations

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "persist.h"

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
	// Persistent file operations for NodeMCU (SPIFFS file system)

#include <FS.h>
#ifdef ARDUINO_ARCH_ESP32
  #include <SPIFFS.h>
#endif

#define FILE_NAME "/ublockscode"

File codeFile;

static void closeAndOpenCodeFile() {
	if (codeFile) codeFile.close();
	codeFile = SPIFFS.open(FILE_NAME, "a");
}

extern "C" void initCodeFile(uint8 *flash, int flashByteCount) {
	SPIFFS.begin();
	codeFile = SPIFFS.open(FILE_NAME, "r");
	// read code file into simulated Flash:
	if (codeFile) codeFile.readBytes((char*) flash, flashByteCount);
	closeAndOpenCodeFile();
}

extern "C" void writeCodeFile(uint8 *code, int byteCount) {
	if (codeFile) codeFile.write(code, byteCount);
	closeAndOpenCodeFile();
}

extern "C" void writeCodeFileWord(int word) {
	if (codeFile) codeFile.write((uint8 *) &word, 4);
}

extern "C" void clearCodeFile() {
	if (codeFile) codeFile.close();
	SPIFFS.remove(FILE_NAME);
	codeFile = SPIFFS.open(FILE_NAME, "a");
	int cycleCount = ('S' << 24) | 1; // Header record, version 1
	writeCodeFileWord(cycleCount);
	closeAndOpenCodeFile();
}

#endif
