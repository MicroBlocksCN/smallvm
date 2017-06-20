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

// Code Chunks

// The code chunk table is an array of CodeChunkRecords. A code chunk is referenced by its
// index in this table. This "chunk index" is used for several purposes:
//
//	1. to specify the called function in function calls
//	2. to specify the code to run when starting a task
//	3. to communicate with the client IDE about code chunks and tasks
//
// Referencing code chunks via their index in the code chunk table allows the actual code
// chunk objects, which may be located in either Flash or RAM memory, to be updated by user
// or edits. When code chunks are stored in Flash (which is write-once until it is erased),
// newer versions of a chunk are appended to the end of Flash. At startup time, Flash memory
// is scanned, and the chunks[] table is reconstructed with references to the latest version
// of each chunk.

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
	uint8 taskErrorCode;
	OBJ returnValueOrErrorIP;
} CodeChunkRecord;

#define MAX_CHUNKS 32
extern CodeChunkRecord chunks[MAX_CHUNKS];

// Task List

// The task list is an array of taskCount Tasks. Each Task has a chunkIndex and a
// wakeTime based on the microsecond clock. "When <condition>" hats have their condition
// test compiled into them and loop back and suspend when the condition is false. When
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
	uint8 status; // TaskStatus_t, stored as a byte
	uint8 taskChunkIndex; // chunk index of the top-level stack for this task
	uint8 currentChunkIndex; // chunk index when inside a function
	uint32 wakeTime;
	OBJ code;
	int ip;
	int sp;
	int fp;
	OBJ stack[10];
} Task;

#define MAX_TASKS 16
extern Task tasks[MAX_TASKS];
extern int taskCount;

// String buffer used by the 'print' block

#define PRINT_BUF_SIZE 100
extern char printBuffer[PRINT_BUF_SIZE];
extern int printBufferByteCount;

// Serial Protocol Messages

#define okayReply				0
#define errorReply				1
#define storeChunkMsg			2
#define deleteChunkMsg			3
#define startAllMsg				4
#define stopAllMsg				5
#define startChunkMsg			6
#define stopChunkMsg			7
#define getTaskStatusMsg		8
#define getTaskStatusReply		9
#define getOutputMsg			10
#define getOutputReply			11
#define getReturnValueMsg		12
#define getReturnValueReply		13
#define getTaskErrorInfoMsg		14
#define getTaskErrorInfoReply	15
#define systemResetMsg			16

// Error Codes (codes 1-9 reserved for protocol errors, codes 10 and up for task errors)

#define noError					0
#define unspecifiedError		1
#define badChunkIndexError		2

#define divideByZeroError		10
#define needsNonNegativeError	11
#define needsIntegerError		12
#define needs0to255IntError		13
#define needsArrayError			14
#define indexOutOfRangeError	15

// Runtime Operations

void initTasks(void);
void stepTasks(void);
void stopAllTasks(void);
void printStartMessage(char *s);
void processMessage(void);
OBJ failure(uint8 code, const char *explanation);

// Testing Support

void storeCodeChunk(uint8 chunkIndex, uint8 chunkType, int byteCount, uint8 *data);
void startTaskForChunk(uint8 chunkIndex);
void runTasksUntilDone(void);

// Platform Specific Operations

int serialDataAvailable(void);
int readBytes(uint8 *buf, int count);
void writeBytes(uint8 *buf, int count);

uint32 millisecs(void);

void hardwareInit(void);
void systemReset(void);

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
