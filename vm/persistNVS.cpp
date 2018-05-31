/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistNVS.cpp - Persistent operations for ESP32 on NVS (Non Volatile Storage)
// Gilles Mateu - IMERIR

#if defined(ARDUINO_ARCH_ESP32)
#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

#include "nvs_flash.h"
#include "nvs.h"

#define NVS_NAME "ublockscode"
#define NVS_KEY "code"
#define NVS_CHUNK_SIZE 1024
#define HALF_SPACE 5*1024

int NVS_offset;
nvs_handle NVS_handle;
uint8 *NVS_blob = 0;
int NVS_blob_count = HALF_SPACE / NVS_CHUNK_SIZE + 1 ;

extern "C" void initNVS(uint8 *flash, int flashByteCount) {
  esp_err_t err;
  size_t NVS_bytecount = NVS_CHUNK_SIZE;
  NVS_offset = 0;

  if ( NVS_blob == 0 ) {
    NVS_blob = (uint8 *)malloc(flashByteCount*sizeof(uint8));
    memset(NVS_blob,(uint8)0,flashByteCount);
  }
  err = nvs_flash_init();
  err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
  for (int i=0 ; i < NVS_blob_count ; i++) {
    char nvskey[32];
    sprintf(nvskey,"%s%d",NVS_KEY,i);
    err = nvs_get_blob(NVS_handle, nvskey, &NVS_blob[i*NVS_CHUNK_SIZE], &NVS_bytecount);  
  }
  memcpy(flash,NVS_blob,flashByteCount);
}

extern "C" void writeNVS(uint8 *code, int byteCount) {
  size_t NVS_bytecount;
  esp_err_t err;
  memcpy(&(NVS_blob[NVS_offset]),code,byteCount);
  err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
  
  /* very ugly code, we write all the memory */
  for (int i=0 ; i < NVS_blob_count + 1 ; i++) {
    char nvskey[32];
    sprintf(nvskey,"%s%d",NVS_KEY,i);  
    err = nvs_set_blob(NVS_handle, nvskey, &NVS_blob[i*NVS_CHUNK_SIZE] , NVS_CHUNK_SIZE);
  }
  err = nvs_commit(NVS_handle);
  NVS_offset+=byteCount;
}

extern "C" void writeNVSWord(int word) {
  writeNVS((uint8 *) &word, 4);
}

extern "C" void clearNVS() {
  size_t NVS_bytecount;
  esp_err_t err;
  err = nvs_flash_init();
  err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
  if (err == ESP_OK) { 
    nvs_erase_all(NVS_handle);
    err = nvs_commit(NVS_handle);
  }
  NVS_offset=0;
  err = nvs_open(NVS_NAME, NVS_READWRITE, &NVS_handle);
  if (err == ESP_OK) {
    uint32 cycleCount = ('S' << 24) | 1; // Header record, version 1
    writeNVSWord(cycleCount);
  }
  nvs_close(NVS_handle);  
}

#endif
