/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// filePrims.c - File system primitives for Linux boards.
// John Maloney, April 2020

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>

#include "mem.h"
#include "interp.h"

FILE *currentFilePointer;
char *currentFileName;
DIR *directory;
struct dirent *nextDirEntry;
struct stat fileStat;

static char *extractFilename(OBJ obj) {
	char *fileName = "\0";
	if (IS_TYPE(obj, StringType)) {
		fileName = obj2str(obj);
		if (strcmp(fileName, "ublockscode") == 0) return "\0";
	} else {
		fail(needsStringError);
	}
	return fileName;
}

char ensureOpen (char *fileName) {
	if (strcmp(currentFileName, fileName) != 0) {
		// currently open file is different from requested one
		if (currentFilePointer != NULL) {
			// and there was a currently open file, so we close it first
			fclose(currentFilePointer);
		}
		memcpy(currentFileName, fileName, strlen(fileName));
		currentFilePointer = fopen(currentFileName, "a+");
	} else if (fileName[0] && currentFilePointer == NULL) {
		// current file was closed, so we reopen it
		currentFilePointer = fopen(currentFileName, "a+");
	}
	return currentFilePointer != NULL;
}

static OBJ primOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	currentFileName = extractFilename(args[0]);
	if (!currentFileName[0]) return falseObj;
	currentFilePointer = fopen(currentFileName, "a+");
	return falseObj;
}

static OBJ primClose(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (strcmp(currentFileName, fileName) == 0 &&
			currentFilePointer != NULL) {
		fclose(currentFilePointer);
		currentFilePointer = NULL;
	}
	return falseObj;
}

static OBJ primDelete(int argCount, OBJ *args) { return falseObj; }

static OBJ primEndOfFile(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0] || !ensureOpen(fileName)) return trueObj;

	return feof(currentFilePointer) ? trueObj : falseObj;
}

static OBJ primReadLine(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0] || !ensureOpen(fileName)) return newString(0);

	char buf[800];
	uint32 byteCount = 0;

	if (fgets(buf, 800, currentFilePointer) != NULL) {
		byteCount = strlen(buf);
		OBJ result = newString(byteCount);
		if (result) {
			memcpy(obj2str(result), buf, byteCount);
			return result;
		}
	}
	return newString(0);
}

static OBJ primReadBytes(int argCount, OBJ *args) { return falseObj; }

static OBJ primAppendLine(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char *fileName = extractFilename(args[1]);
	OBJ arg = args[0];

	if (!fileName[0] || !ensureOpen(fileName)) return newString(0);

	if (IS_TYPE(arg, StringType)) {
		fprintf(currentFilePointer, "%s", obj2str(arg));
	} else if (isInt(arg)) {
		fprintf(currentFilePointer, "%i", obj2int(arg));
	} else if (isBoolean(arg)) {
		fprintf(currentFilePointer, "%s", (trueObj == arg) ? "true" : "false");
	} else if (IS_TYPE(arg, ListType)) {
		// print list items separated by spaces
		int count = obj2int(FIELD(arg, 0));
		for (int j = 1; j <= count; j++) {
			OBJ item = FIELD(arg, j);
			if (IS_TYPE(item, StringType)) {
				fprintf(currentFilePointer, "%s", obj2str(item));
			} else if (isInt(item)) {
				fprintf(currentFilePointer, "%i", obj2int(item));
			} else if (isBoolean(item)) {
				fprintf(currentFilePointer, "%s", (trueObj == item) ? "true" : "false");
			}
			if (j < count) fprintf(currentFilePointer, " ");
		}
	}
	fprintf(currentFilePointer, "\n");
	processMessage();
	return falseObj;
}

static OBJ primAppendBytes(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	OBJ data = args[0];
	char *fileName = extractFilename(args[1]);
	if (fileName[0] && ensureOpen(fileName)) {
		if (IS_TYPE(data, ByteArrayType)) {
			fwrite((uint8 *) &FIELD(data, 0), 8, BYTES(data), currentFilePointer);
		} else if (IS_TYPE(data, StringType)) {
			char *s = obj2str(data);
			fwrite((uint8 *) s, 8, strlen(s), currentFilePointer);
		}
	}
	processMessage();
	return falseObj;
}

static OBJ primFileSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char *fileName = extractFilename(args[0]);
	if (!fileName[0] || !ensureOpen(fileName)) return int2obj(0);
	struct stat st;
	stat(fileName, &st);
	return int2obj(st.st_size);
}

static OBJ primStartFileList(int argCount, OBJ *args) {
	directory = opendir(".");
	return falseObj;
}

static OBJ primNextFileInList(int argCount, OBJ *args) {
	char fileName[100];
	if (directory) {
		if ((nextDirEntry = readdir(directory)) != NULL) {
			// check entry type
			stat(nextDirEntry->d_name, &fileStat);
			if (S_ISREG(fileStat.st_mode)) {
				// it's a regular file, we're okay
				strncat(fileName, nextDirEntry->d_name, 99);
			} else {
				// it's not a regular file, let's recurse into the next entry
				return primNextFileInList(argCount, args);
			}
		} else {
			closedir(directory);
			directory = NULL;
		}
	}
	return newStringFromBytes(fileName, strlen(fileName));
}

static OBJ primSystemInfo(int argCount, OBJ *args) { return falseObj; }

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
