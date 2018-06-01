/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.cpp - Persistent file/non-volatile storage operations

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "persist.h"

#if defined(ESP8266)
	// Persistent file operations for NodeMCU (SPIFFS file system)

#include <FS.h>

File codeFile;

extern "C" void initCodeFile(uint8 *flash, int flashByteCount) {
	SPIFFS.begin();
	codeFile = SPIFFS.open("ublockscode", "a+");
	// read code file into simulated Flash:
	long int bytesRead = codeFile.readBytes((char*) flash, flashByteCount);
}

extern "C" void writeCodeFile(uint8 *code, int byteCount) {
	codeFile.write(code, byteCount);
	codeFile.flush();
}

extern "C" void writeCodeFileWord(int word) {
	codeFile.write((uint8 *) &word, 4);
	codeFile.flush();
}

extern "C" void clearCodeFile() {
	codeFile.close();
	SPIFFS.remove("ublockscode");
	codeFile = SPIFFS.open("ublockscode", "a+");
	uint32 cycleCount = ('S' << 24) | 1; // Header record, version 1
	int bytesWritten = codeFile.write((uint8 *) &cycleCount, 4);
	codeFile.flush();
}

#elif defined(ARDUINO_ARCH_ESP32)
	// Persistent operations for ESP32 using NVS
	// Contributed by Gilles Mateu - IMERIR

#include "nvs_flash.h"
#include "nvs.h"

#define NVS_NAME "ublockscode"
#define NVS_KEY "code"
#define NVS_CHUNK_SIZE 1024
#define HALF_SPACE 5 * 1024

int NVS_offset;
nvs_handle NVS_handle;
uint8 *NVS_blob = 0;
int NVS_blob_count = HALF_SPACE / NVS_CHUNK_SIZE + 1;

extern "C" void initCodeFile(uint8 *flash, int flashByteCount) {
	esp_err_t err;
	size_t NVS_bytecount = NVS_CHUNK_SIZE;
	NVS_offset = 0;

	if (NVS_blob == 0) {
		NVS_blob = (uint8 *) malloc(flashByteCount * sizeof(uint8));
		memset(NVS_blob, (uint8) 0, flashByteCount);
	}
	err = nvs_flash_init();
	err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
	for (int i = 0; i < NVS_blob_count; i++) {
		char nvskey[32];
		sprintf(nvskey, "%s%d", NVS_KEY, i);
		err = nvs_get_blob(NVS_handle, nvskey, &NVS_blob[i * NVS_CHUNK_SIZE], &NVS_bytecount);
	}
	memcpy(flash, NVS_blob, flashByteCount);
}

extern "C" void writeCodeFile(uint8 *code, int byteCount) {
	size_t NVS_bytecount;
	esp_err_t err;
	memcpy(&(NVS_blob[NVS_offset]), code, byteCount);
	err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);

	/* very ugly code, we write all the memory */
	for (int i = 0; i < NVS_blob_count + 1; i++) {
		char nvskey[32];
		sprintf(nvskey,"%s%d", NVS_KEY, i);
		err = nvs_set_blob(NVS_handle, nvskey, &NVS_blob[i * NVS_CHUNK_SIZE] , NVS_CHUNK_SIZE);
	}
	err = nvs_commit(NVS_handle);
	NVS_offset += byteCount;
}

extern "C" void writeCodeFileWord(int word) {
	writeCodeFile((uint8 *) &word, 4);
}

extern "C" void clearCodeFile() {
	size_t NVS_bytecount;
	esp_err_t err;
	err = nvs_flash_init();
	err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
	if (err == ESP_OK) {
		nvs_erase_all(NVS_handle);
		err = nvs_commit(NVS_handle);
	}
	NVS_offset = 0;
	err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
	if (err == ESP_OK) {
		uint32 cycleCount = ('S' << 24) | 1; // Header record, version 1
		writeCodeFileWord(cycleCount);
	}
	nvs_close(NVS_handle);
}

#endif
