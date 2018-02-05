// linux.c - Microblocks for Linux
// An adaptation of raspberryPi.c by John Maloney to
// work on a GNU/Linux TTY as a serial device

// John Maloney, December 2017
// Bernat Romagosa, February 2018

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <unistd.h>

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

static int pty; // pseudo terminal used for communication with the IDE

static void openPseudoTerminal() {
	pty = posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (-1 == pty) {
		perror("Error opening pseudo terminal\n");
		exit(-1);
	}
 	grantpt(pty);
 	unlockpt(pty);
}

int readBytes(uint8 *buf, int count) {
	int readCount = read(pty, buf, count);
	if (readCount < 0) readCount = 0;
	return readCount;
}

int canReadByte() {
	int bytesAvailable;
	ioctl(pty, FIONREAD, &bytesAvailable);
	return (bytesAvailable > 0);
}

int canSendByte() { return true; }

void sendByte(char aByte) {
//printf("byte %d %c\n", aByte, ((aByte > 0) ? aByte : ' '));
	write(pty, &aByte, 1);
}

// System Functions

const char * boardType() { return "Linux Computer"; }
void systemReset() { } // noop on Linux

// Stubs for IO primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(0); }
OBJ primDigitalPins(OBJ *args) { return int2obj(0); }
OBJ primAnalogRead(OBJ *args) { return int2obj(0); }
OBJ primAnalogWrite(OBJ *args) { return nilObj; }
OBJ primDigitalRead(OBJ *args) { return nilObj; }
OBJ primDigitalWrite(OBJ *args) { return nilObj; }
OBJ primSetLED(OBJ *args) { return nilObj; }
OBJ primI2cGet(OBJ *args) { return nilObj; }
OBJ primI2cSet(OBJ *args) { return nilObj; }
OBJ primSPISend(OBJ *args) { return nilObj; }
OBJ primSPIRecv(OBJ *args) { return nilObj; }

// Bogus micro:bit primitives

OBJ primMBDisplay(OBJ *args) { return nilObj; }
OBJ primMBDisplayOff(OBJ *args) { return nilObj; }
OBJ primMBPlot(OBJ *args) { return nilObj; }
OBJ primMBUnplot(OBJ *args) { return nilObj; }
OBJ primMBTiltX(OBJ *args) { return nilObj; }
OBJ primMBTiltY(OBJ *args) { return nilObj; }
OBJ primMBTiltZ(OBJ *args) { return nilObj; }
OBJ primMBTemp(OBJ *args) { return nilObj; }
OBJ primMBButtonA(OBJ *args) { return nilObj; }
OBJ primMBButtonB(OBJ *args) { return nilObj; }

// Linux Main

int main() {
	openPseudoTerminal();
    printf("Starting Linux MicroBlocks... Connect on %s\n", ptsname(pty));
    initTimers();
    memInit(10000); // 10k words = 40k bytes
    initTasks();
	restoreScripts();
    outputString("Welcome to uBlocks for Linux!");
    vmLoop();
    return 0;
}
