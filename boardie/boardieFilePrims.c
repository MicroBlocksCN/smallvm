/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieFilePrims.c - File system primitives.
// John Maloney and Bernat Romagosa, November 2022

// Files are stored as JavaScript strings in localStorage. Boardie can also
// read files from the &files URL parameter. Such files are temporarily
// stored in sessionStorage to avoid overwriting user files in localStorage.
// Temporary files in sessionStorage have preference over user files with
// matching names in localStorage.

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"

// Helper functions

void closeAndDeleteFile(char *fileName) {
	// Also called from fileTransfer.cpp.
	EM_ASM_({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return;
		var origin = window.useSessionStorage ? 'session' : 'local';
		delete(window[origin + 'Storage'][fileName]);
		delete(window.fileCharPositions[fileName]);
	}, fileName);
}

int openFile(char *fileName, int createIfNotExists) {
	return EM_ASM_INT({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return 0;
		var origin = window.useSessionStorage ? 'session' : 'local';
		if (window[origin + 'Storage'][fileName] === undefined) {
			if ($1) {
				window[origin + 'Storage'][fileName] = "";
			} else {
				return 0;
			}
		}

		// some file ops take a _long_ time to run so we yield after max_cycles
		window.max_cycles = 512;

		if (!window.fileCharPositions) { window.fileCharPositions = {}; }
		if (!window.fileCharPositions[fileName] || $1) {
			window.fileCharPositions[fileName] = 0;
		}
		return 1;
	}, fileName, createIfNotExists);
}

// Open, Close, Delete

static OBJ primOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);
	if (!fileName[0]) return falseObj;

	openFile(fileName, 1);
	return falseObj;
}

static OBJ primClose(int argCount, OBJ *args) {
	return falseObj;
}

static OBJ primDelete(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);
	if (!fileName[0] || !openFile(fileName, 0)) return falseObj;

	closeAndDeleteFile(fileName);
	return falseObj;
}

// Reading

static OBJ primEndOfFile(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);

	if (!openFile(fileName, 0)) return falseObj;

	return EM_ASM_INT({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return 0;
		var origin = window.useSessionStorage ? 'session' : 'local';
		return window.fileCharPositions[fileName] >=
			window[origin + 'Storage'][fileName].length;
	}, fileName) ? trueObj : falseObj;
}

static OBJ primReadLine(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);
	if (!fileName[0] || !openFile(fileName, 0)) return newString(0);
	char line[1024];
	char *s = line;

	EM_ASM_({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return;
		var origin = window.useSessionStorage ? 'session' : 'local';
		var file = window[origin + 'Storage'][fileName];
		if (window.fileCharPositions[fileName] < file.length) {
			var endIndex =
				file.indexOf('\n', window.fileCharPositions[fileName]);
			if (endIndex === -1) { endIndex = file.length }
			var line = file.substring(
				window.fileCharPositions[fileName],
				endIndex
			);
			stringToUTF8(line, $1, 1024);
			window.fileCharPositions[fileName] = endIndex + 1;
		} else {
			stringToUTF8("", $1, 1024);
		}
	}, fileName, s);

	return newStringFromBytes(s, strlen(s));
}

static OBJ primReadBytes(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	uint32 byteCount = obj2int(args[0]);
	char *fileName = obj2str(args[1]);
	if (!fileName[0] || !openFile(fileName, 0)) return newString(0);
	uint8 buf[1024];
	if (byteCount > sizeof(buf)) byteCount = sizeof(buf);
	int startIndex = ((argCount > 2) && isInt(args[2])) ? obj2int(args[2]) : 0;

	int readCount = EM_ASM_INT({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return 0;
		var origin = window.useSessionStorage ? 'session' : 'local';
		var file = window[origin + 'Storage'][fileName];
		var startIndex = $3 > 0 ? $3 : window.fileCharPositions[fileName];
		var endIndex = (startIndex + $1 > file.length) ?
			file.length :
			startIndex + $1;

		for (var i = startIndex; i < endIndex; i++) {
			HEAP8[$2] = file.charCodeAt(i);
			$2++;
			// yield from time to time when dealing with big files
			if ((i - startIndex) % window.max_cycles == window.max_cycles - 1) {
				_taskSleep(1);
			}
		}

		window.fileCharPositions[fileName] = endIndex;

		return endIndex - startIndex;
	}, fileName, byteCount, buf, startIndex);

	int wordCount = (readCount + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (result) {
		setByteCountAdjust(result, readCount);
		memcpy(&FIELD(result, 0), buf, readCount);
		return result;
	}
	return newObj(ByteArrayType, 0, falseObj); // empty byte array
}

static OBJ primReadInto(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	OBJ buf = args[0];
	char *fileName = obj2str(args[1]);
	if (ByteArrayType != objType(buf)) return fail(needsByteArray);
	if (!fileName[0] || !openFile(fileName, 0)) { return int2obj(0); }
	return int2obj(EM_ASM_INT({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return 0;
		var origin = window.useSessionStorage ? 'session' : 'local';
		var file = window[origin + 'Storage'][fileName];
		var startIndex = window.fileCharPositions[fileName];
		var endIndex = $2 + startIndex > file.length ?
			file.length :
			$2 + startIndex;
		for (var i = startIndex; i < endIndex; i++) {
			HEAP8[$1] = file.charCodeAt(i);
			$1++;
			// yield from time to time when dealing with big files
			if ((i - startIndex) % window.max_cycles == window.max_cycles - 1) {
				_taskSleep(1);
			}
		}
		window.fileCharPositions[fileName] = endIndex;
		return endIndex - startIndex;

	}, fileName, (uint8 *) &FIELD(buf, 0), BYTES(buf)));
}

// Read positioning

static OBJ primReadPosition(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);
	return int2obj(EM_ASM_INT({
		var fileName = UTF8ToString($0);
		if (!(fileName in window.fileCharPositions)) return 0;
		return window.fileCharPositions[fileName];
	}, fileName));
}

static OBJ primSetReadPosition(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	int newPosition = evalInt(args[0]);
	char *fileName = obj2str(args[1]);

	EM_ASM_({
		var fileName = UTF8ToString($0);
		var newPosition = $1;
		if (!(fileName in window.fileCharPositions)) return;
		window.fileCharPositions[fileName] = newPosition;
	}, fileName, newPosition);

	return falseObj;
}

// Writing

static OBJ primAppendLine(int argCount, OBJ *args) {
	// Append a String to a file followed by a newline.

	if (argCount < 2) return fail(notEnoughArguments);
	char *fileName = obj2str(args[1]);
	if (!openFile(fileName, 0)) return falseObj;
	char line[1024] = "";
	OBJ arg = args[0];

	if (IS_TYPE(arg, StringType)) {
		sprintf(line, obj2str(arg));
	} else if (isInt(arg)) {
		sprintf(line, "%d", obj2int(arg));
	} else if (isBoolean(arg)) {
		sprintf(line, (trueObj == arg) ? "true" : "false");
	} else if (IS_TYPE(arg, ListType)) {
		// print list items separated by spaces
		int count = obj2int(FIELD(arg, 0));
		for (int j = 1; j <= count; j++) {
			OBJ item = FIELD(arg, j);
			if (IS_TYPE(item, StringType)) {
				strcat(line, obj2str(item));
			} else if (isInt(item)) {
				char num[100];
				sprintf(num, "%d", obj2int(item));
				strcat(line, num);
			} else if (isBoolean(item)) {
				strcat(line, (trueObj == item) ? "true" : "false");
			}
			if (j < count) strcat(line, " "); // space
		}
	}

	EM_ASM_({
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return;
		var line = UTF8ToString($1);
		var origin = window.useSessionStorage ? 'session' : 'local';

		window[origin + 'Storage'][fileName] += line + '\n';

	}, fileName, line);

	return falseObj;
}

static OBJ primAppendBytes(int argCount, OBJ *args) {
	// Append a ByteArray or String to a file. No newline is added.

	if (argCount < 2) return fail(notEnoughArguments);
	OBJ data = args[0];
	char *fileName = obj2str(args[1]);
	if (!openFile(fileName, 0)) return falseObj;

	if (IS_TYPE(data, ByteArrayType)) {
		EM_ASM_({
			var origin = window.useSessionStorage ? 'session' : 'local';
			var fileName = UTF8ToString($0);
			if (fileName === 'user-prefs') return;
			var data = HEAP8.subarray($1, $1 + $2);
			var newContents = window[origin + 'Storage'][fileName];
			for (var i = 0; i < data.length; i++) {
				newContents += String.fromCharCode(data[i]);
			}
			window[origin + 'Storage'][fileName] = newContents;
		}, fileName, (uint8 *) &FIELD(data, 0), BYTES(data));
	} else if (IS_TYPE(data, StringType)) {
		EM_ASM_({
			var origin = window.useSessionStorage ? 'session' : 'local';
			var fileName = UTF8ToString($0);
			if (fileName === 'user-prefs') return;
			window[origin + 'Storage'][fileName] += UTF8ToString($1);
		}, fileName, (uint8 *) obj2str(data));
	}

	return falseObj;
}

// File list

static OBJ primFileSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = obj2str(args[0]);
	if (!fileName[0] || !openFile(fileName, 0)) return int2obj(-1);
	return int2obj(EM_ASM_INT({
		var origin = window.useSessionStorage ? 'session' : 'local';
		var fileName = UTF8ToString($0);
		if (fileName === 'user-prefs') return 0;
		var file = window[origin + 'Storage'][fileName];
		return file.length;
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
		var origin = window.useSessionStorage ? 'session' : 'local';
		var fileNames =
			Object.keys(
				window[origin + 'Storage']).filter(fn => fn !== 'user-prefs');
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
	addPrimitiveSet(FilePrims, "file", sizeof(entries) / sizeof(PrimEntry), entries);
}
