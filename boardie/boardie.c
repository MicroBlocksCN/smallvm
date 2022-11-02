/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardie.c - Boardie - A Simulated MicroBlocks Board for Web Browsers
// John Maloney and Bernat Romagosa, October 2022

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#include <emscripten.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Timing Functions

static int startSecs = 0;

static void initTimers() {
	struct timeval now;
	gettimeofday(&now, NULL);
	startSecs = now.tv_sec;
}

uint32 microsecs() {
	struct timeval now;
	gettimeofday(&now, NULL);

	return (1000000 * (now.tv_sec - startSecs)) + now.tv_usec;
}

uint32 millisecs() {
	struct timeval now;
	gettimeofday(&now, NULL);

	return (1000 * (now.tv_sec - startSecs)) + (now.tv_usec / 1000);
}

// Communication/System Functions

void initMessageService() {
	EM_ASM_({
		window.recvBuffer = [];
		window.addEventListener('message', function (event) {
			window.recvBuffer.push(...event.data);
		}, false);
	});
}

int nextByte() {
	return EM_ASM_INT({
		// Returns first byte in the buffer, and removes it from the buffer
		return window.recvBuffer.splice(0, 1)[0];
	});
}

int canReadByte() {
	return EM_ASM_INT({
		if (!window.recvBuffer) { window.recvBuffer = []; }
		return window.recvBuffer.length > 0;
	});
}

int recvBytes(uint8 *buf, int count) {
	int total = 0;
	while (canReadByte() && total <= count) {
		buf[total] = nextByte();
		total++;
	}
	return total;
}

int sendBytes(uint8 *buf, int start, int end) {
	EM_ASM_({
		var bytes = new Uint8Array($2 - $1);
		for (var i = $1; i < $2; i++) {
			bytes[i - $1] = getValue($0 + i, 'i8');
		}
		window.parent.postMessage(bytes);
	}, buf, start, end);
	return end - start;
}

// Keyboard support
void initKeyboardHandler() {
	EM_ASM_({
		window.keys = new Map();
		window.buttons = [];
		buttons[37] = document.querySelector('.btn-37');
		buttons[39] = document.querySelector('.btn-39');
		window.addEventListener('keydown', function (event) {
			if (buttons[event.keyCode]) {
				buttons[event.keyCode].classList.add('active');
			}
			window.keys.set(event.keyCode, true);
		}, false);
		window.addEventListener('keyup', function (event) {
			if (buttons[event.keyCode]) {
				window.buttons[event.keyCode].classList.remove('active');
			}
			window.keys.set(event.keyCode, false);
		}, false);
	});
}

// Sound support
void initSound() {
	EM_ASM_({
		var context = new AudioContext();
		window.gainNode = context.createGain();
		window.oscillator = context.createOscillator();
		oscillator.type = 'square';
		oscillator.start();
		gainNode.connect(context.destination);
	});
};

// System Functions

const char * boardType() {
	return "Boardie (MicroBlocks Virtual Board)";
}

// Stubs for functions not used by Boardie

void addFilePrims() {}
void addNetPrims() {}
void addSerialPrims() {}
void delay(int msecs) {}
void processFileMessage(int msgType, int dataSize, char *data) {}

// Stubs for code file (persistence) not used by Boardie

void initCodeFile(uint8 *flash, int flashByteCount) {}
void writeCodeFile(uint8 *code, int byteCount) { }
void writeCodeFileWord(int word) { }
void clearCodeFile(int ignore) { }

// Main loop

int main(int argc, char *argv[]) {
	printf("Starting Boardie\n");

	initMessageService();
	initKeyboardHandler();
	initSound();

	initTimers();
	memInit();
	primsInit();
	restoreScripts();
	startAll();

	printf("Starting interpreter\n");
	emscripten_set_main_loop(interpretStep, 60, true); // callback, fps, loopFlag
}
