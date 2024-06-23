/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// interp.h - Simple interpreter based on 32-bit opcodes
// John Maloney, April 2017

#include "mem.h"
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

// Instruction Format

#define OP(opcode, arg) (((unsigned) arg << 8) | (opcode & 0xFF))
#define CMD(n) (n & 0x7F) // use only low 7 bits for now
#define ARG(n) (n >> 8)

// Global Variables

#define MAX_VARS 128
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
	buttonsAandBHat = 9,
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

#ifdef GNUBLOCKS
	#define STACK_LIMIT 10000 // Task size is 6 + STACK_LIMIT words
#else
	#define STACK_LIMIT 54 // Task size is 6 + STACK_LIMIT words
#endif

typedef struct {
	uint8 status; // MicroBlocksTaskStatus_t, stored as a byte
	uint8 taskChunkIndex; // chunk index of the top-level stack for this task
	uint8 currentChunkIndex; // chunk index when inside a function
	uint32 wakeTime;
	OBJ code;
	int ip; // ip offset in code
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
#define getChunkCRCMsg			11
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
#define chunkCRCMsg				23

// Serial Protocol Messages: Bidirectional

#define pingMsg					26
#define broadcastMsg			27
#define chunkAttributeMsg		28
#define varNameMsg				29
#define extendedMsg				30
#define enableBLEMsg			31
#define chunkCode16Msg			32

// Serial Protocol Messages: CRC Exchange

#define getAllCRCsMsg			38
#define allCRCsMsg				39
#define LAST_MSG				39

// Error Codes (codes 1-9 are reserved for protocol errors; 10 and up are runtime errors)

#define noError					0	// No error
#define unspecifiedError		1	// Unknown error
#define badChunkIndexError		2	// Unknown chunk index

#define insufficientMemoryError	10	// Insufficient memory to allocate object
#define needsListError			11	// Needs a list
#define needsBooleanError		12	// Needs a boolean
#define needsIntegerError		13	// Needs an integer
#define needsStringError		14	// Needs a string
#define nonComparableError		15	// Those objects cannot be compared for equality
#define arraySizeError			16	// List size must be a non-negative integer
#define needsIntegerIndexError	17	// List or string index must be an integer
#define indexOutOfRangeError	18	// List or string index out of range
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
#define argIndexOutOfRange		32	// Argument index out of range
#define needsIndexable			33	// Needs an indexable type such as a string or list
#define joinArgsNotSameType		34	// All arguments to join must be the same type (e.g. lists)
#define i2cTransferFailed		35	// I2C transfer failed
#define needsByteArray			36	// Needs a byte array
#define serialPortNotOpen		37	// Serial port not open
#define serialWriteTooBig		38	// Serial port write is limited to 128 bytes
#define needsListOfIntegers		39	// Needs a list of integers
#define byteOutOfRange			40	// Needs a value between 0 and 255
#define needsPositiveIncrement	41	// Range increment must be a positive integer
#define needsIntOrListOfInts	42	// Needs an integer or a list of integers
#define wifiNotConnected		43	// Not connected to a WiFi network
#define cannotConvertToInteger	44	// Cannot convert that to an integer
#define cannotConvertToBoolean	45	// Cannot convert that to a boolean
#define cannotConvertToList		46	// Cannot convert that to a list
#define cannotConvertToByteArray 47	// Cannot convert that to a byte array
#define unknownDatatype			48	// Unknown datatype
#define invalidUnicodeValue		49	// Unicode values must be between 0 and 1114111 (0x10FFFF)
#define cannotUseWithBLE		50	// Cannot use this feature when board is connected to IDE via Bluetooth
#define bad8BitBitmap			51	// Needs an 8-bit bitmap: a list containing the bitmap width and contents (a byte array)
#define badColorPalette			52	// Needs a color palette: a list of positive 24-bit integers representing RGB values
#define encoderNotStarted		53	// Encoder not started; pin may not support interrupts
#define sleepSignal				255	// Not a real error; used to make current task sleep

// Runtime Operations

OBJ fail(uint8 errCode);
int failure();
void initTasks(void);
void startAll();
void stopAllTasksButThis(Task *task);
void startReceiversOfBroadcast(char *msg, int byteCount);
void processMessage(void);
int hasOutputSpace(int byteCount);
void logData(char *s);
void outputString(const char *s);
void sendTaskDone(uint8 chunkIndex);
void sendTaskError(uint8 chunkIndex, uint8 errorCode, int where);
void sendTaskReturnValue(uint8 chunkIndex, OBJ returnValue);
void sendBroadcastToIDE(char *s, int len);
int broadcastMatches(uint8 chunkIndex, char *msg, int byteCount);
void sendSayForChunk(char *s, int len, uint8 chunkIndex);
void vmLoop(void);
void interpretStep();
void taskSleep(int msecs);
void vmPanic(const char *s);
int indexOfVarNamed(const char *varName);
void processFileMessage(int msgType, int dataSize, char *data);
void waitAndSendMessage(int msgType, int chunkIndex, int dataSize, char *data);
void suspendCodeFileUpdates();
void resumeCodeFileUpdates();

// Integer Evaluation

static inline int evalInt(OBJ obj) {
	if (isInt(obj)) {
		return obj2int(obj);
	} else if (IS_TYPE(obj, StringType)) {
		// try to parse an int out of a string
		return strtol(obj2str(obj), NULL, 10); // returns 0 if string is not a number
	} else if (IS_TYPE(obj, ByteArrayType)) {
		// try to parse an int out of a byte array (treating it as a string)
		return strtol((char *) &FIELD(obj, 0), NULL, 10); // returns 0 if string is not a number
	} else {
		fail(needsIntegerError);
		return 0;
	}
}

// Testing Support

void startTaskForChunk(uint8 chunkIndex);
void runTasksUntilDone(void);

void interpTests1(void);
void taskTest(void);

void compactCodeStore();
void outputRecordHeaders();

// Platform Specific Operations

uint64 totalMicrosecs();
uint32 microsecs(void);
uint32 millisecs(void);
uint32 seconds();
void handleMicosecondClockWrap();

int ideConnected();
int recvBytes(uint8 *buf, int count);
int sendBytes(uint8 *buf, int start, int end);
void captureIncomingBytes();
void restartSerial();

const char *boardType();
void hardwareInit(void);

int readI2CReg(int deviceID, int reg);
void writeI2CReg(int deviceID, int reg, int value);

// I/O Support

extern int mbDisplayColor;

int pinCount();
int mapDigitalPinNum(int userPinNum);
void setPinMode(int pin, int newMode);
void turnOffPins();
void resetTimer();
int hasI2CPullups();
void updateMicrobitDisplay();
void checkButtons();
void resetRadio();
void stopPWM();
void stopServos();
void stopTone();
int readAnalogMicrophone();
void setPicoEdSpeakerPin(int pin);
void showMicroBitPixels(int microBitDisplayBits, int xPos, int yPos);
void setAllNeoPixels(int pin, int ledCount, int color);

// Primitives

OBJ primNewList(int argCount, OBJ *args);
OBJ primFillList(int argCount, OBJ *args);
OBJ primAt(int argCount, OBJ *args);
OBJ primAtPut(int argCount, OBJ *args);
OBJ primLength(int argCount, OBJ *args);

OBJ primHexToInt(int argCount, OBJ *args);

OBJ primBroadcastToIDEOnly(int argCount, OBJ *args);

OBJ primAnalogPins(OBJ *args);
OBJ primDigitalPins(OBJ *args);
OBJ primAnalogRead(int argCount, OBJ *args);
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
OBJ primMBEnableDisplay(int argCount, OBJ *args);
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

// CoCube Sensor Support
void cocubeSensorInit();
void cocubeSensorUpdate();

// BLE Support

extern int BLE_connected_to_IDE;
extern char BLE_ThreeLetterID[4];
extern uint32 lastRcvTime;

void BLE_initThreeLetterID();
void BLE_start();
void BLE_stop();

void BLE_pauseAdvertising();
void BLE_resumeAdvertising();
void BLE_setPicoAdvertisingData(char *name, const char *uuidString);

void BLE_setEnabled(int enableFlag);
int BLE_isEnabled();

void BLE_UART_ReceiveCallback(uint8 *data, int byteCount);
void BLE_UART_Send(uint8 *data, int byteCount);

void getMACAddress(uint8 *sixBytes);

// Primitive Sets

// These primitive set indices are compiled into primitive calls, so their order cannot change.
// New primitive sets must be added at the end, just before PrimitiveSetCount.
typedef enum {
	VarPrims,
	DataPrims,
	MiscPrims,
	IOPrims,
	SensorPrims,
	SerialPrims,
	DisplayPrims,
	FilePrims,
	NetPrims,
	BLEPrims,
	RadioPrims,
	TFTPrims,
	HIDPrims,
	CameraPrims,
	OneWirePrims,
	EncoderPrims,
	PrimitiveSetCount
} PrimitiveSetIndex;

void addVarPrims();
void addDataPrims();
void addMiscPrims();
void addIOPrims();
void addSensorPrims();
void addSerialPrims();
void addDisplayPrims();
void addFilePrims();
void addNetPrims();
void addBLEPrims();
void addRadioPrims();
void addTFTPrims();
void addHIDPrims();
void addCameraPrims();
void addOneWirePrims();
void addEncoderPrims();

// Named Primitive Support

typedef OBJ (*PrimitiveFunction)(int argCount, OBJ *args);

typedef const struct {
	const char *primName;
	PrimitiveFunction primFunc;
} PrimEntry;

void addPrimitiveSet(PrimitiveSetIndex primSetIndex, const char *setName, int entryCount, PrimEntry *entries);
OBJ doPrimitiveCall(PrimitiveSetIndex setIndex, const char *primName, int argCount, OBJ *args);
void primsInit();

#ifdef __cplusplus
}
#endif
