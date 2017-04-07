// interp.h - SmallVM Interpreter
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Opcodes

#define halt 0
#define noop 1
#define pushImmediate 2 // true, false, and small ints
#define pushLiteral 3 // string or array from literals frame
#define pushVar 4
#define popVar 5
#define incrementVar 6
#define pop 7
#define jmp 8
#define jmpTrue 9
#define jmpFalse 10
#define decrementAndJmp 11
#define callFunction 12
#define returnResult 13
#define primitive 14
#define primitiveNoResult 15
#define add 16
#define subtract 17
#define multiply 18
#define lessThan 19
#define at 20
#define atPut 21

#define OPCODE_COUNT 22

// Instruction Format

// #define OP(opcode, arg) ((opcode << 24) | (arg & 0xFFFFFF))
// #define CMD(n) ((n >> 24) & 0xFF)
// #define ARG(n) (((n & 0xFFFFFF) << 8) >> 8)

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0xFF)
#define ARG(n) (n >> 8)

// Primitive Function Typedef

typedef OBJ (*PrimFunc)(OBJ args[]);

// Primitives

void primPrint(OBJ args[]);
OBJ primAdd(OBJ args[]);
OBJ primMul(OBJ args[]);
OBJ primLess(OBJ args[]);
OBJ primNewArray(OBJ args[]);
OBJ primArrayAt(OBJ args[]);
OBJ primArrayAtPut(OBJ args[]);
OBJ primArrayFill(OBJ args[]);

// Interpreter state

extern OBJ literals[];

// Entry point

OBJ runProg(int *prog);

#ifdef __cplusplus
}
#endif
