/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// filePrims.c - File system primitives for ESP boards.
// John Maloney, April 2020

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
// File system operations for Espressif boards (SPIFFS file system)

#include <FS.h>
#ifdef ARDUINO_ARCH_ESP32
	#include <SPIFFS.h>
	#include <esp_spiffs.h>
#endif

// Variables

static int spiffsStarted = false;
static char fullPath[32]; // used to prefix "/" to file names

typedef struct {
	char fileName[32];
	File file;
} FileEntry;

#define FILE_ENTRIES 8
static FileEntry fileEntry[FILE_ENTRIES]; // records open files

// Helper functions

static void initSPIFFS() {
	if (spiffsStarted) return;

	#ifdef ESP8266
		SPIFFS.begin();
	#else
		SPIFFS.begin(true);
	#endif
	spiffsStarted = true;
}

static char *extractFilename(OBJ obj) {
	fullPath[0] = '\0';
	if (IS_TYPE(obj, StringType)) {
		char *fileName = obj2str(obj);
		if (strcmp(fileName, "ublockscode") == 0) return fullPath;
		if ('/' == fileName[0]) return fileName; // fileName already had a leading "/"
		snprintf(fullPath, 31, "/%s", fileName);
	} else {
		fail(needsStringError);
	}
	return fullPath;
}

static int entryFor(char *fileName) {
	// Return the index of a file entry for the file with the given path.
	// Return -1 if fileName doesn't match any entry.

	if (!fileName[0]) return -1; // empty string is not a valid file name
	for (int i = 0; i < FILE_ENTRIES; i++) {
		if (0 == strcmp(fileName, fileEntry[i].fileName)) return i;
	}
	return -1;
}

static int freeEntry() {
	// Return the index of an unused file entry or -1 if there isn't one.

	for (int i = 0; i < FILE_ENTRIES; i++) {
		if (!fileEntry[i].file) return i;
	}
	return -1; // no free entry
}

// Open, Close, Delete

static OBJ primOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0]) return falseObj;

	initSPIFFS();
	int i = entryFor(fileName);
	if (i >= 0) { // found an existing entry; close and reopen
		fileEntry[i].file.close();
		fileEntry[i].file = SPIFFS.open(fileName, "a+");
		fileEntry[i].file.seek(0, SeekSet); // read from start of file
		return falseObj;
	}

	i = freeEntry();
	if (i >= 0) { // initialize new entry
		fileEntry[i].fileName[0] = '\0';
		strncat(fileEntry[i].fileName, fileName, 31);
		fileEntry[i].file = SPIFFS.open(fileName, "a+");
		fileEntry[i].file.seek(0, SeekSet); // read from start of file
	}
	return falseObj;
}

static OBJ primClose(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);

	initSPIFFS();
	int i = entryFor(fileName);
	if (i >= 0) {
		fileEntry[i].fileName[0] = '\0';
		fileEntry[i].file.close();
		return falseObj;
	}
	return falseObj;
}

static OBJ primDelete(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0]) return falseObj;

	initSPIFFS();
	if (SPIFFS.exists(fileName)) SPIFFS.remove(fileName);
	int i = entryFor(fileName);
	if (i >= 0) {
		fileEntry[i].fileName[0] = '\0';
		fileEntry[i].file.close();
	}
	return falseObj;
}

// Reading

static OBJ primEndOfFile(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);

	int i = entryFor(fileName);
	if (i < 0) return trueObj;

	return (!fileEntry[i].file.available()) ? trueObj : falseObj;
}

static OBJ primReadLine(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);

	int i = entryFor(fileName);
	if (i < 0) return newString(0);

	File file = fileEntry[i].file;
	char buf[800];
	uint32 byteCount = 0;
	while ((byteCount < sizeof(buf)) && file.available()) {
		int ch = file.read();
		if ((10 == ch) || (13 == ch)) {
			if ((10 == ch) && (13 == file.peek())) file.read(); // lf-cr ending
			if ((13 == ch) && (10 == file.peek())) file.read(); // cr-lf ending
			break;
		}
		buf[byteCount++] = ch;
	}
	OBJ result = newString(byteCount);
	if (result) {
		memcpy(obj2str(result), buf, byteCount);
	}
	return result;
}

static OBJ primReadBytes(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	uint32 byteCount = obj2int(args[0]);
	char *fileName = extractFilename(args[1]);

	int i = entryFor(fileName);
	if (i >= 0) {
		uint8 buf[800];
		if (byteCount > sizeof(buf)) byteCount = sizeof(buf);
		if ((argCount > 2) && isInt(args[2])) {
			fileEntry[i].file.seek(obj2int(args[2]), SeekSet);
		}
		byteCount = fileEntry[i].file.read(buf, byteCount);
		if (!byteCount && fileEntry[i].file.available()) {
			// workaround for rare read error -- skip to the next block
			int pos = fileEntry[i].file.position();
			reportNum("skipping bad file block at", pos);
			fileEntry[i].file.seek(pos + 256, SeekSet);
			byteCount = fileEntry[i].file.read(buf, byteCount);
		}
		int wordCount = (byteCount + 3) / 4;
		OBJ result = newObj(ByteArrayType, wordCount, falseObj);
		if (result) {
			setByteCountAdjust(result, byteCount);
			memcpy(&FIELD(result, 0), buf, byteCount);
			return result;
		}
	}
	return newObj(ByteArrayType, 0, falseObj); // empty byte array
}

// Writing

static OBJ primAppendLine(int argCount, OBJ *args) {
	// Append a String to a file followed by a newline.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	char *fileName = extractFilename(args[1]);

	int i = entryFor(fileName);
	if (i >= 0) {
		File file = fileEntry[i].file;
		int oldPos = file.position();
		int oldSize = file.size();
		if (oldPos != oldSize) file.seek(0, SeekEnd); // seek to current end
		fileEntry[i].file.print(obj2str(args[0]));
		fileEntry[i].file.write(10); // newline
		if (oldPos != oldSize) file.seek(oldPos, SeekSet); // reset position for reading
	}
	return falseObj;
}

static OBJ primAppendBytes(int argCount, OBJ *args) {
	// Append a ByteArray or String to a file. No newline is added.

	if (argCount < 2) return fail(notEnoughArguments);
	OBJ data = args[0];
	char *fileName = extractFilename(args[1]);

	int i = entryFor(fileName);
	if (i < 0) return falseObj;

	File f = fileEntry[i].file;
	if (IS_TYPE(data, ByteArrayType)) {
		f.write((uint8 *) &FIELD(data, 0), BYTES(data));
	} else if (IS_TYPE(data, StringType)) {
		char *s = obj2str(data);
		f.write((uint8 *) s, strlen(s));
	}
	return falseObj;
}

// File list

// Root directory used for listing files
#if defined(ESP8266)
	Dir rootDir;
#elif defined(ESP32)
	File rootDir;
#endif

static OBJ primFileSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0]) return int2obj(0);

	File file = SPIFFS.open(fileName, "r");
	if (!file) return int2obj(0);
	file.seek(0, SeekEnd); // seek to end
	int size = file.position();
	file.close();
	return int2obj(size);
}

static OBJ primStartFileList(int argCount, OBJ *args) {
	initSPIFFS();
	#if defined(ESP8266)
		rootDir = SPIFFS.openDir("/");
	#elif defined(ESP32)
		rootDir = SPIFFS.open("/");
	#endif
	return falseObj;
}

static OBJ primNextFileInList(int argCount, OBJ *args) {
	char fileName[32];
	fileName[0] = '\0';

	#if defined(ESP8266)
 		if (rootDir.next()) {
			if ((strcmp("/ublockscode", rootDir.fileName().c_str()) != 0) || rootDir.next()) {
 				strncat(fileName, rootDir.fileName().c_str(), 31);
 			}
		}
	#elif defined(ESP32)
		if (rootDir) {
			File file = rootDir.openNextFile();
			if (file && (strcmp("/ublockscode", file.name()) == 0)) file = rootDir.openNextFile();
			if (file) strncat(fileName, file.name(), 31);
		}
	#endif
	char *s = fileName;
	if ('/' == s[0]) s++; // skip leading slash
	return newStringFromBytes(s, strlen(s));
}

// System info

static OBJ primSystemInfo(int argCount, OBJ *args) {
	initSPIFFS();
	size_t totalBytes = 0;
	size_t usedBytes = 0;

	#if defined(ESP8266)
		FSInfo info;
		SPIFFS.info(info);
		totalBytes = info.totalBytes;
		usedBytes = info.usedBytes;
	#elif defined(ESP32)
		esp_spiffs_info(NULL, &totalBytes, &usedBytes);
	#endif

	char result[100];
	sprintf(result, "%u bytes used of %u", usedBytes, totalBytes);
	return newStringFromBytes(result, strlen(result));
}

#else

static OBJ primOpen(int argCount, OBJ *args) { return falseObj; }
static OBJ primClose(int argCount, OBJ *args) { return falseObj; }
static OBJ primDelete(int argCount, OBJ *args) { return falseObj; }
static OBJ primEndOfFile(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadBytes(int argCount, OBJ *args) { return falseObj; }
static OBJ primAppendLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primAppendBytes(int argCount, OBJ *args) { return falseObj; }
static OBJ primFileSize(int argCount, OBJ *args) { return falseObj; };
static OBJ primStartFileList(int argCount, OBJ *args) { return falseObj; }
static OBJ primNextFileInList(int argCount, OBJ *args) { return falseObj; }
static OBJ primSystemInfo(int argCount, OBJ *args) { return falseObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	{"open", primOpen},
	{"close", primClose},
	{"delete", primDelete},
	{"endOfFile", primEndOfFile},
	{"readLine", primReadLine},
	{"readBytes", primReadBytes},
	{"appendLine", primAppendLine},
	{"appendBytes", primAppendBytes},
	{"fileSize", primFileSize},
	{"startList", primStartFileList},
	{"nextInList", primNextFileInList},
	{"systemInfo", primSystemInfo},
};

void addFilePrims() {
	addPrimitiveSet("file", sizeof(entries) / sizeof(PrimEntry), entries);
}
