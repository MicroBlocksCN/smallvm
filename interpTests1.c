// interTests1.c - Test interpreter.
// John Maloney, April 2017

#include <stdio.h>

#include "mem.h"
#include "interp.h"

// test programs

static int prog1[] = {
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


static int prog2[] = {
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

static int prog3[] = {
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

static int emptyLoop[] = {
	OP(pushImmediate, int2obj(1000000)), // push repeat count
	OP(decrementAndJmp, -1),
	OP(halt, 0),
};

static int loopWithNoops[] = {
	// Like emptyLoop but with 10 noop's in the body; used to measure dispatch overhead
	OP(pushImmediate, int2obj(1000000)), // push repeat count
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(noop, 0),
	OP(decrementAndJmp, -11),
	OP(halt, 0),
};

static int loopTest[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0),

	OP(pushImmediate, int2obj(1000000)), // push repeat count
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

static int sumTest[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // sum
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 1), // i

	OP(jmp, 8), // jump to loop test

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)),
	OP(add, 2),
	OP(popVar, 0),

	OP(pushVar, 1),
	OP(pushImmediate, int2obj(1)),
	OP(add, 2),
	OP(popVar, 1),

	// loop test:
	OP(pushVar, 1),
	OP(pushImmediate, int2obj(1000000)),
	OP(lessThan, 2),
	OP(jmpTrue, -12),

// OP(pushVar, 0),
// OP(printIt, 1),
// OP(pop, 1),

	OP(halt, 0),
};

static int sumTestWithRepeat[] = {
	// Uses the internal add opcode
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, int2obj(1000000)), // push repeat count

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)),
	OP(add, 2),
	OP(popVar, 0),
	OP(decrementAndJmp, -5),

// OP(pushVar, 0),
// OP(printIt, 1),
// OP(pop, 1),

	OP(halt, 0),
};

int sumTestWithRepeatAndIncrement[] = {
	// Like sumTestWithRepeat but uses incrementVar
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, int2obj(1000000)), // push repeat count

	// loop body:
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

// OP(pushVar, 0),
// OP(printIt, 1),
// OP(pop, 1),

	OP(halt, 0),
};

int function1[] = {
	OP(pushLiteral, 15),
	OP(pushArg, 0),
	OP(printIt, 2),
	OP(pop, 1),

	OP(pushArgCount, 0),
	OP(printIt, 1),
	OP(pop, 1),

	OP(pushImmediate, int2obj(42)),
	OP(popLocal, 0),

	OP(pushImmediate, int2obj(5)),
	OP(incrementLocal, 0),

	OP(pushLocal, 0),
	OP(printIt, 1),
	OP(pop, 1),

	OP(pushImmediate, int2obj(17)), // return 17
	OP(returnResult, 0),

	HEADER(StringClass, 2), // "Hello!"
	0x6c6c6548,
	0x216f,
};

int callTest[] = {
	// Call function with chunkIndex 0 three times, and print the three values it returns
	OP(pushImmediate, int2obj(1)),
	CALL(0, 1, 1),
	OP(pushImmediate, int2obj(2)),
	CALL(0, 1, 1),
	OP(pushImmediate, int2obj(3)),
	OP(pushImmediate, int2obj(17)),
	CALL(0, 2, 1),
	OP(printIt, 3),
	OP(pop, 1),
	OP(pushImmediate, int2obj(42)), // return 42
	OP(returnResult, 0),
};

static int microWaitTest[] = {
	OP(pushImmediate, int2obj(10)), // loop counter
	OP(microsOp, 0),
	OP(printIt, 1),
	OP(pop, 1),
	OP(pushImmediate, int2obj(1000000)), // 1 second
	OP(waitMicrosOp, 1),
	OP(pop, 1),
	OP(decrementAndJmp, -7),
//	OP(decrementAndJmp, -4),
	OP(halt, 0),
};

static int milliWaitTest[] = {
	OP(pushImmediate, int2obj(10)), // loop counter
	OP(millisOp, 0),
	OP(printIt, 1),
	OP(pop, 1),
	OP(pushImmediate, int2obj(500)), // 0.5 second
	OP(waitMillisOp, 1),
	OP(pop, 1),
	OP(decrementAndJmp, -7),
//	OP(decrementAndJmp, -4),
	OP(halt, 0),
};

// symbolic var names for findPrimes

#define var_primeCount 0
#define var_flags 1
#define var_i 2
#define var_j 3

static int findPrimes[] = {
	OP(pushImmediate, int2obj(8190)),
	OP(newArray, 1),
	OP(popVar, var_flags),

	OP(pushImmediate, int2obj(0)),
	OP(popVar, var_primeCount),

	OP(pushVar, var_flags),
	OP(pushImmediate, (int) trueObj),
	OP(fillArray, 2),
	OP(pop, 1),

	OP(pushImmediate, int2obj(2)),
	OP(popVar, var_i),

	OP(pushImmediate, int2obj(8188)), // push repeat count
	OP(pushVar, var_flags), // repeatLoopStart
	OP(pushVar, var_i),
	OP(at, 2),
	OP(jmpFalse, 21), // jmpFalse ifEnd

	OP(pushVar, var_i),
	OP(printIt, 1),
	OP(pop, 1),

	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, var_primeCount),

	OP(pushImmediate, int2obj(2)),
	OP(pushVar, var_i),
	OP(multiply, 2),
	OP(popVar, var_j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, var_flags), // whileLoopStart
	OP(pushVar, var_j),
	OP(pushImmediate, (int) falseObj),
	OP(atPut, 3),
	OP(pop, 1),

	OP(pushVar, var_i),
	OP(incrementVar, var_j),

	OP(pushVar, var_j), // whileEndTest
	OP(pushImmediate, int2obj(8190)),
	OP(lessThan, 2),
	OP(jmpTrue, -11), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -28), // decrementAndJmp, repeatLoopStart

	OP(pushVar, var_primeCount),
	OP(printIt, 1),
	OP(pop, 1),

	OP(halt, 0),
};

static int primes1000[] = {
	OP(pushImmediate, int2obj(8190)),
	OP(newArray, 1),
	OP(popVar, var_flags),

	OP(pushImmediate, int2obj(10)), // outer loop counter

	OP(pushImmediate, int2obj(0)),
	OP(popVar, var_primeCount),

	OP(pushVar, var_flags),
	OP(pushImmediate, (int) trueObj),
	OP(fillArray, 2),
	OP(pop, 1),

	OP(pushImmediate, int2obj(2)),
	OP(popVar, var_i),

	OP(pushImmediate, int2obj(8188)), // push repeat count
	OP(pushVar, var_flags), // repeatLoopStart
	OP(pushVar, var_i),
	OP(at, 2),
	OP(jmpFalse, 18), // jmpFalse ifEnd

	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, var_primeCount),

	OP(pushImmediate, int2obj(2)),
	OP(pushVar, var_i),
	OP(multiply, 2),
	OP(popVar, var_j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, var_flags), // whileLoopStart
	OP(pushVar, var_j),
	OP(pushImmediate, (int) falseObj),
	OP(atPut, 3),
	OP(pop, 1),

	OP(pushVar, var_i),
	OP(incrementVar, var_j),

	OP(pushVar, var_j), // whileEndTest
	OP(pushImmediate, int2obj(8190)),
	OP(lessThan, 2),
	OP(jmpTrue, -11), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -25), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -35), // decrementAndJmp, outerRepeatLoopStart

// 	OP(pushVar, var_primeCount),
// 	OP(printIt, 1),
// 	OP(pop, 1),

	OP(halt, 0),
};

// Timer

static unsigned timerStart;

#define START_TIMER() { timerStart = TICKS(); }
#define TIMER_US() (TICKS() - timerStart)

// Helpers

static uint8 nextChunkIndex = 0;

static void runProg(int* prog, int byteCount) {
	initTasks();
	storeCodeChunk(nextChunkIndex, 1, byteCount, (uint8 *) prog);
	startTaskForChunk(nextChunkIndex++);
	runTasksUntilDone();
}

static void printResult(char *testName, int usecs, float nanoSecsPerInstruction) {
	float cyclesPerNanosec = 0.064; // clock rate divided by 10e9
	float cyclesPerOp = cyclesPerNanosec * nanoSecsPerInstruction;
	printf("%s: %d usecs (%.2f nsecs, %.2f cycles per op)\r\n",
		testName, usecs, nanoSecsPerInstruction, cyclesPerOp);
}

void interpTests1() {
	unsigned long n, usecs, emptyLoopTime;

// 	START_TIMER();
// 	runProg(microWaitTest, sizeof(microWaitTest));
// 	printf("usecs test %d\r\n", (int) TIMER_US());
// 	START_TIMER();
// 	runProg(milliWaitTest, sizeof(milliWaitTest));
// 	printf("msecs test %d\r\n", (int) TIMER_US());
// return;

// 	storeCodeChunk(nextChunkIndex++, 1, sizeof(function1), (uint8 *) function1);
// 	runProg(callTest, sizeof(callTest));
// 	return;

	START_TIMER();
	runProg(emptyLoop, sizeof(emptyLoop));
	usecs = TIMER_US();
	emptyLoopTime = usecs;
	n = 1000002;
	printResult("empty loop", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(loopWithNoops, sizeof(loopWithNoops));
	usecs = TIMER_US() - emptyLoopTime;
	n = 10000000; // number of noops executed
	printResult("noop loop", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(loopTest, sizeof(loopTest));
	usecs = TIMER_US();
	n = 3000004;
	printResult("loopTest", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTest, sizeof(sumTest));
	usecs = TIMER_US();
	n = 12000010;
	printResult("sumTest", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeat, sizeof(sumTestWithRepeat));
	usecs = TIMER_US();
	n = 5000004;
	printResult("sumTestWithRepeat", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeatAndIncrement, sizeof(sumTestWithRepeatAndIncrement));
	usecs = TIMER_US();
	n = 3000004;
	printResult("sumTestWithRepeatAndIncrement", usecs, (1000.0 * usecs) / n);

return;

	// The following test requires ~32kbytes (or ~8k if using a byte array for flags)
	// and thus do not run on boards with limited RAM such as the micro:bit.

	START_TIMER();
	runProg(primes1000, sizeof(primes1000));
	usecs = TIMER_US();
	n = 2554625;
	printResult("primes1000", usecs, (1000.0 * usecs) / n);

}
