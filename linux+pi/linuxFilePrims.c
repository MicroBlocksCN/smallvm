/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxFilePrims.c - File system primitives for Linux boards.
// John Maloney, April 2020
// Adapted to Linux VM by Bernat Romagosa, February 2021

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <dirent.h>

#include "mem.h"
#include "interp.h"

typedef struct {
	char fileName[100];
	FILE *file;
} FileEntry;

#define FILE_ENTRIES 64
static FileEntry fileEntry[FILE_ENTRIES]; // records open files

DIR *directory;
struct dirent *nextDirEntry;
struct stat fileStat;
struct statvfs fsStat;

static void extractFilename(OBJ obj, char *outputFileName) {
	outputFileName[0] = '\0';
	if (IS_TYPE(obj, StringType)) {
		int size = strlen(obj2str(obj));
		memcpy(outputFileName, obj2str(obj), size);
		outputFileName[size] = '\0';
		if (strcmp(outputFileName, "ublockscode") == 0) {
			outputFileName[0] = '\0';
		}
	} else {
		fail(needsStringError);
	}
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

static void tryToOpen(int entryIndex, char* fileName) {
	if (entryIndex >= 0) {
		if (fileEntry[entryIndex].file) fclose(fileEntry[entryIndex].file);

		fileEntry[entryIndex].file = fopen(fileName, "a+");

		if (!fileEntry[entryIndex].file) {
			fileEntry[entryIndex].file = fopen(fileName, "r");
		}

		if (fileEntry[entryIndex].file) {
			fseek(fileEntry[entryIndex].file, 0, SEEK_SET); // read from start of file
		} else {
			fileEntry[entryIndex].fileName[0] = '\0';
		}
	}
}

static OBJ primOpen(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char fileName[100];
	extractFilename(args[0], fileName);
	int i = entryFor(fileName);
	if (i >= 0) { // found an existing entry; close and reopen
		tryToOpen(i, fileName);
		return falseObj;
	}
	i = freeEntry();
	if (i >= 0) { // initialize new entry
		fileEntry[i].fileName[0] = '\0';
		strncpy(fileEntry[i].fileName, fileName, 99);
		fileEntry[i].fileName[99] = '\0'; // ensure null termination
		tryToOpen(i, fileName);
	}
	return falseObj;
}

static OBJ primClose(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char fileName[100];
	extractFilename(args[0], fileName);
	int i = entryFor(fileName);
	if (i >= 0) {
		fileEntry[i].fileName[0] = '\0';
		fclose(fileEntry[i].file);
		return falseObj;
	}
	return falseObj;
}

static OBJ primDelete(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char fileName[100];
	extractFilename(args[0], fileName);

	int i = entryFor(fileName);
	if (i >= 0) {
		fileEntry[i].fileName[0] = '\0';
		fclose(fileEntry[i].file);
	}

	if (fileName[0]) remove(fileName);
	return falseObj;
}

static OBJ primEndOfFile(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char fileName[100];
	extractFilename(args[0], fileName);

	int i = entryFor(fileName);
	if (i < 0) return trueObj;

	return feof(fileEntry[i].file) ? trueObj : falseObj;
}

static OBJ primReadLine(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char fileName[100];
	extractFilename(args[0], fileName);

	int i = entryFor(fileName);
	if (i < 0) return newString(0);

	char buf[800];
	uint32 byteCount = 0;

	if (fgets(buf, 800, fileEntry[i].file) != NULL) {
		byteCount = strlen(buf);
		OBJ result = newString(byteCount);
		if (result) {
			memcpy(obj2str(result), buf, byteCount);
			return result;
		}
	}
	return newString(0);
}

static OBJ primReadBytes(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	uint32 byteCount = obj2int(args[0]);
	char fileName[100];
	extractFilename(args[1], fileName);

	int i = entryFor(fileName);
	if (i >= 0) {
		uint8 buf[800];
		if (byteCount > sizeof(buf)) byteCount = sizeof(buf);
		if ((argCount > 2) && isInt(args[2])) {
			fseek(fileEntry[i].file, obj2int(args[2]), SEEK_SET);
		}
		byteCount = fread(buf, 1, byteCount, fileEntry[i].file);
		int wordCount = (byteCount + 3) / 4;
		OBJ result = newObj(ByteArrayType, wordCount, falseObj);
		if (result) {
			setByteCountAdjust(result, byteCount);
			memcpy(&FIELD(result, 0), buf, byteCount);
			return result;
		}
	}
	return newObj(ByteArrayType, 0 ,falseObj);
}

static OBJ primAppendLine(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[1], StringType)) return fail(needsStringError);
	char fileName[100];
	extractFilename(args[1], fileName);
	OBJ arg = args[0];

	int i = entryFor(fileName);
	if (i >= 0) {
		if (IS_TYPE(arg, StringType)) {
			fprintf(fileEntry[i].file, "%s", obj2str(arg));
		} else if (isInt(arg)) {
			fprintf(fileEntry[i].file, "%i", obj2int(arg));
		} else if (isBoolean(arg)) {
			fprintf(fileEntry[i].file, "%s", (trueObj == arg) ?
					"true" : "false");
		} else if (IS_TYPE(arg, ListType)) {
			// print list items separated by spaces
			int count = obj2int(FIELD(arg, 0));
			for (int j = 1; j <= count; j++) {
				OBJ item = FIELD(arg, j);
				if (IS_TYPE(item, StringType)) {
					fprintf(fileEntry[i].file, "%s", obj2str(item));
				} else if (isInt(item)) {
					fprintf(fileEntry[i].file, "%i", obj2int(item));
				} else if (isBoolean(item)) {
					fprintf(fileEntry[i].file, "%s", (trueObj == item) ?
							"true" : "false");
				}
				if (j < count) fprintf(fileEntry[i].file, " ");
			}
		}
		fprintf(fileEntry[i].file, "\n");
	}
	processMessage();
	return falseObj;
}

static OBJ primAppendBytes(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	OBJ data = args[0];
	char fileName[100];
	extractFilename(args[1], fileName);

	int i = entryFor(fileName);
	if (i < 0) return falseObj;

	if (IS_TYPE(data, ByteArrayType)) {
		fwrite((uint8 *) &FIELD(data, 0), 1, BYTES(data), fileEntry[i].file);
	} else if (IS_TYPE(data, StringType)) {
		char *s = obj2str(data);
		fwrite((uint8 *) s, 1, strlen(s), fileEntry[i].file);
	}
	processMessage();
	return falseObj;
}

static OBJ primFileSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	char fileName[100];
	extractFilename(args[0], fileName);
	if (!fileName[0]) return int2obj(0);
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
	int length = 0;
	if (directory) {
		if ((nextDirEntry = readdir(directory)) != NULL) {
			// check entry type
			stat(nextDirEntry->d_name, &fileStat);
			if (S_ISREG(fileStat.st_mode)) {
				// it's a regular file, we're okay
				length = strlen(nextDirEntry->d_name);
				if (length > 99) length = 99;
				strncpy(fileName, nextDirEntry->d_name, length);
				fileName[length] = '\0'; // ensure null termination
			} else {
				// it's not a regular file, let's recurse into the next entry
				return primNextFileInList(argCount, args);
			}
		} else {
			closedir(directory);
			directory = NULL;
		}
	}
	return newStringFromBytes(fileName, length);
}

static OBJ primSystemInfo(int argCount, OBJ *args) {
	char result[100];
	statvfs(".", &fsStat);
	int freeBytes = fsStat.f_bavail * fsStat.f_frsize;
	int totalBytes = fsStat.f_blocks * fsStat.f_frsize;
	sprintf(result, "%u bytes used of %u", totalBytes - freeBytes, totalBytes);
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
