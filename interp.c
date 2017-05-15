// interp.c - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#define USE_TASKS true

// Interpreter State

static OBJ vars[25];

CodeChunkRecord chunks[MAX_CHUNKS];

Task tasks[MAX_TASKS];
int taskCount = 0;

char printBuffer[PRINT_BUF_SIZE];
int printBufferByteCount = 0;

// Error Reporting

// When a primitive encounters an error, it calls failure() with an error code.
// The VM stops the task and records the error code and IP where the error occurred.

uint8 errorCode = noError;

OBJ failure(uint8 reason, const char *explanation) { errorCode = reason; return nilObj; }

// Printing

static void printObj(OBJ obj) {
	// Append a printed representation of the given object to printBuffer.

	char *dst = &printBuffer[printBufferByteCount];
	int n = PRINT_BUF_SIZE - printBufferByteCount;

	if (isInt(obj)) snprintf(dst, n, "%d ", obj2int(obj));
	else if (obj == nilObj) snprintf(dst, n, "nil ");
	else if (obj == trueObj) snprintf(dst, n, "true ");
	else if (obj == falseObj) snprintf(dst, n, "false ");
	else if (objClass(obj) == StringClass) {
		snprintf(dst, n, "%s ", obj2str(obj));
	} else {
		snprintf(dst, n, "OBJ(addr: %d, class: %d) ", (int) obj, objClass(obj));
	}
	printBufferByteCount = strlen(printBuffer);
}

static OBJ primPrint(int argCount, OBJ *args) {
	for (int i = 0; i < argCount; i++) {
		printObj(args[i]);
	}
	if (printBufferByteCount && (' ' == printBuffer[printBufferByteCount - 1])) {
		// Remove final space character
		printBuffer[printBufferByteCount - 1] = 0;
		printBufferByteCount--;
	}
#if !USE_TASKS
	// if not using tasks, print immediately
	printf("(NO TASKS) %s", printBuffer);
	printBufferByteCount = 0;
	printBuffer[0] = 0;  // null terminate
	return nilObj;
#endif
	return nilObj;
}

void printStartMessage(char *s) {
	strcpy(printBuffer, s);
	printBufferByteCount = strlen(printBuffer);
}

// Interpreter

// Macro to inline dispatch in the end of each opcode (avoiding a jump back to the top)
#define DISPATCH() { \
	op = *ip++; \
	arg = ARG(op); \
/*	printf("ip: %d cmd: %d arg: %d sp: %d\n", (ip - task->code), CMD(op), arg, (sp - task->stack)); */   \
	goto *jumpTable[CMD(op)]; \
}

static inline int runTask(Task *task) {
	register int op;
	register int *ip;
	register OBJ *sp;
	register OBJ *fp;
	int arg, tmp;
	OBJ tmpObj;

	// Restore task state
	ip = task->code + task->ip;
	sp = task->stack + task->sp;
	fp = task->stack + task->fp;

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
		&&pushArgCount_op,
		&&pushArg_op,
		&&pushLocal_op,
		&&popLocal_op,
		&&incrementLocal_op,
		&&pop_op,
		&&jmp_op,
		&&jmpTrue_op,
		&&jmpFalse_op,
		&&decrementAndJmp_op,
		&&callFunction_op,
		&&returnResult_op,
		&&waitMicros_op,
		&&waitMillis_op,
		&&printIt_op,
		&&stopAll_op,
		&&add_op,
		&&subtract_op,
		&&multiply_op,
		&&divide_op,
		&&lessThan_op,
		&&newArray_op,
		&&newByteArray_op,
		&&fillArray_op,
		&&at_op,
		&&atPut_op,
		&&analogRead_op,
		&&analogWrite_op,
		&&digitalRead_op,
		&&digitalWrite_op,
		&&setLED_op,
		&&micros_op,
		&&millis_op,
		&&peek_op,
		&&poke_op,
	};

	DISPATCH();

	error:
		// set error status and record ip
		task->status = done_Error;
		// encode and store the error location: <22 bit ip><8 bit chunkIndex>
		tmp = ((ip - task->code) << 8) | (task->currentChunkIndex & 0xFF);
		chunks[task->taskChunkIndex].returnValueOrErrorIP = int2obj(tmp);
		chunks[task->taskChunkIndex].taskErrorCode = errorCode;
		errorCode = noError; // clear the error
		goto suspend;
	suspend:
		// save task state
		task->ip = ip - task->code;
		task->sp = sp - task->stack;
		task->fp = fp - task->stack;
		return task->status;
	halt_op:
		task->status = done;
		goto suspend;
	noop_op:
		*sp++ = nilObj;
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
	pushArgCount_op:
		*sp++ = *(fp - 3);
		DISPATCH();
	pushArg_op:
		*sp++ = *(fp - obj2int(*(fp - 3)) - 3 + arg);
		DISPATCH();
	pushLocal_op:
		*sp++ = *(fp + arg);
		DISPATCH();
	popLocal_op:
		*(fp + arg) = *--sp;
		DISPATCH();
	incrementLocal_op:
		*(fp + arg) = int2obj(obj2int(*(fp + arg)) + evalInt(*--sp));
		DISPATCH();
	pop_op:
		sp -= arg;
		if (sp >= task->stack) {
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
		if (falseObj == (*--sp)) {
			ip += arg;
			if (arg < 0) { // backward jmpFalse is a polling condition hat block
				task->status = polling;
				goto suspend;
			}
		}
		DISPATCH();
	 decrementAndJmp_op:
		tmp = obj2int(*(sp - 1)) - 1; // decrement loop counter
		if (tmp > 0) {
			ip += arg; // loop counter > 0, so branch
			*(sp - 1) = int2obj(tmp); // update loop counter
#if USE_TASKS
			task->status = running;
			goto suspend;
#else
			DISPATCH();
#endif
		} else {
			sp--; // loop done, pop loop counter
		}
		DISPATCH();
	callFunction_op:
		// function call stack layout for N function arguments and M local variables:
		// local M-1
		// ...
		// local 0 <- fp points here during call, so the value of local m is *(fp + m)
		// *(fp - 1), the old fp
		// *(fp - 2), return address, <22 bit ip><8 bit chunkIndex> encoded as an integer object
		// *(fp - 3), # of function arguments
		// arg N-1
		// ...
		// arg 0
		*sp++ = int2obj((arg >> 8) & 0xFF); // # of arguments (middle byte of arg)
		*sp++ = int2obj(((ip - task->code) << 8) | (task->currentChunkIndex & 0xFF)); // return address
		*sp++ = int2obj(fp - task->stack); // old fp
		fp = sp;
		tmp = (arg >> 16) & 0xFF; // # of locals (high byte of arg)
		while (tmp-- > 0) *sp++ = int2obj(0); // reserve space for local vars & initialize to zero
		task->currentChunkIndex = arg & 0xFF; // callee's chunk index (low byte of arg)
		task->code = chunks[task->currentChunkIndex].code;
		ip = task->code + HEADER_WORDS; // first instruction in callee
		DISPATCH();
	returnResult_op:
		tmpObj = *(sp - 1);
		if (!(fp - task->stack)) { // not in a function call
			task->status = done_Value;
			chunks[task->taskChunkIndex].returnValueOrErrorIP = tmpObj;
			goto suspend;
		}
		sp = fp - obj2int(*(fp - 3)) - 3; // restore stack pointer; *(fp - 3) is the arg count
		*sp++ = tmpObj;
		tmp = obj2int(*(fp - 2)); // return address
		task->currentChunkIndex = tmp & 0xFF;
		task->code = chunks[task->currentChunkIndex].code;
		ip = task->code + ((tmp >> 8) & 0x3FFFFF);
		fp = task->stack + obj2int(*(fp - 1)); // restore the old fp
		DISPATCH();
	waitMicros_op:
	 	tmp = evalInt(*(sp - 1)); // wait time in usecs
		sp -= arg - 1;
		task->status = waiting_micros;
		task->wakeTime = TICKS() + tmp;
		goto suspend;
	waitMillis_op:
	 	tmp = evalInt(*(sp - 1)); // wait time in usecs
		sp -= arg - 1;
		task->status = waiting_millis;
		task->wakeTime = millisecs() + tmp;
		goto suspend;
	printIt_op:
		if (printBufferByteCount) { // print buffer is in use
			ip--; // restart this operation when resumed
			task->status = waiting_print;
			goto suspend;
		}
		*(sp - arg) = primPrint(arg, sp - arg); // arg = # of arguments
		sp -= arg - 1;
		DISPATCH();
	stopAll_op:
		stopAllTasks(); // clears all tasks, including the current one
		return done;

	// For the primitive ops below, arg is the number of arguments (any primitive can be variadic).
	// All primitive ops pop all their args and leave a result on the top of the stack.
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
	newArray_op:
		*(sp - arg) = primNewArray(sp - arg);
		sp -= arg - 1;
		if (errorCode) goto error;
		DISPATCH();
	newByteArray_op:
		*(sp - arg) = primNewByteArray(sp - arg);
		sp -= arg - 1;
		if (errorCode) goto error;
		DISPATCH();
	fillArray_op:
		*(sp - arg) = primArrayFill(sp - arg);
		sp -= arg - 1;
		if (errorCode) goto error;
		DISPATCH();
	at_op:
		*(sp - arg) = primArrayAt(sp - arg);
		sp -= arg - 1;
		if (errorCode) goto error;
		DISPATCH();
	atPut_op:
		*(sp - arg) = primArrayAtPut(sp - arg);
		sp -= arg - 1;
		if (errorCode) goto error;
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
	setLED_op:
		*(sp - arg) = primSetLED(sp - arg);
		sp -= arg - 1;
		DISPATCH();
	micros_op:
		*(sp - arg) = int2obj(TICKS());
		sp -= arg - 1;
		DISPATCH();
	millis_op:
		*(sp - arg) = int2obj(millisecs());
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

// Task Scheduler

// RECENT is a threshold for waking up tasks waiting on timers
// (The timer can be up to this many ticks or milliseconds after the wakeup time)

#define RECENT 1000000

void stepTasks() {
	// Run every runnable task and update its status. Wake up waiting tasks whose wakeup time
	// has arrived. Return true if there are still running or waiting tasks.

	while (!serialDataAvailable()) {
		uint32 usecs = TICKS();
		uint32 msecs = millisecs();
		for (int t = 0; t < taskCount; t++) {
			int status = tasks[t].status;
			if ((waiting_micros == status) && ((usecs - tasks[t].wakeTime) < RECENT)) {
				tasks[t].status = status = running;
			} else if ((waiting_millis == status) && ((msecs - tasks[t].wakeTime) < RECENT)) {
				tasks[t].status = status = running;
			}
			if (status >= polling) runTask(&tasks[t]);
		}
	}
}

// Testing (used for testing the interpreter on a desktop/laptop computer)

static void printOutput() {
	// Print output, if any. Used during testing/debugging on a laptop.
	printf("%s", printBuffer);
	for (int i = 0; i < MAX_TASKS; i++) {
		// Make all tasks waiting for the print buffer be runnable.
		if (waiting_print == tasks[i].status) {
			tasks[i].status = running;
		}
	}
	printBufferByteCount = 0;
	printBuffer[0] = 0; // null terminate
}

static int stepTasksOnce() {
	// Used for testing on laptop. Run every runnable task and update its status.
	// Wake up waiting tasks whose wakeup time has arrived.
	// Return true if there are still running or waiting tasks.

	int hasActiveTasks = false;
	uint32 usecs = TICKS();
	uint32 msecs = millisecs();
	for (int t = 0; t < taskCount; t++) {
		int status = tasks[t].status;
		if ((waiting_micros == status) && ((usecs - tasks[t].wakeTime) < RECENT)) {
			tasks[t].status = status = running;
		} else if ((waiting_millis == status) && ((msecs - tasks[t].wakeTime) < RECENT)) {
			tasks[t].status = status = running;
		}
		if (status >= polling) runTask(&tasks[t]);
		if (status >= waiting_micros) hasActiveTasks = true;
	}
	return hasActiveTasks;
}

void runTasksUntilDone() {
#if USE_TASKS
	int isRunning = true;
	while (isRunning) {
		if (printBufferByteCount) printOutput();
		isRunning = stepTasksOnce();
	}
	if (printBufferByteCount) printOutput();
#else
	// Run each task to completion
	for (int i = 0; i < taskCount; i++) {
		runTask(&tasks[i]);
	}
#endif
	if (errorCode) printf("Error: %d\r\n", errorCode);
}
