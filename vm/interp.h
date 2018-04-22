// interp.h - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Opcodes

#define halt 0
#define noop 1
#define pushImmediate 2		// true, false, and ints that fit in 24 bits
#define pushBigImmediate 3	// ints that do not fit in 24 bits (and later, floats)
#define pushLiteral 4		// string or array constant from literals frame
#define pushVar 5
#define storeVar 6
#define incrementVar 7
#define pushArgCount 8
#define pushArg 9
#define storeArg 10
#define incrementArg 11
#define pushLocal 12
#define storeLocal 13
#define incrementLocal 14
#define pop 15
#define jmp 16
#define jmpTrue 17
#define jmpFalse 18
#define decrementAndJmp 19
#define callFunction 20
#define returnResult 21
#define waitMicros 22
#define waitMillis 23
#define sendBroadcast 24
#define recvBroadcast 25
#define stopAll 26
#define forLoop 27
#define initLocals 28
// reserved 29
// reserved 30
// reserved 31
// reserved 32
// reserved 33
// reserved 34
#define lessThan 35
#define lessOrEq 36
#define equal 37
#define notEqual 38
#define greaterOrEq 39
#define greaterThan 40
#define notOp 41
#define add 42
#define subtract 43
#define multiply 44
#define divide 45
#define modulo 46
#define absoluteValue 47
#define random 48
#define hexToInt 49
#define bitAnd 50
#define bitOr 51
#define bitXor 52
#define bitInvert 53
#define bitShiftLeft 54
#define bitShiftRight 55
// reserved 56
// reserved 57
// reserved 58
// reserved 59
#define newArray 60
#define newByteArray 61
#define fillArray 62
#define at 63
#define atPut 64
#define size 65
// reserved 66
// reserved 67
// reserved 68
// reserved 69
#define millisOp 70
#define microsOp 71
#define peek 72
#define poke 73
#define sayIt 74
#define printIt 75
// reserved 76
// reserved 77
// reserved 78
// reserved 79
#define analogPins 80
#define digitalPins 81
#define analogReadOp 82
#define analogWriteOp 83
#define digitalReadOp 84
#define digitalWriteOp 85
#define digitalSet 86
#define digitalClear 87
#define buttonA 88
#define buttonB 89
#define setUserLED 90
#define i2cSet 91
#define i2cGet 92
#define spiSend 93
#define spiRecv 94
// reserved 95
// reserved 96
// reserved 97
// reserved 98
// reserved 99
#define mbDisplay 100 		// temporary micro:bit primitives for demos
#define mbDisplayOff 101
#define mbPlot 102
#define mbUnplot 103
#define mbTiltX 104
#define mbTiltY 105
#define mbTiltZ 106
#define mbTemp 107
#define neoPixelSend 108

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0x7F) // use only low 7 bits for now
#define ARG(n) (n >> 8)

// Global Variables

#define MAX_VARS 25
extern OBJ vars[MAX_VARS];

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
	broadcastHat = 6,
} ChunkType_t;

typedef struct {
	OBJ code;
	uint8 chunkType;
} CodeChunkRecord;

#define MAX_CHUNKS 255
extern CodeChunkRecord chunks[MAX_CHUNKS];

// Task List

// The task list is an array of taskCount Tasks. Each Task has a chunkIndex for
// the top-level block of the task, as well as for the current function chunk
// when inside a call to user-defined function. It also holds the task status, processor
// state (instruction pointer (ip), stack pointer (sp), and frame pointer (fp)), and
// the wakeTime (used when a task is waiting on the millisecond or microsecond clock).
// In the current design, Tasks have a fixed-size stack built in. In the future,
// this will become a reference to a growable stack object in memory.
//
// "When <condition>" hats have their condition test compiled into them. They
// loop back and suspend themselves when the condition is false. When the condition
// becomes true, execution proceeds to the blocks under the hat.

typedef enum {
	unusedTask = 0, // task entry is available
	waiting_micros = 1, // waiting for microseconds to reach wakeTime
	waiting_millis = 2, // waiting for milliseconds to reach wakeTime
	running = 3,
} TaskStatus_t;

#define STACK_LIMIT 19

typedef struct {
	uint8 status; // TaskStatus_t, stored as a byte
	uint8 taskChunkIndex; // chunk index of the top-level stack for this task
	uint8 currentChunkIndex; // chunk index when inside a function
	uint32 wakeTime;
	OBJ code;
	int ip;
	int sp;
	int fp;
	OBJ stack[STACK_LIMIT];
} Task;

// Task list shared by interp.c and runtime.c

#define MAX_TASKS 16
extern Task tasks[MAX_TASKS];
extern int taskCount;

// Serial Protocol Messages: IDE -> Board

#define chunkCodeMsg			1	// bidirectional
#define deleteChunkMsg			2
#define startChunkMsg			3
#define stopChunkMsg			4
#define startAllMsg				5
#define stopAllMsg				6
#define getVarMsg				7	// value returned to IDE via varValueMsg
#define setVarMsg				8
#define deleteVarMsg			10
#define deleteCommentMsg		11
#define getVersionMsg			12
#define getAllCodeMsg			13
#define deleteAllCodeMsg		14
#define systemResetMsg			15

// Serial Protocol Messages: Board -> IDE

#define taskStartedMsg			16
#define taskDoneMsg				17
#define taskReturnedValueMsg	18
#define taskErrorMsg			19
#define outputValueMsg			20
#define varValueMsg				21
#define versionMsg				22

// Serial Protocol Messages: Bidirectional

#define pingMsg					26
#define broadcastMsg			27
#define chunkAttributeMsg		28
#define varNameMsg				29
#define commentMsg				30
#define commentPositionMsg		31

// Error Codes (codes 1-9 are reserved for protocol errors; 10 and up are runtime errors)

#define noError					0	// No error
#define unspecifiedError		1	// Unknown error
#define badChunkIndexError		2	// Unknown chunk index

#define insufficientMemoryError	10	// Insufficient memory to allocate object
#define needsArrayError			11	// Needs an Array or ByteArray
#define needsBooleanError		12	// Needs a boolean
#define needsIntegerError		13	// Needs an integer
#define needsStringError		14	// Needs a string
#define nonComparableError		15	// Those objects cannot be compared for equality
#define arraySizeError			16	// Array size must be a non-negative integer
#define needsIntegerIndexError	17	// Array index must be an integer
#define indexOutOfRangeError	18	// Array index out of range
#define byteArrayStoreError		19 	// A ByteArray can only store integer values between 0 and 255
#define hexRangeError			20	// Hexadecimal input must between between -1FFFFFFF and 1FFFFFFF
#define i2cDeviceIDOutOfRange	21	// I2C device ID must be between 0 and 127
#define i2cRegisterIDOutOfRange	22	// I2C register must be between 0 and 255
#define i2cValueOutOfRange		23	// I2C value must be between 0 and 255
#define notInFunction			24	// Attempt to access an argument outside of a function
#define badForLoopArg			25	// for-loop argument must be a positive integer, array, or bytearray
#define stackOverflow			26	// Insufficient stack space

// Runtime Operations

OBJ fail(uint8 errCode);
void initTasks(void);
void startAll();
void stopAllTasks(void);
void startReceiversOfBroadcast(char *msg, int byteCount);
void processMessage(void);
int hasOutputSpace(int byteCount);
void outputString(char *s);
void outputValue(OBJ value, int chunkIndex);
void sendTaskDone(uint8 chunkIndex);
void sendTaskError(uint8 chunkIndex, uint8 errorCode, int where);
void sendTaskReturnValue(uint8 chunkIndex, OBJ returnValue);
void sendBroadcastToIDE(char *s, int len);
void vmLoop(void);
void vmPanic(char *s);

// Integer Evaluation

static inline int evalInt(OBJ obj) {
	if (isInt(obj)) return obj2int(obj);
	fail(needsIntegerError);
	return 0;
}

// Testing Support

void startTaskForChunk(uint8 chunkIndex);
void runTasksUntilDone(void);

void interpTests1(void);
void taskTest(void);

// Printf macro for Arduino (many thanks to Michael McElligott)

#ifdef ARDUINO
	void putSerial(char *s);
	extern char printfBuffer[100];

	#define printf(format, ...) \
		do { \
		snprintf(printfBuffer, sizeof(printfBuffer), format, ##__VA_ARGS__); \
		putSerial(printfBuffer); \
		} while(0)
#endif

// Platform Specific Operations

uint32 microsecs(void);
uint32 millisecs(void);

int canReadByte(void);
int readBytes(uint8 *buf, int count);
int sendByte(char aByte);

const char *boardType();
void hardwareInit(void);
void systemReset(void);

void updateMicrobitDisplay(); // temporary

// Primitives

OBJ primNewArray(OBJ *args);
OBJ primNewByteArray(OBJ *args);
void primArrayFill(OBJ *args);
OBJ primArrayAt(OBJ *args);
void primArrayAtPut(OBJ *args);
OBJ primArraySize(OBJ *args);

OBJ primHexToInt(OBJ *args);
OBJ primPeek(OBJ *args);
void primPoke(OBJ *args);

OBJ primAnalogPins(OBJ *args);
OBJ primDigitalPins(OBJ *args);
OBJ primAnalogRead(OBJ *args);
void primAnalogWrite(OBJ *args);
OBJ primDigitalRead(OBJ *args);
void primDigitalWrite(OBJ *args);
void primDigitalSet(int pinNum, int flag);
OBJ primButtonA(OBJ *args);
OBJ primButtonB(OBJ *args);
void primSetUserLED(OBJ *args);

OBJ primI2cGet(OBJ *args);
OBJ primI2cSet(OBJ *args);
OBJ primSPISend(OBJ *args);
OBJ primSPIRecv(OBJ *args);

void primMBDisplay(OBJ *args);
void primMBDisplayOff(OBJ *args);
void primMBPlot(OBJ *args);
void primMBUnplot(OBJ *args);
OBJ primMBTiltX(OBJ *args);
OBJ primMBTiltY(OBJ *args);
OBJ primMBTiltZ(OBJ *args);
OBJ primMBTemp(OBJ *args);
void primNeoPixelSend(OBJ *args);

#ifdef __cplusplus
}
#endif
