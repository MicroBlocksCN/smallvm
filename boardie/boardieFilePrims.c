/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// filePrims.c - File system primitives.
// John Maloney, April 2020

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"

// Fake declarations for stuff that came from ESP File system
typedef int File;
int myFS;

// Variables

typedef struct {
	char fileName[32];
	int file;
//s	File file;
} FileEntry;

char fullPath[40]; // buffer for full file path

#define FILE_ENTRIES 8
static FileEntry fileEntry[FILE_ENTRIES]; // fileEntry[] records open files

// Helper functions

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
// 		fileEntry[i].fileName[0] = '\0';
// 		fileEntry[i].file.close();
	}
}

void closeAndDeleteFile(char *fileName) {
	// Called from fileTransfer.cpp.

	closeIfOpen(fileName);

	// to avoid a LittleFS error message, must ensure that the file exists before removing it
// 	File tempFile = myFS.open(fileName, "w");
// 	tempFile.close();
// 	myFS.remove(fileName);
}

// Open, Close, Delete

static OBJ primOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = args[0];
	if (!fileName[0]) return falseObj;

	int i = entryFor(fileName);
/*
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
*/
	return falseObj;
}

static OBJ primClose(int argCount, OBJ *args) {
	return falseObj;
}

static OBJ primDelete(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = args[0];
	if (!fileName[0]) return falseObj;

	closeAndDeleteFile(fileName);
	return falseObj;
}

// Reading

static OBJ primEndOfFile(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = args[0];

	int i = entryFor(fileName);
	if (i < 0) return trueObj;

return falseObj; // placeholder
//	return (!fileEntry[i].file.available()) ? trueObj : falseObj;
}

static OBJ primReadLine(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = args[0];

	int i = entryFor(fileName);
	if (i < 0) return newString(0);

/*
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
*/
char buf[4]; // placeholder
int byteCount = 0; // placeholder
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
	char *fileName = args[1];

	int i = entryFor(fileName);
	if (i >= 0) {
		uint8 buf[800];
		if (byteCount > sizeof(buf)) byteCount = sizeof(buf);
		if ((argCount > 2) && isInt(args[2])) {
//			fileEntry[i].file.seek(obj2int(args[2]), SeekSet);
		}
/*
		byteCount = fileEntry[i].file.read(buf, byteCount);
		if (!byteCount && fileEntry[i].file.available()) {
			// workaround for rare read error -- skip to the next block
			int pos = fileEntry[i].file.position();
			reportNum("skipping bad file block at", pos);
			fileEntry[i].file.seek(pos + 256, SeekSet);
			byteCount = fileEntry[i].file.read(buf, byteCount);
		}
*/
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
	char *fileName = args[1];
	if (ByteArrayType != objType(buf)) return fail(needsByteArray);

	int i = entryFor(fileName);
	if (i < 0) return zeroObj; // file not found

int bytesRead = 0; // placeholder
//	int bytesRead = fileEntry[i].file.read((uint8 *) &FIELD(buf, 0), BYTES(buf));
	return int2obj(bytesRead);
}

// Writing

static OBJ primAppendLine(int argCount, OBJ *args) {
	// Append a String to a file followed by a newline.

	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *fileName = args[1];
	OBJ arg = args[0];

	int i = entryFor(fileName);
	if (i >= 0) {
/*
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
		if (oldPos != oldSize) file.seek(oldPos, SeekSet); // reset position for reading
*/
	}
	processMessage();
	return falseObj;
}

static OBJ primAppendBytes(int argCount, OBJ *args) {
	// Append a ByteArray or String to a file. No newline is added.

	if (argCount < 2) return fail(notEnoughArguments);
	OBJ data = args[0];
	char *fileName = args[1];

	int i = entryFor(fileName);
	if (i < 0) return falseObj;

	File f = fileEntry[i].file;
	if (IS_TYPE(data, ByteArrayType)) {
//		f.write((uint8 *) &FIELD(data, 0), BYTES(data));
	} else if (IS_TYPE(data, StringType)) {
		char *s = obj2str(data);
//		f.write((uint8 *) s, strlen(s));
	}
	processMessage();
	return falseObj;
}

// File list

static OBJ primFileSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);
	if (!fileName[0]) return int2obj(0);
	return int2obj(EM_ASM_INT({
		var file = localStorage[UTF8ToString($0)];
		return file ? file.length : -1;
	}, fileName));
}

static OBJ primStartFileList(int argCount, OBJ *args) {
	EM_ASM_({ window.currentFileIndex = 0; });
	return falseObj;
}

static OBJ primNextFileInList(int argCount, OBJ *args) {
	char fileName[100];
	char *s = fileName;
	EM_ASM_({
		var fileNames = Object.keys(window.localStorage);
		if (!window.currentFileIndex) { window.currentFileIndex = 0; }
		if (window.currentFileIndex >= fileNames.length) {
			stringToUTF8("", $0, 100);
		} else {
			stringToUTF8(fileNames[window.currentFileIndex], $0, 100);
			window.currentFileIndex ++;
		}
	}, s);
	return newStringFromBytes(s, strlen(s));
}

// System info

static OBJ primSystemInfo(int argCount, OBJ *args) {
	char result[100];
	sprintf(result, "Using browser localStorage FS");
	return newStringFromBytes(result, strlen(result));
}

// Primitives

static PrimEntry entries[] = {
	{"open", primOpen},
	{"close", primClose},
	{"delete", primDelete},
	{"endOfFile", primEndOfFile},
	{"readLine", primReadLine},
	{"readBytes", primReadBytes},
	{"readInto", primReadInto},
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
