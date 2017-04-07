// interp.cpp - Simple interpreter based on 16-bit opcodes (several variations for testing)
// John Maloney, October, 2013

//#include "mbed.h"
#include <stdio.h>
#include <stdlib.h>

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
    exit(-1);
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

int runProg1(int *prog) {
    int *sp = stack;
    int *ip = prog;
    int tmp;
    PrimFunc prim;
    OBJ array;

    while (true) {
        int op = *ip++;
        int arg = ARG(op);
//		printf("ip: %d cmd: %d sp: %d\r\n", (ip - prog), CMD(op), (sp - stack));
        switch (CMD(op)) {
            case halt:
                return 0;
            case noop:
                break;
            case pushImmediate:
                *sp++ = arg;
                break;
            case pushLiteral:
                *sp++ = (int) literals[arg];
                break;
            case pushVar:
                *sp++ = vars[arg];
                break;
            case popVar:
                vars[arg] = *--sp;
                break;
            case incrementVar:
                vars[arg] = (int) int2obj(evalInt((OBJ) vars[arg]) + evalInt((OBJ) (*--sp)));
                break;
            case jmp:
                ip += arg;
                break;
            case jmpTrue:
                if ((int) trueObj == (*--sp)) ip += arg;
                break;
            case jmpFalse:
                if ((int) falseObj == (*--sp)) ip += arg;
                break;
            case decrementAndJmp:
                if ((--*(sp - 1)) > 0) ip += arg; // loop counter > 0, so branch
                else sp--; // pop loop count
                break;
            case primitive:
                // arg = # of arguments
                prim = (PrimFunc) *ip++;
                *(sp - arg) = (int) prim((OBJ *) sp - arg);  // arg = #of arguments
                sp -= arg - 1;
                break;
            case primitiveNoResult:
                // arg = # of arguments
                prim = (PrimFunc) *ip++;
                prim((OBJ *) (sp - arg));
                sp -= arg;
                break;
            case add:
                *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) + evalInt((OBJ) *(sp - 1)));
                sp -= 1;
                break;
            case subtract:
                *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) - evalInt((OBJ) *(sp - 1)));
                sp -= 1;
                break;
            case multiply:
                *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) * evalInt((OBJ) *(sp - 1)));
                sp -= 1;
                break;
            case lessThan:
                *(sp - 2) = (int) ((evalInt((OBJ) *(sp - 2)) < evalInt((OBJ) *(sp - 1))) ? trueObj :falseObj);
                sp -= 1;
                break;
            case at:
                array = (OBJ) *(sp - 2);
                if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
                if (!isInt(*(sp - 1))) return (int)indexClassFailure();

                tmp = obj2int(*(sp - 1)); // index
                if ((tmp < 1) || (tmp > (objWords(array) * 4))) { return (int) outOfRangeFailure(); }
                *(sp - 2) = array[HEADER_WORDS + tmp - 1];
                sp -= 1;
                break;
            case atPut:
                array = (OBJ) *(sp - 3);
                if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
                if (!isInt(*(sp - 2))) return (int) indexClassFailure();

                tmp = obj2int(*(sp - 2)); // index
                if ((tmp < 1) || (tmp > (objWords(array) * 4))) return (int) outOfRangeFailure();
                array[HEADER_WORDS + tmp - 1] = *(sp - 1);
                sp -= 3;
                break;
            default:
                printf("Unknown opcode: %d\r\n", ((op >> 24) & 0xF));
                return 0;
        }
    }
}

int runProg2(int *prog) {
    int *sp = stack;
    int *ip = prog;
    int op, arg, tmp;
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

    dispatch:
        op = *ip++;
        arg = ARG(op);
//		printf("ip: %d cmd: %d arg: %d sp: %d\r\n", (ip - prog), CMD(op), arg, (sp - stack));
        goto *jumpTable[CMD(op)];

    halt_op:
        return 0;
    noop_op:
        goto dispatch;
    pushImmediate_op:
        *sp++ = arg;
        goto dispatch;
    pushLiteral_op:
        *sp++ = (int) literals[arg];
        goto dispatch;
    pushVar_op:
        *sp++ = vars[arg];
        goto dispatch;
    popVar_op:
        vars[arg] = *--sp;
        goto dispatch;
    incrementVar_op:
        vars[arg] = (int) int2obj(evalInt((OBJ) vars[arg]) + evalInt((OBJ) (*--sp)));
        goto dispatch;
    pop_op:
        sp--;
        goto dispatch;
    jmp_op:
        ip += arg;
        goto dispatch;
    jmpTrue_op:
        if ((int) trueObj == (*--sp)) ip += arg;
        goto dispatch;
    jmpFalse_op:
        if ((int) falseObj == (*--sp)) ip += arg;
        goto dispatch;
    decrementAndJmp_op:
        if ((--*(sp - 1)) > 0) ip += arg; // loop counter > 0, so branch
        else sp--; // pop loop count
        goto dispatch;
    callFunction_op:
        goto dispatch;
    returnResult_op:
        goto dispatch;
    primitive_op:
        // arg = # of arguments
        prim = (PrimFunc) *ip++;
        *(sp - arg) = (int) prim((OBJ *) sp - arg);  // arg = #of arguments
        sp -= arg - 1;
        goto dispatch;
    primitiveNoResult_op:
        // arg = # of arguments
        prim = (PrimFunc) *ip++;
        prim((OBJ *) (sp - arg));
        sp -= arg;
        goto dispatch;
    add_op:
        *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) + evalInt((OBJ) *(sp - 1)));
        sp -= 1;
        goto dispatch;
    subtract_op:
        *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) - evalInt((OBJ) *(sp - 1)));
        sp -= 1;
        goto dispatch;
    multiply_op:
        *(sp - 2) = (int) int2obj(evalInt((OBJ) *(sp - 2)) * evalInt((OBJ) *(sp - 1)));
        sp -= 1;
        goto dispatch;
    lessThan_op:
        *(sp - 2) = (int) ((evalInt((OBJ) *(sp - 2)) < evalInt((OBJ) *(sp - 1))) ? trueObj :falseObj);
        sp -= 1;
        goto dispatch;
    at_op:
        array = (OBJ) *(sp - 2);
        if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
        if (!isInt(*(sp - 1))) return (int)indexClassFailure();

        tmp = obj2int(*(sp - 1)); // index
        if ((tmp < 1) || (tmp > (objWords(array) * 4))) { return (int) outOfRangeFailure(); }
        *(sp - 2) = array[HEADER_WORDS + tmp - 1];
        sp -= 1;
        goto dispatch;
    atPut_op:
        array = (OBJ) *(sp - 3);
        if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
        if (!isInt(*(sp - 2))) return (int) indexClassFailure();

        tmp = obj2int(*(sp - 2)); // index
        if ((tmp < 1) || (tmp > (objWords(array) * 4))) return (int) outOfRangeFailure();
        array[HEADER_WORDS + tmp - 1] = *(sp - 1);
        sp -= 3;
        goto dispatch;

  return 0;
}

#define DISPATCH() { \
	op = *ip++; \
	arg = ARG(op); \
	goto *jumpTable[CMD(op)]; \
}

int runProg3(int *prog) {
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
        return 0;
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
        *(sp - 2) = (int) ((evalInt((OBJ) *(sp - 2)) < evalInt((OBJ) *(sp - 1))) ? trueObj :falseObj);
        sp -= 1;
        DISPATCH();
    at_op:
        array = (OBJ) *(sp - 2);
        if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
        if (!isInt(*(sp - 1))) return (int)indexClassFailure();

        tmp = obj2int(*(sp - 1)); // index
        if ((tmp < 1) || (tmp > (objWords(array) * 4))) { return (int) outOfRangeFailure(); }
        *(sp - 2) = array[HEADER_WORDS + tmp - 1];
        sp -= 1;
        DISPATCH();
    atPut_op:
        array = (OBJ) *(sp - 3);
        if (NOT_CLASS(array, ArrayClass)) return (int) arrayClassFailure();
        if (!isInt(*(sp - 2))) return (int) indexClassFailure();

        tmp = obj2int(*(sp - 2)); // index
        if ((tmp < 1) || (tmp > (objWords(array) * 4))) return (int) outOfRangeFailure();
        array[HEADER_WORDS + tmp - 1] = *(sp - 1);
        sp -= 3;
        DISPATCH();
    return 0;
}

void runProg(int which, int *prog) {
	switch (which) {
	case 1:
		runProg1(prog);
		break;
	case 2:
		runProg2(prog);
		break;
	case 3:
		runProg3(prog);
		break;
	default:
		printf("Unknown Interpreter\r\n");
	}
}
