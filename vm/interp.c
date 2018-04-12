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
// The timer can be up to this much past the wakeup time.

#define RECENT 100000

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

#define PRINT_BUF_SIZE 100
static char printBuffer[PRINT_BUF_SIZE];
static int printBufferByteCount = 0;

static void printObj(OBJ obj) {
	// Append a printed representation of the given object to printBuffer.

	char *dst = &printBuffer[printBufferByteCount];
	int n = PRINT_BUF_SIZE - printBufferByteCount;

	if (isInt(obj)) snprintf(dst, n, "%d ", obj2int(obj));
	else if (obj == falseObj) snprintf(dst, n, "false ");
	else if (obj == trueObj) snprintf(dst, n, "true ");
	else if (objClass(obj) == StringClass) {
		snprintf(dst, n, "%s ", obj2str(obj));
	} else {
		snprintf(dst, n, "OBJ(addr: %d, class: %d) ", (int) obj, objClass(obj));
	}
	printBufferByteCount = strlen(printBuffer);
}

static void primPrint(int argCount, OBJ *args) {
	// This is a variadic "print" for the GP IDE.

	printBuffer[0] = 0; // null terminate
	printBufferByteCount = 0;

	for (int i = 0; i < argCount; i++) {
		printObj(args[i]);
	}
	if (printBufferByteCount && (' ' == printBuffer[printBufferByteCount - 1])) {
		// Remove final space character
		printBuffer[printBufferByteCount - 1] = 0; // null terminate
		printBufferByteCount--;
	}
#if USE_TASKS
	outputString(printBuffer);
#else
	printf("(NO TASKS) %s\r\n", printBuffer);
#endif
}

static int bytesForObject(OBJ value) {
	// Return the number of bytes needed to transmit the given value.

	int headerBytes = 6; // message header (5 bytes) + type byte
	if (isInt(value)) { // 32-bit integer
		return headerBytes + 4;
	} else if (IS_CLASS(value, StringClass)) { // string
		return headerBytes + strlen(obj2str(value));
	} else if ((value == trueObj) || (value == falseObj)) { // boolean
		return headerBytes + 1;
	}
	return 0; // arrays and byte arrays are not yet serializeable
}

// Broadcast

static void primSendBroadcast(OBJ *args) {
	if (IS_CLASS(args[0], StringClass)) {
		char *s = obj2str(args[0]);
		startReceiversOfBroadcast(s, strlen(s));
		sendBroadcastToIDE(s);
	}
}

// Interpreter

// Macros to pop arguments for commands and reporters (pops args, leaves result on stack)
#define POP_ARGS_COMMAND() { sp -= arg; }
#define POP_ARGS_REPORTER() { sp -= arg - 1; }

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
		&&stopAll_op,
		&&forLoop_op,
		&&initLocals_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
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
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&newArray_op,
		&&newByteArray_op,
		&&fillArray_op,
		&&at_op,
		&&atPut_op,
		&&size_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&millis_op,
		&&micros_op,
		&&peek_op,
		&&poke_op,
		&&sayIt_op,
		&&printIt_op,
		&&RESERVED_op,
		&&RESERVED_op,
		&&RESERVED_op,
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
	storeVar_op:
		vars[arg] = *--sp;
		DISPATCH();
	incrementVar_op:
		tmp = isInt(vars[arg]) ? evalInt(vars[arg]) : 0;
		vars[arg] = int2obj(tmp + evalInt(*--sp));
		DISPATCH();
	pushArgCount_op:
		*sp++ = IN_CALL() ? *(fp - 3) : 0;
		DISPATCH();
	pushArg_op:
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
			tmpObj = *(fp - obj2int(*(fp - 3)) - 3 + arg);
			tmp = isInt(tmpObj) ? evalInt(tmpObj) : 0;
			*(fp - obj2int(*(fp - 3)) - 3 + arg) = int2obj(tmp + evalInt(*--sp));
		} else {
			fail(notInFunction);
		}
		DISPATCH();
	pushLocal_op:
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
		if (falseObj == (*--sp)) ip += arg;
#if USE_TASKS
		if ((arg < 0) && (falseObj == *sp)) goto suspend;
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
		task->currentChunkIndex = arg & 0xFF; // callee's chunk index (low byte of arg)
		task->code = chunks[task->currentChunkIndex].code;
		ip = task->code + PERSISTENT_HEADER_WORDS; // first instruction in callee
		DISPATCH();
	returnResult_op:
		tmpObj = *(sp - 1); // return value
		if (fp == task->stack) { // not in a function call
			if (!hasOutputSpace(bytesForObject(*(sp - 1)) + 100)) { // leave room for other messages
				ip--; // retry when task is resumed
				goto suspend;
			}
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
	 	POP_ARGS_COMMAND();
	 	if (tmp <= 30) {
			// busy-wait for wait times up to 30 usecs to avoid a context switch
			tmp = (microsecs() + tmp) - 8; // wake time, adjusted for dispatch overhead
			while ((microsecs() - tmp) >= RECENT) /* busy wait */;
			DISPATCH();
		}
		task->status = waiting_micros;
		task->wakeTime = (microsecs() + tmp) - 17; // adjusted for approximate scheduler overhead
		goto suspend;
	waitMillis_op:
	 	tmp = evalInt(*(sp - 1)); // wait time in usecs
	 	POP_ARGS_COMMAND();
	 	if (tmp < 1000) {
	 		// use usecs for waits under a second for greater precision
			task->status = waiting_micros;
			task->wakeTime = microsecs() + ((1000 * tmp) - 17);
	 	} else {
			task->status = waiting_millis;
			task->wakeTime = millisecs() + tmp;
		}
		goto suspend;
	sendBroadcast_op:
		primSendBroadcast(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	recvBroadcast_op:
		POP_ARGS_COMMAND(); // pop the broadcast name (a literal string)
		DISPATCH();
	stopAll_op:
		stopAllTasks(); // clears all tasks, including the current one
		return;
	forLoop_op:
		// stack layout:
		// *(sp - 1) the loop counter (decreases from N to 1); falseObj the very first time
		// *(sp - 2) N, the total loop count or size of the array/bytearray argument
		// *(sp - 3) the object being iterated over, a positive integer, array, or bytearray

		tmpObj = *(sp - 1); // loop counter, or falseObj the very first time
		if (falseObj == tmpObj) { // first time: compute N, the total iterations (in tmp)
			tmpObj = *(sp - 3);
			if (isInt(tmpObj)) {
				tmp = obj2int(tmpObj);
			} else if (IS_CLASS(tmpObj, ArrayClass)) {
				tmp = objWords(tmpObj);
			} else if (IS_CLASS(tmpObj, ByteArrayClass)) {
				tmp = 4 * objWords(tmpObj);
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
				*(fp + arg) = int2obj(tmp + 1); // add 1 get range 1 to N
			} else if (IS_CLASS(tmpObj, ArrayClass)) {
				// set the index variable to the array element at the index variable
				*(fp + arg) = FIELD(tmpObj, tmp); // array elements
			} else if (IS_CLASS(tmpObj, ByteArrayClass)) {
				// set the index variable to the byte at the index variable
				*(fp + arg) = int2obj( ((uint8 *) &FIELD(tmpObj, 0))[tmp] ); // bytearray elements
			} else {
				fail(badForLoopArg);
				goto error;
			}
		} else { // loop counter <= 0
			ip++; // skip the following jmp instruction thus ending the loop
		}
		DISPATCH();
	initLocals_op:
		// Reserve stack space for arg locals initialized to false
		while (arg-- > 0) *sp++ = falseObj;
		DISPATCH();

	// For the primitive ops below, arg is the number of arguments (any primitive can be variadic).
	// Commands pop all their arguments.
	// Reporters pop all their arguments and leave a result on the top of the stack.
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
		} else {
			fail(nonComparableError);
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
		} else {
			fail(nonComparableError);
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
		tmpObj = *(sp - 1);
		if (trueObj == tmpObj) {
			*(sp - arg) = falseObj;
		} else if (falseObj == tmpObj) {
			*(sp - arg) = trueObj;
		} else {
			fail(needsBooleanError);
		}
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
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) / evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	modulo_op:
		*(sp - arg) = int2obj(evalInt(*(sp - 2)) % evalInt(*(sp - 1)));
		POP_ARGS_REPORTER();
		DISPATCH();
	absoluteValue_op:
		*(sp - arg) =  int2obj(abs(evalInt(*(sp - 1))));
		POP_ARGS_REPORTER();
		DISPATCH();
	random_op:
		tmp = evalInt(*(sp - 1));
		if (tmp <= 0) tmp = 1;
		*(sp - arg) = int2obj((rand() % tmp) + 1); // result range is [1..tmp], inclusive
		POP_ARGS_REPORTER();
		DISPATCH();
	hexToInt_op:
		*(sp - arg) = primHexToInt(sp - arg);
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

	// array operations:
	newArray_op:
		*(sp - arg) = primNewArray(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	newByteArray_op:
		*(sp - arg) = primNewByteArray(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	fillArray_op:
		primArrayFill(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	at_op:
		*(sp - arg) = primArrayAt(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	atPut_op:
		primArrayAtPut(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	size_op:
		*(sp - arg) = primArraySize(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();

	// miscellaneous operations:
	millis_op:
		*sp++ = int2obj(millisecs());
		DISPATCH();
	micros_op:
		*sp++ = int2obj(microsecs() & 0x3FFFFFFF); // low 30-bits so result is positive
		DISPATCH();
	peek_op:
		*(sp - arg) = primPeek(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	poke_op:
		primPoke(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	sayIt_op:
		if (!hasOutputSpace(bytesForObject(*(sp - arg)) + 100)) { // leave room for other messages
			ip--; // retry when task is resumed
			goto suspend;
		}
		outputValue(*(sp - arg), task->taskChunkIndex);
		POP_ARGS_COMMAND();
		DISPATCH();
	printIt_op:
		if (!hasOutputSpace(PRINT_BUF_SIZE + 100)) { // leave room for other messages
			ip--; // retry when task is resumed
			goto suspend;
		}
		primPrint(arg, sp - arg); // arg = # of arguments
		POP_ARGS_COMMAND();
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
		*(sp - arg) = primAnalogRead(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	analogWrite_op:
		primAnalogWrite(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	digitalRead_op:
		*(sp - arg) = primDigitalRead(sp - arg);
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
		primMBDisplay(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbDisplayOff_op:
		primMBDisplayOff(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbPlot_op:
		primMBPlot(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbUnplot_op:
		primMBUnplot(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
	mbTiltX_op:
		*(sp - arg) = primMBTiltX(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	mbTiltY_op:
		*(sp - arg) = primMBTiltY(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	mbTiltZ_op:
		*(sp - arg) = primMBTiltZ(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	mbTemp_op:
		*(sp - arg) = primMBTemp(sp - arg);
		POP_ARGS_REPORTER();
		DISPATCH();
	neoPixelSend_op:
		primNeoPixelSend(sp - arg);
		POP_ARGS_COMMAND();
		DISPATCH();
}

// Task Scheduler

static int currentTaskIndex = -1;

void vmLoop() {
	// Run the next runnable task. Wake up any waiting tasks whose wakeup time has arrived.

	int count = 0;
	while (true) {
		if (count-- <= 0) {
#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE)
			updateMicrobitDisplay();
#endif
			processMessage();
			count = 100; // reduce to 30 when building on mbed to avoid serial errors
		}
		uint32 usecs = 0, msecs = 0; // compute times only the first time they are needed
		for (int t = 0; t < taskCount; t++) {
			currentTaskIndex++;
			if (currentTaskIndex >= taskCount) currentTaskIndex = 0;
			Task *task = &tasks[currentTaskIndex];
			if (running == task->status) {
				runTask(task);
				break;
			} else if (unusedTask == task->status) {
				continue;
			} else if (waiting_micros == task->status) {
				if (!usecs) usecs = microsecs(); // get usecs
				if ((usecs - task->wakeTime) < RECENT) task->status = running;
			} else if (waiting_millis == task->status) {
				// Note: The millisecond timer is effectively only 22 bits so
				// compare only the low 22-bits of the current/wakeTime difference.
				if (!msecs) msecs = millisecs(); // get msecs
				if (((msecs - task->wakeTime) & 0x3FFFFF) < RECENT) task->status = running;
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
		uint32 usecs = 0, msecs = 0; // compute times only the first time they are needed
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
			} else if (waiting_millis == task->status) {
				// Note: The millisecond timer is effectively only 22 bits so
				// compare only the low 22-bits of the current/wakeTime difference.
				if (!msecs) msecs = millisecs(); // get msecs
				if (((msecs - task->wakeTime) & 0x3FFFFF) < RECENT) task->status = running;
			}
			if (running == task->status) runTask(task);
			hasActiveTasks = true;
		}
	}
}
