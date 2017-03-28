// wordCodeTest.c - Simple interpreter based on 16-bit opcodes.
// John Maloney, October, 2013

#include "mem.h"
#include "interp.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef __arm__
	#include <objects.h>
	#include <analogout_api.h>
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

// vars and literal indices for findPrimes

#define primeCount 0
#define flags 1
#define i 2
#define j 3
#define literal8190 2
#define literal8188 3

void initLiterals() {
	literals[0] = 10000000; // loop counter, not int obj
	literals[1] = (int) int2obj(1000000);
	literals[2] = (int) int2obj(8190);
	literals[3] = 8188; // loop counter, not int obj
	literals[4] = 1000000; // loop counter, not int obj
}

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
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 0), // n = 0
	OP(pushImmediate, 10), // loop counter

	OP(pushImmediate, (int) int2obj(1)), // loop body start
	OP(changeVarBy, 0), // n++
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
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 0),

	OP(pushImmediate, 1000000), // push repeat count
	OP(pushImmediate, (int) int2obj(1)),
	OP(changeVarBy, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

int sumTest[] = {
	// This version calls primAdd and primLess primitives.

	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 0), // sum
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 1), // i

	OP(jmp, 10), // jump to loop test

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, (int) int2obj(1)), // OP(pushVar, 1),
	OP(primitive, 2),
	(int) primAdd,
	OP(popVar, 0),

	OP(pushVar, 1),
	OP(pushImmediate, (int) int2obj(1)),
	OP(primitive, 2),
	(int) primAdd,
	OP(popVar, 1),

	// loop test:
	OP(pushVar, 1),
	OP(pushImmediate, (int) int2obj(1000000)),
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

	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 0), // sum
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 1), // i

	OP(jmp, 8), // jump to loop test

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, (int) int2obj(1)),
	OP(add, 0),
	OP(popVar, 0),

	OP(pushVar, 1),
	OP(pushImmediate, (int) int2obj(1)),
	OP(add, 0),
	OP(popVar, 1),

	// loop test:
	OP(pushVar, 1),
	OP(pushImmediate, (int) int2obj(1000000)),
	OP(lessThan, 0),
	OP(jmpTrue, -12),

// 	OP(pushVar, 0),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int sumTestWithRepeat[] = {
	// Calls primAdd
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, 1000000), // push repeat count

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, (int) int2obj(1)),
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
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, 1000000), // push repeat count

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, (int) int2obj(1)),
	OP(add, 0),
	OP(popVar, 0),
	OP(decrementAndJmp, -5),

// 	OP(pushVar, 0),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int findPrimes[] = {
	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, primeCount),

	OP(pushConstant, literal8190),
	OP(primitive, 1),
	(int) primnewArray,
	OP(popVar, flags),

	OP(pushVar, flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitive, 2),
	(int) primArrayAtAllPut,

	OP(pushImmediate, (int) int2obj(2)),
	OP(popVar, i),

	OP(pushConstant, literal8188), // push repeat count
	OP(pushVar, flags), // repeatLoopStart
	OP(pushVar, i),
	OP(primitive, 2),
	(int) primArrayAt,
	OP(jmpFalse, 23), // jmpFalse ifEnd

	OP(pushVar, i),
	OP(primitiveNoResult, 1),
	(int) primPrint,

	OP(pushImmediate, (int) int2obj(1)),
	OP(changeVarBy, primeCount),

	OP(pushImmediate, (int) int2obj(2)),
	OP(pushVar, i),
	OP(primitive, 2),
	(int) primMul,
	OP(popVar, j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, flags), // whileLoopStart
	OP(pushVar, j),
	OP(pushImmediate, (int) falseObj),
	OP(primitiveNoResult, 3),
	(int) primArrayAtPut,

	OP(pushVar, i),
	OP(changeVarBy, j),

	OP(pushVar, j), // whileEndTest
	OP(pushConstant, literal8190),
	OP(primitive, 2),
	(int) primLess,
	OP(jmpTrue, -12), // jmpTrue whileLoopStart

	OP(pushImmediate, (int) int2obj(1)), // ifEnd
	OP(changeVarBy, i),

	OP(decrementAndJmp, -31), // decrementAndJmp, repeatLoopStart

// 	OP(pushVar, primeCount),
// 	OP(primitiveNoResult, 1),
// 	(int) primPrint,

	OP(halt, 0),
};

int primes1000[] = {
	OP(pushConstant, literal8190),
	OP(primitive, 1),
	(int) primnewArray,
	OP(popVar, flags),

	OP(pushImmediate, 10), // outer loop counter

	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, primeCount),

	OP(pushVar, flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitiveNoResult, 2),
	(int) primArrayAtAllPut,

	OP(pushImmediate, (int) int2obj(2)),
	OP(popVar, i),

	OP(pushConstant, literal8188), // push repeat count
	OP(pushVar, flags), // repeatLoopStart
	OP(pushVar, i),
	OP(primitive, 2),
	(int) primArrayAt,
	OP(jmpFalse, 20), // jmpFalse ifEnd

	OP(pushImmediate, (int) int2obj(1)),
	OP(changeVarBy, primeCount),

	OP(pushImmediate, (int) int2obj(2)),
	OP(pushVar, i),
	OP(primitive, 2),
	(int) primMul,
	OP(popVar, j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, flags), // whileLoopStart
	OP(pushVar, j),
	OP(pushImmediate, (int) falseObj),
	OP(primitiveNoResult, 3),
	(int) primArrayAtPut,

	OP(pushVar, i),
	OP(changeVarBy, j),

	OP(pushVar, j), // whileEndTest
	OP(pushConstant, literal8190),
	OP(primitive, 2),
	(int) primLess,
	OP(jmpTrue, -12), // jmpTrue whileLoopStart

	OP(pushImmediate, (int) int2obj(1)), // ifEnd
	OP(changeVarBy, i),

	OP(decrementAndJmp, -28), // decrementAndJmp, repeatLoopStart

	OP(pushVar, primeCount),
	OP(primitiveNoResult, 1),
	(int) primPrint,

	OP(decrementAndJmp, -41), // decrementAndJmp, outerRepeatLoopStart
// 	OP(decrementAndJmp, -38), // decrementAndJmp, outerRepeatLoopStart

	OP(halt, 0),
};

int primes1000_2[] = {
	OP(pushConstant, literal8190),
	OP(primitive, 1),
	(int) primnewArray,
	OP(popVar, flags),

	OP(pushImmediate, 10), // outer loop counter

	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, primeCount),

	OP(pushVar, flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitiveNoResult, 2),
	(int) primArrayAtAllPut,

	OP(pushImmediate, (int) int2obj(2)),
	OP(popVar, i),

	OP(pushConstant, literal8188), // push repeat count
	OP(pushVar, flags), // repeatLoopStart
	OP(pushVar, i),
	OP(primitive, 2),
	(int) primArrayAt,
	OP(jmpFalse, 18), // jmpFalse ifEnd

	OP(pushImmediate, (int) int2obj(1)),
	OP(changeVarBy, primeCount),

	OP(pushImmediate, (int) int2obj(2)),
	OP(pushVar, i),
	OP(multiply, 0),
	OP(popVar, j),

	OP(jmp, 7), // jmp whileEndTest
	OP(pushVar, flags), // whileLoopStart
	OP(pushVar, j),
	OP(pushImmediate, (int) falseObj),
	OP(primitiveNoResult, 3),
	(int) primArrayAtPut,

	OP(pushVar, i),
	OP(changeVarBy, j),

	OP(pushVar, j), // whileEndTest
	OP(pushConstant, literal8190),
	OP(lessThan, 0),
	OP(jmpTrue, -11), // jmpTrue whileLoopStart

	OP(pushImmediate, (int) int2obj(1)), // ifEnd
	OP(changeVarBy, i),

	OP(decrementAndJmp, -26), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -36), // decrementAndJmp, outerRepeatLoopStart

	OP(halt, 0),
};

int primes1000_3[] = {
	OP(pushConstant, literal8190),
	OP(primitive, 1),
	(int) primnewArray,
	OP(popVar, flags),

	OP(pushImmediate, 10), // outer loop counter

	OP(pushImmediate, (int) int2obj(0)),
	OP(popVar, primeCount),

	OP(pushVar, flags),
	OP(pushImmediate, (int) trueObj),
	OP(primitiveNoResult, 2),
	(int) primArrayAtAllPut,

	OP(pushImmediate, (int) int2obj(2)),
	OP(popVar, i),

	OP(pushConstant, literal8188), // push repeat count
	OP(pushVar, flags), // repeatLoopStart
	OP(pushVar, i),
	OP(at, 0),
	OP(jmpFalse, 17), // jmpFalse ifEnd

	OP(pushImmediate, (int) int2obj(1)),
	OP(changeVarBy, primeCount),

	OP(pushImmediate, (int) int2obj(2)),
	OP(pushVar, i),
	OP(multiply, 0),
	OP(popVar, j),

	OP(jmp, 6), // jmp whileEndTest
	OP(pushVar, flags), // whileLoopStart
	OP(pushVar, j),
	OP(pushImmediate, (int) falseObj),
	OP(atPut, 0),

	OP(pushVar, i),
	OP(changeVarBy, j),

	OP(pushVar, j), // whileEndTest
	OP(pushConstant, literal8188),
	OP(lessThan, 0),
	OP(jmpTrue, -10), // jmpTrue whileLoopStart

	OP(pushImmediate, (int) int2obj(1)), // ifEnd
	OP(changeVarBy, i),

	OP(decrementAndJmp, -24), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -34), // decrementAndJmp, outerRepeatLoopStart

	OP(halt, 0),
};

#ifdef __arm__

#define START_TICKS() { /* noop */ }
#define TICKS() (us_ticker_read())

dac_t dacRecord;

static void initDAC() { analogout_init(&dacRecord, p18); }
static void writeDAC(float aFloat) { analogout_write(&dacRecord, aFloat); }

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

static void initDAC() { /* noop */ }
static void writeDAC(aFloat) { /* noop */ }

#endif

// Timer

unsigned timerStart;

#define START_TIMER() { timerStart = TICKS(); }
#define TIMER_US() (TICKS() - timerStart)

// DAC Test

void sawtooth2(int freq, float secs) {
	float delay = (1000000.0 / (freq * 100));
	printf("freq %d delay %f\r\n", freq, delay);

	unsigned long now = TICKS();
	unsigned long end = (now + (int) (secs * 1000000));
	float nextT = now;

	int sample = 0;
	while (now < end) {
		if (now >= nextT) {
			sample += 1;
		if (sample >= 100) sample = 0;
			writeDAC(sample / 2000.0);
			nextT += delay;
		}
		now = TICKS();
	}
}

void sawtooth3(int delay, float secs) {
	printf("delay %d usecs\r\n", delay);

	int *dac = (void *) 0x4008C000;

	unsigned long now = TICKS();
	unsigned long end = (now + (int) (secs * 1000000));
	unsigned long nextT = now;

	int sample = 0;
	while (now < end) {
		if (now >= nextT) {
			sample += 1;
			if (sample >= 100) sample = 0;
			unsigned long before = TICKS() - now;
//			writeDAC(sample / 2000.0);
			*dac = (sample << 7) & 0x3FFF;
			unsigned long after = TICKS() - now;
			if ((before > (now + 1)) || (after > (now + 2))) {
			   printf("before %d after %d \r\n", before, after);
			}
			nextT += delay;
		}
		now = TICKS();
	}
}

int main(int argc, char *argv[]) {
	int n, usecs, emptyLoopTime;

	memInit(5000);
	initLiterals();
	initDAC();

// 	for (int freq = 220; freq < 880; freq += 10) {
// 		printf("freq %d\r\n", freq);
// 		sawtooth2(freq, 0.2);
// 	}
	for (int delay = 15; delay >= 0; delay += -1) {
		sawtooth3(delay, 0.3);
	}
	return 0;

	for (int v = 1; v < 4; v++) {
		printf("\r\nIntpreter %d results:\r\n", v);

		START_TIMER();
		runProg(v, emptyLoop);
		usecs = TIMER_US();
		emptyLoopTime = usecs;
		n = 1000002;
		printf("empty loop: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		START_TIMER();
		runProg(v, loopWithNoops);
		usecs = TIMER_US() - emptyLoopTime;
		n = 10000000; // number of noops executed
		printf("noop loop: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		START_TIMER();
		runProg(v, loopTest);
		usecs = TIMER_US();
		n = 3000006;
		printf("loopTest: %d usecs %f\r\n", usecs, ((double) usecs) / n);

continue;

		START_TIMER();
		runProg(v, sumTest);
		usecs = TIMER_US();
		n = 10000002;
		printf("sumTest: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		START_TIMER();
		runProg(v, sumTest2);
		usecs = TIMER_US();
		n = 12000012;
		printf("sumTest2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		START_TIMER();
		runProg(v, sumTestWithRepeat);
		usecs = TIMER_US();
		n = 5000006;
		printf("sumTestWithRepeat: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		START_TIMER();
		runProg(v, sumTestWithRepeat2);
		usecs = TIMER_US();
		n = 5000006;
		printf("sumTestWithRepeat2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		START_TIMER();
		runProg(v, primes1000);
		usecs = TIMER_US();
		n = 2554645;
		printf("primes1000: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		memClear();
		START_TIMER();
		runProg(v, primes1000_2);
		usecs = TIMER_US();
		n = 2554645;
		printf("primes1000_2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		memClear();
		START_TIMER();
		runProg(v, primes1000_3);
		usecs = TIMER_US();
		printf("primes1000_3: %d usecs\r\n", usecs);
	}
	return 0;
}
