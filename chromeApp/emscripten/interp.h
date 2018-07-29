// interp.h - Interpreter data structures and definitions

#include <math.h>

// First Command Line Argument (usually the application file name or path)

extern char argv0[1024];

// Interpreter State

extern struct timeval startTime;
extern int profileTick;

extern OBJ vmRoots;
extern OBJ emptyArray;
extern OBJ sharedStrings;
extern OBJ classes;
extern OBJ eventKeys;
extern OBJ currentTask;
extern OBJ debugeeTask;

extern OBJ currentModule;
extern OBJ sessionModule;
extern OBJ topLevelModule;
extern OBJ consoleModule;

// Primitives

extern OBJ primitiveDictionary;

typedef struct {
	char *primName;
	void *primFunc;
	char *help;
} PrimEntry;

typedef void (*EntryFunction)(PrimEntry *entry);

// Inlined Prims and Actions
// Note: These are GP integer objects, so they must be odd.
// Note: The interpreter needs to distinguish between these primitives,
// which are inlined into the interpreter, and primtives that are function
// pointers. On most platforms, function pointers will never be at low
// addresses in memory, so we encode the inlined primitives as integers
// under 500. Emscripten, however, represents functions pointers as indices
// into a function pointer table, so they have "addresses" starting
// with 0. Thus, in EMSCRIPTEN, we encode the inlined primitives as
// higher-valued integers and assume that primitives with lowever values
// are function pointers (i.e. we assume that there no function pointer
// table will have more than 10,000 entries).

#ifdef EMSCRIPTEN

#define STOP			10201 // the GP integer 5100
#define GETVAR			10203
#define SETVAR			10205
#define LOCALVAR		10207
#define CHANGEBY		10209
#define ARG_COUNT		10211
#define GETARG			10213
#define IF				10221
#define REPEAT			10223
#define ANIMATE			10225
#define WHILE			10227
#define WAIT_UNTIL		10229
#define FOR				10231
#define FOR_EACH		10233
#define RETURN			10235
#define REPORTER_END	10237
#define CMD_END			10239
#define GC				10241
#define CURRENT_TASK	10243
#define RESUME			10245
#define UNINTERRUPTEDLY	10247
#define LAST_RECEIVER	10249
#define IS_NIL			10251
#define NOT_NIL			10253
#define CALL			10255
#define APPLY			10257
#define APPLY_TO_ARRAY	10259
#define ADD				10261
#define SUB				10263
#define LESS			10265
#define NOOP			10267 // when adding to this list, NOOP should be last

#else

#define STOP			201 // the GP integer 100
#define GETVAR			203
#define SETVAR			205
#define LOCALVAR		207
#define CHANGEBY		209
#define ARG_COUNT		211
#define GETARG			213
#define IF				221
#define REPEAT			223
#define ANIMATE			225
#define WHILE			227
#define WAIT_UNTIL		229
#define FOR				231
#define FOR_EACH		233
#define RETURN			235
#define REPORTER_END	237
#define CMD_END			239
#define GC				241
#define CURRENT_TASK	243
#define RESUME			245
#define UNINTERRUPTEDLY	247
#define LAST_RECEIVER	249
#define IS_NIL			251
#define NOT_NIL			253
#define CALL			255
#define APPLY			257
#define APPLY_TO_ARRAY	259
#define ADD				261
#define SUB				263
#define LESS			265
#define NOOP			267 // when adding to this list, NOOP should be last

#endif

// Function Declarations

void initGP();
void initPrimitiveTable();
void loadPrimitivePlugins();
int recordCommandLine(int argc, char *argv[]);

OBJ getEvent();

void failure(char *reason);
OBJ notEnoughArgsFailure();
OBJ outOfMemoryFailure();
OBJ primFailed(char *reason);
PrimEntry* primLookup(char *primName);

OBJ run(OBJ block);
void stop();
int succeeded();
void yield();

void initCurrentTask(OBJ prog);
void stepCurrentTask();

void saveVMRoots();
void restoreVMRoots();

OBJ copyObj(OBJ srcObj, int newSize, int srcIndex);
void printlnObj(OBJ obj);
void printObj(OBJ obj, int arrayDepth);

OBJ primLogicalAnd(int nargs, OBJ args[]);
OBJ primLogicalOr(int nargs, OBJ args[]);
OBJ primHash(int nargs, OBJ args[]);

double largeIntToDouble(OBJ obj);
uint32 uint32Value(OBJ obj);
OBJ uint32Obj(unsigned int val);

// To allow stop() to turn off audio.
OBJ primClosePortAudio(int nargs, OBJ args[]);

// Inlined Functions

static inline int intArg(int i, int defaultValue, int nargs, OBJ args[]) {
	if ((i < 0) || (i >= nargs)) return defaultValue;
	return isInt(args[i]) ? obj2int(args[i]) : defaultValue;
}

static inline char * strArg(int i, char *defaultValue, int nargs, OBJ args[]) {
	if ((i < 0) || (i >= nargs)) return defaultValue;
	OBJ arg = args[i];
	return NOT_CLASS(arg, StringClass) ? defaultValue : obj2str(arg);
}

static inline int clip(int n, int min, int max) {
	if (n < min) return min;
	if (n > max) return max;
	return n;
}

static inline double evalFloat(OBJ obj) {
	// Covert the given object to a double-precision floating point number.
	// Assumes the object is an Integer, LargeInteger, or Float.
	if (isInt(obj)) return (double) obj2int(obj);
	if (IS_CLASS(obj, FloatClass)) return *((align4_double *)BODY(obj));
	if (IS_CLASS(obj, LargeIntegerClass)) return largeIntToDouble(obj);
	primFailed("Expected integer or float");
	return 0.0;
}

static inline double floatArg(int i, double defaultValue, int nargs, OBJ args[]) {
	if ((i < 0) || (i >= nargs)) return defaultValue;
	return evalFloat(args[i]);
}

static inline int intOrFloatArg(int i, int defaultValue, int nargs, OBJ args[]) {
	// Accept either an Integer or Float argument and return an integer.
	// If argument is a Float, round to the nearest integer.
	if ((i < 0) || (i >= nargs)) return defaultValue;
	OBJ arg = args[i];
	if (isInt(arg)) return obj2int(arg);
	if (nilObj == arg) return defaultValue;
	return (int) round(evalFloat(arg)); // also handles LargeInteger
}
