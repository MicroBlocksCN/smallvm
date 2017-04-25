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
#define waitMicrosOp 31
#define waitMillisOp 32
#define peekOp 33
#define pokeOp 34

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0xFF)
#define ARG(n) (n >> 8)

// Code Chunk Table

// The code chunk table is an array of CodeChunkRecords. A code chunk is referenced by its
// index in this table. This "chunk index" is used for several purposes:
//
//	1. to specify the called function in function calls
//	2. to specify the code to run when starting a task
//	3. to communicate with the client IDE about code chunks and tasks
//
// Referencing code chunks via their index in the code chunk table allows the actual code
// chunk object, which may be located in either Flash or RAM memory, to be updated by user
// or edits or moved by the garbage collector or Flash memory manager.

typedef enum {
	unusedChunk = 0,
	command = 1,
	reporter = 2,
	functionHat = 3,
	startHat = 4,
	whenConditionHat = 5,
} ChunkType_t;

typedef struct {
	OBJ code;
	uint8 chunkType;
	uint8 taskStatus;
	OBJ returnValueOrErrorIP;
} CodeChunkRecord;

#define MAX_CHUNKS 32
extern CodeChunkRecord chunks[MAX_CHUNKS];

// Task List

// The task list is an array of taskCount Tasks. Each Task has a chunkIndex and a
// wakeTime based on the microsecond clock. "When <condition>" hats have their condition
// test compiled into them and loop back and suspect when the condition is false. When
// the condition becomes true, execution proceeds to the blocks under the hat and the
// task status changes from 'polling' to 'running'.

typedef enum {
	unusedTask = 0, // task entry is available
	unknown = 0, // not started
	done = 1, // completed normally, no value returned
	done_Value = 2, // returned a value; value stored in chunk's returnValueOrErrorIP
	done_Error = 3, // got an error; IP of error block stored in chunk's returnValueOrErrorIP
	waiting_micros = 4, // waiting for the timer to reach wakeTime
	waiting_millis = 5, // waiting for the timer to reach wakeTime
	waiting_print = 6, // waiting to use the console output buffer
	polling = 7, // condition hat in polling mode
	running = 8,
} TaskStatus_t;

typedef struct {
	uint8 status;
	uint8 chunkIndex;
	uint32 wakeTime;
	OBJ code;
	int sp;
	int ip;
	OBJ stack[10];
} Task;

#define MAX_TASKS 25
extern Task tasks[MAX_TASKS];
extern int taskCount;

// Task Ops

void initTasks(void);

void storeCodeChunk(uint8 chunkIndex, uint8 chunkType, int byteCount, uint8 *data);  // for testing
void startTaskForChunk(uint8 chunkIndex); // for testing
void runTasksUntilDone(void); // for testing

// Client Interaction

typedef enum {
	okayReply,
	errorReply,
	storeChunkMsg,
	deleteChunkMsg,
	startAllMsg,
	stopAllMsg,
	startChunkMsg,
	stopChunkMsg,
	getTaskStatusMsg,
	getTaskStatusReply,
	getOutputMsg,
	getOutputReply,
	getReturnValueMsg,
	getReturnValueReply,
	getErrorIPMsg,
	getErrorIPReply,
} MessageType_t;

void processMessage(void);

// Platform Specific Operations

int readBytes(uint8 *buf, int count);
void writeBytes(uint8 *buf, int count);
uint32 millisecs(void);

// String buffer used by the 'print' block

#define PRINT_BUF_SIZE 100
extern char printBuffer[PRINT_BUF_SIZE];
extern int printBufferByteCount;

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
