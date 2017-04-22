// interp.c - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "runtime.h"

// Interpreter State

static OBJ vars[25];
static OBJ stack[25];

// Interpreter Helper Functions

static void printObj(OBJ obj) {
	if (isInt(obj)) printf("%d", obj2int(obj));
	else if (obj == nilObj) printf("nil");
	else if (obj == trueObj) printf("true");
	else if (obj == falseObj) printf("false");
	else if (objClass(obj) == StringClass) {
		printf("%s", obj2str(obj));
	} else {
		printf("OBJ(addr: %d, class: %d)", (int) obj, objClass(obj));
	}
}

static inline int evalInt(OBJ obj) {
	if (isInt(obj)) return obj2int(obj);
	printf("evalInt got non-integer: ");
	printObj(obj);
	printf("\n");
	return 0;
}

void showStack(OBJ *sp, OBJ *fp) {
	OBJ *ptr = sp;
	printf("sp: %d\n", (int) *ptr);
	while (--ptr >= &stack[0]) {
		printf("%s %d\n", ((fp == ptr) ? "fp:" : ""), (int) *ptr);
	}
	printf("-----\n");
}

// Primitives

OBJ failure(const char *reason) {
	// Print a message and stop the interpreter.
	printf("Primitive failed: %s\n", reason);
	return 0;
}

OBJ sizeFailure() { return failure("Size must be a positive integer"); }
OBJ arrayClassFailure() { return failure("Must must be an Array"); }
OBJ indexClassFailure() { return failure("Index must be an integer"); }
OBJ outOfRangeFailure() { return failure("Index out of range"); }

OBJ primPrint(int argCount, OBJ args[]) {
	for (int i = 0; i < argCount; i++) {
		printObj(args[i]);
		printf(" ");
	}
	printf("\n");
	return nilObj;
}

OBJ primNewArray(OBJ args[]) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return sizeFailure();
// hack for primes benchmark: use byte array to simulate array of booleans
	OBJ result = newObj(ArrayClass, (obj2int(n) + 3) / 4, nilObj); // bytes
	return result;
}

OBJ primArrayAt(OBJ args[]) {
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	OBJ index = args[1];
	if (!isInt(index)) return indexClassFailure();

	int i = obj2int(index);
	if ((i < 1) || (i > (objWords(array) * 4))) { return outOfRangeFailure(); }
// hack for primes benchmark: use byte array to simulate array of booleans
	char *bytes = (char *) array;
	return (bytes[(4 * HEADER_WORDS) + (i - 1)]) ? trueObj : falseObj;
}

OBJ primArrayAtPut(OBJ args[]) {
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	OBJ index = args[1];
	if (!isInt(index)) return indexClassFailure();
	OBJ value = args[2];

	int i = obj2int(index);
	if ((i < 1) || (i > (objWords(array) * 4))) return outOfRangeFailure();

// hack for primes benchmark: use byte array to simulate array of booleans
	char *bytes = (char *) array;
	bytes[(4 * HEADER_WORDS) + (i - 1)] = (value == trueObj);
	return nilObj;
}

OBJ primArrayFill(OBJ args[]) {
	OBJ array = args[0];
	if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
	OBJ value = args[1];

	value = (OBJ) ((value == trueObj) ? 0x01010101 : 0); // hack to encode flag array as bytes

	int end = objWords(array) + HEADER_WORDS;
	for (int i = HEADER_WORDS; i < end; i++) ((OBJ *) array)[i] = value;
	return nilObj;
}

// Interpreter

// Macro to inline dispatch in the end of each opcode (avoiding a jump back to the top)
#define DISPATCH() { \
	op = *ip++; \
	arg = ARG(op); \
/*	printf("ip: %d cmd: %d arg: %d sp: %d\n", (ip - task->code), CMD(op), arg, (sp - stack)); */ \
	goto *jumpTable[CMD(op)]; \
}

static inline int runTask(Task *task) {
	register int *ip;
	register OBJ *sp;
	register int op;
	int arg, tmp;
	OBJ array;

	// Restore task state
	ip = task->code + task->ip;
	sp = task->stack + task->sp;

	// initialize jump table (padded to 32 entries since op is 5 bits)
	static void *jumpTable[] = {
		&&halt_op,
		&&noop_op,
		&&pushImmediate_op,
		&&pushBigImmediate_op,
		&&pushLiteral_op,
		&&pushVar_op,
		&&popVar_op,
		&&incrementVar_op,
		&&pop_op,
		&&jmp_op,
		&&jmpTrue_op,
		&&jmpFalse_op,
		&&decrementAndJmp_op,
		&&callFunction_op,
		&&returnResult_op,
		&&add_op,
		&&subtract_op,
		&&multiply_op,
		&&divide_op,
		&&lessThan_op,
		&&printIt_op,
		&&at_op,
		&&atPut_op,
		&&newArray_op,
		&&fillArray_op,
		&&analogRead_op,
		&&analogWrite_op,
		&&digitalRead_op,
		&&digitalWrite_op,
		&&micros_op,
		&&millis_op,
		&&peek_op,
		&&poke_op,
	};

	DISPATCH();

	suspend:
		// save task state
		task->ip = ip - task->code;
		task->sp = sp - task->stack;
		return task->status;
	halt_op:
		task->status = done;
		goto suspend;
	noop_op:
		DISPATCH();
	pushImmediate_op:
		*sp++ = (OBJ) arg;
		DISPATCH();
	pushBigImmediate_op:
		*sp++ = (OBJ) *ip++;
		DISPATCH();
	pushLiteral_op:
		*sp++ = (OBJ) (ip + arg); // arg is offset from the current ip to the literal object
		DISPATCH();
	pushVar_op:
		*sp++ = vars[arg];
		DISPATCH();
	popVar_op:
		vars[arg] = *--sp;
		DISPATCH();
	incrementVar_op:
		vars[arg] = int2obj(evalInt(vars[arg]) + evalInt(*--sp));
		DISPATCH();
	pop_op:
		sp -= arg;
		if (sp >= stack) {
			DISPATCH();
		} else {
			panic("Stack underflow");
		}
		DISPATCH();
	jmp_op:
		ip += arg;
		DISPATCH();
	jmpTrue_op:
		if (trueObj == (*--sp)) ip += arg;
		DISPATCH();
	jmpFalse_op:
		if (falseObj == (*--sp)) ip += arg;
		DISPATCH();
	 decrementAndJmp_op:
		tmp = obj2int(*(sp - 1)) - 1; // decrement loop counter
		if (tmp > 0) {
			ip += arg; // loop counter > 0, so branch
			*(sp - 1) = int2obj(tmp); // update loop counter

#define USE_TASKS true
#if USE_TASKS
			task->status = running;
			goto suspend;
#endif
			DISPATCH();
		} else {
			sp--; // loop done, pop loop counter
		}
		DISPATCH();
	callFunction_op:
		// xxx not yet implemented
		DISPATCH();
	returnResult_op:
		task->status = done_Value;
		return task->status;
		DISPATCH();
	// For primitive ops, arg is the number of arguments (any primitive can be variadic).
	// Primitive functions return a result that is left on the stack; all args are popped.
	add_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) + evalInt(*(sp - 1)));
		sp -= arg - 1;
		DISPATCH();
	subtract_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) - evalInt(*(sp - 1)));
		sp -= arg - 1;
		DISPATCH();
	multiply_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) * evalInt(*(sp - 1)));
		sp -= arg - 1;
		DISPATCH();
	divide_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) / evalInt(*(sp - 1)));
		sp -= arg - 1;
		DISPATCH();
	lessThan_op:
		*(sp - arg) = ((evalInt(*(sp - 2)) < evalInt(*(sp - 1))) ? trueObj : falseObj);
		sp -= arg - 1;
		DISPATCH();
	printIt_op:
		*(sp - arg) = primPrint(arg, sp - arg); // arg = # of arguments
		sp -= arg - 1;
		DISPATCH();
	at_op:
		array = *(sp - 2);
		if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
		if (!isInt(*(sp - 1))) return (int) indexClassFailure();

		tmp = obj2int(*(sp - 1)); // index
		if ((tmp < 1) || (tmp > (objWords(array) * 4))) { return (int) outOfRangeFailure(); }
// hack for primes benchmark: use byte array to simulate array of booleans
//		*(sp - arg) = (OBJ) array[HEADER_WORDS + tmp - 1];
char *bytes = (char *) array;
*(sp - arg) = (bytes[(4 * HEADER_WORDS) + tmp - 1]) ? trueObj : falseObj;
		sp -= arg - 1;
		DISPATCH();
	atPut_op:
		array = *(sp - 3);
		if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
		if (!isInt(*(sp - 2))) return (int) indexClassFailure();

		tmp = obj2int(*(sp - 2)); // index
		if ((tmp < 1) || (tmp > (objWords(array) * 4))) return (int) outOfRangeFailure();
// hack for primes benchmark: use byte array to simulate array of booleans
//		array[HEADER_WORDS + tmp - 1] = (int) *(sp - 1);
bytes = (char *) array;
bytes[(4 * HEADER_WORDS) + tmp - 1] = (*(sp - 1) == trueObj);
		sp -= arg - 1;
		DISPATCH();
	newArray_op:
		*(sp - arg) = primNewArray(sp - arg); // arg = # of arguments
		sp -= arg - 1;
		DISPATCH();
	fillArray_op:
		*(sp - arg) = primArrayFill(sp - arg); // arg = # of arguments
		sp -= arg - 1;
		DISPATCH();
	analogRead_op:
		*(sp - arg) = primAnalogRead(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	analogWrite_op:
		*(sp - arg) = primAnalogWrite(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	digitalRead_op:
		*(sp - arg) = primDigitalRead(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	digitalWrite_op:
		*(sp - arg) = primDigitalWrite(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	micros_op:
		*(sp - arg) = primMicros(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	millis_op:
		*(sp - arg) = primMillis(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	peek_op:
		*(sp - arg) = primPeek(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	poke_op:
		*(sp - arg) = primPoke(sp - arg);
		sp -= arg - 1;
		DISPATCH();

	return 0;
}

int stepTasks() {
	// Run every task that is runnable and update its status.
	// Return true if task has changed status.

	// get current usecs
	// step each task that is now runnable:
	//	update task wakeTime and status
	//	update status when a hat switches between polling and running
	//	completed tasks will be processed by the caller
	//	return when a task changes status or after stepTime usecs

	int runnable = 0;
	for (int i = 0; i < taskCount; i++) {
		if (running == tasks[i].status) {
			runTask(&tasks[i]);
			runnable++;
		}
	}
	return runnable;
}

void runTasksUntilDone() {
	while (true) {
		int done = true;
		for (int i = 0; i < taskCount; i++) {
			if (running == tasks[i].status) {
				int newStatus = runTask(&tasks[i]);
				if (done_Value == newStatus) {
					OBJ returnValue = tasks[i].stack[tasks[i].sp - 1];
					printf("Returned: %d ", (int) returnValue);
					printObj(returnValue);
					printf("\n");
				}
				done = false;
			}
		}
		if (done) return;
	}
}
