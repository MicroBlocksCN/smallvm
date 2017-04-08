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

// additional primitives

void primHello(OBJ args[]) {
#ifdef ARDUINO
	Serial.print("hello");
	Serial.print((isInt(args[0]) ? obj2int(args[0]) : (int) args[0]));
	Serial.print((isInt(args[1]) ? obj2int(args[1]) : (int) args[1]));
#else
	printf("hello %d %d\n",
		(isInt(args[0]) ? obj2int(args[0]) : (int) args[0]),
		(isInt(args[1]) ? obj2int(args[1]) : (int) args[1]));
#endif
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

// OP(pushVar, 0),
// OP(primitiveNoResult, 1),
// (int) primPrint,

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

// OP(pushVar, 0),
// OP(primitiveNoResult, 1),
// (int) primPrint,

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

// OP(pushVar, 0),
// OP(primitiveNoResult, 1),
// (int) primPrint,

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

// OP(pushVar, 0),
// OP(primitiveNoResult, 1),
// (int) primPrint,

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

	OP(pushVar, var_primeCount),
	OP(primitiveNoResult, 1),
	(int) primPrint,

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
	OP(pushImmediate, int2obj(8190)),
	OP(lessThan, 0),
	OP(jmpTrue, -10), // jmpTrue whileLoopStart

	OP(pushImmediate, int2obj(1)), // ifEnd
	OP(incrementVar, var_i),

	OP(decrementAndJmp, -24), // decrementAndJmp, repeatLoopStart
	OP(decrementAndJmp, -34), // decrementAndJmp, outerRepeatLoopStart

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
	Serial.print(" nsecs/op");
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
	n = 12000012;
	printResult("sumTest", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTest2);
	usecs = TIMER_US();
	n = 12000012;
	printResult("sumTest2", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeat);
	usecs = TIMER_US();
	n = 5000006;
	printResult("sumTestWithRepeat", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(sumTestWithRepeat2);
	usecs = TIMER_US();
	n = 5000006;
	printResult("sumTestWithRepeat2", usecs, (1000.0 * usecs) / n);

	START_TIMER();
	runProg(primes1000);
	usecs = TIMER_US();
	n = 2554625;
	printResult("primes1000", usecs, (1000.0 * usecs) / n);

	memClear();
	START_TIMER();
	runProg(primes1000_2);
	usecs = TIMER_US();
	n = 2554625;
	printResult("primes1000_2", usecs, (1000.0 * usecs) / n);

	memClear();
	START_TIMER();
	runProg(primes1000_3);
	usecs = TIMER_US();
	n = 2554625;
	printResult("primes1000_3", usecs, (1000.0 * usecs) / n);
}
