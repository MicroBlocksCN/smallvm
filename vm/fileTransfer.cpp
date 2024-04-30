/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// fileTransfer.c - File tranfer support.
// John Maloney, December 2021

#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// File Messages

#define DeleteFileMsg 200
#define ListFilesMsg 201
#define FileInfoMsg 202
#define StartReadingFileMsg 203
#define StartWritingFileMsg 204
#define FileChunkMsg 205

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(RP2040_PHILHOWER)

#include "fileSys.h"

// Variables

char receivedFileName[32];
int receiveID = 0;
int receivedBytes = 0;
File tempFile;

const char tempFileName[] = "/_TMP_incoming_TMP_";

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

static void clearFileReceiveState() {
	receivedFileName[0] = 0;
	receiveID = 0;
	receivedBytes = 0;
}

static void receiveChunk(int msgByteCount, char *msg) {
	// Append the incoming chunk to the file being received.

	if (!receiveID) return; // not receiving a file; ignore

	int transferID = readInt(&msg[0]);
	int offset = readInt(&msg[4]);
	char *chunkData = &msg[8];
	int chunkSize = msgByteCount - 8;

	if ((transferID != receiveID) || (offset != receivedBytes)) {
		// Unexpected transferID or offset; abort file transfer.
		outputString("Communication error; file transfer cancelled");
		tempFile.close();
		clearFileReceiveState();
		return;
	}

	if (chunkSize > 0) { // append chunk to the temporary file
		tempFile.write((uint8_t *) chunkData, chunkSize);
		receivedBytes += chunkSize;
	} else { // tranfer complete
		// close and rename file
		tempFile.close();
		closeAndDeleteFile(receivedFileName); // delete the old version
		myFS.rename(tempFileName, receivedFileName);
		clearFileReceiveState();
	}
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
	closeIfOpen((char *) tempFileName);
	tempFile = myFS.open(tempFileName, "w");
}

static void sendFile(int id, char *fileName) {
	const int chunkSize = 960;
	int byteIndex = 0;
	char buf[1024];

	File file = myFS.open(fileName, "r");
	if (!file) return; // could not open file
	while (file.available()) { // send file chunks
		int byteCount = file.read((uint8_t *) &buf[8], chunkSize);
		// format: <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
		writeInt(id, &buf[0]);
		writeInt(byteIndex, &buf[4]);
		waitAndSendMessage(FileChunkMsg, 0, byteCount + 8, buf);
		byteIndex += byteCount;
	}

	// send a final, empty chunk to indicate end of file
	writeInt(id, &buf[0]);
	writeInt(byteIndex, &buf[4]);
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
	memcpy(&buf[8], fileName, len);
	waitAndSendMessage(FileInfoMsg, 0, len + 8, buf);
}

static void sendFileList() {
	char fileName[32];
	int fileIndex = 1;

	#if defined(ESP32)
		File rootDir = myFS.open("/");
		while (true) {
			File file = rootDir.openNextFile();
			if (!file) break;
			memset(fileName, 0, sizeof(fileName));
			strncpy(fileName, file.name(), 31);
			if ((strcmp(fileName, "/") != 0) && (strcmp(fileName, "/ublockscode") != 0)) {
				sendFileInfo(fileName, file.size(), fileIndex);
				fileIndex++;
			}
		}
	// xxx Could this be just #else? Need to test with all non-ESP32 boards
	#elif defined(ESP8266) || defined(RP2040_PHILHOWER)
		Dir rootDir = myFS.openDir("/");
		while (rootDir.next()) {
			memset(fileName, 0, sizeof(fileName));
			strncpy(fileName, rootDir.fileName().c_str(), 31);
			if ((strcmp(fileName, "/") != 0) &&
				(strcmp(fileName, "/ublockscode") != 0) &&
				(strcmp(fileName, "ublockscode") != 0)) {
					sendFileInfo(fileName, rootDir.fileSize(), fileIndex);
					fileIndex++;
			}
		}
	#endif
}

void processFileMessage(int msgType, int dataSize, char *data) {
	// Process a file message (msgType [200..205]).

	int id = 0;
	char fileName[32]; // max of 30 characters after the leading "/"
	strcpy(fileName, "/"); // add the leading slash

	switch (msgType) {
	case DeleteFileMsg:
		// format: <file name>
		if (dataSize > 30) dataSize = 30;
		strncat(fileName, data, dataSize);
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

#else

// File system messages are just ignored on non-Espressif boards

void processFileMessage(int msgType, int dataSize, char *data) { }

#endif
