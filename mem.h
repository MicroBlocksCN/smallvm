// mem.h - Object memory definitions

typedef int * OBJ;

// OBJ constants for nil, true, and false
// Note: These are virtual objects; they don't refer to an object in memory.

#define nilObj ((OBJ) 0)
#define trueObj ((OBJ) 2)
#define falseObj ((OBJ) 4)

// 31-bit signed integers have a 1 in their lowest bit and a value in their top 31 bits.
// Note: The value of an integer is encoded in the object pointer; there is no memory object.

#define isInt(obj) (((int) (obj)) & 1)
#define isNilTrueFalse(obj) (((OBJ) obj) <= falseObj)
#define int2obj(n) ((OBJ) (((n) << 1) | 1))
#define obj2int(obj) ((int)(obj) >> 1)

// Class ID Constants

#define ObjectClass 1
#define NilClass 2
#define BooleanClass 3
#define IntClass 4
#define StringClass 5
#define ArrayClass 6

// Objects
//
// Even-valued object pointers a 1 in their lowest bit and point to an object in memory.
// (Except the nil, true, and false constants.)
// Note: All objects have at least these fields.

typedef struct {
	int gpClass;
	int wordCount;
	int cache; // used by the garbage collector
} objHeaderPtr;

#define HEADER_WORDS 3
#define CLASS(obj) ((obj)[0])
#define WORDS(obj) ((int) (obj)[1])

inline int objWords(OBJ obj) {
	if (isInt(obj) || (obj <= falseObj)) return 0;
	return ((int *) obj)[1];
}

inline int objClass(OBJ obj) {
	if (isInt(obj)) return IntClass;
	if (obj <= falseObj) return (obj == nilObj) ? NilClass : BooleanClass;
	return ((int *) obj)[0];
}

// Low level functions to get/set object fields. Zero-based indexing. NOT RANGE CHECKED!

inline OBJ getField(OBJ obj, int i) { return ((OBJ *) obj)[HEADER_WORDS + i]; }
inline void setField(OBJ obj, int i, OBJ newValue) { ((OBJ *) obj)[HEADER_WORDS + i] = newValue; }

// Class Check
// Note: Only for classes with memory instances. There are faster ways to test for small integers, booleans, or nil.

#define NOT_CLASS(obj, classID) ((((int) obj) & 3) || (obj <= falseObj) || (obj[0] != classID))

// Object Allocation and String Operations

OBJ newObj(int classID, int wordCount, OBJ fill);
OBJ newString(char *s, int byteCount);
char* obj2str(OBJ obj);

// Other Operations

void memInit(int wordCount);
void memClear();
void memPrintStatus();
void memDump();
void dumpObj(OBJ obj);
