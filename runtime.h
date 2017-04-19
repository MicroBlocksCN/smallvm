// runtime.h - Runtime for uBlocks, including CodeChunk and Task management
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Code Chunk Table

// The code chunk table is an array of CodeChunkRecords. A code chunk is referenced by its
// index in this table. The code chunk index is used for several purposes:
//
//	1. to specify the callee "address" in function calls
//	2. to specify the code to run when starting a task
//  3. to communicate with the client IDE about code chunks and tasks
//
// A given code chunk may be located in either Flash or RAM memory. The index for a given
// code chunk does not change even when that chunk is updated or moved.

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

// Task List

// The Task List is an array of taskCount Tasks. Each Task has a codeChunkIndex and a
// wakeTime based on the microsecond clock. "When <condition>" hats have their condition
// test compiled into them and return immediately when the condition is false. When their
// condition becomes true, execution proceeds to the blocks under the hat and the task
// status changes from 'polling' to 'running'.

typedef enum {
	unusedTask = 0, // task entry is available
	unknown = 0, // not started
	done = 1, // completed normally, no value returned
	done_Value = 2, // returned a value; value stored in chunk's returnValueOrErrorIP
	done_Error = 3, // got an error; IP of error block stored in chunk's returnValueOrErrorIP
	waiting = 4, // waiting for the timer to reach wakeTime
	polling = 5, // condition hat in polling mode
	running = 6,
} TaskStatus_t;

typedef struct {
	uint8 status;
	uint8 codeChunkIndex;
	uint32 wakeTime;
	OBJ code;
	int sp;
	int ip;
	OBJ stack[10];
} Task;

#define MAX_TASKS 25
extern Task tasks[MAX_TASKS];
extern int taskCount;

// Code Chunk Ops

void storeCodeChunk(uint8 chunkIndex, uint8 chunkType, int byteCount, uint8 *data);
void deleteCodeChunk(uint8 chunkIndex);

// Task Ops

void initTasks(void);

OBJ taskReturnValueOrErrorIP(uint8 chunkIndex);
uint8 taskStatus(uint8 chunkIndex);
int getStatusForAllTasks(uint8 *buf, int bufSize);

void startTaskForChunk(uint8 chunkIndex);
void stopChunkTask(uint8 chunkIndex);

void startAll(void);
void stopAll(void);

#ifdef __cplusplus
}
#endif
