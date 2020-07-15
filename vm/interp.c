/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// interp.c - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Tasks - Set USE_TASKS to false to test interpreter performance without task switching

#define USE_TASKS true

// RECENT is a threshold for waking up tasks waiting on timers
// The timer can be up to this many usecs past the wakeup time.

#define RECENT 1000000

// Interpreter State

CodeChunkRecord chunks[MAX_CHUNKS];

Task tasks[MAX_TASKS];
int taskCount = 0;

OBJ vars[MAX_VARS];

// Error Reporting

// When a primitive encounters an error, it calls fail() with an error code.
// The VM stops the task and records the error code and IP where the error occurred.

static uint8 errorCode = noError;

OBJ fail(uint8 errCode) {
	errorCode = errCode;
	return falseObj;
}

// Printing

#define PRINT_BUF_SIZE 800
static char printBuffer[PRINT_BUF_SIZE];
static int printBufferByteCount = 0;

int extraByteDelay = 1600; // default of 1600 usecs assumes serial throughput of 625 bytes/sec

static void printObj(OBJ obj) {
	// Append a printed representation of the given object to printBuffer.

	char *dst = &printBuffer[printBufferByteCount];
	int n = PRINT_BUF_SIZE - printBufferByteCount;

	if (isInt(obj)) snprintf(dst, n, "%d", obj2int(obj));
	else if (obj == falseObj) snprintf(dst, n, "false");
	else if (obj == trueObj) snprintf(dst, n, "true");
	else if (objType(obj) == StringType) {
		snprintf(dst, n, "%s", obj2str(obj));
	} else if (objType(obj) == ListType) {
		snprintf(dst, n, "[%d item list]", obj2int(FIELD(obj, 0)));
	} else if (objType(obj) == ByteArrayType) {
		snprintf(dst, n, "(%d bytes)", BYTES(obj));
	} else {
		snprintf(dst, n, "(object type: %d)", objType(obj));
	}
	printBufferByteCount = strlen(printBuffer);
}

static void printArgs(int argCount, OBJ *args, int forSay, int insertSpaces) {
	// Print all args into printBuffer and return the size of the resulting string.

	if (forSay) {
		printBuffer[0] = 2; // type is string (printBuffer is used as outputValue message body)
		printBufferByteCount = 1;
	} else {
		printBufferByteCount = 0;
	}
	printBuffer[printBufferByteCount] = 0; // null terminate

	for (int i = 0; i < argCount; i++) {
		printObj(args[i]);
		if (insertSpaces && (i < (argCount - 1)) && (printBufferByteCount < PRINT_BUF_SIZE)) {
			printBuffer[printBufferByteCount++] = ' '; // add a space
			printBuffer[printBufferByteCount] = 0; // null terminate
		}
	}
}

static int bytesForObject(OBJ value) {
	// Return the number of bytes needed to transmit the given value.

	int headerBytes = 6; // message header (5 bytes) + type byte
	if (isInt(value)) { // 32-bit integer
		return headerBytes + 4;
	} else if (IS_TYPE(value, StringType)) { // string
		return headerBytes + strlen(obj2str(value));
	} else if ((value == trueObj) || (value == falseObj)) { // boolean
		return headerBytes + 1;
	}
	return 512; // maximum that might be needed, based on size of buffer in sendValueMessage
}

// Broadcast

OBJ lastBroadcast = zeroObj; // Note: This variable must be processed by the garbage collector!

static void primSendBroadcast(int argCount, OBJ *args) {
	// Variadic broadcast; all args are concatenated into printBuffer.
	printArgs(argCount, args, false, false);
	// save the last broadcasted message
	lastBroadcast = newStringFromBytes(printBuffer, printBufferByteCount);
	startReceiversOfBroadcast(printBuffer, printBufferByteCount);
	sendBroadcastToIDE(printBuffer, printBufferByteCount);
}

// Timer

static uint32 timerStart = 0;

static void resetTimer() { timerStart = millisecs(); }

static int timer() {
	// Return the number of milliseconds since the timer was last reset.
	// Note: The millisecond clock is the 32-bit microsecond clock divided by 1000,
	// so it wraps around to zero when the microsecond clock wraps, which occurs
	// about every 72 minutes and 35 seconds. That's the maximum duration that can
	// be measured with this simple timer implementation.

	const uint32 msecWrap = 4294967; // 2^32 / 1000, value at which the millisecond clock wraps

	uint32 now = millisecs();
	if (now < timerStart) { // clock wrapped
		return (msecWrap - timerStart) + now; // time to wrap + time since wrap
	}
	return now - timerStart;
}


// Board Type

#define BOARD_TYPE_SIZE 32

// statically allocated object for the boardType primitive result
static struct {
	uint32 header;
	char body[BOARD_TYPE_SIZE];
} boardTypeObj;

OBJ primBoardType() {
	strncpy(boardTypeObj.body, boardType(), BOARD_TYPE_SIZE - 1);
	int wordCount = (strlen(boardTypeObj.body) + 4) / 4;
	boardTypeObj.header = HEADER(StringType, wordCount);
	return (OBJ) &boardTypeObj;
}

// Misc primitives

static OBJ primRandom(int argCount, OBJ *args) {
	int base, range;
	if (argCount == 1) {
		base = 1;
		range = evalInt(args[0]);
	} else {
		base = evalInt(args[0]);
		range = (evalInt(args[1]) + 1) - base;
	}
	if (range < 1) range = 1;
	return int2obj((rand() % range) + base); // result range is [base..base+range], inclusive
}

static OBJ primMinimum(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	int result = obj2int(args[0]);
	for (int i = 0; i < argCount; i++) {
		OBJ arg = args[i];
		if (!isInt(arg)) return fail(needsIntegerError);
		int n = obj2int(arg);
		if (n < result) result = n;
	}
	return int2obj(result);
}

static OBJ primMaximum(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	int result = obj2int(args[0]);
	for (int i = 0; i < argCount; i++) {
		OBJ arg = args[i];
		if (!isInt(arg)) return fail(needsIntegerError);
		int n = obj2int(arg);
		if (n > result) result = n;
	}
	return int2obj(result);
}

static int stringsEqual(OBJ obj1, OBJ obj2) {
	// Return true if the given strings have the same length and contents.
	// Assume s1 and s2 are of Strings.

	int byteCount = 4 * objWords(obj1);
	if (byteCount != (4 * objWords(obj2))) return false; // different lengths
	char *s1 = (char *) &FIELD(obj1, 0);
	char *s2 = (char *) &FIELD(obj2, 0);
	char *end = s1 + byteCount;
	while (s1 < end) {
		if (!*s1 && !*s2) return true; // null terminator in both strings
		if (*s1++ != *s2++) return false; // not equal
	}
	return true;
}

// Interpreter

// Macros to pop arguments for commands and reporters (pops args, leaves result on stack)
#define POP_ARGS_COMMAND() { sp -= arg; }
#define POP_ARGS_REPORTER() { sp -= arg - 1; }

// Macro to check for stack overflow
#define STACK_CHECK(n) { \
	if (((sp + (n)) - task->stack) > STACK_LIMIT) { \
		errorCode = stackOverflow; \
		goto error; \
	} \
}

// Macros to support function calls
#define IN_CALL() (fp > task->stack)

// Macro to inline dispatch in the end of each opcode (avoiding a jump back to the top)
#define DISPATCH() { \
	if (errorCode) goto error; \
	op = *ip++; \
	arg = ARG(op); \
/*	printf("ip: %d cmd: %d arg: %d sp: %d\n", (ip - task->code), CMD(op), arg, (sp - task->stack)); */ \
	goto *jumpTable[CMD(op)]; \
}

static void runTask(Task *task) {
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
		&&storeVar_op,
		&&incrementVar_op,
		&&pushArgCount_op,
		&&pushArg_op,
		&&storeArg_op,
		&&incrementArg_op,
		&&pushLocal_op,
		&&storeLocal_op,
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
		&&sendBroadcast_op,
		&&recvBroadcast_op,
		&&stopAllButThis_op,
		&&forLoop_op,
		&&initLocals_op,
		&&getArg_op,
		&&getLastBroadcast_op,
		&&jmpOr_op,
		&&jmpAnd_op,
		&&minimum_op,
		&&maximum_op,
		&&lessThan_op,
		&&lessOrEq_op,
		&&equal_op,
		&&notEqual_op,
		&&greaterOrEq_op,
		&&greaterThan_op,
		&&not_op,
		&&add_op,
		&&subtract_op,
		&&multiply_op,
		&&divide_op,
		&&modulo_op,
		&&absoluteValue_op,
		&&random_op,
		&&hexToInt_op,
		&&bitAnd_op,
		&&bitOr_op,
		&&bitXor_op,
		&&bitInvert_op,
		&&bitShiftLeft_op,
		&&bitShiftRight_op,
		&&longMultiply_op,
		&&isType_op,
		&&jmpFalse_op, // this is the waitUntil opcode, an alias for jmpFalse_op
		&&RESERVED_op,
		&&newList_op,
		&&RESERVED_op,
		&&fillList_op,
		&&at_op,
		&&atPut_op,
		&&length_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&millis_op,
		&&micros_op,
		&&timer_op,
		&&resetTimer_op,
		&&sayIt_op,
		&&logData_op,
		&&boardType_op,
		&&comment_op,
		&&resetAndRestart_op,
		&&RESERVED_op,
		&&analogPins_op,
		&&digitalPins_op,
		&&analogRead_op,
		&&analogWrite_op,
		&&digitalRead_op,
		&&digitalWrite_op,
		&&digitalSet_op,
		&&digitalClear_op,
		&&buttonA_op,
		&&buttonB_op,
		&&setUserLED_op,
		&&i2cSet_op,
		&&i2cGet_op,
		&&spiSend_op,
		&&spiRecv_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&mbDisplay_op,
		&&mbDisplayOff_op,
		&&mbPlot_op,
		&&mbUnplot_op,
		&&mbTiltX_op,
		&&mbTiltY_op,
		&&mbTiltZ_op,
		&&mbTemp_op,
		&&neoPixelSend_op,
		&&drawShape_op,
		&&shapeForLetter_op,
		&&neoPixelSetPin_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&callCommandPrimitive_op,
		&&callReporterPrimitive_op,
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
	RESERVED_op:
	halt_op:
		sendTaskDone(task->taskChunkIndex);
		task->status = unusedTask;
		goto suspend;
	noop_op:
		DISPATCH();
	pushImmediate_op:
		STACK_CHECK(1);
		*sp++ = (OBJ) arg;
		DISPATCH();
	pushBigImmediate_op:
		STACK_CHECK(1);
		*sp++ = (OBJ) *ip++;
		DISPATCH();
	pushLiteral_op:
		STACK_CHECK(1);
		*sp++ = (OBJ) (ip + arg); // arg is offset from the current ip to the literal object
		DISPATCH();
	pushVar_op:
		STACK_CHECK(1);
		*sp++ = vars[arg];
		DISPATCH();
	storeVar_op:
		vars[arg] = *--sp;
		DISPATCH();
	incrementVar_op:
		vars[arg] = int2obj(evalInt(vars[arg]) + evalInt(*--sp));
		DISPATCH();
	pushArgCount_op:
		STACK_CHECK(1);
		*sp++ = IN_CALL() ? *(fp - 3) : zeroObj;
		DISPATCH();
	pushArg_op:
		STACK_CHECK(1);
		if (IN_CALL()) {
			*sp++ = *(fp - obj2int(*(fp - 3)) - 3 + arg);
		} else {
			*sp++ = fail(notInFunction);
		}
		DISPATCH();
	storeArg_op:
		if (IN_CALL()) {
			*(fp - obj2int(*(fp - 3)) - 3 + arg) = *--sp;
		} else {
			fail(notInFunction);
		}
		DISPATCH();
	incrementArg_op:
		if (IN_CALL()) {
			tmp = evalInt(*(fp - obj2int(*(fp - 3)) - 3 + arg)) + evalInt(*--sp);
			*(fp - obj2int(*(fp - 3)) - 3 + arg) = int2obj(tmp);
		} else {
			fail(notInFunction);
		}
		DISPATCH();
	pushLocal_op:
		STACK_CHECK(1);
		*sp++ = *(fp + arg);
		DISPATCH();
	storeLocal_op:
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
			vmPanic("Stack underflow");
		}
		DISPATCH();
	jmp_op:
		ip += arg;
#if USE_TASKS
		if (arg < 0) goto suspend;
#endif
		DISPATCH();
	jmpTrue_op:
		if (trueObj == (*--sp)) ip += arg;
#if USE_TASKS
		if ((arg < 0) && (trueObj == *sp)) goto suspend;
#endif
		DISPATCH();
	jmpFalse_op:
		if (trueObj != (*--sp)) ip += arg; // treat any value but true as false
#if USE_TASKS
		if ((arg < 0) && (trueObj != *sp)) goto suspend;
#endif
		DISPATCH();
	 decrementAndJmp_op:
		tmp = obj2int(*(sp - 1)) - 1; // decrement loop counter
		if (tmp >= 0) {
			ip += arg; // loop counter >= 0, so branch
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
		STACK_CHECK(3);
		*sp++ = int2obj(arg & 0xFF); // # of arguments (low byte of arg)
		*sp++ = int2obj(((ip - task->code) << 8) | (task->currentChunkIndex & 0xFF)); // return address
		*sp++ = int2obj(fp - task->stack); // old fp
		fp = sp;
		task->currentChunkIndex = (arg >> 8) & 0xFF; // callee's chunk index (middle byte of arg)
		task->code = chunks[task->currentChunkIndex].code;
		ip = task->code + PERSISTENT_HEADER_WORDS; // first instruction in callee
		DISPATCH();
	returnResult_op:
		tmpObj = *(sp - 1); // return value
		if (fp == task->stack) { // not in a function call
			if (!hasOutputSpace(bytesForObject(tmpObj) + 100)) { // leave room for other messages
				ip--; // retry when task is resumed
				goto suspend;
			}
			sendTaskReturnValue(task->taskChunkIndex, tmpObj);
			task->status = unusedTask;
			goto suspend;
		}
		sp = fp - obj2int(*(fp - 3)) - 3; // restore stack pointer; *(fp - 3) is the arg count
		*sp++ = tmpObj; // push return value (no need for a stack check; just recovered at least 3 words from the old call frame)
		tmp = obj2int(*(fp - 2)); // return address
		task->currentChunkIndex = tmp & 0xFF;
		task->code = chunks[task->currentChunkIndex].code;
		ip = task->code + ((tmp >> 8) & 0x3FFFFF); // restore old ip
		fp = task->stack + obj2int(*(fp - 1)); // restore the old fp
		DISPATCH();
	waitMicros_op:
	 	tmp = evalInt(*(sp - 1)); // wait time in usecs
	 	POP_ARGS_COMMAND();
	 	if (tmp <= 30) {
	 		if (tmp <= 0) { DISPATCH(); } // don't wait at all
			// busy-wait for wait times up to 30 usecs to avoid a context switch
			tmp = microsecs() + tmp - 3; // wake time
			while ((microsecs() - tmp) >= RECENT) { } // busy wait
			DISPATCH();
		}
		task->status = waiting_micros;
		task->wakeTime = (microsecs() + tmp) - 10; // adjusted for approximate scheduler overhead
		goto suspend;
	waitMillis_op:
	 	tmp = evalInt(*(sp - 1)); // wait time in usecs
	 	POP_ARGS_COMMAND();
	 	if (tmp <= 0) { DISPATCH(); } // don't wait at all
	 	if (tmp > 3600000) {
	 		fail(waitTooLong);
	 		goto error;
	 	}
		task->status = waiting_micros;
		task->wakeTime = microsecs() + ((1000 * tmp) - 10);
		goto suspend;
	sendBroadcast_op:
		primSendBroadcast(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	recvBroadcast_op:
		POP_ARGS_COMMAND(); // pop the broadcast name (a literal string)
		DISPATCH();
	stopAllButThis_op:
		stopAllTasksButThis(task); // clears all tasks except the current one
		DISPATCH();
	forLoop_op:
		// stack layout:
		// *(sp - 1) the loop counter (decreases from N to 1); falseObj the very first time
		// *(sp - 2) N, the total loop count or item count of the list argument
		// *(sp - 3) the object being iterated over, a positive integer or list

		tmpObj = *(sp - 1); // loop counter, or falseObj the very first time
		if (falseObj == tmpObj) { // first time: compute N, the total iterations (in tmp)
			tmpObj = *(sp - 3);
			if (isInt(tmpObj)) {
				tmp = obj2int(tmpObj);
			} else if (IS_TYPE(tmpObj, ListType)) {
				tmp = obj2int(FIELD(tmpObj, 0));
			} else {
				fail(badForLoopArg);
				goto error;
			}
			*(sp - 2) = int2obj(tmp); // save N, the total iterations; tmp is initial loop counter
		} else { // not the first time
			tmp = obj2int(tmpObj) - 1; // decrement the loop counter (in tmp)
		}
		if (tmp > 0) { // loop counter > 0
			*(sp - 1) = int2obj(tmp); // store the loop counter
			tmp = obj2int(*(sp - 2)) - tmp; // set tmp to the loop index (increasing from 0 to N-1)
			tmpObj = *(sp - 3); // set tmpObj to thing being iterated over
			if (isInt(tmpObj)) {
				// set the index variable to the loop index
				*(fp + arg) = int2obj(tmp + 1); // add 1 to get range 1..N
			} else if (IS_TYPE(tmpObj, ListType)) {
				// set the index variable to the next list item
				*(fp + arg) = FIELD(tmpObj, tmp + 1); // list item (list object indices 1..N)
			} else {
				fail(badForLoopArg);
				goto error;
			}
		} else { // loop counter <= 0
			ip++; // skip the following jmp instruction thus ending the loop
		}
		DISPATCH();
	initLocals_op:
		// Reserve stack space for 'arg' locals initialized to zero
		STACK_CHECK(arg);
		while (arg-- > 0) *sp++ = zeroObj;
		DISPATCH();
	getArg_op:
		// For variadic functions. Unlike pushVar, the argument index is passed on the stack.
		STACK_CHECK(1);
		if (IN_CALL()) {
			tmp = evalInt(*(sp - 1));
			if ((1 <= tmp) && (tmp <= obj2int(*(fp - 3)))) { // if arg index in range:
				*(sp - arg) = *(fp - obj2int(*(fp - 3)) - 4 + tmp);
			} else {
				fail(argIndexOutOfRange);
			}
		} else {
			fail(notInFunction);
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	getLastBroadcast_op:
		*(sp - arg) = lastBroadcast;
		POP_ARGS_REPORTER();
		DISPATCH();
	jmpOr_op:
		// if true, jump leaving true (result of "or" expression) on stack, otherwise pop
		if (trueObj == *(sp - 1)) { ip += arg; } else { sp--; }
		DISPATCH();
	jmpAnd_op:
		// if not true, push false (result of "and" expression) on stack and jump
		if (trueObj != (*--sp)) { // treat any value but true as false
			*sp++ = falseObj;
			ip += arg;
		}
		DISPATCH();

	// For the primitive ops below, arg is the number of arguments (any primitive can be variadic).
	// Commands pop all their arguments.
	// Reporters pop all their arguments and leave a result on the top of the stack.
	minimum_op:
		*(sp - arg) = primMinimum(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	maximum_op:
		*(sp - arg) = primMaximum(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	lessThan_op:
		*(sp - arg) = ((evalInt(*(sp - 2)) < evalInt(*(sp - 1))) ? trueObj : falseObj);
		POP_ARGS_REPORTER();
		DISPATCH();
	lessOrEq_op:
		*(sp - arg) = ((evalInt(*(sp - 2)) <= evalInt(*(sp - 1))) ? trueObj : falseObj);
		POP_ARGS_REPORTER();
		DISPATCH();
	equal_op:
		tmpObj = *(sp - 2);
		if (tmpObj == *(sp - 1)) { // identical objects
			*(sp - arg) = trueObj;
		} else if (tmpObj <= trueObj) {
			*(sp - arg) = falseObj; // boolean, not equal
		} else if (isInt(tmpObj) && isInt(*(sp - 1))) {
			*(sp - arg) = falseObj; // integer, not equal
		} else if (IS_TYPE(tmpObj, StringType) && IS_TYPE(*(sp - 1), StringType)) {
			*(sp - arg) = (stringsEqual(tmpObj, *(sp - 1)) ? trueObj : falseObj);
		} else {
			*(sp - arg) = falseObj; // not comparable, so not equal
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	notEqual_op:
		tmpObj = *(sp - 2);
		if (tmpObj == *(sp - 1)) { // identical objects
			*(sp - arg) = falseObj;
		} else if (tmpObj <= trueObj) {
			*(sp - arg) = trueObj; // boolean, not equal
		} else if (isInt(tmpObj) && isInt(*(sp - 1))) {
			*(sp - arg) = trueObj; // integer, not equal
		} else if (IS_TYPE(tmpObj, StringType) && IS_TYPE(*(sp - 1), StringType)) {
			*(sp - arg) = (stringsEqual(tmpObj, *(sp - 1)) ? falseObj : trueObj);
		} else {
			*(sp - arg) = trueObj; // not comparable, so not equal
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	greaterOrEq_op:
		*(sp - arg) = ((evalInt(*(sp - 2)) >= evalInt(*(sp - 1))) ? trueObj : falseObj);
		POP_ARGS_REPORTER();
		DISPATCH();
	greaterThan_op:
		*(sp - arg) = ((evalInt(*(sp - 2)) > evalInt(*(sp - 1))) ? trueObj : falseObj);
		POP_ARGS_REPORTER();
		DISPATCH();
	not_op:
		*(sp - arg) = (trueObj == *(sp - 1)) ? falseObj : trueObj;
		POP_ARGS_REPORTER();
		DISPATCH();
	add_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) + evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	subtract_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) - evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	multiply_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) * evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	divide_op:
		tmp = evalInt(*(sp - 1));
		*(sp - arg) = ((0 == tmp) ? fail(zeroDivide) : int2obj(evalInt(*(sp - 2)) / tmp));
		POP_ARGS_REPORTER();
		DISPATCH();
	modulo_op:
		tmp = evalInt(*(sp - 1));
		*(sp - arg) = ((0 == tmp) ? fail(zeroDivide) : int2obj(evalInt(*(sp - 2)) % tmp));
		POP_ARGS_REPORTER();
		DISPATCH();
	absoluteValue_op:
		*(sp - arg) = int2obj(abs(evalInt(*(sp - 1))));
		POP_ARGS_REPORTER();
		DISPATCH();
	random_op:
		*(sp - arg) = primRandom(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	hexToInt_op:
		*(sp - arg) = primHexToInt(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();

	// bit operations:
	bitAnd_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) & evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	bitOr_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) | evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	bitXor_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) ^ evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	bitInvert_op:
		*(sp - arg) = int2obj(~evalInt(*(sp - 1)));;
		POP_ARGS_REPORTER();
		DISPATCH();
	bitShiftLeft_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) << evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	bitShiftRight_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) >> evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	longMultiply_op:
		{
			long long product = (long long) (evalInt(*(sp - 3))) * (long long) (evalInt(*(sp - 2)));
			tmp = (int) ((product >> (evalInt(*(sp - 1)))) & 0xFFFFFFFF);
			*(sp - arg) = int2obj(tmp);
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	// list operations:
	newList_op:
		*(sp - arg) = primNewList(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	fillList_op:
		primFillList(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	at_op:
		*(sp - arg) = primAt(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	atPut_op:
		primAtPut(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	length_op:
		*(sp - arg) = primLength(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	// miscellaneous operations:
	isType_op:
		{
			char *type = obj2str(*(sp - 1));
			switch (objType(*(sp - 2))) {
				case BooleanType:
					*(sp - arg) = strcmp(type, "boolean") == 0 ? trueObj : falseObj;
					break;
				case IntegerType:
					*(sp - arg) = strcmp(type, "number") == 0 ? trueObj : falseObj;
					break;
				case StringType:
					*(sp - arg) = strcmp(type, "string") == 0 ? trueObj : falseObj;
					break;
				case ListType:
					*(sp - arg) = strcmp(type, "list") == 0 ? trueObj : falseObj;
					break;
				case ByteArrayType:
					*(sp - arg) = strcmp(type, "byte array") == 0 ? trueObj : falseObj;
					break;
			}
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	millis_op:
		STACK_CHECK(1);
		*sp++ = int2obj(millisecs());
		DISPATCH();
	micros_op:
		STACK_CHECK(1);
		*sp++ = int2obj(microsecs() & 0x3FFFFFFF); // low 30-bits so result is positive
		DISPATCH();
	timer_op:
		STACK_CHECK(1);
		*sp++ = int2obj(timer());
		DISPATCH();
	resetTimer_op:
		resetTimer();
		POP_ARGS_COMMAND();
		DISPATCH();
	sayIt_op:
		printArgs(arg, sp - arg, true, true);
		if (!hasOutputSpace(printBufferByteCount + 100)) { // leave room for other messages
			ip--; // retry when task is resumed
			goto suspend;
		}
		sendSayForChunk(printBuffer, printBufferByteCount, task->taskChunkIndex);
		POP_ARGS_COMMAND();
		// wait for data to be sent; prevents use in tight loop from clogging serial line
		task->status = waiting_micros;
		task->wakeTime = microsecs() + (extraByteDelay * (printBufferByteCount + 6));
		goto suspend;
	logData_op:
		printArgs(arg, sp - arg, false, true);
		if (!hasOutputSpace(printBufferByteCount + 100)) { // leave room for other messages
			ip--; // retry when task is resumed
			goto suspend;
		}
		#if USE_TASKS
			logData(printBuffer);
		#else
			printf("(NO TASKS) %s\r\n", printBuffer);
		#endif
		POP_ARGS_COMMAND();
		// wait for data to be sent; prevents use in tight loop from clogging serial line
		task->status = waiting_micros;
		task->wakeTime = microsecs() + (extraByteDelay * (printBufferByteCount + 6));
		goto suspend;
	boardType_op:
		*(sp - arg) = primBoardType();
		POP_ARGS_REPORTER();
		DISPATCH();
	comment_op:
		POP_ARGS_COMMAND();
		DISPATCH();
	resetAndRestart_op:
		resetAndRestart();
		return;

	// I/O operations:
	analogPins_op:
		*(sp - arg) = primAnalogPins(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	digitalPins_op:
		*(sp - arg) = primDigitalPins(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	analogRead_op:
		*(sp - arg) = primAnalogRead(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	analogWrite_op:
		primAnalogWrite(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	digitalRead_op:
		*(sp - arg) = primDigitalRead(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	digitalWrite_op:
		primDigitalWrite(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	digitalSet_op:
		// no args to pop; pin number is encoded in arg field of instruction
		primDigitalSet(arg, true);
		DISPATCH();
	digitalClear_op:
		// no args to pop; pin number is encoded in arg field of instruction
		primDigitalSet(arg, false);
		DISPATCH();
	buttonA_op:
		*(sp - arg) = primButtonA(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	buttonB_op:
		*(sp - arg) = primButtonB(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	setUserLED_op:
		primSetUserLED(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	i2cSet_op:
		primI2cSet(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	i2cGet_op:
		*(sp - arg) = primI2cGet(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	spiSend_op:
		primSPISend(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	spiRecv_op:
		*(sp - arg) = primSPIRecv(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();

	// micro:bit operations:
	mbDisplay_op:
		primMBDisplay(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbDisplayOff_op:
		primMBDisplayOff(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbPlot_op:
		primMBPlot(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbUnplot_op:
		primMBUnplot(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbTiltX_op:
		*(sp - arg) = primMBTiltX(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	mbTiltY_op:
		*(sp - arg) = primMBTiltY(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	mbTiltZ_op:
		*(sp - arg) = primMBTiltZ(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	mbTemp_op:
		*(sp - arg) = primMBTemp(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	neoPixelSend_op:
		primNeoPixelSend(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	drawShape_op:
		primMBDrawShape(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	shapeForLetter_op:
		*(sp - arg) = primMBShapeForLetter(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	neoPixelSetPin_op:
		primNeoPixelSetPin(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();

	// named primitives:
	callCommandPrimitive_op:
		task->sp = sp - task->stack; // record the stack pointer in case primitive does a GC
		callPrimitive(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	callReporterPrimitive_op:
		task->sp = sp - task->stack; // record the stack pointer in case primitive does a GC
		*(sp - arg) = callPrimitive(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
}

// Task Scheduler

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || \
	defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_SAMD_MKR1000)
		#define HAS_WIFI true
#endif

static int currentTaskIndex = -1;

void vmLoop() {
	// Run the next runnable task. Wake up any waiting tasks whose wakeup time has arrived.

	int count = 0;
	while (true) {
		if (count-- < 0) {
			// do background VM tasks once every N VM loop cycles
			#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE_MINI) || defined(ARDUINO_M5Atom_Matrix_ESP32)
				updateMicrobitDisplay();
			#endif
			checkButtons();
			processMessage();
			count = 25; // must be under 30 when building on mbed to avoid serial errors
		}
		uint32 usecs = 0; // compute times only the first time they are needed
		for (int t = 0; t < taskCount; t++) {
			currentTaskIndex++;
			if (currentTaskIndex >= taskCount) currentTaskIndex = 0;
			Task *task = &tasks[currentTaskIndex];
			if (unusedTask == task->status) {
				continue;
			} else if (running == task->status) {
				runTask(task);
				break;
			} else if (waiting_micros == task->status) {
				if (!usecs) usecs = microsecs(); // get usecs
				if ((usecs - task->wakeTime) < RECENT) task->status = running;
			}
			if (running == task->status) {
				runTask(task);
				break;
			}
		}
	}
}

// Testing

void runTasksUntilDone() {
	// Used for testing/benchmarking the interpreter. Run all tasks to completion.

	int count = 0;
	int hasActiveTasks = true;
	while (hasActiveTasks) {
		if (count-- <= 0) {
			processMessage();
			count = 100; // reduce to 30 when building on mbed to avoid serial errors
		}
		hasActiveTasks = false;
		uint32 usecs = 0; // compute times only the first time they are needed
		for (int t = 0; t < taskCount; t++) {
			Task *task = &tasks[t];
			if (running == task->status) {
				runTask(task);
				hasActiveTasks = true;
				continue;
			} else if (unusedTask == task->status) {
				continue;
			} else if (waiting_micros == task->status) {
				if (!usecs) usecs = microsecs(); // get usecs
				if ((usecs - task->wakeTime) < RECENT) task->status = running;
			}
			if (running == task->status) runTask(task);
			hasActiveTasks = true;
		}
	}
}
