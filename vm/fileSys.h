/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// fileSys.c - File system selection.
// John Maloney, December 2021

#include <FS.h>

// Select file system (Note: LittleFS is often much slower than SPIFFS)
#define useLittleFS defined(ARDUINO_RASPBERRY_PI_PICO)
#if useLittleFS
	#ifdef ARDUINO_ARCH_ESP32
		#include <LITTLEFS.h>
		#define myFS LITTLEFS
	#else
		#include <LittleFS.h>
		#define myFS LittleFS
	#endif
#else
	#ifdef ARDUINO_ARCH_ESP32
		#include <SPIFFS.h>
	#endif
	#define myFS SPIFFS
#endif
