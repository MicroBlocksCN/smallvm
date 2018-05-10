/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.cpp - Persistent file operations for NodeMCU (SPIFFS file system)
// Bernat Romagosa and John Maloney

#ifdef ARDUINO_ESP8266_NODEMCU

#include <stdio.h>
#include <FS.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

File codeFile;

extern "C" void initCodeFile(uint8 *flash, int flashByteCount) {
	SPIFFS.begin();
	codeFile = SPIFFS.open("ublockscode", "a+");

	// read code file into simulated Flash:
	long int bytesRead = codeFile.readBytes((char*) flash, flashByteCount);

char s[100];
sprintf(s, "Read %d bytes from code file (file size %d)", bytesRead, codeFile.size());
outputString(s);
}

extern "C" void writeCodeFile(uint8 *code, int byteCount) {
	int bytesWritten = codeFile.write(code, byteCount);
	codeFile.flush();
}

extern "C"  void clearCodeFile() {
	codeFile.close();
	SPIFFS.remove("ublockscode");
	codeFile = SPIFFS.open("ublockscode", "a+");
	uint32 cycleCount = ('S' << 24) | 1; // Header record, version 1
	int bytesWritten = codeFile.write((uint8 *) &cycleCount, 4);
	codeFile.flush();
outputString("Code file cleared");
}

#endif
