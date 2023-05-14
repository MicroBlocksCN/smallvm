/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// linux.c - Microblocks for Linux
// An adaptation of raspberryPi.c by John Maloney to
// work on a GNU/Linux TTY as a serial device

// John Maloney, December 2017
// Bernat Romagosa, February 2018

#define _XOPEN_SOURCE 600
#define _DEFAULT_SOURCE

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h> // still needed?
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/time.h> // still needed?
#include <termios.h>
#include <unistd.h>
#include <signal.h>

#ifdef ARDUINO_RASPBERRY_PI
#include <wiringPi.h>
#include <wiringSerial.h>
#endif

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Keyboard
int KEY_SCANCODE[255];

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

#ifndef ARDUINO_RASPBERRY_PI
void delay(int ms) {
	clock_t start = millisecs();
	while (millisecs() < start + ms);
}
#endif


// Communication/System Functions

static int pty; // pseudo terminal used for communication with the IDE

int serialConnected() {
	return pty > -1;
}

static void makePtyFile() {
	FILE *file = fopen("/tmp/ublocksptyname", "w");
	if (file) {
		fprintf(file, "%s", (char*) ptsname(pty));
		fclose(file);
	}
}

static void exitGracefully() {
	remove("/tmp/ublocksptyname");
	exit(0);
}

static void openPseudoTerminal() {
	pty = posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (-1 == pty) {
		perror("Error opening pseudo terminal\n");
		exit(-1);
	}

	struct termios settings;
	tcgetattr(pty, &settings);
	cfmakeraw(&settings);
	tcsetattr(pty, TCSANOW, &settings);

 	grantpt(pty);
 	unlockpt(pty);

	makePtyFile();
}

int recvBytes(uint8 *buf, int count) {
	int readCount = read(pty, buf, count);
	if (readCount < 0) readCount = 0;
	return readCount;
}

int canReadByte() {
	int bytesAvailable;
	ioctl(pty, FIONREAD, &bytesAvailable);
	return (bytesAvailable > 0);
}

int sendByte(char aByte) {
	return write(pty, &aByte, 1);
}

// System Functions

const char * boardType() {
#ifdef ARDUINO_RASPBERRY_PI
	return "Raspberry Pi";
#else
	return "Linux";
#endif
}

#ifdef ARDUINO_RASPBERRY_PI
// General Purpose I/O Pins

#define DIGITAL_PINS 32
#define ANALOG_PINS 0
#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
#define PIN_LED 0

// Pin Modes

// To speed up pin I/O, the current pin input/output mode is recorded in the currentMode[]
// array to avoid calling pinMode() unless the pin mode has actually changed.

static char currentMode[TOTAL_PINS];

#define MODE_NOT_SET (-1)

#define SET_MODE(pin, newMode) { \
	if ((newMode) != currentMode[pin]) { \
		pinMode((pin), newMode); \
		currentMode[pin] = newMode; \
	} \
}

static void initPins(void) {
	// Initialize currentMode to MODE_NOT_SET (neigher INPUT nor OUTPUT)
	// to force the pin's mode to be set on first use.

	for (int i = 0; i < TOTAL_PINS; i++) currentMode[i] = MODE_NOT_SET;
}

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }
OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(int argCount, OBJ *args) { return int2obj(0); } // no analog inputs
void primAnalogWrite(OBJ *args) { } // analog output is not supported

OBJ primDigitalRead(int argCount, OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return falseObj;
	SET_MODE(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

void primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	primDigitalSet(pinNum, value);
}

void primDigitalSet(int pinNum, int flag) {
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return;
	SET_MODE(pinNum, OUTPUT);
	digitalWrite(pinNum, flag);
};

#else // Regular Linux system (not a Raspberry Pi)

// Stubs for IO primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(0); }
OBJ primDigitalPins(OBJ *args) { return int2obj(0); }
OBJ primAnalogRead(int argCount, OBJ *args) { return int2obj(0); }
void primAnalogWrite(OBJ *args) { }
OBJ primDigitalRead(int argCount, OBJ *args) { return int2obj(0); }
void primDigitalWrite(OBJ *args) { }
void primDigitalSet(int pinNum, int flag) { };
#endif

// Stubs for other functions not used on Linux

void addSerialPrims() {}
void addHIDPrims() {}
void addOneWirePrims() {}
void processFileMessage(int msgType, int dataSize, char *data) {}
void resetServos() {}
void stopPWM() {}
void systemReset() {}
void turnOffPins() {}
void stopServos() {}

// Persistence support

char *codeFileName = "ublockscode";
FILE *codeFile;

void initCodeFile(uint8 *flash, int flashByteCount) {
	codeFile = fopen(codeFileName, "ab+");
	fseek(codeFile, 0 , SEEK_END);
	long fileSize = ftell(codeFile);

	// read code file into simulated Flash:
	fseek(codeFile, 0L, SEEK_SET);
	long bytesRead = fread((char*) flash, 1, flashByteCount, codeFile);
	if (bytesRead != fileSize) {
		outputString("initCodeFile did not read entire file");
	}
}

void writeCodeFile(uint8 *code, int byteCount) {
	fwrite(code, 1, byteCount, codeFile);
	fflush(codeFile);
}

void writeCodeFileWord(int word) {
	fwrite(&word, 1, 4, codeFile);
	fflush(codeFile);
}

void clearCodeFile(int ignore) {
	fclose(codeFile);
	remove(codeFileName);
	codeFile = fopen(codeFileName, "ab+");
	uint32 cycleCount = ('S' << 24) | 1; // Header record, version 1
	fwrite((uint8 *) &cycleCount, 1, 4, codeFile);
}

// Debug

void segfault() {
	printf("-- VM crashed --\n");
	exitGracefully();
}

// Linux Main

int main(int argc, char *argv[]) {
	codeFileName = "ublockscode"; // to do: allow code file name from command line

	if (argc > 1) {
		codeFileName = argv[1];
		printf("codeFileName: %s\n", codeFileName);
	}
	signal(SIGSEGV, segfault);
	signal(SIGINT, exit);
	atexit(exitGracefully);
	openPseudoTerminal();
	printf(
		"Starting Linux MicroBlocks... Connect on %s\n",
		(char*) ptsname(pty));
#ifdef ARDUINO_RASPBERRY_PI
	wiringPiSetup();
	initPins();
#endif
	initTimers();
	memInit(10000); // 10k words = 40k bytes
	primsInit();
	outputString("Welcome to uBlocks for Linux!");
	restoreScripts();
	startAll();
	vmLoop();
	return 0;
}
