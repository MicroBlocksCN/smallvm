/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// interp.h - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0x7F) // use only low 7 bits for now
#define ARG(n) (n >> 8)

// Global Variables

#define MAX_VARS 100
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
	buttonAHat = 7,
	buttonBHat = 8,
} ChunkType_t;

typedef struct {
	OBJ code;
	uint8 chunkType;
} CodeChunkRecord;

#define MAX_CHUNKS 255
extern CodeChunkRecord chunks[MAX_CHUNKS];

// Task List

// The task list is an array of taskCount Tasks. Each Task has a chunkIndex for
// the top-level block of the task, as well as for the current function chunk when
// inside a call to user-defined function. It also holds the task status, processor
// state (instruction pointer (ip), stack pointer (sp), and frame pointer (fp)),
// and the wakeTime (used when a task is waiting on the microsecond clock).
// In the current design, Tasks have a fixed-size stack built in. In the future,
// this will become a reference to a growable stack object in memory.
//
// "When <condition>" hats have their condition test compiled into them. They
// loop back and suspend themselves when the condition is false. When the condition
// becomes true, execution proceeds to the blocks under the hat.

typedef enum {
	unusedTask = 0, // task entry is available
	waiting_micros = 1, // waiting for microseconds to reach wakeTime
	running = 2,
} MicroBlocksTaskStatus_t;

#define STACK_LIMIT 54 // Task size is 6 + STACK_LIMIT words

typedef struct {
	uint8 status; // MicroBlocksTaskStatus_t, stored as a byte
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

#define MAX_TASKS 10
extern Task tasks[MAX_TASKS];
extern int taskCount;

// Extra delay used to limit serial transmission speed

extern int extraByteDelay;

// Serial Protocol Messages: IDE -> Board

#define chunkCodeMsg			1	// bidirectional
#define deleteChunkMsg			2
#define startChunkMsg			3
#define stopChunkMsg			4
#define startAllMsg				5
#define stopAllMsg				6
#define getVarMsg				7	// value returned to IDE via varValueMsg
#define setVarMsg				8
#define getVarNamesMsg			9
#define clearVarsMsg			10
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
#define extendedMsg				30

// Error Codes (codes 1-9 are reserved for protocol errors; 10 and up are runtime errors)

#define noError					0	// No error
#define unspecifiedError		1	// Unknown error
#define badChunkIndexError		2	// Unknown chunk index

#define insufficientMemoryError	10	// Insufficient memory to allocate object
#define needsArrayError			11	// Needs a list
#define needsBooleanError		12	// Needs a boolean
#define needsIntegerError		13	// Needs an integer
#define needsStringError		14	// Needs a string
#define nonComparableError		15	// Those objects cannot be compared for equality
#define arraySizeError			16	// List size must be a non-negative integer
#define needsIntegerIndexError	17	// List index must be an integer
#define indexOutOfRangeError	18	// List index out of range
#define byteArrayStoreError		19	// A ByteArray can only store integer values between 0 and 255
#define hexRangeError			20	// Hexadecimal input must between between -1FFFFFFF and 1FFFFFFF
#define i2cDeviceIDOutOfRange	21	// I2C device ID must be between 0 and 127
#define i2cRegisterIDOutOfRange	22	// I2C register must be between 0 and 255
#define i2cValueOutOfRange		23	// I2C value must be between 0 and 255
#define notInFunction			24	// Attempt to access an argument outside of a function
#define badForLoopArg			25	// for-loop argument must be a positive integer or list
#define stackOverflow			26	// Insufficient stack space
#define primitiveNotImplemented	27	// Primitive not implemented in this virtual machine
#define notEnoughArguments		28	// Not enough arguments passed to primitive
#define waitTooLong				29	// The maximum wait time is 3600000 milliseconds (one hour)
#define noWiFi					30	// This board does not support WiFi
#define zeroDivide				31	// Division (or modulo) by zero is not defined

// Runtime Operations

OBJ fail(uint8 errCode);
void initTasks(void);
void startAll();
void stopAllTasks(void);
void startReceiversOfBroadcast(char *msg, int byteCount);
void processMessage(void);
int hasOutputSpace(int byteCount);
void logData(char *s);
void outputString(char *s);
void sendTaskDone(uint8 chunkIndex);
void sendTaskError(uint8 chunkIndex, uint8 errorCode, int where);
void sendTaskReturnValue(uint8 chunkIndex, OBJ returnValue);
void queueBroadcastAsThingEvent(char *s, int len);
void sendBroadcastToIDE(char *s, int len);
void sendSayForChunk(char *s, int len, uint8 chunkIndex);
void vmLoop(void);
void vmPanic(char *s);
int indexOfVarNamed(char *varName);

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

void compact();
void outputRecordHeaders();

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

int recvBytes(uint8 *buf, int count);
int sendByte(char aByte);
void restartSerial();

const char *boardType();
void hardwareInit(void);

// I/O Support

void setPinMode(int pin, int newMode);
void turnOffPins();
void updateMicrobitDisplay();
void checkButtons();
void resetServos();
void stopTone();
void webServerLoop();

// Primitives

OBJ primNewArray(int argCount, OBJ *args);
OBJ primNewByteArray(int argCount, OBJ *args);
OBJ primArrayFill(int argCount, OBJ *args);
OBJ primArrayAt(int argCount, OBJ *args);
OBJ primArrayAtPut(int argCount, OBJ *args);
OBJ primLength(int argCount, OBJ *args);

OBJ primHexToInt(int argCount, OBJ *args);

OBJ primAnalogPins(OBJ *args);
OBJ primDigitalPins(OBJ *args);
OBJ primAnalogRead(OBJ *args);
void primAnalogWrite(OBJ *args);
OBJ primDigitalRead(int argCount, OBJ *args);
void primDigitalWrite(OBJ *args);
void primDigitalSet(int pinNum, int flag);
OBJ primButtonA(OBJ *args);
OBJ primButtonB(OBJ *args);
void primSetUserLED(OBJ *args);

OBJ primI2cGet(OBJ *args);
OBJ primI2cSet(OBJ *args);
OBJ primSPISend(OBJ *args);
OBJ primSPIRecv(OBJ *args);

OBJ primMBDisplay(int argCount, OBJ *args);
OBJ primMBDisplayOff(int argCount, OBJ *args);
OBJ primMBPlot(int argCount, OBJ *args);
OBJ primMBUnplot(int argCount, OBJ *args);

OBJ primMBDrawShape(int argCount, OBJ *args);
OBJ primMBShapeForLetter(int argCount, OBJ *args);

OBJ primMBTiltX(int argCount, OBJ *args);
OBJ primMBTiltY(int argCount, OBJ *args);
OBJ primMBTiltZ(int argCount, OBJ *args);
OBJ primMBTemp(int argCount, OBJ *args);

OBJ primNeoPixelSend(int argCount, OBJ *args);
OBJ primNeoPixelSetPin(int argCount, OBJ *args);
void turnOffInternalNeoPixels();

// TFT Support

extern int useTFT;

void tftInit();
void tftClear();
void tftSetHugePixel(int x, int y, int state);
void tftSetHugePixelBits(int bits);

// Primitive Sets

void addDisplayPrims();
void addIOPrims();
void addMiscPrims();
void addNetPrims();
void addRadioPrims();
void addSensorPrims();
void addTFTPrims();

// Named Primitive Support

typedef OBJ (*PrimitiveFunction)(int argCount, OBJ *args);

typedef struct {
	char *primName;
	PrimitiveFunction primFunc;
} PrimEntry;

void addPrimitiveSet(char *setName, int entryCount, PrimEntry *entries);
OBJ callPrimitive(int argCount, OBJ *args);
void primsInit();

#ifdef __cplusplus
}
#endif
