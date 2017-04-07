// interp.cpp - Simple interpreter based on 16-bit opcodes (several variations for testing)
// John Maloney, October, 2013

#include <stdio.h>

#include "mem.h"
#include "interp.h"

// Interpreter State

OBJ literals[5];
static int vars[5];
static int stack[5];

// Helper Functions

void printObj(OBJ obj) {
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

void printlnObj(OBJ obj) {
    printObj(obj);
    printf("\r\n");
}

static inline int evalInt(OBJ obj) {
	if (isInt(obj)) return obj2int(obj);
	printf("evalInt got non-integer: ");
	printlnObj(obj);
	return 0;
}

void showStack(int *sp, int *fp) {
    int *ptr = sp;
    printf("sp: %d\r\n", *ptr);
    while (--ptr >= &stack[0]) {
        printf("%s  %d\r\n", ((fp == ptr) ? "fp:" : ""), *ptr);
    }
    printf("-----\r\n");
}

// Basic Primitives

void primPrint(OBJ args[]) { printlnObj(args[0]); }
OBJ primAdd(OBJ args[]) { return int2obj(evalInt(args[0]) + evalInt(args[1])); }
OBJ primMul(OBJ args[]) { return int2obj(evalInt(args[0]) * evalInt(args[1])); }
OBJ primLess(OBJ args[]) { return (evalInt(args[0]) < evalInt(args[1])) ? trueObj : falseObj; }

// Array Primitives

void primFailed(const char *reason) {
    // Print a message and stop the interpreter.
    printf("Primitive failed: %s\r\n", reason);
}

OBJ sizeFailure() { primFailed("Size must be a positive integer"); return 0; }
OBJ arrayClassFailure() { primFailed("Must must be an Array"); return 0; }
OBJ indexClassFailure() { primFailed("Index must be an integer"); return 0; }
OBJ outOfRangeFailure() { primFailed("Index out of range"); return 0; }

OBJ primNewArray(OBJ args[]) {
    OBJ n = args[0];
    if (!isInt(n) || ((int) n < 0)) return sizeFailure();
    OBJ result = newObj(ArrayClass, (obj2int(n) + 3) / 4, nilObj); // bytes
    return result;
}

OBJ primArrayAt(OBJ args[]) {
    OBJ array = args[0];
    if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
    OBJ index = args[1];
    if (!isInt(index)) return indexClassFailure();

    int i = obj2int(index);
    if ((i < 1) || (i > (objWords(array) * 4))) { outOfRangeFailure(); return nilObj; }
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
    for (int i = HEADER_WORDS; i < end; i++) array[i] = (int) value;
    return nilObj;
}

// Macro to inline dispatch in the end of each opcode (avoiding a jump back to the top)
#define DISPATCH() { \
	op = *ip++; \
	arg = ARG(op); \
/*	printf("ip: %d cmd: %d arg: %d sp: %d\r\n", (ip - prog), CMD(op), arg, (sp - stack)); */ \
	goto *jumpTable[CMD(op)]; \
}

OBJ runProg(int *prog) {
    register int *sp = stack;
    register int *ip = prog;
    register int arg;
    int op;
    int tmp;
    PrimFunc prim;
    OBJ array;

    // initialize jump table
    static void *jumpTable[] = {
		&&halt_op,
		&&noop_op,
		&&pushImmediate_op,
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
		&&primitive_op,
		&&primitiveNoResult_op,
		&&add_op,
		&&subtract_op,
		&&multiply_op,
		&&lessThan_op,
		&&at_op,
		&&atPut_op
    };

    DISPATCH();

    halt_op:
        return nilObj;
    noop_op:
        DISPATCH();
    pushImmediate_op:
        *sp++ = arg;
        DISPATCH();
    pushLiteral_op:
        *sp++ = (int) literals[arg];
        DISPATCH();
    pushVar_op:
        *sp++ = vars[arg];
        DISPATCH();
    popVar_op:
        vars[arg] = *--sp;
        DISPATCH();
    incrementVar_op:
        vars[arg] = (int) int2obj(evalInt((OBJ) vars[arg]) + evalInt((OBJ) (*--sp)));
        DISPATCH();
    pop_op:
        sp--;
        DISPATCH();
    jmp_op:
        ip += arg;
        DISPATCH();
    jmpTrue_op:
        if ((int) trueObj == (*--sp)) ip += arg;
        DISPATCH();
    jmpFalse_op:
        if ((int) falseObj == (*--sp)) ip += arg;
        DISPATCH();
    decrementAndJmp_op:
        if ((--*(sp - 1)) > 0) ip += arg; // loop counter > 0, so branch
        else sp--; // pop loop count
        DISPATCH();
    callFunction_op:
        DISPATCH();
    returnResult_op:
		return (OBJ) *sp;
        DISPATCH();
    primitive_op:
        // arg = # of arguments
        prim = (PrimFunc) *ip++;
        *(sp - arg) = (int) prim((OBJ *) sp - arg);  // arg = #of arguments
        sp -= arg - 1;
        DISPATCH();
    primitiveNoResult_op:
        // arg = # of arguments
        prim = (PrimFunc) *ip++;
        prim((OBJ *) (sp - arg));
        sp -= arg;
        DISPATCH();
    add_op:
        *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) + evalInt((OBJ) *(sp - 1)));
        sp -= 1;
        DISPATCH();
    subtract_op:
        *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) - evalInt((OBJ) *(sp - 1)));
        sp -= 1;
        DISPATCH();
    multiply_op:
        *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) * evalInt((OBJ) *(sp - 1)));
        sp -= 1;
        DISPATCH();
    lessThan_op:
        *(sp - 2) = (int) ((evalInt((OBJ) *(sp - 2)) < evalInt((OBJ) *(sp - 1))) ? trueObj : falseObj);
        sp -= 1;
        DISPATCH();
    at_op:
        array = (OBJ) *(sp - 2);
        if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
        if (!isInt(*(sp - 1))) return indexClassFailure();

        tmp = obj2int(*(sp - 1)); // index
        if ((tmp < 1) || (tmp > (objWords(array) * 4))) { return outOfRangeFailure(); }
        *(sp - 2) = array[HEADER_WORDS + tmp - 1];
        sp -= 1;
        DISPATCH();
    atPut_op:
        array = (OBJ) *(sp - 3);
        if (NOT_CLASS(array, ArrayClass)) return arrayClassFailure();
        if (!isInt(*(sp - 2))) return indexClassFailure();

        tmp = obj2int(*(sp - 2)); // index
        if ((tmp < 1) || (tmp > (objWords(array) * 4))) return outOfRangeFailure();
        array[HEADER_WORDS + tmp - 1] = *(sp - 1);
        sp -= 3;
        DISPATCH();
    return 0;
}
