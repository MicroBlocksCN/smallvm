/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// fileTransfer.c - File tranfer support.
// John Maloney, December 2021

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
// File system operations for Espressif boards

#include "fileSys.h"

// File Messages

#define DeleteFileMsg 200
#define ListFilesMsg 201
#define FileInfoMsg 202
#define StartReadingFileMsg 203
#define StartWritingFileMsg 204
#define FileChunkMsg 205

// Variables

char receivedFileName[32];
int receiveFileName = false;
int receiveID = 0;
int receivedBytes = 0;
File tempFile;

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

static void endFileReceive(int saveFile) {
	if (!receiveFileName) return;
	if (saveFile && !tempFile) { // rename the file
		myFS.remove(receivedFileName); // delete old file, if any
		myFS.rename(tempFile.name(), receivedFileName);
	}
	// clear file receive state
	receivedFileName[0] = 0;
	receiveFileName = false;
	receiveID = 0;
	receivedBytes = 0;
	tempFile.close();
}

static void receiveChunk(int byteCount, char *msg) {
	//
	if (!receiveFileName) return;
	// check the receiveID and abort if it doesn't match
	// check the offset and do something it doesn't match (abort? write zeros? print error msg?)
	if (!tempFile) {
		// TBD append chunk data
		// tempFile.write(buf, bufSize);
		// receivedBytes += bufSize;
	}
	// clear file receive state
	receivedFileName[0] = 0;
	receiveFileName = false;
	receivedBytes = 0;
	tempFile.close();
}

// File Operations

static void deleteFile(char *fileName) {
	outputString("delete:");
	outputString(fileName);
	myFS.remove(fileName);
}

static void receiveFile(int id, char *fileName) {

// debug xxx
outputString("receiveFile:");
reportNum("id", id);
outputString(fileName);
return;

	receiveFileName = true;
	strncpy(receivedFileName, fileName, 31);
	receiveID = id;
	receivedBytes = 0;
	tempFile = myFS.open("_TMP_incoming_TMP_", "w");

	// TBD loop waiting for file to arrive or timeout
}

static void sendFile(int id, char *fileName) {
// debug xxx
outputString("sendFile:");
reportNum("id", id);
outputString(fileName);

	const int chunkSize = 960;
	int byteIndex = 0;
	char buf[1024];

	File file = myFS.open(fileName, "r");
	if (!file) return; // could not open file
	while (file.available()) { // send file chunks
		int byteCount = file.read((uint8_t *) &buf[8], chunkSize);
// xxx
// reportNum("id", id);
// reportNum("byteIndex", byteIndex);
// reportNum("byteCount", byteCount);
// outputString("----");

		// format: <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
		writeInt(id, &buf[0]);
		writeInt(byteIndex, &buf[4]);
		waitAndSendMessage(FileChunkMsg, 0, byteCount + 8, buf);

		byteIndex += byteCount;
		if (!byteCount) break;
	}

	// send a final, empty chunk to indicate end of file
	writeInt(id, &buf[0]);
	writeInt(0, &buf[4]);
	waitAndSendMessage(FileChunkMsg, 0, 8, buf);
	file.close();
}

static void sendFileInfo(char *fileName, int fileSize, int entryIndex) {
	//  Send file info message. Format: (entryIndex, file size in bytes, name)
	char buf[1024];
	if ('/' == fileName[0]) fileName++; // skip leading '/'
	int len = strlen(fileName);

	writeInt(entryIndex, &buf[0]);
	writeInt(fileSize, &buf[4]);
	buf[8] = len; // one byte file name length
	char *dst = &buf[9];
	for (int i = 0; i < len; i++) {
		*dst++ = fileName[i];
	}
	waitAndSendMessage(FileInfoMsg, 0, len + 9, buf);
}

static void sendFileList() {
	char fileName[32];
	int fileIndex = 1;

	#if defined(ESP8266)
		Dir rootDir = myFS.openDir("/");
		while (rootDir.next()) {
			strncpy(fileName, rootDir.fileName().c_str(), 31);
			if ((strcmp(fileName, "/") != 0) && (strcmp(fileName, "/ublockscode") != 0)) {
				sendFileInfo(fileName, rootDir.fileSize(), fileIndex);
				fileIndex++;
			}
		}
	#elif defined(ESP32)
		File rootDir = myFS.open("/");
		while (true) {
			File file = rootDir.openNextFile();
			if (!file) break;
			strncpy(fileName, file.name(), 31);
			if ((strcmp(fileName, "/") != 0) && (strcmp(fileName, "/ublockscode") != 0)) {
				sendFileInfo(fileName, file.size(), fileIndex);
				fileIndex++;
			}
		}
	#endif
}

void processFileMessage(int msgType, int dataSize, char *data) {
	// Process a file message (msgType [200..205]).

	int id = 0;
	char fileName[32];
	strcpy(fileName, "/"); // add the leading slash

	switch (msgType) {
	case DeleteFileMsg:
		// format: <file name>
		if (dataSize < 32) {
			strncat(fileName, data, dataSize);
			deleteFile(fileName);
		}
		break;
	case ListFilesMsg:
		// format: no data (short message)
		sendFileList();
		break;
	case StartReadingFileMsg:
		// format: <transfer ID (4 byte int)><file name>
		id = readInt(data);
		dataSize -= 4;
		if (dataSize < 32) {
			strncat(fileName, &data[4], dataSize);
			sendFile(id, fileName);
		}
		break;
	case StartWritingFileMsg:
		// format: <transfer ID (4 byte int)><file name>
		id = readInt(data);
		dataSize -= 4;
		if (dataSize < 32) {
			strncat(fileName, &data[4], dataSize);
			receiveFile(id, fileName);
		}
		break;
	case FileChunkMsg:
		// format: <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
		receiveChunk(dataSize, data);
		break;
	}
}

#else
// File system operation messages simply ignored on Espressif boards

void processFileMessage(int msgType, int dataSize, char *data) { }

#endif
