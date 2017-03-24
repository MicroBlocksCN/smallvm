// wordCodeTest.c - Simple interpreter based on 16-bit opcodes.
// John Maloney, October, 2013

#include "mbed.h"
#include "mem.h"
#include "interp.h"

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
    literals[0] = 10000000;  // loop counter, not int obj
    literals[1] = (int) int2obj(1000000);
    literals[2] = (int) int2obj(8190);
    literals[3] = 8188; // loop counter, not int obj
    literals[4] = 1000000;  // loop counter, not int obj
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

//     OP(pushVar, 0),
//     OP(primitiveNoResult, 1),
//     (int) primPrint,

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

//     OP(pushVar, 0),
//     OP(primitiveNoResult, 1),
//     (int) primPrint,

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

//     OP(pushVar, 0),
//     OP(primitiveNoResult, 1),
//     (int) primPrint,

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

//     OP(pushVar, 0),
//     OP(primitiveNoResult, 1),
//     (int) primPrint,

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
    OP(pushVar, flags),  // repeatLoopStart
    OP(pushVar, i),
    OP(primitive, 2),
    (int) primArrayAt,
    OP(jmpFalse, 23), // jmpFalse ifEnd

//  OP(pushVar, i),
//  OP(primitiveNoResult, 1),
//  (int) primPrint,

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

    OP(pushImmediate, (int) int2obj(1)),  // ifEnd
    OP(changeVarBy, i),

    OP(decrementAndJmp, -31), // decrementAndJmp, repeatLoopStart

//  OP(pushVar, primeCount),
//  OP(primitiveNoResult, 1),
//  (int) primPrint,

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
    OP(pushVar, flags),  // repeatLoopStart
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

    OP(pushImmediate, (int) int2obj(1)),  // ifEnd
    OP(changeVarBy, i),

    OP(decrementAndJmp, -28), // decrementAndJmp, repeatLoopStart

  OP(pushVar, primeCount),
  OP(primitiveNoResult, 1),
  (int) primPrint,

  OP(decrementAndJmp, -41), // decrementAndJmp, outerRepeatLoopStart
 //   OP(decrementAndJmp, -38), // decrementAndJmp, outerRepeatLoopStart

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
    OP(pushVar, flags),  // repeatLoopStart
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

    OP(pushImmediate, (int) int2obj(1)),  // ifEnd
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
    OP(pushVar, flags),  // repeatLoopStart
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

    OP(pushImmediate, (int) int2obj(1)),  // ifEnd
    OP(changeVarBy, i),

    OP(decrementAndJmp, -24), // decrementAndJmp, repeatLoopStart
    OP(decrementAndJmp, -34), // decrementAndJmp, outerRepeatLoopStart

    OP(halt, 0),
};

static unsigned long lastT = 0;
static unsigned long maxVal = 0;
static int maxDelta = 0;

void readTimer() {
	unsigned long now = us_ticker_read();
	if (lastT) {
		int delta = now - lastT;
		if (delta > maxDelta) maxDelta = delta;
		if (now > maxVal) {
			maxVal = now;
			printf("maxVal %lu\r\n", maxVal);
		}
		if (now < lastT) {
			printf("clock wrapped! %lu -> %lu\r\n", lastT, now);
			maxVal = 0;
		}
	}
	lastT = now;
}

void readTimer2() {
	unsigned long now = us_ticker_read();
	printf("now %lu\r\n", now);
	if (now < lastT) {
		printf("clock wrapped! %lu -> %lu\r\n", lastT, now);
		maxVal = 0;
	}
	lastT = now;
}

int sawtooth(int freq, int secs) {
	AnalogOut out(p18);
	float delay = 1.0 / (freq * 101);

    for (int cycles = (secs * freq); cycles > 0; cycles--) {
        for (int t = 0; t <= 100; t++) {
            out = (float) t / 100; // t goes from 0 to 100 inclusive
			wait(delay);
        }
    }
}

int sawtooth2(int freq, float secs) {
	AnalogOut out(p18);
	int delay = (1000000 / (freq * 100));
	printf("freq %d delay %d\r\n", freq, delay);

	unsigned long now = us_ticker_read();
	unsigned long end = (now + (int) (secs * 1000000));
	unsigned long nextT = now;

    int sample = 0;
	while (now < end) {
	    if (now >= nextT) {
	    	sample += 1;
	    	if (sample >= 100) sample = 0;
			out = sample / 100.0;
			nextT += delay;
	    }
        now = us_ticker_read();
    }
}

int main(int argc, char *argv[]) {
    int n, usecs, emptyLoopTime;
    Timer t;

    memInit(5000);
    initLiterals();

	for (int freq = 440; freq < 1000; freq += 10) {
	    printf("freq %d\r\n", freq);
	    sawtooth2(freq, 0.1);
	}
return 0;

for (int cnt = 0; cnt < 10000000; cnt++) {
	readTimer2();
	wait(60); // seconds
}
printf("maxDelta %d\r\n", maxDelta);
return 0;

    t.start();

    for (int v = 1; v < 4; v++) {
		printf("\r\nIntpreter %d results:\r\n", v);

		t.reset();
		runProg(v, emptyLoop);
		usecs = t.read_us();
		emptyLoopTime = usecs;
		n = 1000002;
		printf("empty loop: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		t.reset();
		runProg(v, loopWithNoops);
		usecs = t.read_us() - emptyLoopTime;
		n = 10000000; // number of noops executed
		printf("noop loop: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		t.reset();
		runProg(v, loopTest);
		usecs = t.read_us();
		n = 3000006;
		printf("loopTest: %d usecs %f\r\n", usecs, ((double) usecs) / n);

continue;

		t.reset();
		runProg(v, sumTest);
		usecs = t.read_us();
		n = 10000002;
		printf("sumTest: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		t.reset();
		runProg(v, sumTest2);
		usecs = t.read_us();
		n = 12000012;
		printf("sumTest2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		t.reset();
		runProg(v, sumTestWithRepeat);
		usecs = t.read_us();
		n = 5000006;
		printf("sumTestWithRepeat: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		t.reset();
		runProg(v, sumTestWithRepeat2);
		usecs = t.read_us();
		n = 5000006;
		printf("sumTestWithRepeat2: %d usecs %f\r\n", usecs, ((double) usecs) / n);


		t.reset();
		runProg(v, primes1000);
		usecs = t.read_us();
		n = 2554645;
		printf("primes1000: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		memClear();
		t.reset();
		runProg(v, primes1000_2);
		usecs = t.read_us();
		n = 2554645;
		printf("primes1000_2: %d usecs %f\r\n", usecs, ((double) usecs) / n);

		memClear();
		t.reset();
		runProg(v, primes1000_3);
		usecs = t.read_us();
		printf("primes1000_3: %d usecs\r\n", usecs);
	}
	return 0;
}
