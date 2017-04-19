// interTests1.c - Test interpreter.
// John Maloney, April 2017

#include <stdio.h>

#include "mem.h"
#include "interp.h"
#include "runtime.h"

void runTasksUntilDone();

// test programs

int prog1[] = {
	OP(pushLiteral, 3),
	OP(printIt, 1),
	OP(pop, 1),
	OP(halt, 0),

	HEADER(StringClass, 4), // "Hello, uBlocks!"
	0x6c6c6548,
	0x75202c6f,
	0x636f6c42,
	0x21736b,
};


int prog2[] = {
	OP(pushImmediate, int2obj(10)), // loop counter
	OP(pushLiteral, 4),
	OP(printIt, 1),
	OP(pop, 1),
	OP(decrementAndJmp, -4),
	OP(halt, 0),

	HEADER(StringClass, 2), // "Hello!"
	0x6c6c6548,
	0x216f,
};

int prog3[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // n = 0
	OP(pushImmediate, int2obj(10)), // loop counter

	OP(pushImmediate, int2obj(1)), // loop body start
	OP(incrementVar, 0), // n++
	OP(pushLiteral, 5),
	OP(pushVar, 0), // push n
	OP(printIt, 2),
	OP(pop, 1),
	OP(decrementAndJmp, -7),

	OP(halt, 0),

	HEADER(StringClass, 1), // "N ="
	0x3d204e,
};

int sum50k[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, int2obj(50000)), // push repeat count

	// loop body:
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

int sum100k[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, int2obj(100000)), // push repeat count

	// loop body:
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

int sum200k[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, int2obj(200000)), // push repeat count

	// loop body:
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

// Helper

static uint8 nextChunkIndex = 0;

void startTask(int* prog, int byteCount) {
	storeCodeChunk(nextChunkIndex, 0, byteCount, (uint8 *) prog);
	startTaskForChunk(nextChunkIndex);
	nextChunkIndex++;
}

// Timer

static unsigned timerStart;

#define START_TIMER() { timerStart = TICKS(); }
#define TIMER_US() (TICKS() - timerStart)

int main(int argc, char *argv[]) {
	int usecs;

	printf("\r\nStarting 2...\r\n");
	memInit(5000);

	START_TIMER();
	for (int i = 0; i < 200000; i++) TICKS();
	printf("200k calls to TICKS() took %d usecs\r\n", (int) TIMER_US());

	initTasks();
	startTask(prog2, sizeof(prog2));
	startTask(prog3, sizeof(prog3));
	runTasksUntilDone();

	// four tasks, 50k iterations each
	initTasks();
	startTask(sum50k, sizeof(sum50k));
	startTask(sum50k, sizeof(sum50k));
	startTask(sum50k, sizeof(sum50k));
	startTask(sum50k, sizeof(sum50k));

	START_TIMER();
	runTasksUntilDone();
	usecs = TIMER_US();
	printf("Four 50k tasks in parallel %d usecs\r\n", usecs);

	// single task 200k iterations
	initTasks();
	startTask(sum200k, sizeof(sum200k));

	START_TIMER();
	runTasksUntilDone();
	usecs = TIMER_US();
	printf("One 200k task %d usecs\r\n", usecs);

	return 0;
}
