// Direct Reference Object for Microcontrollers
// Copyright (c) John Maloney, October 2019

#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Temporary: Function Declarations

void initObjmem();
void resizeObj(OBJ obj, int newWordCount);
int fieldCount(OBJ obj);
OBJ nth(OBJ obj, int index);
void setnth(OBJ obj, int index, OBJ value);

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

#define OBJSTORE_WORDS 6
static uint32_t objstore[OBJSTORE_WORDS];
static uint32_t *freeChunk; // last free chunk in the object store; used for allocation

#define FREE_CHUNK 0

// OBJ Forwarding

void clearForwardingFields() {
	// Set all forwarding fields to zero. This may not be needed if we maintain the invariant
	// that forward fields are zero except during garbage collection or forwarding operations.

	uint32_t *end = &objstore[OBJSTORE_WORDS];
	uint32_t *next = objstore + 1;
	while (next < end) {
		*(next - 1) = 0; // clear forwarding field
		next += WORDS(next) + 2;
	}
}

void applyForwarding() {
	// Update all forwarded references.

	uint32_t *end = &objstore[OBJSTORE_WORDS];
	uint32_t *next = objstore + 1;
	while (next < end) {
		int info = TYPE(next);
		if (info && (StringType != info)) { // non-free chunk with OBJ fields (not a string)
			for (int i = fieldCount((OBJ) next); i > 0; i--) {
				OBJ child = (OBJ) next[i];
				if (!isInt(child) && *(child - 1)) { // child has a non-zero forwarding field
					next[i] = *(child - 1); // update the forwarded OBJ
				}
			}
		}
		next += WORDS(next) + 2;
	}
}

// Mark-Sweep-Compact Garbage Collector

#define SET_MARK(obj) ((*(((uint32_t *) (obj)) - 1)) = 1)
#define IS_MARKED(obj) (*(((uint32_t *) (obj)) - 1))

void mark(OBJ root) {
	// Mark all objects reachable from the given root.

	if (isInt(root) || isBoolean(root) || IS_MARKED(root)) return;

	OBJ current = root;
	int i = fieldCount(current); // scan backwards from last field

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
		if (!isInt(child) && !isBoolean(child) && !IS_MARKED(child) && (StringType != TYPE(child))) { // child is not an integer, String, or marked
			// reverse pointers before processing child
			current[i] = *child; // store child's header it ith field of current
			*(current - 1) = i; // store i in forwarding field of current
			i = fieldCount(child); // scan backwards from last field of child
			*child = (int) current; // backpointer to current
			current = child; // process child
		} else {
			i--;
		}
	}
}

void sweep() {
	// Scan object memory and set the forwarding fields of surviving objects that will move.

	uint32_t *next = objstore + 1;
	uint32_t *dst = next;
	uint32_t *end = &objstore[OBJSTORE_WORDS];
	while (next < end) {
		uint32_t wordCount = WORDS(next);
		if (*(next - 1)) { // surviving object
			// set the forwarding field to dst if the object will move, zero if not
			*(next - 1) = (dst != next) ? (uint32_t) dst : 0;
			dst += wordCount + 2;
		} else { // inaccessible object or free chunk
			// mark chunk as free by clearing its info field
			*next = HEADER(FREE_CHUNK, wordCount);
		}
		next += wordCount + 2;
	}
}

void compact() {
	// Consolidate free space into a single free chunk.

	uint32_t *next = objstore + 1;
	uint32_t *dst = next;
	uint32_t *end = &objstore[OBJSTORE_WORDS];
	while (next < end) {
		uint32_t wordCount = WORDS(next);
		if (TYPE(next)) { // live object chunk
			if (dst != next) memmove(dst, next, 4 * (wordCount + 1)); // move object, if necessary
			dst += wordCount + 1;
			*dst++ = 0; // forwarding word
		}
		next += wordCount + 2;
	}
	uint32_t freeWords = (end - dst) - 2;
	*dst = HEADER(FREE_CHUNK, freeWords);
	freeChunk = dst;
}

OBJ markSweepGC(OBJ root) {
	// Simple mark-sweep-compact garbage collector.

//	clearForwardingFields(); // assume: forwarding pointers cleared at end of compaction
	mark(root);
	sweep();
	applyForwarding();
	OBJ newRoot = (OBJ) *(root - 1);
	compact();
	return newRoot ? newRoot : root;
}

void gc() {
	// xxx to do: this must call the interpreter to mark all the roots
}

// Range check

static int rangeCheck(int index, int limit) {
	if ((1 <= index) && (index <= limit)) return 1;
	outputString("Error: Index out of range");
	return 0;
}

// Debugging Utilities

void reportNum(char *msg, int n) {
	char s[100];
	sprintf(s, "%s: %d", msg, n);
	outputString(s);
}

void reportHex(char *msg, int n) {
	char s[100];
	sprintf(s, "%s: 0x%x", msg, n);
	outputString(s);
}

void reportObj(char *msg, OBJ obj) {
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
	case ArrayType:
		sprintf(s, "%s: Array (%d fields)", msg, fieldCount(obj));
		break;
	default:
		sprintf(s, "%s: <type %d> (%d fields)", msg, type, fieldCount(obj));
	}
	outputString(s);
}

void dumpObjectStore() {
	char s[100];

	outputString("Object store:");
	uint32_t *end = &objstore[OBJSTORE_WORDS];
	uint32_t *next = objstore + 1;
	while (next < end) {
		uint32_t wordCount = WORDS(next);
		int info = TYPE(next);
		if (info) {
			uint32_t *fwd = (uint32_t *) *(next - 1);
			if (fwd) {
				if (fwd > objstore) fwd = (uint32_t *) (fwd - objstore); // word offset in objstore
				sprintf(s, "%d type: %d words: %ld fwd: %d", (next - objstore), info, wordCount, (int) fwd);
			} else {
				sprintf(s, "%d type: %d words: %ld", (next - objstore), info, wordCount);
			}
		} else {
			sprintf(s, "%d FREE %ld", (next - objstore), wordCount);
		}
		outputString(s);
		next = next + wordCount + 2;
	}
	outputString("----------");
}

// Entry Points

void initObjmem() {
	// Initialize the chunk heap, object table, and freeChunk.

	memset(objstore, 0, sizeof(objstore));

	// create the free chunk (prefixed by a forwarding word)
	objstore[0] = 0; // forwarding word
	objstore[1] = HEADER(FREE_CHUNK, OBJSTORE_WORDS - 2); // free chunk
	freeChunk = &objstore[1];
}

OBJ newObj2(int type, int wordCount, OBJ fill) {
	// Allocate a new object of the given size.

	// check available space
	int available = WORDS(freeChunk);
	if (available < (wordCount + 2)) {
		gc(); // not enough space available in freeChunk; collect garbage and retry
		available = WORDS(freeChunk);
		if (available < (wordCount + 2)) return falseObj; // out of memory
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
	while (ptr < end) { *ptr++ = int2obj(0); }
	return result;
}

void resizeObj(OBJ oldObj, int wordCount) {
	// Change the size of the given object to wordCount.

	if (isInt(oldObj) || isBoolean(oldObj)) return;

	int type = objType(oldObj);
	if (!type || (StringType == type)) return;

	OBJ result = newObj(type, wordCount, int2obj(0));
	int copyCount = WORDS(oldObj);
	if (wordCount < copyCount) copyCount = wordCount; // new size is smaller

	memcpy(result + 1, oldObj + 1, 4 * copyCount); // copy from the old to the new body
	clearForwardingFields();
	*(oldObj - 1) = (uint32_t) result; // point forwarding field of oldObj to result
	applyForwarding();
	*(oldObj - 1) = 0; // clear forwarding field
	*oldObj = WORDS(oldObj); // mark old chunk free
}

int fieldCount(OBJ obj) {
	// Return the number of fields of the given object or the number of bytes of a string.

	if (isInt(obj) || isBoolean(obj)) return 0;
	if (IS_TYPE(obj, StringType)) return strlen(obj2str(obj));
	return WORDS(obj);
}

OBJ nth(OBJ obj, int n) {
	// Return the nth (one-based) field of the given object.

	if (isInt(obj)) {
		outputString("Error: Integers are not indexable");
		return falseObj;
	}
	if (StringType == objType(obj)) {
		char *s = obj2str(obj);
		if (!rangeCheck(n, strlen(s))) return int2obj(0);
		return int2obj(s[n - 1]);
	}

	if (!rangeCheck(n, fieldCount(obj))) return falseObj;
	return (OBJ) *(obj + n);
}

void setnth(OBJ obj, int n, OBJ value) {
	// Set the nth (one-based) field of obj to value.

	if (isInt(obj)) { outputString("Error: Integers are not indexable"); return; }
	if (StringType == objType(obj)) { outputString("Error: Strings are immutable"); return; }

	if (!rangeCheck(n, fieldCount(obj))) return;
	*((OBJ *)(obj + n)) = value;
}

// Strings

OBJ newString(char *bytes, int byteCount) {
	int wordCount = ((byteCount + 1) + 3) / 4; // leave room for terminator byte
	OBJ result = newObj(StringType, wordCount, falseObj);
	if (!result) return result;

	memcpy(result + 1, bytes, byteCount);
	*(((char *) result) + 4 + byteCount) = 0; // null terminate
	return result;
}

int objStrEq(OBJ s1, OBJ s2) {
	// Return true if s1 and s2 are equal.

	if (s1 == s2) return 1;
	if (!IS_TYPE(s1, StringType) || !IS_TYPE(s2, StringType)) return 0;
	return (0 == strcmp(obj2str(s1), obj2str(s2)));
}

uint32_t hash(OBJ obj) {
	// Hash oop contents using JS Hash Function from:
	// http://www.partow.net/programming/hashfunctions/index.html#Introduction

	uint32_t result = 1315423911;
	if (isInt(obj)) return result + obj2int(obj);
	if (isBoolean(obj)) return result + (int) obj;
	uint8_t *ptr = (uint8_t *) (obj + 1);
	uint8_t *end = (uint8_t *) (obj + 1 + WORDS(obj));
	while (ptr < end) {
		result ^= ((result << 5) + (*ptr++) + (result >> 2));
	}
	return result;
}
