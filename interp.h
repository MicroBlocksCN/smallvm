// interp.h - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Opcodes

#define halt 0
#define noop 1
#define pushImmediate 2 // true, false, and ints that fit in 24 bits
#define pushBigImmediate 3 // ints that do not fit in 24 bits (and later, floats)
#define pushLiteral 4 // string or array constant from literals frame
#define pushVar 5
#define popVar 6
#define incrementVar 7
#define pop 8
#define jmp 9
#define jmpTrue 10
#define jmpFalse 11
#define decrementAndJmp 12
#define callFunction 13
#define returnResult 14
#define add 15
#define subtract 16
#define multiply 17
#define divide 18
#define lessThan 19
#define printIt 20
#define at 21
#define atPut 22
#define newArray 23
#define fillArray 24
#define analogReadOp 25
#define analogWriteOp 26
#define digitalReadOp 27
#define digitalWriteOp 28
#define microsOp 29
#define millisOp 30
#define peekOp 31
#define pokeOp 32

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0xFF)
#define ARG(n) (n >> 8)

// Primitives

OBJ primAnalogRead(OBJ args[]);
OBJ primAnalogWrite(OBJ args[]);
OBJ primDigitalRead(OBJ args[]);
OBJ primDigitalWrite(OBJ args[]);
OBJ primMicros(OBJ args[]);
OBJ primMillis(OBJ args[]);
OBJ primPeek(OBJ args[]);
OBJ primPoke(OBJ args[]);

#ifdef __cplusplus
}
#endif
