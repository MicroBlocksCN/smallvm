// interTests1.c - Test interpreter.
// John Maloney, April 2017

#include <stdio.h>
#include "mem.h"
#include "interp.h"

#ifdef __arm__
	#ifdef ARDUINO
		#include "Arduino.h"
		#define TICKS() (micros())
		void debug(char *s) { Serial.println(s); }
	#else
		#include <us_ticker_api.h>
		#define TICKS() (us_ticker_read())
		void debug(char *s) { printf("%s\r\n", s); }
	#endif
#else
	#include <sys/time.h>
	#include <time.h>
	static inline unsigned TICKS() {
		struct timeval now;
		gettimeofday(&now, NULL);
		return ((1000000L * now.tv_sec) + now.tv_usec) & 0xFFFFFFFF;
	}
	void debug(char *s) { printf("%s\r\n", s); }
#endif

// test programs

int prog1[] = {
	OP(pushLiteral, 3),
	OP(print, 1),
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
	OP(print, 1),
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
	OP(print, 2),
	OP(pop, 1),
	OP(decrementAndJmp, -7),

	OP(halt, 0),

	HEADER(StringClass, 1), // "N ="
	0x3d204e,
};

int emptyLoop[] = {
	OP(pushImmediate, int2obj(1000000)), // push repeat count
	OP(decrementAndJmp, -1),
	OP(halt, 0),
};

int loopWithNoops[] = {
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

int loopTest[] = {
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0),

	OP(pushImmediate, int2obj(1000000)), // push repeat count
	OP(pushImmediate, int2obj(1)),
	OP(incrementVar, 0),
	OP(decrementAndJmp, -3),

	OP(halt, 0),
};

int sumTest[] = {
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

// OP(pushVar, 0),
// OP(print, 1),
// OP(pop, 1),

	OP(halt, 0),
};

int sumTestWithRepeat[] = {
	// Uses the internal add opcode
	OP(pushImmediate, int2obj(0)),
	OP(popVar, 0), // total = 0

	OP(pushImmediate, int2obj(1000000)), // push repeat count

	// loop body:
	OP(pushVar, 0),
	OP(pushImmediate, int2obj(1)),
	OP(add, 0),
	OP(popVar, 0),
	OP(decrementAndJmp, -5),

// OP(pushVar, 0),
// OP(print, 1),
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
// OP(print, 1),
// OP(pop, 1),

	OP(halt, 0),
};

// symbolic var names for findPrimes

#define var_primeCount 0
#define var_flags 1
#define var_i 2
#define var_j 3

int findPrimes[] = {
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
	OP(print, 1),
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
	OP(print, 1),
	OP(pop, 1),

	OP(halt, 0),
};

int primes1000[] = {
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
	OP(multiply, 0),
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
	OP(lessThan, 0),
	OP(jmpTrue, -11), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -25), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -35), // decrementAndJmp, outerRepeatLoopStart

// 	OP(pushVar, var_primeCount),
// 	OP(print, 1),
// 	OP(pop, 1),

	OP(halt, 0),
};

// Timer

unsigned timerStart;

#define START_TIMER() { timerStart = TICKS(); }
#define TIMER_US() (TICKS() - timerStart)

void printResult(char *testName, int usecs, float nanoSecsPerInstruction) {
	float cyclesPerNanosec = 0.064; // clock rate divided by 10e9
	float cyclesPerOp = cyclesPerNanosec * nanoSecsPerInstruction;
#ifdef ARDUINO
	Serial.print(testName);
	Serial.print(": ");
	Serial.print(usecs);
	Serial.print(" usecs, ");
	Serial.print(nanoSecsPerInstruction, 0);
	Serial.print(" nsecs/op ");
	Serial.print(cyclesPerOp, 2);
	Serial.println(" cycles/op");
#else
	printf("%s: %d usecs (%.2f nsecs, %.2f cycles per op)\r\n",
		testName, usecs, nanoSecsPerInstruction, cyclesPerOp);
#endif
}

void interpTests1() {
	unsigned long n, usecs, emptyLoopTime;

	START_TIMER();
	runProg(emptyLoop);
	usecs = TIMER_US();
	emptyLoopTime = usecs;
	n = 1000002;
	printResult("empty loop", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(loopWithNoops);
	usecs = TIMER_US() - emptyLoopTime;
	n = 10000000; // number of noops executed
	printResult("noop loop", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(loopTest);
	usecs = TIMER_US();
	n = 3000004;
	printResult("loopTest", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTest);
	usecs = TIMER_US();
	n = 12000010;
	printResult("sumTest", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeat);
	usecs = TIMER_US();
	n = 5000004;
	printResult("sumTestWithRepeat", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeatAndIncrement);
	usecs = TIMER_US();
	n = 3000004;
	printResult("sumTestWithRepeatAndIncrement", usecs, (1000.0 * usecs) / n);

return;

	// The following test requires ~32kbytes (or ~8k if using a byte array for flags)
	// and thus do not run on boards with limited RAM such as the micro:bit.

	START_TIMER();
	runProg(primes1000);
	usecs = TIMER_US();
	n = 2554625;
	printResult("primes1000", usecs, (1000.0 * usecs) / n);

}
