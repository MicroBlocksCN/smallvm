/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// interp.c - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#define _DEFAULT_SOURCE // enable usleep() declaration from unistd.h

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// Tasks - Set USE_TASKS to false to test interpreter performance without task switching

#define USE_TASKS true

// RECENT is a threshold for waking up tasks waiting on timers
// The timer can be up to this many usecs past the wakeup time.

#define RECENT 10000000

// Interpreter State

CodeChunkRecord chunks[MAX_CHUNKS];

Task tasks[MAX_TASKS];
int taskCount = 0;

OBJ vars[MAX_VARS];

// Error Reporting

// When a primitive encounters an error, it calls fail() with an error code.
// The VM stops the task and records the error code and IP where the error occurred.

static uint8 errorCode = noError;
static int taskSleepMSecs = 0;

OBJ fail(uint8 errCode) {
	errorCode = errCode;
	return falseObj;
}

int failure() {
	return errorCode != noError;
}

#ifndef EMSCRIPTEN
	void taskSleep(int msecs) {
		// Make the current task sleep for the given number of milliseconds to free up cycles.
		taskSleepMSecs = msecs;
		errorCode = sleepSignal;
	}
#endif

// Printing

#define PRINT_BUF_SIZE 1000
static char printBuffer[PRINT_BUF_SIZE];
static int printBufferByteCount = 0;

int extraByteDelay = 1000; // default of 1000 usecs assumes serial throughput of ~1000 bytes/sec

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
		int len = strlen(obj2str(value));
		if (len > 800) len = 800;
		return headerBytes + len;
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

OBJ primBroadcastToIDEOnly(int argCount, OBJ *args) {
	// Broadcast a string to the IDE only, not locally.

	printArgs(argCount, args, false, false);
	sendBroadcastToIDE(printBuffer, printBufferByteCount);
	return falseObj;
}

// Timing Support

static uint32 timerStart = 0;

void resetTimer() { timerStart = millisecs(); }

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

static OBJ primMSecsSince(int argCount, OBJ *args) {
	int startTime = obj2int(args[0]);
	int endTime = ((argCount > 1) && isInt(args[1])) ?
		obj2int(args[1]) :
		((uint32) ((totalMicrosecs() / 1000))) & 0x3FFFFFFF;

	int deltaTime = endTime - startTime;
	if (deltaTime < 0) deltaTime += 0x40000000;
	return int2obj(deltaTime);
}

static OBJ primUSecsSince(int argCount, OBJ *args) {
	int startTime = obj2int(args[0]);
	int endTime = ((argCount > 1) && isInt(args[1])) ?
		obj2int(args[1]) :
		microsecs() & 0x3FFFFFFF;

	int deltaTime = endTime - startTime;
	if (deltaTime < 0) deltaTime += 0x40000000;
	return int2obj(deltaTime);
}

// String Access

static inline char * nextUTF8(char *s) {
	// Return a pointer to the start of the UTF8 character following the given one.
	// If s points to a null byte (i.e. end of the string) return it unchanged.

	if (!*s) return s; // end of string
	if ((uint8) *s < 128) return s + 1; // single-byte character
	if (0xC0 == (*s & 0xC0)) s++; // start of multi-byte character
	while (0x80 == (*s & 0xC0)) s++; // skip continuation bytes
	return s;
}

static int countUTF8(char *s) {
	int count = 0;
	while (*s) {
		s = nextUTF8(s);
		count++;
	}
	return count;
}

static OBJ charAt(OBJ stringObj, int i) {
	char *start = obj2str(stringObj);
	while (i-- > 1) { // find start of the ith Unicode character
		if (!*start) return fail(indexOutOfRangeError); // end of string
		start = nextUTF8(start);
	}
	int byteCount = nextUTF8(start) - start;
	OBJ result = newString(byteCount);
	if (result) {
		memcpy(obj2str(result), start, byteCount);
	}
	return result;
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

static OBJ primModulo(int argCount, OBJ *args) {
	int n = evalInt(args[0]);
	int modulus = evalInt(args[1]);
	if (0 == modulus) return fail(zeroDivide);
	if (modulus < 0) modulus = -modulus;
	int result = n % modulus;
	if (result < 0) result += modulus;
	return int2obj(result);
}

static OBJ primRandom(int argCount, OBJ *args) {
	int first = 1, last = 100; // defaults for zero arguments
	if (argCount == 1) { // use range [1..arg]
		first = 1;
		last = evalInt(args[0]);
		if (last < 0) first = -1;
	} else if (argCount == 2) { // use range [first..last]
		first = evalInt(args[0]);
		last = evalInt(args[1]);
	}
	if (first > last) { // ensure first <= last
		int tmp = first;
		first = last;
		last = tmp;
	}
	int range = (last + 1) - first; // if first == last range is 1 and first is returned
	return int2obj(first + (rand() % range)); // result range is [first..last], inclusive
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

static inline int compareObjects(OBJ obj1, OBJ obj2) {
	// Compare two objects with the given operator and return one of:
	//	-1 (<), 0 (==), 1 (>)
	// For mixed string-int comparison, try to convert the string to an integer.
	// Set nonComparableError flag if the objects are not comparable.

	int n1 = 0, n2 = 0;
	if (IS_TYPE(obj1, StringType) && IS_TYPE(obj2, StringType)) {
		return strcmp(obj2str(obj1), obj2str(obj2));
	} else if (IS_TYPE(obj1, StringType) && isInt(obj2)) {
		n1 = strtol(obj2str(obj1), NULL, 10);
		n2 = obj2int(obj2);
	} else if (isInt(obj1) && IS_TYPE(obj2, StringType)) {
		n1 = obj2int(obj1);
		n2 = strtol(obj2str(obj2), NULL, 10);
	} else if (isInt(obj1) && isInt(obj2)) {
		// Note: For efficiency, caller should handle this special case
		n1 = obj2int(obj1);
		n2 = obj2int(obj2);
	} else {
		fail(nonComparableError);
	}
	if (n1 < n2) return -1;
	if (n1 > n2) return 1;
	return 0;
}

static OBJ primCompare(int op, OBJ obj1, OBJ obj2) {
	// Compare objects with the given operator:
	//	-2 (<), -1 (<=), 0 (==), 1 (>=), 2 (>)
	// Return a boolean. Set nonComparableError error if objects are not comparable.

	int result = compareObjects(obj1, obj2);
	if (result < 0) return (op < 0) ? trueObj : falseObj;
	if (result > 0) return (op > 0) ? trueObj : falseObj;
	return ((-1 <= op) && (op <= 1)) ? trueObj : falseObj;
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

static OBJ argOrDefault(OBJ *fp, int argNum, OBJ defaultValue) {
	// Useful for working with optional arguments.
	// Return the given argument or defaultValue if the argument was not supplied by the caller.

	if (argNum < 1) return defaultValue; // argNum index is 1-based
	int actualArgCount = obj2int(*(fp - 3));
	if (argNum > actualArgCount) return defaultValue; // argument not supplied, return default
	return *(fp - (4 + actualArgCount) + argNum); // return the desired argument
}

static int functionNameMatches(int chunkIndex, char *functionName) {
	// Return true if given chunk is the function with the given function name.
	// Use the function name in the function's metadata.
	// Scan backwards from the end of the chunk to avoid possible
	// matches of the meta flag with offsets in instructions.
	// Note: 248 (0xF8) is not a valid byte in UTF-8 encoding

	const uint8 META_FLAG = 248;
	char *metaData = NULL;
	uint32 *code = (uint32 *) chunks[chunkIndex].code;
	uint8 *chunkStart = (uint8 *) (code + PERSISTENT_HEADER_WORDS);
	uint8 *src = chunkStart + (4 * code[1]) - 1; // start at last byte
	while (src > chunkStart) {
		if (META_FLAG == *src) {
			metaData = (char *) src + 1;
			break;
		}
		src--; // scan backwards to find start of metadata
	}
	if (!metaData) return false; // no metadata

	// return true if metaDat starts with the given function name
	return (strstr(metaData, functionName) == metaData);
}

static int chunkIndexForFunction(char *functionName) {
	// Return the chunk index for the function with the given name or -1 if not found.

	int nameLength = strlen(functionName);
	for (int i = 0; i < MAX_CHUNKS; i++) {
		int chunkType = chunks[i].chunkType;
		if (functionHat == chunkType) {
			if (broadcastMatches(i, functionName, nameLength)) return i;
			if (functionNameMatches(i, functionName)) return i;
		}
	}
	return -1;
}

PrimitiveFunction findPrimitive(char *namedPrimitive);

static int findCallee(char *functionOrPrimitiveName) {
	// Look for a primitive match first since that is fast
	PrimitiveFunction f = findPrimitive(functionOrPrimitiveName);
	if (f) return (int) f;

	// Look for a user-defined function match (slow if no match found!)
	int result = chunkIndexForFunction(functionOrPrimitiveName);
	if (result >= 0) return (0xFFFFFF00 | result); // set top 24 bits to show callee is a chunk
	// assume: result < 256 (MAX_CHUNKS) so it fits in low 8 bits

	fail(primitiveNotImplemented);
	return -1;
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

static void interpDebug(int ip, int cmd, int arg, int sp) {
	// Show interpreter state for debugging.

	char tmpStr[100];
	sprintf(tmpStr, "ip: %d cmd: %d arg: %d sp: %d", ip - 4, cmd, arg, sp);
	outputString(tmpStr); \
}

// Macro to inline dispatch in the end of each opcode (avoiding a jump back to the top)
#define DISPATCH() { \
	if (errorCode) goto error; \
	op = *ip++; \
	arg = ARG(op); \
	task->sp = sp - task->stack; /* record stack pointer for garbage collector */ \
	/* interpDebug((ip - (int16 *) task->code), CMD(op), arg, task->sp); */ \
	goto *jumpTable[CMD(op)]; \
}

// Macro for debugging stack errors
#define SHOW_SP(s) { \
	outputString(s); \
	reportNum("sp", sp - task->stack); \
	reportNum("fp", fp - task->stack); \
}

static void runTask(Task *task) {
	register int op;
	register int16 *ip;
	register OBJ *sp;
	register OBJ *fp;
	int arg, tmp;
	OBJ tmpObj;

	// initialize jump table
	static void *jumpTable[] = {
		&&halt_op,					// stop this task
		&&stopAll_op,				// stop all tasks except this one
		&&pushImmediate_op,			// true, false, and ints that fit in 8 bits [-64..63]
		&&pushLargeInteger_op,		// ints that fit in 24 bits
		&&pushHugeInteger_op,		// ints that need > 24 bits
		&&pushLiteral_op,			// string constant from literals frame
		&&pushGlobal_op,
		&&storeGlobal_op,
		&&incrementGlobal_op,
		&&initLocals_op,
		&&pushLocal_op,				// 10
		&&storeLocal_op,
		&&incrementLocal_op,
		&&pushArg_op,
		&&storeArg_op,
		&&incrementArg_op,			// 15
		&&pushArgCount_op,
		&&getArg_op,
		&&argOrDefault_op,
		&&pop_op,
		&&ignoreArgs_op,			// 20 (alias for pop_op)
		&&noop_op,
		&&jmp_op,
		&&longJmp_op,				// (alias for jmp_op)
		&&jmpTrue_op,
		&&jmpFalse_op,				// 25
		&&decrementAndJmp_op,
		&&forLoop_op,
		&&jmpOr_op,
		&&jmpAnd_op,
		&&waitUntil_op,				// 30 (alias for jmpFalse_op)
	&&RESERVED_op,
		&&waitMicros_op,
		&&waitMillis_op,
		&&callFunction_op,
		&&returnResult_op,			// 35
		&&commandPrimitive_op,
		&&reporterPrimitive_op,
		&&callCustomCommand_op,
		&&callCustomReporter_op,
		&&sendBroadcast_op,			// 40
		&&recvBroadcast_op,
		&&getLastBroadcast_op,
		&&millis_op,
		&&micros_op,
		&&secs_op,					// 45
		&&millisSince_op,
		&&microsSince_op,
		&&timer_op,
		&&resetTimer_op,
		&&add_op,					// 50
		&&subtract_op,
		&&multiply_op,
		&&divide_op,
		&&modulo_op,
		&&bitAnd_op,				// 55
		&&bitOr_op,
		&&bitXor_op,
		&&bitInvert_op,
		&&bitShiftLeft_op,
		&&bitShiftRight_op,			// 60
		&&lessThan_op,
		&&lessOrEq_op,
		&&equal_op,
		&&notEqual_op,
		&&greaterOrEq_op,			// 65
		&&greaterThan_op,
		&&not_op,
	&&RESERVED_op,
	&&RESERVED_op,
		&&longMultiply_op,			// 70
		&&absoluteValue_op,
		&&minimum_op,
		&&maximum_op,
		&&random_op,
		&&hexToInt_op,				// 75
		&&isType_op,
		&&sayIt_op,
		&&graphIt_op,
		&&boardType_op,
		&&newList_op,				// 80
		&&at_op,
		&&atPut_op,
		&&size_op,
		&&analogPins_op,
		&&digitalPins_op,			// 85
		&&analogRead_op,
		&&analogWrite_op,
		&&digitalRead_op,
		&&digitalWrite_op,
		&&digitalSet_op,			// 90
		&&digitalClear_op,
		&&buttonA_op,
		&&buttonB_op,
		&&setUserLED_op,
		&&i2cSet_op,				// 95
		&&i2cGet_op,
		&&spiSend_op,
		&&spiRecv_op,
	&&RESERVED_op,
	&&RESERVED_op,					// 100
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
		&&comment_op,				// (alias for noop_op)
		&&codeEnd_op,				// 127 (alias for halt_op)
	};

	// Restore task state
	ip = (int16 *) task->code + task->ip;
	sp = task->stack + task->sp;
	fp = task->stack + task->fp;

	DISPATCH();

	error:
		// sleepSignal is not a actual error; it just suspends the current task
		if (sleepSignal == errorCode) {
			errorCode = noError; // clear the error
			if (taskSleepMSecs > 0) {
				task->status = waiting_micros;
				task->wakeTime = microsecs() + (taskSleepMSecs * 1000);
			}
			goto suspend;
		}
		// tmp encodes the error location: <22 bit ip><8 bit chunkIndex>
		tmp = ((ip - (int16 *) task->code) << 8) | (task->currentChunkIndex & 0xFF);
		sendTaskError(task->taskChunkIndex, errorCode, tmp);
		task->status = unusedTask;
		if (unusedTask == tasks[taskCount - 1].status) taskCount--;
		errorCode = noError; // clear the error
		goto suspend;
	suspend:
		// save task state
		task->ip = ip - (int16 *) task->code;
		task->sp = sp - task->stack;
		task->fp = fp - task->stack;
		return;
	RESERVED_op:
	halt_op:
	codeEnd_op:
		sendTaskDone(task->taskChunkIndex);
		task->status = unusedTask;
		if (unusedTask == tasks[taskCount - 1].status) taskCount--;
		goto suspend;
	noop_op:
	comment_op:
		POP_ARGS_COMMAND();
		DISPATCH();
	pushImmediate_op:
		STACK_CHECK(1);
		*sp++ = (OBJ) arg;
		DISPATCH();
	pushLargeInteger_op:
		// push an integer object that fits into 24 bits
		STACK_CHECK(1);
		tmp = (*ip++ << 8) | (arg & 0xFF); // most significant bits are in the following 16-bit word
		*sp++ = (OBJ) tmp;
		DISPATCH();
	pushLiteral_op:
		STACK_CHECK(1);
		tmp = *ip; // offset to the literal is in the following 16-bit word
		*sp++ = (OBJ) (ip++ + tmp);
		DISPATCH();
	pushGlobal_op:
		STACK_CHECK(1);
		*sp++ = vars[arg];
		DISPATCH();
	storeGlobal_op:
		vars[arg] = *--sp;
		DISPATCH();
	incrementGlobal_op:
		tmp = evalInt(vars[arg]);
		if (!errorCode) {
			vars[arg] = int2obj(tmp + evalInt(*--sp));
		}
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
	ignoreArgs_op:
		sp -= arg;
		if (sp >= task->stack) {
			DISPATCH();
		} else {
			vmPanic("Stack underflow");
		}
		DISPATCH();
	jmp_op:
	longJmp_op:
		if (!arg) arg = *ip++; // zero arg means offset is in the next word
		ip += arg;
#if USE_TASKS
		if (arg < 0) goto suspend;
#endif
		DISPATCH();
	jmpTrue_op:
		if (!arg) arg = *ip++; // zero arg means offset is in the next word
		if (trueObj == (*--sp)) ip += arg;
#if USE_TASKS
		if ((arg < 0) && (trueObj == *sp)) goto suspend;
#endif
		DISPATCH();
	jmpFalse_op:
	waitUntil_op:
		if (!arg) arg = *ip++; // zero arg means offset is in the next word
		if (trueObj != (*--sp)) ip += arg; // treat any value but true as false
#if USE_TASKS
		if ((arg < 0) && (trueObj != *sp)) goto suspend;
#endif
		DISPATCH();
	 decrementAndJmp_op:
		if (!arg) arg = *ip++; // zero arg means offset is in the next word
		if (isInt(*(sp - 1))) {
			tmp = obj2int(*(sp - 1)) - 1; // decrement loop counter (normal case)
		} else {
			tmp = evalInt(*(sp - 1)) - 1; // decrement loop counter (first time: convert string to int if needed)
		}
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
		arg = *ip++;
	callFunctionByName:
		tmp = (arg >> 8) & 0xFF; // callee's chunk index (middle byte of arg)
		if (chunks[tmp].chunkType != functionHat) {
			fail(badChunkIndexError);
			goto error;
		}
		STACK_CHECK(3);
		*sp++ = int2obj(arg & 0xFF); // # of arguments (low byte of arg)
		*sp++ = int2obj(((ip - (int16 *) task->code) << 8) | (task->currentChunkIndex & 0xFF)); // return address
		*sp++ = int2obj(fp - task->stack); // old fp
		fp = sp;
		task->currentChunkIndex = tmp; // callee's chunk index (middle byte of arg)
		task->code = chunks[task->currentChunkIndex].code;
		ip = (int16 *) (task->code + PERSISTENT_HEADER_WORDS); // first instruction in callee
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
		ip = ((int16 *) task->code) + ((tmp >> 8) & 0x3FFFFF); // restore old ip
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
		task->wakeTime = (microsecs() + tmp) - 7; // adjusted for approximate scheduler overhead
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
		task->wakeTime = microsecs() + ((1000 * tmp) - 7);
		goto suspend;
	sendBroadcast_op:
		primSendBroadcast(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	recvBroadcast_op:
		POP_ARGS_COMMAND(); // pop the broadcast name (a literal string)
		DISPATCH();
	stopAll_op:
		stopAllTasksButThis(task); // clears all tasks except the current one
		DISPATCH();
	forLoop_op:
		// stack layout:
		// *(sp - 1) the loop counter (decreases from N to 1); falseObj the very first time
		// *(sp - 2) N, the total loop count or item count of a list, string or byte array
		// *(sp - 3) the object being iterated over: an integer, list, string, or byte array

		tmpObj = *(sp - 1); // loop counter, or falseObj the very first time
		if (falseObj == tmpObj) { // first time: compute N, the total iterations (in tmp)
			tmpObj = *(sp - 3);
			if (isInt(tmpObj)) {
				tmp = obj2int(tmpObj);
			} else if (IS_TYPE(tmpObj, ListType)) {
				tmp = obj2int(FIELD(tmpObj, 0));
			} else if (IS_TYPE(tmpObj, StringType)) {
				tmp = countUTF8(obj2str(tmpObj));
			} else if (IS_TYPE(tmpObj, ByteArrayType)) {
				tmp = BYTES(tmpObj);
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
				*(fp + arg) = FIELD(tmpObj, tmp + 1); // skip count field
			} else if (IS_TYPE(tmpObj, StringType)) {
				// set the index variable to the next character of a string
				*(fp + arg) = charAt(tmpObj, tmp + 1);
			} else if (IS_TYPE(tmpObj, ByteArrayType)) {
				// set the index variable to the next byte of a byte array
				*(fp + arg) = int2obj(((uint8 *) &FIELD(tmpObj, 0))[tmp]);
			} else {
				fail(badForLoopArg);
				goto error;
			}
		} else { // loop counter <= 0
			ip += 2; // skip the following longJmp instruction (two words) thus ending the loop
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
		if (!arg) arg = *ip++; // zero arg means offset is in the next word
		// if true, jump leaving true (result of "or" expression) on stack, otherwise pop
		if (trueObj == *(sp - 1)) { ip += arg; } else { sp--; }
		DISPATCH();
	jmpAnd_op:
		if (!arg) arg = *ip++; // zero arg means offset is in the next word
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
		tmpObj = *(sp - 2);
		if (isInt(tmpObj) && isInt(*(sp - 1))) { // special case for integers:
			*(sp - arg) = (obj2int(tmpObj) < obj2int(*(sp - 1))) ? trueObj : falseObj;
		} else {
			*(sp - arg) = primCompare(-2, tmpObj, *(sp - 1));
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	lessOrEq_op:
		tmpObj = *(sp - 2);
		if (isInt(tmpObj) && isInt(*(sp - 1))) { // special case for integers:
			*(sp - arg) = (obj2int(tmpObj) <= obj2int(*(sp - 1))) ? trueObj : falseObj;
		} else {
			*(sp - arg) = primCompare(-1, tmpObj, *(sp - 1));
		}
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
		tmpObj = *(sp - 2);
		if (isInt(tmpObj) && isInt(*(sp - 1))) { // special case for integers:
			*(sp - arg) = (obj2int(tmpObj) >= obj2int(*(sp - 1))) ? trueObj : falseObj;
		} else {
			*(sp - arg) = primCompare(1, tmpObj, *(sp - 1));
		}
		POP_ARGS_REPORTER();
		DISPATCH();
	greaterThan_op:
		tmpObj = *(sp - 2);
		if (isInt(tmpObj) && isInt(*(sp - 1))) { // special case for integers:
			*(sp - arg) = (obj2int(tmpObj) > obj2int(*(sp - 1))) ? trueObj : falseObj;
		} else {
			*(sp - arg) = primCompare(2, tmpObj, *(sp - 1));
		}
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
		*(sp - arg) = primModulo(arg, sp - arg);
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
	at_op:
		*(sp - arg) = primAt(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	atPut_op:
		primAtPut(arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	size_op:
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
		*sp++ = int2obj((uint32) ((totalMicrosecs() / 1000) & 0x3FFFFFFF)); // result range is 0 - 1073741823
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
		if (!ideConnected()) {
			POP_ARGS_COMMAND(); // serial port not open; do nothing
			DISPATCH();
		}
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
	graphIt_op:
		if (!ideConnected()) {
			POP_ARGS_COMMAND(); // serial port not open; do nothing
			DISPATCH();
		}
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
	argOrDefault_op:
		if (arg < 2) {
			*(sp - arg) = fail(notEnoughArguments); // not enough arguments to primitive
		} else if (fp <= task->stack) {
			*(sp - arg) = *(sp - 1); // not in a function call; return default value
		} else {
			*(sp - arg) = argOrDefault(fp, obj2int(*(sp - 2)), *(sp - 1));
		}
		POP_ARGS_REPORTER();
		DISPATCH();

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

	// more time operations
	secs_op:
		STACK_CHECK(1);
		*sp++ = int2obj((uint32) ((totalMicrosecs() / 1000000)) & 0x3FFFFFFF); // result range is 0 - 1073741823
		DISPATCH();
	millisSince_op:
		*(sp - arg) = primMSecsSince(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	microsSince_op:
		*(sp - arg) = primUSecsSince(arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();

	pushHugeInteger_op:
		// push integer object that requires 32 bits
		STACK_CHECK(1);
		tmp = (uint16) *ip++; // least significant bits
		tmp |= (uint16) *ip++ << 16; // most significant bits
		*sp++ = (OBJ) tmp;
		DISPATCH();

	// new primitive call ops:
	commandPrimitive_op:
		tmp = (*ip >> 10) & 0x3F; // primitive set index
		tmpObj = (OBJ) (ip + (*ip & 0x3FF)); // primitive name object
		ip++; // skip second instruction word
		arg = arg & 0xFF; // argument count
		newPrimitiveCall(tmp, obj2str(tmpObj), arg, sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	reporterPrimitive_op:
		tmp = (*ip >> 10) & 0x3F; // primitive set index
		tmpObj = (OBJ) (ip + (*ip & 0x3FF)); // primitive name object
		ip++; // skip second instruction word
		arg = arg & 0xFF; // argument count
		*(sp - arg) = newPrimitiveCall(tmp, obj2str(tmpObj), arg, sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();

	// call a function using the function name and parameter list:
	callCustomCommand_op:
	callCustomReporter_op:
		if (arg > 0) {
			taskSleep(-1); // do background VM tasks sooner
			uint32 callee = -1;
			OBJ params = *(sp - 1); // save the parameters array, if any
			// look up the function or primitive name
			if ((arg == 1) && (IS_TYPE(*(sp - 1), StringType))) {
				callee = findCallee(obj2str(*(sp - 1)));
			} else if ((arg == 2) && (IS_TYPE(*(sp - 2), StringType))) {
				callee = findCallee(obj2str(*(sp - 2)));
			}
			POP_ARGS_COMMAND();
			if (callee != -1) { // found a callee
				int paramCount = 0;
				if (arg == 2) { // has an optional parameters list (the second argument)
					if (IS_TYPE(params, ListType)) { // push the parameters onto the stack
						paramCount = (obj2int(FIELD(params, 0)) & 0xFF);
						for (int i = 1; i <= paramCount; i++) {
							*sp++ = FIELD(params, i);
						}
					} else { // fail: parameters must be a list
						*sp++ = fail(needsListError);
						DISPATCH();
					}
				}

				// invoke the callee
				task->sp = sp - task->stack; // record the stack pointer in case callee does a GC
				if ((callee & 0xFFFFFF00) == 0xFFFFFF00) { // callee is a MicroBlocks function (i.e. a chunk index)
					arg = ((callee & 0xFF) << 8) | paramCount;
					goto callFunctionByName;
				} else { // callee is a named primitive (i.e. a pointer to a C function)
					tmpObj = ((PrimitiveFunction) callee)(paramCount, sp - paramCount); // call the primitive
					tempGCRoot = NULL; // clear tempGCRoot in case it was used
					sp -= paramCount;
					*sp++ = tmpObj; // push primitive return value
					DISPATCH();
				}
			}
		}
		// failed: bad arguments
		*sp++ = falseObj; // push a dummy return value
		DISPATCH();
}

// Interpreter Entry Point

#if !defined(EMSCRIPTEN)

void vmLoop() {
	// Run the next runnable task. Wake up any waiting tasks whose wakeup time has arrived.

	int currentTaskIndex = 0;
	int count = 0;
	while (true) {
		if (count-- < 0) {
			// do background VM tasks once every N VM loop cycles
			processMessage();
			checkButtons();
			#if defined(HAS_LED_MATRIX)
				updateMicrobitDisplay();
			#endif
			#if defined(COCUBE)
				cocubeSensorUpdate();
			#endif
			handleMicosecondClockWrap();
			count = 95; // must be under 30 when building on mbed to avoid serial errors
		} else if ((count & 0xF) == 0) {
			captureIncomingBytes();
		}
		int runCount = 0;
		uint32 usecs = 0; // compute times only the first time they are needed
		for (int t = 0; t < taskCount; t++) {
			currentTaskIndex++;
			if (currentTaskIndex >= taskCount) currentTaskIndex = 0;
			Task *task = &tasks[currentTaskIndex];
			if (unusedTask == task->status) {
				continue;
			} else if (running == task->status) {
				runTask(task);
				runCount++;
				break;
			} else if (waiting_micros == task->status) {
				if (!usecs) usecs = microsecs(); // get usecs
				if ((usecs - task->wakeTime) < RECENT) {
					task->status = running;
					runTask(task);
					runCount++;
					break;
				}
			}
		}
		if (taskSleepMSecs) {
			// if any task called taskSleep(), do VM background tasks sooner
			taskSleepMSecs = 0;
			count = (count < 5) ? count : 5;
		}

#ifdef GNUBLOCKS
		if (!runCount) { // no active tasks; consider taking a nap
			if (!usecs) usecs = microsecs(); // get usecs
			int sleepUSecs = 500;
			for (int i = 0; i < taskCount; i++) {
				Task *task = &tasks[i];
				if (waiting_micros == task->status) {
					int usecsUntilWake = (task->wakeTime - usecs) - 5; // leave 5 extra usecs
					if ((usecsUntilWake > 0) && (usecsUntilWake < sleepUSecs)) {
						sleepUSecs = usecsUntilWake;
					}
				}
			}
			if (sleepUSecs > 5) usleep(sleepUSecs); // nap a while to relinquish the CPU
		}
#endif
	}
}

#endif // not EMSCRIPTEN

// Boardie support

#ifdef EMSCRIPTEN

#include <emscripten.h>

#define CLOCK_MASK 0xFFFFFFFF

int shouldYield = false;
void EMSCRIPTEN_KEEPALIVE taskSleep(int msecs) { shouldYield = true; }

static int currentTaskIndex = 0; // remember this across calls to interpretStep()

void interpretStep() {
	uint32 endTime = millisecs() + 15;
	processMessage();
	checkButtons();
	updateMicrobitDisplay();
	shouldYield = false;
	while ((millisecs() < endTime) && !shouldYield) {
		// Run the next runnable task. Wake up any waiting tasks whose wakeup time has arrived.
		int runCount = 0;
		uint32 usecs = microsecs(); // get usecs
		for (int t = 0; t < taskCount; t++) {
			currentTaskIndex++;
			if (currentTaskIndex >= taskCount) currentTaskIndex = 0;
			Task *task = &tasks[currentTaskIndex];
			if (unusedTask == task->status) {
				continue;
			} else if (running == task->status) {
				runTask(task);
				runCount++;
				break;
			} else if (waiting_micros == task->status) {
				if (((usecs - task->wakeTime) & CLOCK_MASK) < RECENT) task->status = running;
			}
			if (running == task->status) {
				runTask(task);
				runCount++;
				break;
			}
		}
		if (!runCount) { // no active tasks; consider taking a nap
			usecs = microsecs(); // get usecs
			int sleepUSecs = 100000;
			for (int i = 0; i < taskCount; i++) {
				Task *task = &tasks[i];
				if (waiting_micros == task->status) {
					int usecsUntilWake = (task->wakeTime - usecs) & CLOCK_MASK;
					if ((usecsUntilWake > 0) && (usecsUntilWake < sleepUSecs)) {
						sleepUSecs = usecsUntilWake;
					}
				}
			}
			if (sleepUSecs > 2000) {
				shouldYield = true;
				break;
			} // relinquish control
		}
	}
}

#endif

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
