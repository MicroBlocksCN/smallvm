// Simple mark-sweep garbage collector.
// John Maloney, December 2013

#include <stdio.h>
#include <sys/time.h>
#include <string.h>
#include "mem.h"
#include "interp.h"

#define DEBUG false

// ***** Variables *****

static gp_boolean compactionNeeded = false;
static ADDR markStackBase;
static ADDR markStackPtr;
static gp_boolean markStackOverflowed;

#define WeakObjectsSize 100
static OBJ weakObjectsArray[WeakObjectsSize];
static ADDR weakObjectsPtr;

// ***** Utility Functions *****

#define MarkAndDoneBits 0x30000000
#define MarkBit 0x20000000
#define MarkingDoneBit 0x10000000
#define AllButMarkAndDoneBits 0xFFFFFFF
#define FORWARD_PTR 2

static inline int isMemoryObj(OBJ obj) { return ((obj & 1) == 0) && (obj > falseObj); }
static inline int notFreeChunk(OBJ ptr) { return *O2A(ptr) != 0; }

int isMarked(OBJ obj) { return (*O2A(obj) & MarkBit) != 0; }
static inline int isMarkingDone(OBJ obj) { return (*O2A(obj) & MarkingDoneBit) != 0; }

static inline void clearMarkBits(OBJ obj) { *O2A(obj) = *O2A(obj) & AllButMarkAndDoneBits; }
static inline void setMark(OBJ obj) { *O2A(obj) = *O2A(obj) | MarkBit; }
static inline void setMarkAndDone(OBJ obj) { *O2A(obj) = *O2A(obj) | MarkAndDoneBits; }

#define W(a, b) ((unsigned int)(((a) - (b)) / sizeof(OBJ)))

static int usecsSince(struct timeval *startTime) {
	struct timeval now;
	gettimeofday(&now, 0);
	int secs = now.tv_sec - startTime->tv_sec;
	int usecs = now.tv_usec - startTime->tv_usec;
	return (secs * 1000000) + usecs;
}

static inline int isWeak(OBJ obj) { return (objClass(obj)) == WeakArrayClass; }

// ***** Marking *****

static void initMarkingStack() {
	markStackBase = markStackPtr = O2A(freeStart);
	markStackOverflowed = false;
}

static void markStackPush(OBJ obj) {
	if (markStackPtr < O2A(memEnd)) {
		*markStackPtr++ = obj;
	} else {
		markStackOverflowed = true;
	}
}

static void markRoot(OBJ obj) {
	if (!HAS_OBJECTS(obj)) {
		setMarkAndDone(obj);
	} else {
		setMark(obj);
		markStackPush(obj);
	}
}

static void clearAllMarkBits() {
	OBJ ptr = memStart;
	while (ptr < freeStart) {
		if (notFreeChunk(ptr)) clearMarkBits(ptr);
		ptr = nextChunk(ptr);
	}
}

static void markClass(OBJ obj) {
	OBJ cls = FIELD(classes, objClass(obj) - 1);
	if (!isMarked(cls)) {
		setMark(cls);
		if (DEBUG) printf("add class to stack\n");
		markStackPush(cls);
	}
	if (objClass(obj) == FunctionClass) {
		int index = obj2int(FIELD(obj, 1));
		if (index > 0) {
			if (index <= objWords(classes)) {
				cls = FIELD(classes, index - 1);
				if (!isMarked(cls)) {
					setMark(cls);
					if (DEBUG) printf("add class to stack\n");
					markStackPush(cls);
				}
			} else {
				printf("bad class index %d; classes size %d\n", index, objWords(classes));
			}
		}
	}
}

static void markAndTrace(OBJ obj) {
	if (DEBUG) printf("markAndTrace %d (class %d), ", W(obj, memStart), CLASS(obj));
	markClass(obj);
	if (isMarkingDone(obj)) {
		if (DEBUG) printf("done bit set\n");
		return;
	}
	if (!HAS_OBJECTS(obj)) {
		if (DEBUG) printf("no pointers\n");
		setMarkAndDone(obj);
		return;
	}
	if (isWeak(obj)) {
		if (weakObjectsPtr < (weakObjectsArray + WeakObjectsSize)) {
			*weakObjectsPtr++ = obj;
		}
		setMarkAndDone(obj);
		return;
	}
	OBJ ptr = obj + HEADER_WORDS * sizeof(OBJ);
	OBJ end = nextChunk(obj);
	if (DEBUG) printf("%d fields\n", (int)((end - ptr) / sizeof(OBJ)));
	while (ptr < end) {
		OBJ obj = *O2A(ptr);
		if (isMemoryObj(obj)) {
			if (DEBUG) printf("  %d (class %d): ", W(obj, memStart), objClass(obj));
			if (!isMarked(obj)) {
				if (HAS_OBJECTS(obj)) {
					setMark(obj);
					if (DEBUG) printf("add to stack\n");
					markStackPush(obj);
				} else {
					if (DEBUG) printf("no pointers\n");
					setMarkAndDone(obj);
				}
			} else {
				if (DEBUG) printf("already marked\n");
			}
		}
		ptr += sizeof(OBJ);
	}
	setMarkAndDone(obj);
}

// ***** Marking Entry Points *****

void initGarbageCollector() {
	weakObjectsPtr = weakObjectsArray;
	saveVMRoots();
	initMarkingStack();
	markRoot(vmRoots);
	if (compactionNeeded) clearAllMarkBits();
	compactionNeeded = false;
}

void markLoop() {
	// Trace and mark objects until the mark stack is empty.
	while (markStackPtr > markStackBase) {
		OBJ obj = *(--markStackPtr);
		markAndTrace(obj);
	}
	while (markStackOverflowed) { // very rare case
		printf("mark stack overflow\n");
		initMarkingStack();
		OBJ ptr = memStart;
		while (ptr < freeStart) {
			if (notFreeChunk(ptr) && !isMarked(ptr)) {
				markAndTrace(ptr);
				markLoop();
			}
			ptr = nextChunk(ptr);
		}
	}
	compactionNeeded = true;
}

// ***** Compaction *****

typedef void (*Finalizer)(OBJ refObj);

static OBJ survivorAfter(OBJ obj) {
	OBJ ptr = obj;
	while (ptr < freeStart) {
		if (isMarked(ptr)) return ptr;
		if (ExternalReferenceClass == CLASS(ptr)) {
		  ADDR field = &FIELD(ptr, 0);
		  Finalizer f = (Finalizer)(*(((ADDR*)field) + 1));
		  if (f && *((ADDR*)field)) {
		    f(ptr); // call the finalizer function on reference
		  }
		}
		ptr = nextChunk(ptr);
	}
	return freeStart;
}

static void sweepAndSetForwardFields() {
	int wordShift = 0;
	OBJ ptr = memStart;
	while (ptr < freeStart) {
		OBJ nextPtr = nextChunk(ptr);
		if (DEBUG) printf("  %d - ", W(ptr, memStart));
		if (isMarked(ptr)) {
			if (DEBUG) printf("survivor\n");
			O2A(ptr)[FORWARD_PTR] = wordShift ? (ptr / sizeof(OBJ) - wordShift) : 0;
#ifdef _LP64
			O2A(ptr)[FORWARD_PTR+1] = 0;  //hack for 64-bit
#endif
		} else {
			nextPtr = survivorAfter(ptr); // find next survivor
			wordShift += (nextPtr - ptr) / sizeof(OBJ);
			if (DEBUG) printf("GARBAGE! next survivor %d shift %d\n", W(nextPtr, memStart), wordShift);
			// make this a free chunk
			O2A(ptr)[0] = 0;
			O2A(ptr)[1] = ((nextPtr - ptr) / sizeof(OBJ)) - HEADER_WORDS; // chunk size does not include header
		}
		ptr = nextPtr;
	}
}

static void updatedForwardedPointers() {
	if (DEBUG) printf("updating pointers\n");
	OBJ ptr = memStart;
	while (ptr < freeStart) {
		int wordCount = HEADER_WORDS + WORDS(ptr);
		if (HAS_OBJECTS(ptr)) {
			if (DEBUG) printf("  %d: updating fields (size %d)\n", W(ptr, memStart), wordCount - HEADER_WORDS);
			for (int i = HEADER_WORDS; i < wordCount; i++) {
				OBJ oldObj = O2A(ptr)[i];
				if (isMemoryObj(oldObj)) {
					OBJ newObj = O2A(oldObj)[FORWARD_PTR] * sizeof(OBJ);
					if (newObj) {
						if (DEBUG) printf("    %d -> %d\n", W(oldObj, memStart), W(newObj, memStart));
						O2A(ptr)[i] = newObj;
					}
				}
			}
		}
		ptr += wordCount * sizeof(OBJ);
	}
}

static OBJ forward(OBJ oldObj) {
	if (isMemoryObj(oldObj)) {
		OBJ newOop = O2A(oldObj)[FORWARD_PTR];
		if (newOop) {
			if (DEBUG) printf("VM roots array moved: %d -> %d\n", W(oldObj, memStart), W(newOop, memStart));
			return newOop;
		}
	}
	return oldObj;
}

static void moveSurvivors() {
	if (DEBUG) printf("moving survivors, old freeStart: %d\n", W(freeStart, memStart));
	OBJ ptr = memStart;
	OBJ dstPtr = ptr;
	while (ptr < freeStart) {
		int chunkWords = HEADER_WORDS + WORDS(ptr);
		clearMarkBits(ptr);  // ?
		if (notFreeChunk(ptr)) {
			O2A(ptr)[FORWARD_PTR] = 0; // clear forwarding pointer
#ifdef _LP64
			O2A(ptr)[FORWARD_PTR + 1] = 0; // hack for for 64 bit case
#endif
			if (dstPtr == ptr) {
				dstPtr += chunkWords * sizeof(OBJ);
			} else {
				OBJ srcPtr = ptr;
				OBJ end = ptr + chunkWords * sizeof(OBJ);
				memmove(O2A(dstPtr), O2A(srcPtr), (end - srcPtr));
				if (DEBUG) printf("  %d -> %d\n", W(ptr, memStart), W(dstPtr, memStart));
				dstPtr += chunkWords * sizeof(OBJ);
				//while (srcPtr < end) *dst++ = *srcPtr++;
			}
		} else {
			if (DEBUG) printf("  free chunk %d (size %d)\n", W(ptr, memStart), chunkWords);
		}
		ptr += chunkWords * sizeof(OBJ);
	}
	freeStart = dstPtr;
	if (DEBUG) printf("moving done, new freeStart: %d\n", W(freeStart, memStart));
}

// ***** Weak Objects *****

void processWeakObjects() {
	ADDR w = weakObjectsArray;
	while (w < weakObjectsPtr) {
		OBJ obj = *w;
		int words = objWords(obj);
		int i = 0;
		for (i = 0; i < words; i++) {
			OBJ field = FIELD(obj, i);
			if (isMemoryObj(field) && !isMarked(field)) {
				FIELD(obj, i) = nilObj;
			}
		}
		w++;
	}
}

// ***** Compaction & GC Entry Points *****

void compact() {
	if (DEBUG) printf("compacting memory (size %d words)\n", W(freeStart, memStart));
	sweepAndSetForwardFields();
	updatedForwardedPointers();
	vmRoots = forward(vmRoots); // if vmRoots is first object in memory, this should do nothing
	moveSurvivors();
	restoreVMRoots();
	compactionNeeded = false;
}

int collectGarbage(int showStats) {
	int preGCBytes = freeStart - memStart;
	struct timeval start;

	gettimeofday(&start, 0);
	initGarbageCollector();
	markLoop();
	int markTime = usecsSince(&start);

	gettimeofday(&start, 0);
	processWeakObjects();
	compact();
	int compactTime = usecsSince(&start);
	int postGCBytes = freeStart - memStart;
	int bytesRecovered = preGCBytes - postGCBytes;

	if (showStats) {
		int kUsed = postGCBytes / 1000;
		int total = memEnd - memStart;
		float percentUsed = (100.0 * postGCBytes) / total;
		int kFree = (memEnd - freeStart) / 1000;
		printf("recovered %dk in %d usecs; used %dk (%.1f%% of %dk) %dk free\n",
			bytesRecovered / 1000, markTime + compactTime, kUsed, percentUsed, total / 1000, kFree);
	}

	allocationsSinceLastGC = 0;
	bytesAllocatedSinceLastGC = 0;
	gcCount++;

	int bytesFree = memEnd - freeStart;
	gcThreshold = bytesFree / 10;
	if (gcThreshold < 1000000) gcThreshold = bytesFree / 2;
	gcNeeded = false;

	return bytesRecovered;
}
