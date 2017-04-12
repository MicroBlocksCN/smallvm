// interp.h - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Opcodes

#define halt 0
#define noop 1
#define pushImmediate 2 // true, false, and ints that fit in 24 bits
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
#define add 14
#define subtract 15
#define multiply 16
#define divide 17
#define lessThan 18
#define printIt 19
#define at 20
#define atPut 21
#define newArray 22
#define fillArray 23

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0xFF)
#define ARG(n) (n >> 8)

// Entry point

OBJ runProg(int *prog);

#ifdef __cplusplus
}
#endif
