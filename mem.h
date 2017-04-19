// mem.h - Object memory definitions using 32-bit object pointers
// John Maloney, April 2017

#ifdef __cplusplus
extern "C" {
#endif

// Unsigned integer types

typedef unsigned char uint8;
typedef unsigned short uint16;
typedef unsigned int uint32;

// Boolean constants for readability

#define true 1
#define false 0

// Object reference type (32-bits)

typedef int * OBJ;

// Class IDs

#define NilClass 1
#define BooleanClass 2
#define IntegerClass 3
#define FloatClass 4
#define StringClass 5
#define ByteArrayClass 6
#define CodeChunkClass 7
#define ArrayClass 8

// Non-memory Objects (object is encoded directly in the object reference

// OBJ constants for nil, true, and false
// Note: These are constants, not pointers to objects in memory.

#define nilObj ((OBJ) 0)
#define trueObj ((OBJ) 2)
#define falseObj ((OBJ) 4)

// 31-bit signed integers have a 1 in their lowest bit and a value in their top 31 bits.
// Note: Integer values are encoded in the object pointer; there is no memory object.

#define isInt(obj) (((int) (obj)) & 1)
#define int2obj(n) ((OBJ) (((n) << 1) | 1))
#define obj2int(obj) ((int)(obj) >> 1)

// Memory Objects
//
// Even-valued object pointers (except nil, true, and false) point to an object in memory.
// Memory objects start with one or more header words.

#define HEADER_WORDS 1
#define HEADER(classID, wordCount) ((wordCount << 4) | (classID & 0xF))
#define CLASS(obj) (*((unsigned*) (obj)) & 0xF)
#define WORDS(obj) (*((unsigned*) (obj)) >> 4)

static inline int objWords(OBJ obj) {
	if (isInt(obj) || (obj <= falseObj)) return 0;
	return WORDS(obj);
}

static inline int objClass(OBJ obj) {
	if (isInt(obj)) return IntegerClass;
	if (obj <= falseObj) return (obj == nilObj) ? NilClass : BooleanClass;
	return CLASS(obj);
}

// FIELD() can be used either to get or set an object field

#define FIELD(obj, i) (((OBJ *) obj)[HEADER_WORDS + (i)])

// Class checks for classes with memory instances
// (Note: there are faster ways to test for small integers, booleans, or nil)

#define NOT_CLASS(obj, classID) ((((int) obj) & 1) || (obj <= falseObj) || (CLASS(obj) != classID))

// Object Memory Initialization

void memInit(int wordCount);
void memClear(void);

// Object Allocation and String Operations

OBJ newObj(int classID, int wordCount, OBJ fill);
OBJ newString(char *s);
char* obj2str(OBJ obj);

// Debugging

void panic(char *s);
void memPrintStatus(void);
void memDumpObj(OBJ obj);

// Printf for Arduino (many thanks to Michael McElligott)

#ifdef ARDUINO
	extern char printfBuffer[100];

	#define printf(format, ...) \
		do { \
		snprintf(printfBuffer, sizeof(printfBuffer), format, ##__VA_ARGS__); \
		putSerial(printfBuffer); \
		} while(0)
#endif

// Microsecond timer

#if defined(ARDUINO)
	#include "Arduino.h"
	#define TICKS() (micros())
#elif defined(__MBED__)
	#include <us_ticker_api.h>
	#define TICKS() (us_ticker_read())
#else
	#include <sys/time.h>
	#include <time.h>
	static inline unsigned TICKS() {
		struct timeval now;
		gettimeofday(&now, NULL);
		return ((1000000L * now.tv_sec) + now.tv_usec) & 0xFFFFFFFF;
	}
#endif

#ifdef __cplusplus
}
#endif
