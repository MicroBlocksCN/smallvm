// Opcodes

#define halt 0
#define noop 1
#define pushImmediate 2 // true, false, nil, and small ints
#define pushConstant 3 // object from constants array
#define pushVar 4
#define popVar 5
#define changeVarBy 6
#define jmp 7
#define jmpTrue 8
#define jmpFalse 9
#define decrementAndJmp 10
#define primitive 11
#define primitiveNoResult 12
#define add 13
#define subtract 14
#define multiply 15
#define lessThan 16
#define at 17
#define atPut 18

#define OPCODE_COUNT 19

// Instruction Format

#define OP(opcode, arg) ((opcode << 24) | (arg & 0xFFFFFF))
#define CMD(n) ((n >> 24) & 0xFF)
#define ARG(n) (((n & 0xFFFFFF) << 8) >> 8)

// Primitive Function Typedef

typedef OBJ (*PrimFunc)(OBJ args[]);

// Primitives

void primPrint(OBJ args[]);
OBJ primAdd(OBJ args[]);
OBJ primMul(OBJ args[]);
OBJ primLess(OBJ args[]);
OBJ primnewArray(OBJ args[]);
OBJ primArrayAt(OBJ args[]);
OBJ primArrayAtPut(OBJ args[]);
OBJ primArrayAtAllPut(OBJ args[]);

// Interpreter state

extern int literals[];

// Entry point

int runProg(int which, int *prog);

