/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// mem.c - object memory
// Just an allocator for now; no garbage collector.
// John Maloney, April 2017

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Object Store
//
// The object store is a contiguous portion of RAM used to store objects. The object store
// contains both object and free memory "chunks". Whether it is an object or free, every
// memory chunk starts with a header word that specifies its length and type. Free chunks
// have a zero type field.
//
// Chunks start on 32-bit word boundaries and are multiples of 32-bit words. Chunks are packed
// contiguously, so the entire object store can be scanned by jumping from one chunk header to
// the next. The final chunk is always a free chunk. The object allocator carves objects off the
// free chunk until it is no longer large enough for a desired allocation. At that point, the
// garbage collector/compactor is run, consolidating all free space into the final free chunk.
//
// Every chunk starts with a header word with its size and type:
//
//		<word count (28-bits)><type (4 bits)>
//
// An extra header word, called the "forwarding field" is reserved immediately before the header
// word of each chunk. That field is used by the marking phase of the garbage collector and to
// update (forward) references of objects that move during compaction and object resizing.

#if defined(NRF51)
  #define OBJSTORE_BYTES 1200
#elif defined(ARDUINO_BBC_MICROBIT_V2) || defined(ARDUINO_CALLIOPE_MINI_V3)
  #define OBJSTORE_BYTES 48000
#elif defined(ARDUINO_NRF52_PRIMO)
  #define OBJSTORE_BYTES 16000
#elif defined(NRF52)
  #define OBJSTORE_BYTES 160000 // max is 219000
#elif defined(ARDUINO_ARCH_SAMD)
  #define OBJSTORE_BYTES 14000
#elif defined(ARDUINO_M5STACK_FIRE)
  #define OBJSTORE_BYTES 200000 // will be allocated from PSRAM
#elif defined(HAS_CAMERA)
  #define OBJSTORE_BYTES 240000 // will be allocated from PSRAM
#elif defined(ESP32_S3) || defined(ESP32_C3)
  #define OBJSTORE_BYTES 80000
#elif defined(ARDUINO_ARCH_ESP32)
  // object store is allocated from heap on ESP32
  #if defined(USE_NIMBLE)
	#define OBJSTORE_BYTES 48000 // max that allows both BLE and WiFi is 59000
  #else
    #define OBJSTORE_BYTES 80000
  #endif
#elif defined(GNUBLOCKS)
  #define OBJSTORE_BYTES 262100 // max number of bytes that we can allocate for now
#elif defined(ARDUINO_ARCH_RP2040)
  #define OBJSTORE_BYTES 100000
#elif defined(ARDUINO_SAM_DUE)
  #define OBJSTORE_BYTES 80000
#elif defined(CONFIG_BOARD_BEAGLECONNECT_FREEDOM)
  #define OBJSTORE_BYTES 40000
#else
  #define OBJSTORE_BYTES 4000
  // max that works on Wemos D1 mini (ESP8266) is 11000
  // however, WiFi is unreliable for 4 concurrent requestions even down to 7200
  // 5000 seems stable for up to 10 concurrent requests
  // max that compiles for all boards is 16886 (17624 NodeMCU)
#endif

#define OBJSTORE_WORDS ((OBJSTORE_BYTES / 4) + 4)

#if defined(ARDUINO_ARCH_ESP32)
  static OBJ *objstore = NULL; // allocated from heap on ESP32
#else
  static OBJ objstore[OBJSTORE_WORDS];
#endif

static OBJ memStart = NULL;
static OBJ memEnd = NULL;
static OBJ freeChunk = NULL;

OBJ tempGCRoot = NULL; // used during resizeObj() and primitives that allocate multiple objects

extern OBJ lastBroadcast; // an additional GC root

// Initialization

void memInit() {
	// verify 32-bit architecture
	if (!(sizeof(int) == 4 && sizeof(int*) == 4 && sizeof(float) == 4)) {
		vmPanic("MicroBlocks expects int, int*, and float to all be 32-bits");
	}

	#if defined(ARDUINO_ARCH_ESP32)
		objstore = (OBJ *) malloc(4 * OBJSTORE_WORDS);
		if (!objstore) vmPanic("ESP32 could not allocate objectstore");
	#endif

	// initialize object heap memory
	memStart = (OBJ) objstore;
	memEnd = (OBJ) (objstore + OBJSTORE_WORDS);
	memClear();
}

void memClear() {
	// Clear object memory and set all global variables to zero.

	// clear global variables
	for (int i = 0; i < MAX_VARS; i++) vars[i] = zeroObj;
	lastBroadcast = zeroObj;

	// zero objectstore memory (not essential)
	memset(objstore, 0, sizeof(objstore));

	// create the free chunk (prefixed by a forwarding word)
	objstore[0] = (OBJ) 0; // forwarding word
	objstore[1] = (OBJ) HEADER(FREE_CHUNK, OBJSTORE_WORDS - 2); // free chunk
	freeChunk = (OBJ) &objstore[1];
}

int wordsFree() {
	int result = WORDS(freeChunk) - 2;
	return (result < 0) ? 0 : result;
}

void vmPanic(const char *errorMessage) {
	// Called when VM encounters a fatal error. Output the given message and loop forever.
	// NOTE: This call never returns!

	char s[100];
	sprintf(s, "\r\nVM Panic: %s\r\n", errorMessage);
	outputString(s);
	while (true) processMessage(); // there's no way to recover; loop forever!
}

// Forward References

void applyForwarding();
void clearForwardingFields();
void gc();

// Object Allocation

OBJ newObj(int type, int wordCount, OBJ fill) {
	// Allocate a new object of the given size.

	// check available space
	int available = WORDS(freeChunk);
	if (available < (wordCount + 2)) {
		gc();
		available = WORDS(freeChunk); // retry after garbage collection
		if (available < (wordCount + 2)) return fail(insufficientMemoryError);
	}

	// allocate result and update freeChunk
	OBJ result = (OBJ) freeChunk;
	freeChunk += wordCount + 2;
	*freeChunk = HEADER(FREE_CHUNK, available - (wordCount + 2));

	// initialize and return the new object
	*(result - 1) = 0; // clear its forwarding word
	*result = HEADER(type, wordCount); // set header word
	OBJ *ptr = (OBJ *) result + 1;
	OBJ *end = ptr + wordCount;
	while (ptr < end) { *ptr++ = fill; }
	return result;
}

OBJ resizeObj(OBJ oldObj, int wordCount) {
	// Change the size of the given object to wordCount and return the new object.

	if (isInt(oldObj)) return oldObj;
	if ((oldObj < memStart) || (oldObj >= memEnd)) return oldObj; // object must be in object store

	tempGCRoot = oldObj; // record oldObj in case newObj() triggers GC that moves it
	OBJ result = newObj(TYPE(oldObj), wordCount, zeroObj);
	oldObj = tempGCRoot; // restore oldObj
	tempGCRoot = NULL;
	if (!result) return oldObj;

	int copyCount = WORDS(oldObj);
	if (wordCount < copyCount) copyCount = wordCount; // new size is smaller
	memcpy(result + 1, oldObj + 1, 4 * copyCount); // copy from the old to the new body

	clearForwardingFields();
	*(oldObj - 1) = (uint32) result; // point forwarding field of oldObj to result
	applyForwarding();
	*(oldObj - 1) = 0; // clear forwarding field
	*oldObj = HEADER(FREE_CHUNK, WORDS(oldObj)); // mark oldObj free

	return result;
}

// String Primitives

OBJ newString(int byteCount) {
	// Allocate a string that can hold byteCount bytes.

	int wordCount = ((byteCount + 1) + 3) / 4; // leave room for terminator byte
	return newObj(StringType, wordCount, 0);
}

OBJ newStringFromBytes(const char *bytes, int byteCount) {
	// Create a new string object with the given bytes.
	// Round up to an even number of words and pad with nulls.

	OBJ result = newString(byteCount);
	if (!result) return result; // insufficient room to allocate string (newObj reported failure)

	char *dst = (char *) &result[HEADER_WORDS];
	for (int i = 0; i < byteCount; i++) *dst++ = *bytes++;
	*dst = 0; // null terminator byte
	return result;
}

char* obj2str(OBJ obj) {
	if (isInt(obj)) return (char *) "<Integer>";
	if (isBoolean(obj)) return (char *) ((trueObj == obj) ? "true" : "false");
	if (IS_TYPE(obj, StringType)) return (char *) &obj[HEADER_WORDS];
	if (IS_TYPE(obj, ListType)) return (char *) "<List>";
	if (IS_TYPE(obj, ByteArrayType)) return (char *) "<ByteArray>";
	return (char *) "<Object>";
}

// Debugging Utilities

void reportNum(const char *msg, int n) {
	char s[100];
	sprintf(s, "%s: %d", msg, n);
	outputString(s);
}

void reportHex(const char *msg, int n) {
	char s[100];
	sprintf(s, "%s: 0x%x", msg, n);
	outputString(s);
}

void reportObj(const char *msg, OBJ obj) {
	char s[100];
	int type = objType(obj);
	switch (type) {
	case IntegerType:
		sprintf(s, "%s: %d", msg, obj2int(obj));
		break;
	case StringType:
		sprintf(s, "%s: %s", msg, obj2str(obj));
		break;
	case BooleanType:
		sprintf(s, "%s: %s", msg, ((trueObj == obj) ? "true" : "false"));
		break;
	case ListType:
		sprintf(s, "%s: List (%d fields)", msg, obj2int(FIELD(obj, 0)));
		break;
	default:
		sprintf(s, "%s: <type %d> (%d fields)", msg, type, WORDS(obj));
	}
	outputString(s);
}

void dumpObjectStore() {
	char s[100];

	outputString("Object store:");
	uint32 *end = (uint32 *) &objstore[OBJSTORE_WORDS];
	uint32 *next = (uint32 *) objstore + 1;
	uint32 *base = (uint32 *) objstore;
	while (next < end) {
		int wordCount = WORDS(next);
		int type = TYPE(next);
		if (type) {
			uint32 *fwd = (uint32 *) *(next - 1);
			if (fwd) {
				if (fwd > base) fwd = (uint32 *) (fwd - base); // word offset in objstore
				sprintf(s, "%d type: %d words: %d fwd: %d", (next - base), type, wordCount, (int) fwd);
			} else {
				sprintf(s, "%d type: %d words: %d", (next - base), type, wordCount);
			}
		} else {
			sprintf(s, "%d FREE %d", (next - base), wordCount);
		}
		outputString(s);
		next = next + wordCount + 2;
	}
	outputString("----------");
}

void memDumpObj(OBJ obj) {
	char s[100];

	if ((obj < memStart) || (obj >= memEnd)) {
		sprintf(s, "bad object at %x", (int) obj);
		outputString(s);
		return;
	}
	int typeID = TYPE(obj);
	int wordCount = WORDS(obj);
	sprintf(s, "%x: %d words, typeID %d", (int) obj, wordCount, typeID);
	outputString(s);

	sprintf(s, "Header: %x", obj[0]);
	outputString(s);

	for (int i = 0; i < wordCount; i++) {
		sprintf(s, "	0x%x,", obj[HEADER_WORDS + i]);
		outputString(s);
	}
}

// Object Forwarding

void clearForwardingFields() {
	// Set all forwarding fields to zero. This may not be needed if we maintain the invariant
	// that forward fields are zero except during garbage collection or forwarding operations.

	uint32 *end = (uint32 *) &objstore[OBJSTORE_WORDS];
	uint32 *next = (uint32 *) objstore + 1;
	while (next < end) {
		*(next - 1) = 0; // clear forwarding field
		next += WORDS(next) + 2;
	}
}

static inline OBJ forward(OBJ obj) {
	if (isInt(obj)) return obj;
	if ((obj < memStart) || (obj > memEnd)) return obj; // outside the object store
	OBJ fwd = (OBJ) *(obj - 1);
	return fwd ? fwd : obj; // forward if the forwarding field is not zero
}

static void forwardRoots(void) {
	// forward global variables
	for (int i = 0; i < MAX_VARS; i++) vars[i] = forward(vars[i]);
	lastBroadcast = forward(lastBroadcast);

	if (tempGCRoot) tempGCRoot = forward(tempGCRoot);

	// forward objects on Task stacks
	for (int i = 0; i < taskCount; i++) {
		Task *task = &tasks[i];
		if (task->status != unusedTask) {
			for (int j = tasks[i].sp - 1; j >= 0; j--) {
				task->stack[j] = forward(task->stack[j]);
			}
		}
	}
}

void applyForwarding() {
	// Update all forwarded references.

	uint32 *end = (uint32 *) &objstore[OBJSTORE_WORDS];
	uint32 *next = (uint32 *) objstore + 1;
	while (next < end) {
		if (TYPE(next) > BinaryObjectTypes) { // non-free chunk with OBJ fields (not a string)
			for (int i = WORDS(next); i > 0; i--) {
				OBJ child = (OBJ) next[i];
				if (!isInt(child) && // child is not an integer
					((memStart < child) && (child <= memEnd)) && // child is in the object store
					*(child - 1)) { // child has a non-zero forwarding field
						next[i] = *(child - 1); // update the forwarded OBJ
				}
			}
		}
		next += WORDS(next) + 2;
	}
	forwardRoots();
}

// Mark-Sweep-Compact Garbage Collector

#define SET_MARK(obj) ((*(((uint32 *) (obj)) - 1)) = 1)
#define IS_MARKED(obj) (*(((uint32 *) (obj)) - 1))

void mark(OBJ root) {
	// Mark all objects reachable from the given root.

	if (isInt(root)) return;
	if ((root < memStart) || (root > memEnd)) return; // ignore objects outside the object store
	if (IS_MARKED(root)) return; // already marked

	OBJ current = root;
	int i = WORDS(current); // scan backwards from last field

	while (1) {
		if (i == 0) { // done processing fields of the current object
			SET_MARK(current);
			if (current == root) return; // we're done!
			OBJ parent = (OBJ) *current; // backpointer to parent was stored in header
			i = *(parent - 1); // restore field index in parent
			*current = parent[i]; // restore header of child
			parent[i] = (int) current; // restore pointer to child in parent[i]
			current = parent;
			i--; // process the next field of parent
			continue;
		}

		// process next child
		OBJ child = (OBJ) current[i];
		if (!isInt(child) && (memStart <= child) && (child <= memEnd) && !IS_MARKED(child)) {
			// child an unmarked, non-integer object in the object store
			if (TYPE(child) > BinaryObjectTypes) { // child has pointer fields to process
				// reverse pointers before processing child
				current[i] = *child; // store child's header it ith field of current
				*(current - 1) = i; // store i in forwarding field of current
				i = WORDS(child); // scan backwards from last field of child
				*child = (int) current; // backpointer to current
				current = child; // process child
			} else {
				SET_MARK(child);
			}
		} else {
			i--;
		}
	}
}

static void markRoots(void) {
	// mark global variables
	for (int i = 0; i < MAX_VARS; i++) mark(vars[i]);
	mark(lastBroadcast);

	// mark temporary object used during object resizing
	if (tempGCRoot) mark(tempGCRoot);

	// mark objects on Task stacks
	for (int i = 0; i < taskCount; i++) {
		Task *task = &tasks[i];
		if (task->status != unusedTask) {
			for (int j = tasks[i].sp - 1; j >= 0; j--) {
				mark(task->stack[j]);
			}
		}
	}
}

void sweep() {
	// Scan object memory and set the forwarding fields of surviving objects that will move.

	uint32 *end = (uint32 *) &objstore[OBJSTORE_WORDS];
	uint32 *next = (uint32 *) objstore + 1;
	uint32 *dst = next;
	while (next < end) {
		uint32 wordCount = WORDS(next);
		if (*(next - 1)) { // surviving object
			// set the forwarding field to dst if the object will move, zero if not
			*(next - 1) = (dst != next) ? (uint32) dst : 0;
			dst += wordCount + 2;
		} else { // inaccessible object or free chunk
			// mark chunk as free by clearing its type field
			*next = HEADER(FREE_CHUNK, wordCount);
		}
		next += wordCount + 2;
	}
}

void compact() {
	// Consolidate free space into a single free chunk.

	uint32 *next = (uint32 *) objstore + 1;
	uint32 *end = (uint32 *) &objstore[OBJSTORE_WORDS];
	uint32 *dst = next;
	while (next < end) {
		uint32 wordCount = WORDS(next);
		if (TYPE(next)) { // live object chunk
			if (dst != next) memmove(dst, next, 4 * (wordCount + 1)); // move object, if necessary
			dst += wordCount + 1;
			*dst++ = 0; // forwarding word
		}
		next += wordCount + 2;
	}
	uint32 freeWords = (end - dst) - 1;
	*dst = HEADER(FREE_CHUNK, freeWords);
	freeChunk = (OBJ) dst;
}

void gc() {
	// Perform a garbage collection to reclaim unused objects and compact memory.
	// Call captureIncomingBytes() to avoid serial buffer overruns during garbage collection.

	captureIncomingBytes();
	updateMicrobitDisplay();

	uint32 usecs = microsecs();

	// assume: forwarding pointers cleared at end of compaction so no need to clear them here
	markRoots();
	sweep();
	applyForwarding();
	compact();

	usecs = microsecs() - usecs;

	char s[100];
	sprintf(s, "GC took %d usecs; free %d words", usecs, WORDS(freeChunk) - 2);
	outputString(s);

	captureIncomingBytes();
	updateMicrobitDisplay();
}
