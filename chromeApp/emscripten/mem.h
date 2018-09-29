// mem.h - Object memory definitions plus a few important classes.
// John Maloney, July 2013

/* Virtual machine datatypes:

 gp_boolean -> true/false (0 or 1) value. It is typedef'ed as int so it is 32 bits.
 int     -> signed integer whose exact size doesn't matter (but assumed to be 32-bits).
 uint32  -> unsigned 32-bit integer (good for sizes and counts).
 OBJ     -> uint32; either a direct memory reference or an offset from baseAddress.
 ADDR    -> always a direct memory reference (See notes below on 32/64 bit object memory.)

 char vs. unsigned char: Although we often use "char *" for strings. remember that
	GP strings are UTF8, so their bytes are actually unsigned.
*/

typedef int gp_boolean;
typedef unsigned int uint32;
typedef uint32 OBJ;		// offset from object memory base address
typedef uint32 *ADDR;	// actual address
typedef double __attribute__((aligned(4))) align4_double;	// double aligned to a 32-bit word address

#define true 1
#define false 0

// Platforms

#if defined(__APPLE__) && defined(__MACH__)
  #include <TargetConditionals.h>
  #if TARGET_OS_IPHONE == 1
    #define IOS 1
  #elif TARGET_OS_MAC == 1
    #define MAC 1
  #endif
#endif

// macro for exporting functions from dynamically loaded libraries

#if defined(IOS) || defined(MAC)
  #define EXPORT __attribute__((visibility("default")))
#else
  #define EXPORT
#endif

// Endian flag

extern gp_boolean cpuIsBigEndian;

// Memory typedefs and macros

// OBJ constants for nil, true, and false
// Note: These constants are encoded in the object pointer; there is no memory object.

#define nilObj ((OBJ) 0)
#define trueObj ((OBJ) 2)
#define falseObj ((OBJ) 4)

#define bool2obj(b) ((b) ? trueObj : falseObj)
#define isNilTrueFalse(obj) (((OBJ) obj) <= falseObj)
#define isNil(obj) (obj == 0)

// 31-bit signed integers have 1 in their lowest bit and a signed integer value in their top 31 bits.
// Note: The value of an integer is encoded in the object pointer; there is no memory object.

#define isInt(obj) ((obj) & 1)
#define bothInts(a, b) ((a) & (b) & 1)
#define int2obj(n) (((n) << 1) | 1)
#define obj2int(obj) (((int)(obj)) >> 1)

/* Object Memory for 32/64-bit Architectures

This object memory design uses 32-bit object pointers on both 32-bit and 64-bit
architectures, and the same object header format as much as possible. On 32-bit
machines, object pointers (type OBJ) are direct memory addresses. On 64-bit machines,
they are 32-bit offsets from a 64-bit base address.

The O2A() macro converts an object pointer (OBJ) to a memory address (ADDR).
The A2O() macro converts a memory address (ADDR) to an object pointer (OBJ).

These macros do nothing on 32-bit machines.
*/

extern unsigned char *baseAddress;

#ifdef _LP64
#  define HEADER_WORDS 5
#  define O2A(oop)   ((ADDR)(((unsigned long)(oop)) + (unsigned long)baseAddress))
#  define A2O(addr) ((OBJ)((unsigned long)addr) - (unsigned long)baseAddress)
#else
#  define HEADER_WORDS 4
#  define O2A(oop)   ((ADDR)(oop))
#  define A2O(addr) ((OBJ)(addr))
#endif

# define ExternalReferenceWords ((2 * sizeof(ADDR)) / sizeof(OBJ))

// Class ID Constants

#define NilClass 1
#define BooleanClass 2
#define IntegerClass 3
#define FloatClass 4
#define StringClass 5
#define ArrayClass 6
#define BinaryDataClass 7
#define ExternalReferenceClass 8
#define ListClass 9
#define DictionaryClass 10
#define CmdClass 11
#define ReporterClass 12
#define ClassClass 13
#define FunctionClass 14
#define ModuleClass 15
#define TaskClass 16
#define WeakArrayClass 17
#define LargeIntegerClass 18

// Objects
//
// Even-valued object pointers have 0 in their lowest bit and point to an object in memory.
// The nil, true, and false constants (oops 0, 2, and 4) have no memory representation.
// All other objects have a memory representation with the following header fields.

// Memory Object Format

typedef struct {
	uint32 formatAndClass;
	uint32 wordCount;
	void* prim; // not traced by the garbage collector! used as primitive function cache and for object forwarding
	uint32 hash;
} *ObjHeaderPtr;

#define CLASS_MASK 0xFFFFFF
#define FORMAT_MASK 0xFF000000
#define HAS_OBJECTS_BIT 0x1000000

// Two bit field indicating number of bytes to subtract from the last
// word of a BinaryData object to compute its extact byte length.
#define EXTRA_BYTES_MASK 0x6000000
#define EXTRA_BYTES_SHIFT 25

#define CLASS(obj) ((O2A(obj)[0]) & CLASS_MASK)
#define SETCLASS(obj, classIndex) O2A(obj)[0] = ((O2A(obj)[0] & FORMAT_MASK) | ((classIndex) & CLASS_MASK))
#define WORDS(obj) (O2A(obj)[1])
#define HASH(obj) (((ObjHeaderPtr)O2A(obj))->hash)
#define HAS_OBJECTS(obj) ((O2A(obj)[0] & HAS_OBJECTS_BIT) != 0)

// BODY() returns the address of the first field of obj
#define BODY(obj) (O2A(obj) + HEADER_WORDS)

// FIELD() can be used either to get or set an object field
#define FIELD(obj, i) (O2A(obj)[HEADER_WORDS + (i)])

static inline uint32 objWords(OBJ obj) {
	if (isInt(obj) || (obj <= falseObj)) return 0;
	return WORDS(obj);
}

static inline uint32 objClass(OBJ obj) {
	if (isInt(obj)) return IntegerClass;
	if (obj <= falseObj) return (obj == nilObj) ? NilClass : BooleanClass;
	return CLASS(obj);
}

// Return the number of bytes in a BinaryData object
static inline uint32 objBytes(OBJ obj) {
	if (isInt(obj) || (obj <= falseObj)) return 0;
	return (sizeof(uint32) * WORDS(obj)) - ((O2A(obj)[0] & EXTRA_BYTES_MASK) >> EXTRA_BYTES_SHIFT);
}

// Return the object or free chunk after the given object or free chunk
// Note: A free chunk has zero in its formatAndClass field.
static inline OBJ nextChunk(OBJ obj) {
	return obj + (HEADER_WORDS + WORDS(obj)) * sizeof(OBJ);
}

// Class Checks
// Note: Only for classes with memory instances. There are faster ways to test for small integers, booleans, or nil.

#define IS_CLASS(obj, classID) (((((OBJ) obj) & 3) == 0) && (((OBJ) obj) > falseObj) && (CLASS(obj) == classID))
#define NOT_CLASS(obj, classID) ((((OBJ) obj) & 3) || (((OBJ) obj) <= falseObj) || (CLASS(obj) != classID))

// Command/Reporter objects used by interpreter (two classes, same format)

#define CmdFieldCount 6
typedef struct cmd {
	uint32 formatAndClass;
	uint32 wordCount;
	void* prim; // cached C pointer to the primitive function (not traced by the garbage collector!)
	uint32 hash;
	OBJ primName;
	OBJ lineno;
	OBJ fileName;
	OBJ cache;
	OBJ classIDCache;
	OBJ nextBlock;
	OBJ args[];
} *CmdPtr;

// Function pointer to a GP primitive operation

typedef OBJ (*PrimPtr)(int nargs, OBJ args[]);

// Object Allocation

gp_boolean canAllocate(int wordCount);
OBJ newObj(int classID, int wordCount, OBJ fill);
OBJ newArray(int wordCount);
OBJ newBinaryData(int byteCount);
OBJ newBinaryObj(int classID, int wordCount);
OBJ newFloat(double f);
OBJ cloneObj(OBJ obj);
OBJ copyObj(OBJ srcObj, int newSize, int srcIndex);

// String Operations

OBJ newString(char *s);
OBJ allocateString(int byteCount);
int stringBytes(OBJ stringObj);
char* obj2str(OBJ obj);
gp_boolean strEQ(char *s, OBJ obj);
gp_boolean isBadUTF8(char *s);

// Object Enumeration

OBJ objectAfter(OBJ prevObj, int classID);
OBJ referencesToObject(OBJ target);
void replaceObjects(OBJ srcArray, OBJ dstArray);

// Other Operations

void memInit(uint32 mbytes);
void memDumpWords();
void memDumpObjects();
void dumpObj(OBJ obj);

// Garbage Collection

extern OBJ memStart, freeStart, memEnd;
extern int allocationsSinceLastGC, bytesAllocatedSinceLastGC, gcCount, gcThreshold;
extern gp_boolean gcNeeded;

int collectGarbage(gp_boolean showStats);
void initGarbageCollector();
int isMarked(OBJ obj);
void markLoop();
