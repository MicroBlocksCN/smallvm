/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// filePrims.c - File system primitives.
// John Maloney, April 2020

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#if defined(ESP8266) || defined(ESP32) || defined(RP2040_PHILHOWER)

// This operations assume that the file system was mounted by restoreScripts() at startup.

#include "fileSys.h"

// Variables

static char fullPath[32]; // used to prefix "/" to file names

typedef struct {
	char fileName[32];
	File file;
} FileEntry;

#define FILE_ENTRIES 8
static FileEntry fileEntry[FILE_ENTRIES]; // fileEntry[] records open files

// Helper functions

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

void closeIfOpen(char *fileName) {
	// Called from fileTransfer.cpp.

	int i = entryFor(fileName);
	if (i >= 0) {
		fileEntry[i].fileName[0] = '\0';
		fileEntry[i].file.close();
	}
}

void closeAndDeleteFile(char *fileName) {
	// Called from fileTransfer.cpp.

	closeIfOpen(fileName);

	// to avoid a LittleFS error message, must ensure that the file exists before removing it
	File tempFile = myFS.open(fileName, "w");
	tempFile.close();
	myFS.remove(fileName);
}

// Open, Close, Delete

static OBJ primOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0]) return falseObj;

	int i = entryFor(fileName);
	if (i >= 0) { // found an existing entry; close and reopen
		fileEntry[i].file.close();
		fileEntry[i].file = myFS.open(fileName, "a+");
		fileEntry[i].file.seek(0, SeekSet); // read from start of file
		return falseObj;
	}

	i = freeEntry();
	if (i >= 0) { // initialize new entry
		fileEntry[i].fileName[0] = '\0';
		strncat(fileEntry[i].fileName, fileName, 31);
		fileEntry[i].file = myFS.open(fileName, "a+");
		fileEntry[i].file.seek(0, SeekSet); // read from start of file
	}
	return falseObj;
}

static OBJ primClose(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);

	closeIfOpen(fileName);
	return falseObj;
}

static OBJ primDelete(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0]) return falseObj;

	closeAndDeleteFile(fileName);
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

static OBJ primReadInto(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	OBJ buf = args[0];
	char *fileName = extractFilename(args[1]);
	if (ByteArrayType != objType(buf)) return fail(needsByteArray);

	int i = entryFor(fileName);
	if (i < 0) return zeroObj; // file not found

	int bytesRead = fileEntry[i].file.read((uint8 *) &FIELD(buf, 0), BYTES(buf));
	return int2obj(bytesRead);
}

// Read positioning

static OBJ primReadPosition(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	char *fileName = extractFilename(args[0]);

	int result = 0;
	int i = entryFor(fileName);
	if (i >= 0) {
		result = fileEntry[i].file.position();
	}
	return int2obj(result);
}

static OBJ primSetReadPosition(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *fileName = extractFilename(args[1]);
	int newPosition = evalInt(args[0]);
	if (newPosition < 0) newPosition = 0;

	int i = entryFor(fileName);
	if (i >= 0) {
		int fileSize = fileEntry[i].file.size();
		if (newPosition > fileSize) newPosition = fileSize;
		fileEntry[i].file.seek(newPosition, SeekSet);
	}
	return falseObj;
}

// Writing

static OBJ primAppendLine(int argCount, OBJ *args) {
	// Append a String to a file followed by a newline.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *fileName = extractFilename(args[1]);
	OBJ arg = args[0];

	int i = entryFor(fileName);
	if (i >= 0) {
		File file = fileEntry[i].file;
		int oldPos = file.position();
		int oldSize = file.size();
		if (oldPos != oldSize) file.seek(0, SeekEnd); // seek to current end
		if (IS_TYPE(arg, StringType)) {
			fileEntry[i].file.print(obj2str(arg));
		} else if (isInt(arg)) {
			fileEntry[i].file.print(obj2int(arg));
		} else if (isBoolean(arg)) {
			fileEntry[i].file.print((trueObj == arg) ? "true" : "false");
		} else if (IS_TYPE(arg, ListType)) {
			// print list items separated by spaces
			int count = obj2int(FIELD(arg, 0));
			for (int j = 1; j <= count; j++) {
				OBJ item = FIELD(arg, j);
				if (IS_TYPE(item, StringType)) {
					fileEntry[i].file.print(obj2str(item));
				} else if (isInt(item)) {
					fileEntry[i].file.print(obj2int(item));
				} else if (isBoolean(item)) {
					fileEntry[i].file.print((trueObj == item) ? "true" : "false");
				}
				if (j < count) fileEntry[i].file.write(32); // space
			}
		}
		fileEntry[i].file.write(10); // newline
		fileEntry[i].file.flush();
		if (oldPos != oldSize) file.seek(oldPos, SeekSet); // reset position for reading
	}
	processMessage();
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
	f.flush();
	processMessage();
	return falseObj;
}

// File list

// Root directory used for listing files
#if defined(ESP32)
	File rootDir;
#else
	Dir rootDir;
#endif

static OBJ primFileSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0]) return int2obj(-1);

	File file = myFS.open(fileName, "r");
	if (!file) return int2obj(-1);
	int size = file.size();
	file.close();
	return int2obj(size);
}

static OBJ primStartFileList(int argCount, OBJ *args) {
	#if defined(ESP32)
		rootDir = myFS.open("/");
	#else
		rootDir = myFS.openDir("/");
	#endif
	return falseObj;
}

static void nextFileName(char *fileName) {
	// Copy the next file name into the argument. Set argument to empty string when done.
	// Argument must have room for at least 32 bytes.

	fileName[0] = '\0'; // clear string
	#if defined(ESP32)
		if (rootDir) {
			File file = rootDir.openNextFile();
			if (file) strncat(fileName, file.name(), 31);
		}
	#else
 		if (rootDir.next()) strncat(fileName, rootDir.fileName().c_str(), 31);
	#endif
}

static OBJ primNextFileInList(int argCount, OBJ *args) {
	char fileName[100];
	nextFileName(fileName);
	while ((strcmp(fileName, "/") == 0) || strstr(fileName, "ublockscode")) {
		nextFileName(fileName); // skip root directory and code file
	}
	char *s = fileName;
	if ('/' == s[0]) s++; // skip leading slash
	return newStringFromBytes(s, strlen(s));
}

// System info

static OBJ primSystemInfo(int argCount, OBJ *args) {
	size_t totalBytes = 0;
	size_t usedBytes = 0;

	#if defined(ESP32)
		totalBytes = myFS.totalBytes();
		usedBytes = myFS.usedBytes();
	#else
		FSInfo info;
		myFS.info(info);
		totalBytes = info.totalBytes;
		usedBytes = info.usedBytes;
	#endif

	char result[100];
	sprintf(result, "%u bytes used of %u", usedBytes, totalBytes);
	return newStringFromBytes(result, strlen(result));
}

#else

static OBJ primOpen(int argCount, OBJ *args) { return falseObj; }
static OBJ primClose(int argCount, OBJ *args) { return falseObj; }
static OBJ primDelete(int argCount, OBJ *args) { return falseObj; }
static OBJ primEndOfFile(int argCount, OBJ *args) { return trueObj; }
static OBJ primReadLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadBytes(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadInto(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadPosition(int argCount, OBJ *args) { return zeroObj; }
static OBJ primSetReadPosition(int argCount, OBJ *args) { return falseObj; }
static OBJ primAppendLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primAppendBytes(int argCount, OBJ *args) { return falseObj; }
static OBJ primFileSize(int argCount, OBJ *args) { return zeroObj; };
static OBJ primStartFileList(int argCount, OBJ *args) { return falseObj; }
static OBJ primNextFileInList(int argCount, OBJ *args) { return newString(0); }
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
	{"readInto", primReadInto},
	{"readPosition", primReadPosition},
	{"setReadPosition", primSetReadPosition},
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
