/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieFileTransfer.c - File tranfer support for Boardie.
// Bernat Romagosa, November 2022

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"

// File Messages

#define DeleteFileMsg 200
#define ListFilesMsg 201
#define FileInfoMsg 202
#define StartReadingFileMsg 203
#define StartWritingFileMsg 204
#define FileChunkMsg 205

// Variables

char receivedFileName[32];
int receiveID = 0;
int receivedBytes = 0;

// Prototypes

void closeAndDeleteFile(char *fileName);

// Helper Functions

static int readInt(char *src) {
	// Read a four-byte integer from the given source in little-endian order.

	return (src[3] << 24) | (src[2] << 16) | (src[1] << 8) | src[0];
}

// File Operations

static void receiveFile(int id, char *fileName) {
	if (strlen(fileName) <= 1) {
		outputString("Empty file name; ignoring.");
		return;
	}
	strncpy(receivedFileName, fileName, 31);

	receiveID = id;
	receivedBytes = 0;
	EM_ASM_({ window.tempFile = ""; });
}

void processFileMessage(int msgType, int dataSize, char *data) {
	// Process a file message (msgType [200..205]).

	int id = 0;
	char fileName[32] = ""; // max of 30 characters after the leading "/"

	switch (msgType) {
	case DeleteFileMsg:
		// format: <file name>
		if (dataSize > 30) dataSize = 30;
		strncat(fileName, data, dataSize);
		printf("delete file %s\n", fileName);
		closeAndDeleteFile(fileName);
		break;
	case ListFilesMsg:
		printf("list files\n");
		// format: no data (short message)
		//sendFileList();
		break;
	case StartReadingFileMsg:
		printf("start reading file\n");
		// format: <transfer ID (4 byte int)><file name>
		/*
		id = readInt(data);
		dataSize -= 4;
		if (dataSize > 30) dataSize = 30;
		strncat(fileName, &data[4], dataSize);
		sendFile(id, fileName);
		*/
		break;
	case StartWritingFileMsg:
		// format: <transfer ID (4 byte int)><file name>
		id = readInt(data);
		dataSize -= 4;
		if (dataSize > 30) dataSize = 30;
		strncat(fileName, &data[4], dataSize);
		receiveFile(id, fileName);
		break;
	case FileChunkMsg:
		printf("file chunk %d\n", dataSize);
		// format: <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
		//receiveChunk(dataSize, data);
		break;
	}
}
