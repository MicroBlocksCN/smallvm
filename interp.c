// interp.c - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Tasks - Set USE_TASKS to false to test interpreter performance without task switching

#define USE_TASKS true

// Interpreter State

CodeChunkRecord chunks[MAX_CHUNKS];

Task tasks[MAX_TASKS];
int taskCount = 0;

static OBJ vars[25];

// Error Reporting

// When a primitive encounters an error, it calls failure() with an error code.
// The VM stops the task and records the error code and IP where the error occurred.
// The explanation string is currently unused.

static uint8 errorCode = noError;

OBJ failure(uint8 reason, const char *explanation) { errorCode = reason; return nilObj; }

// Printing

#define PRINT_BUF_SIZE 100
static char printBuffer[PRINT_BUF_SIZE];
static int printBufferByteCount = 0;

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
	printBuffer[0] = 0; // null terminate
	printBufferByteCount = 0;

	for (int i = 0; i < argCount; i++) {
		printObj(args[i]);
	}
	if (printBufferByteCount && (' ' == printBuffer[printBufferByteCount - 1])) {
		// Remove final space character
		printBuffer[printBufferByteCount - 1] = 0;
		printBufferByteCount--;
	}
#if USE_TASKS
	sendOutputMessage(printBuffer, printBufferByteCount);
#else
	printf("(NO TASKS) %s", printBuffer);
#endif
	return nilObj;
}

void printStartMessage(char *s) {
	sendOutputMessage(s, strlen(s));
}

// Interpreter

// Macro to inline dispatch in the end of each opcode (avoiding a jump back to the top)
#define DISPATCH() { \
	op = *ip++; \
	arg = ARG(op); \
/*	printf("ip: %d cmd: %d arg: %d sp: %d\n", (ip - task->code), CMD(op), arg, (sp - task->stack)); */ \
	goto *jumpTable[CMD(op)]; \
}

static inline void runTask(Task *task) {
	register int op;
	register int *ip;
	register OBJ *sp;
	register OBJ *fp;
	int arg, tmp;
	OBJ tmpObj;

	// initialize jump table
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

	// Restore task state
	ip = task->code + task->ip;
	sp = task->stack + task->sp;
	fp = task->stack + task->fp;

	DISPATCH();

	error:
		// tmp encodes the error location: <22 bit ip><8 bit chunkIndex>
		tmp = ((ip - task->code) << 8) | (task->currentChunkIndex & 0xFF);
		sendTaskError(task->taskChunkIndex, errorCode, tmp);
		task->status = unusedTask;
		errorCode = noError; // clear the error
		goto suspend;
	suspend:
		// save task state
		task->ip = ip - task->code;
		task->sp = sp - task->stack;
		task->fp = fp - task->stack;
		return;
	halt_op:
		sendMessage(taskDone, 0, task->taskChunkIndex, 0, NULL);
		task->status = unusedTask;
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
#if USE_TASKS
		if (arg < 0) goto suspend; // backward jmp is a forever loop
#endif
		DISPATCH();
	jmpTrue_op:
		if (trueObj == (*--sp)) ip += arg;
#if USE_TASKS
		if ((arg < 0) && (trueObj == *sp)) goto suspend; // backward jmpTrue is a while loop
#endif
		DISPATCH();
	jmpFalse_op:
		if (falseObj == (*--sp)) ip += arg;
#if USE_TASKS
		if (arg < 0) { // backward jmpFalse is a condition hat block polling its condition
			// Note: This code hasn't been tested and probably needs refinement.
			// For example, perhaps the condition hat should only be triggered only on
			// the transition to the condition becoming true. Implementing that would require
			// only a few more lines of code (e.g. it should take the jump if its status
			// is already running).
			if (trueObj == *sp) {
				if (running != task->status) sendMessage(taskStarted, 0, task->taskChunkIndex, 0, NULL);
				task->status = running;
			} else {
				if (polling != task->status) sendMessage(taskPolling, 0, task->taskChunkIndex, 0, NULL);
				task->status = polling;
			}
			goto suspend;
		}
#endif
		DISPATCH();
	 decrementAndJmp_op:
		tmp = obj2int(*(sp - 1)) - 1; // decrement loop counter
		if (tmp > 0) {
			ip += arg; // loop counter > 0, so branch
			*(sp - 1) = int2obj(tmp); // update loop counter
#if USE_TASKS
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
		tmpObj = *(sp - 1); // return value
		if (!(fp - task->stack)) { // not in a function call
			sendTaskReturnValue(task->taskChunkIndex, tmpObj);
			task->status = unusedTask;
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
		if (!hasOutputSpace(PRINT_BUF_SIZE + 5)) {
			ip--; // retry when task is resumed
			goto suspend;
		}
		*(sp - arg) = primPrint(arg, sp - arg); // arg = # of arguments
		sp -= arg - 1;
		DISPATCH();
	stopAll_op:
		stopAllTasks(); // clears all tasks, including the current one
		return;

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
}

// Task Scheduler

// RECENT is a threshold for waking up tasks waiting on timers
// (The timer can be up to this many ticks or milliseconds after the wakeup time)

#define RECENT 1000000

static int currentTaskIndex = -1;
static int lastMsgTime = 0;

void vmLoop() {
	// Run the next runnable task. Wake up any waiting tasks whose wakeup time has arrived.

	while (true) {
		uint32 msecs = millisecs();
		if (msecs != lastMsgTime) {
			// Call processMessage() at most once per millisecond
			processMessage();
			lastMsgTime = msecs = millisecs();
		}

		uint32 usecs = 0; // TICKS() is moderately expensive on Arduino; compute only if needed
		for (int i = 0; i < taskCount; i++) {
			currentTaskIndex++;
			if (currentTaskIndex >= taskCount) currentTaskIndex = 0;
			Task *task = &tasks[currentTaskIndex];
			if (waiting_micros == task->status) {
				if (!usecs) usecs = TICKS(); // compute TICKS()
				if ((usecs - task->wakeTime) < RECENT) {
					task->status = running;
					runTask(task);
					continue;
				}
			} else if ((waiting_millis == task->status) && ((msecs - task->wakeTime) < RECENT)) {
				task->status = running;
				runTask(task);
				continue;
			}
			if (task->status >= running) {
				runTask(task);
				continue;
			}
		}
	}
}

// Testing

void runTasksUntilDone() {
	// Used for testing/benchmarking the interpreter. Run all tasks to completion.

	int hasActiveTasks = true;
	while (hasActiveTasks) {
		hasActiveTasks = false;
		uint32 usecs = 0; // TICKS() is moderately expensive on Arduino; compute only if needed
		uint32 msecs = millisecs();
		for (int t = 0; t < taskCount; t++) {
			Task *task = &tasks[t];
			if (waiting_micros == task->status) {
				if (!usecs) usecs = TICKS(); // compute TICKS()
				if ((usecs - task->wakeTime) < RECENT) task->status = running;
			} else if (waiting_millis == task->status) {
				if ((msecs - task->wakeTime) < RECENT) task->status = running;
			}
			if (task->status >= running) {
				runTask(task);
				hasActiveTasks = true;
			} else if (task->status != unusedTask) {
				hasActiveTasks = true;
			}
		}
	}
}
