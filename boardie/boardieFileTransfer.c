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

static void writeInt(int n, char *dst) {
	// Write a four-byte integer to the given destination in little-endian order.

	*dst++ = (n & 0xFF);
	*dst++ = ((n >> 8) & 0xFF);
	*dst++ = ((n >> 16) & 0xFF);
	*dst++ = ((n >> 24) & 0xFF);
}

// File Operations

static void receiveChunk(int msgByteCount, char *msg) {
	// Append the incoming chunk to the file being received.

	// not receiving a file; ignore
	if (!EM_ASM_INT({ return window.tempFile !== undefined })) return;

	int transferID = readInt(&msg[0]);
	int offset = readInt(&msg[4]);
	char *chunkData = &msg[8];
	int chunkSize = msgByteCount - 8;

	if ((transferID != receiveID) /*|| (offset != receivedBytes) */) {
		// Unexpected transferID or offset; abort file transfer.
		outputString("Communication error; file transfer canceled");
		EM_ASM_({ delete(window.tempFile); });
		return;
	}

	if (chunkSize > 0) { // append chunk to the temporary variable
		EM_ASM_({
			for (var i = 0; i < $1; i++) {
				window.tempFile += String.fromCharCode(getValue($0 + i, 'i8'));
			}
		}, (uint8_t *) chunkData, chunkSize);
		receivedBytes += chunkSize;
	} else { // transfer complete
		// move file to localStorage
		EM_ASM_({
			window.localStorage[UTF8ToString($0)] = window.tempFile;
			delete(window.tempFile);
		}, receivedFileName);
	}
}

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

static void sendFile(int id, char *fileName) {
	int byteIndex = 0;
	char buf[1024];

	if (!EM_ASM_INT({
		return window.localStorage[UTF8ToString($0)] !== undefined;
	}, fileName)) {
		// could not find file
		return;
	}

	while (true) {
		int byteCount = EM_ASM_INT({
			var file = window.localStorage[UTF8ToString($0)];
			var chunkSize = Math.min(960, file.length - $2);
			for (var i = 0; i < chunkSize; i ++) {
				setValue($1 + 8 + i, file.charCodeAt($2 + i), 'i8');
			}
			//stringToUTF8(file.substring($2, $2 + chunkSize), $1 + 8, 1024);
			return chunkSize;
		}, fileName, buf, byteIndex);
		if (byteCount > 0) {
			// <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
			writeInt(id, &buf[0]);
			writeInt(byteIndex, &buf[4]);
			waitAndSendMessage(FileChunkMsg, 0, byteCount + 8, buf);
			byteIndex += byteCount;
		} else {
			break;
		}
	}
	printf("all done, sending final chunk\n");

	// send a final, empty chunk to indicate end of file
	writeInt(id, &buf[0]);
	writeInt(byteIndex, &buf[4]);
	waitAndSendMessage(FileChunkMsg, 0, 8, buf);
}

EMSCRIPTEN_KEEPALIVE
void sendFileInfo(int entryIndex, int fileSize) {
	//  Send file info message. Format: (entryIndex, file size in bytes, name)
	char buf[1024];
	char fileName[64];
	EM_ASM_({
		stringToUTF8(Object.keys(window.localStorage)[$0], $1, 64);
	}, entryIndex, fileName);
	int len = strlen(fileName);
	writeInt(entryIndex, &buf[0]);
	writeInt(fileSize, &buf[4]);
	memcpy(&buf[8], fileName, len);
	waitAndSendMessage(FileInfoMsg, 0, len + 8, buf);
}

static void sendFileList() {
	EM_ASM_({
		Object.keys(window.localStorage).forEach(function (fileName, index) {
			_sendFileInfo(index, window.localStorage[fileName].length);
		});
	});
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
		// format: no data (short message)
		sendFileList();
		break;
	case StartReadingFileMsg:
		// format: <transfer ID (4 byte int)><file name>
		id = readInt(data);
		dataSize -= 4;
		if (dataSize > 30) dataSize = 30;
		strncat(fileName, &data[4], dataSize);
		sendFile(id, fileName);
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
		// format: <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
		receiveChunk(dataSize, data);
		break;
	}
}
