/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// ideComm.cpp - Primitives to communicate with the MicroBlocks IDE.
// John Maloney, December 2023

#include <Arduino.h>

#include "mem.h"
#include "interp.h"

// Serial Communications

int recvBytes(uint8 *buf, int count) {
	int bytesRead = Serial.available();
	if (bytesRead > count) bytesRead = count; // there is only enough room for count bytes
	return Serial.readBytes(buf, bytesRead);
}

int sendBytes(uint8 *buf, int start, int end) {
	// Send bytes buf[start] through buf[end - 1] and return the number of bytes sent.

	return Serial.write(&buf[start], end - start);
}

void restartSerial() {
	// Needed to work around a micro:bit issue that Serial can lock up during Flash compaction.

	Serial.end();
	Serial.begin(115200);
}
