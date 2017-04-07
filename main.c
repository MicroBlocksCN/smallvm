// main.c - Test interpreter.
// John Maloney, April 2017

#include "mem.h"
#include "interp.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef __arm__
	#include <us_ticker_api.h>
#else
	#include <sys/time.h>
	#include <time.h>
#endif

// additional primitives

void primHello(OBJ args[]) {
	printf("hello(%d, %d)\r\n",
		(isInt(args[0]) ? obj2int(args[0]) : (int) args[0]),
		(isInt(args[1]) ? obj2int(args[1]) : (int) args[1]));
}

// var index names for findPrimes

#define var_primeCount 0
#define var_flags 1
#define var_i 2
#define var_j 3

// test programs

int prog1[] = {
	OP(primitiveNoResult, 0),
	(int) primHello,
	OP(halt, 0),
};

int prog2[] = {
	OP(pushImmediate, 10), // loop counter
	OP(primitiveNoResult, 0),
	(int) primHello,
	OP(decrementAndJmp, -3),
	OP(halt, 0),
};

int prog3[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // n = 0
	OP(pushImmediate, 10), // loop counter

	OP(pushImmediate, int2obj(1)), // loop body start
	OP(incrementVar, 0), // n++
	OP(pushVar, 0), // push n
	OP(primitiveNoResult, 1),
	(int) primHello,
	OP(decrementAndJmp, -6),

	OP(halt, 0),
};

int emptyLoop[] = {
	OP(pushImmediate, 1000000), // push repeat count
	OP(decrementAndJmp, -1),
	OP(halt, 0),
};

int loopWithNoops[] = {
	// Like emptyLoop but with 10 noop's in the body; used to measure dispatch overhead
	OP(pushImmediate, 1000000), // push repeat count
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

int loopTest[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0),

	OP(pushImmediate, 1000000), // push repeat count
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

int sumTest[] = {
	// This version calls primAdd and primLess primitives.

	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // sum
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 1), // i

	OP(jmp, 10), // jump to loop test

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)), // OP(pushVar, 1),
	OP(primitive, 2),
	(int) primAdd,
	OP(popVar, 0),

	OP(pushVar, 1),
	OP(pushImmediate, int2obj(1)),
	OP(primitive, 2),
	(int) primAdd,
	OP(popVar, 1),

	// loop test:
	OP(pushVar, 1),
	OP(pushImmediate, int2obj(1000000)),
	OP(primitive, 2),
	(int) primLess,
	OP(jmpTrue, -15),

//	OP(pushVar, 0),
//	OP(primitiveNoResult, 1),
//	(int) primPrint,

	OP(halt, 0),
};

int sumTest2[] = {
	// This version uses internal add and less opcodes rather than primitives.

	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // sum
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 1), // i

	OP(jmp, 8), // jump to loop test

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)),
	OP(add, 0),
	OP(popVar, 0),

	OP(pushVar, 1),
	OP(pushImmediate, int2obj(1)),
	OP(add, 0),
	OP(popVar, 1),

	// loop test:
	OP(pushVar, 1),
	OP(pushImmediate, int2obj(1000000)),
	OP(lessThan, 0),
	OP(jmpTrue, -12),

// 	OP(pushVar, 0),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int sumTestWithRepeat[] = {
	// Calls primAdd
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, 1000000), // push repeat count

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)),
	OP(primitive, 2),
	(int) primAdd,
	OP(popVar, 0),
	OP(decrementAndJmp, -6),

// 	OP(pushVar, 0),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int sumTestWithRepeat2[] = {
	// Uses the internal add opcode
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, 1000000), // push repeat count

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)),
	OP(add, 0),
	OP(popVar, 0),
	OP(decrementAndJmp, -5),

// 	OP(pushVar, 0),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int findPrimes[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, var_primeCount),

	OP(pushImmediate, int2obj(8190)),
	OP(primitive, 1),
	(int) primNewArray,
	OP(popVar, var_flags),

	OP(pushVar, var_flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitive, 2),
	(int) primArrayFill,

	OP(pushImmediate, int2obj(2)),
	OP(popVar, var_i),

	OP(pushImmediate, 8188), // push repeat count
	OP(pushVar, var_flags), // repeatLoopStart
	OP(pushVar, var_i),
	OP(primitive, 2),
	(int) primArrayAt,
	OP(jmpFalse, 23), // jmpFalse ifEnd

	OP(pushVar, var_i),
	OP(primitiveNoResult, 1),
	(int) primPrint,

	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, var_primeCount),

	OP(pushImmediate, int2obj(2)),
	OP(pushVar, var_i),
	OP(primitive, 2),
	(int) primMul,
	OP(popVar, var_j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, var_flags), // whileLoopStart
	OP(pushVar, var_j),
	OP(pushImmediate, (int) falseObj),
	OP(primitiveNoResult, 3),
	(int) primArrayAtPut,

	OP(pushVar, var_i),
	OP(incrementVar, var_j),

	OP(pushVar, var_j), // whileEndTest
	OP(pushImmediate, int2obj(8190)),
	OP(primitive, 2),
	(int) primLess,
	OP(jmpTrue, -12), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -31), // decrementAndJmp, repeatLoopStart

// 	OP(pushVar, var_primeCount),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int primes1000[] = {
	// Uses primitives for at, atPut, lessThan, multiply

	OP(pushImmediate, int2obj(8190)),
	OP(primitive, 1),
	(int) primNewArray,
	OP(popVar, var_flags),

	OP(pushImmediate, 10), // outer loop counter

	OP(pushImmediate, int2obj(0)),
	OP(popVar, var_primeCount),

	OP(pushVar, var_flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitiveNoResult, 2),
	(int) primArrayFill,

	OP(pushImmediate, int2obj(2)),
	OP(popVar, var_i),

	OP(pushImmediate, 8188), // push repeat count
	OP(pushVar, var_flags), // repeatLoopStart
	OP(pushVar, var_i),
	OP(primitive, 2),
	(int) primArrayAt,
	OP(jmpFalse, 20), // jmpFalse ifEnd

	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, var_primeCount),

	OP(pushImmediate, int2obj(2)),
	OP(pushVar, var_i),
	OP(primitive, 2),
	(int) primMul,
	OP(popVar, var_j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, var_flags), // whileLoopStart
	OP(pushVar, var_j),
	OP(pushImmediate, (int) falseObj),
	OP(primitiveNoResult, 3),
	(int) primArrayAtPut,

	OP(pushVar, var_i),
	OP(incrementVar, var_j),

	OP(pushVar, var_j), // whileEndTest
	OP(pushImmediate, int2obj(8190)),
	OP(primitive, 2),
	(int) primLess,
	OP(jmpTrue, -12), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -28), // decrementAndJmp, repeatLoopStart
 	OP(decrementAndJmp, -38), // decrementAndJmp, outerRepeatLoopStart

	OP(halt, 0),
};

int primes1000_2[] = {
	// Uses primitives for at, atPut; inlines lessThan and multiply

	OP(pushImmediate, int2obj(8190)),
	OP(primitive, 1),
	(int) primNewArray,
	OP(popVar, var_flags),

	OP(pushImmediate, 10), // outer loop counter

	OP(pushImmediate, int2obj(0)),
	OP(popVar, var_primeCount),

	OP(pushVar, var_flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitiveNoResult, 2),
	(int) primArrayFill,

	OP(pushImmediate, int2obj(2)),
	OP(popVar, var_i),

	OP(pushImmediate, 8188), // push repeat count
	OP(pushVar, var_flags), // repeatLoopStart
	OP(pushVar, var_i),
	OP(primitive, 2),
	(int) primArrayAt,
	OP(jmpFalse, 18), // jmpFalse ifEnd

	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, var_primeCount),

	OP(pushImmediate, int2obj(2)),
	OP(pushVar, var_i),
	OP(multiply, 0),
	OP(popVar, var_j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, var_flags), // whileLoopStart
	OP(pushVar, var_j),
	OP(pushImmediate, (int) falseObj),
	OP(primitiveNoResult, 3),
	(int) primArrayAtPut,

	OP(pushVar, var_i),
	OP(incrementVar, var_j),

	OP(pushVar, var_j), // whileEndTest
	OP(pushImmediate, int2obj(8190)),
	OP(lessThan, 0),
	OP(jmpTrue, -11), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -26), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -36), // decrementAndJmp, outerRepeatLoopStart

	OP(halt, 0),
};

int primes1000_3[] = {
	// No primitives inside loops

	OP(pushImmediate, int2obj(8190)),
	OP(primitive, 1),
	(int) primNewArray,
	OP(popVar, var_flags),

	OP(pushImmediate, 10), // outer loop counter

	OP(pushImmediate, int2obj(0)),
	OP(popVar, var_primeCount),

	OP(pushVar, var_flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitiveNoResult, 2),
	(int) primArrayFill,

	OP(pushImmediate, int2obj(2)),
	OP(popVar, var_i),

	OP(pushImmediate, 8188), // push repeat count
	OP(pushVar, var_flags), // repeatLoopStart
	OP(pushVar, var_i),
	OP(at, 0),
	OP(jmpFalse, 17), // jmpFalse ifEnd

	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, var_primeCount),

	OP(pushImmediate, int2obj(2)),
	OP(pushVar, var_i),
	OP(multiply, 0),
	OP(popVar, var_j),

	OP(jmp, 6), // jmp whileEndTest
	OP(pushVar, var_flags), // whileLoopStart
	OP(pushVar, var_j),
	OP(pushImmediate, (int) falseObj),
	OP(atPut, 0),

	OP(pushVar, var_i),
	OP(incrementVar, var_j),

	OP(pushVar, var_j), // whileEndTest
	OP(pushImmediate, int2obj(8188)),
	OP(lessThan, 0),
	OP(jmpTrue, -10), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -24), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -34), // decrementAndJmp, outerRepeatLoopStart

// 	OP(pushVar, var_primeCount),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,
// 	OP(decrementAndJmp, -37), // decrementAndJmp, outerRepeatLoopStart

	OP(halt, 0),
};

#ifdef __arm__

#define START_TICKS() { /* noop */ }
#define TICKS() (us_ticker_read())

#else

#include <sys/time.h>
#include <time.h>

struct timeval ticksStart;
#define START_TICKS() { gettimeofday(&ticksStart, NULL); }

static inline unsigned TICKS() {
	struct timeval now;
	gettimeofday(&now, NULL);
	unsigned long long secs = now.tv_sec - ticksStart.tv_sec;
	unsigned long long usecs = now.tv_usec - ticksStart.tv_usec;
	return ((1000000 * secs) + usecs) & 0xFFFFFFFF;
}

#endif

// Timer

unsigned timerStart;

#define START_TIMER() { timerStart = TICKS(); }
#define TIMER_US() (TICKS() - timerStart)

int main(int argc, char *argv[]) {
	int n, usecs, emptyLoopTime;

	memInit(5000);

	START_TIMER();
	runProg(emptyLoop);
	usecs = TIMER_US();
	emptyLoopTime = usecs;
	n = 1000002;
	printf("empty loop: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(loopWithNoops);
	usecs = TIMER_US() - emptyLoopTime;
	n = 10000000; // number of noops executed
	printf("noop loop: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(loopTest);
	usecs = TIMER_US();
	n = 3000006;
	printf("loopTest: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(sumTest);
	usecs = TIMER_US();
	n = 10000002;
	printf("sumTest: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(sumTest2);
	usecs = TIMER_US();
	n = 12000012;
	printf("sumTest2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeat);
	usecs = TIMER_US();
	n = 5000006;
	printf("sumTestWithRepeat: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeat2);
	usecs = TIMER_US();
	n = 5000006;
	printf("sumTestWithRepeat2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	START_TIMER();
	runProg(primes1000);
	usecs = TIMER_US();
	n = 2554645;
	printf("primes1000: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	memClear();
	START_TIMER();
	runProg(primes1000_2);
	usecs = TIMER_US();
	n = 2554645;
	printf("primes1000_2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	memClear();
	START_TIMER();
	runProg(primes1000_3); // this test still has a bug
	usecs = TIMER_US();
	n = 2554345;
	printf("primes1000_3: %d usecs %f\r\n", usecs, ((double) usecs) / n);

	return 0;
}
