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
#define pushArgCount 8
#define pushArg 9
#define pushLocal 10
#define popLocal 11
#define incrementLocal 12
#define pop 13
#define jmp 14
#define jmpTrue 15
#define jmpFalse 16
#define decrementAndJmp 17
#define callFunction 18
#define returnResult 19
#define waitMicrosOp 20
#define waitMillisOp 21
#define printIt 22
#define stopAll 23
#define add 24
#define subtract 25
#define multiply 26
#define divide 27
#define lessThan 28
#define newArray 29
#define newByteArray 30
#define fillArray 31
#define at 32
#define atPut 33
#define analogReadOp 34
#define analogWriteOp 35
#define digitalReadOp 36
#define digitalWriteOp 37
#define setLEDOp 38
#define microsOp 39
#define millisOp 40
#define peekOp 41
#define pokeOp 42

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0xFF)
#define ARG(n) (n >> 8)

#define CALL(chunkIndex, argCount, localCount) \
  (((localCount & 0xFF) << 24) | ((argCount & 0xFF) << 16) | \
   ((chunkIndex & 0xFF) << 8)| callFunction)

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
	const char *errorMsg;
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
	uint8 taskChunkIndex; // chunk index of the top-level stack for this task
	uint8 currentChunkIndex; // chunk index when inside a function
	uint32 wakeTime;
	OBJ code;
	int ip;
	int sp;
	int fp;
	OBJ stack[10];
} Task;

#define MAX_TASKS 25
extern Task tasks[MAX_TASKS];
extern int taskCount;

// Task Ops

void initTasks(void);
int stepTasks(void);

// Testing Support

void storeCodeChunk(uint8 chunkIndex, uint8 chunkType, int byteCount, uint8 *data);
void startTaskForChunk(uint8 chunkIndex);
void runTasksUntilDone(void);

// Client Interaction

typedef enum {
	okayReply = 0,
	errorReply,
	storeChunkMsg,
	deleteChunkMsg,
	startAllMsg,
	stopAllMsg,
	startChunkMsg = 6,
	stopChunkMsg,
	getTaskStatusMsg,
	getTaskStatusReply,
	getOutputMsg, // 10
	getOutputReply,
	getReturnValueMsg,
	getReturnValueReply,
	getErrorIPMsg,
	getErrorIPReply,
	showChunksMsg, // 16
	showTasksMsg, // 17
} MessageType_t;

void processMessage(void);
void stopAllTasks(void);

// Platform Specific Operations

int serialDataAvailable(void);
int readBytes(uint8 *buf, int count);
void writeBytes(uint8 *buf, int count);
uint32 millisecs(void);

// String buffer used by the 'print' block

#define PRINT_BUF_SIZE 100
extern char printBuffer[PRINT_BUF_SIZE];
extern int printBufferByteCount;

// Failure

OBJ failure(const char *reason);

// Primitives

OBJ primNewArray(OBJ *args);
OBJ primNewByteArray(OBJ *args);
OBJ primArrayFill(OBJ *args);
OBJ primArrayAt(OBJ *args);
OBJ primArrayAtPut(OBJ *args);

OBJ primAnalogRead(OBJ *args);
OBJ primAnalogWrite(OBJ *args);
OBJ primDigitalRead(OBJ *args);
OBJ primDigitalWrite(OBJ *args);
OBJ primSetLED(OBJ *args);

OBJ primPeek(OBJ *args);
OBJ primPoke(OBJ *args);

#ifdef __cplusplus
}
#endif
