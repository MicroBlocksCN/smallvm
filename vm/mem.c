/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// mem.c - object memory
// Just an allocator for now; no garbage collector.
// John Maloney, April 2017

#include <stdio.h>
#include <stdint.h>
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
  #define OBJSTORE_BYTES 2500 // max is 2612
#else
  #define OBJSTORE_BYTES 14000 // max that compiles for all boards is 16886 (17624 NodeMCU)
#endif

#define OBJSTORE_WORDS ((OBJSTORE_BYTES / 4) + 2)
static OBJ objstore[OBJSTORE_WORDS];
static OBJ memStart = NULL;
static OBJ memEnd = NULL;
static OBJ freeChunk = NULL;

// Initialization

void memInit() {
	// verify 32-bit architecture
	if (!(sizeof(int) == 4 && sizeof(int*) == 4 && sizeof(float) == 4)) {
		vmPanic("MicroBlocks expects int, int*, and float to all be 32-bits");
	}

	// initialize object heap memory
	memStart = (OBJ) objstore;
	memEnd = (OBJ) (objstore + OBJSTORE_WORDS);
	memClear();
}

void memClear() {
	// Clear object memory and set all global variables to zero.

	// clear global variables
	for (int i = 0; i < MAX_VARS; i++) vars[i] = int2obj(0);

	// zero objectstore memory (not essential)
	memset(objstore, 0, sizeof(objstore));

	// create the free chunk (prefixed by a forwarding word)
	objstore[0] = (OBJ) 0; // forwarding word
	objstore[1] = (OBJ)HEADER(FREE_CHUNK, OBJSTORE_WORDS - 2); // free chunk
	freeChunk = (OBJ) &objstore[1];
}

void vmPanic(char *errorMessage) {
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

OBJ newObjOld(int typeID, int wordCount, OBJ fill) {
	if ((freeChunk + HEADER_WORDS + wordCount) > memEnd) {
		return fail(insufficientMemoryError);
	}
	OBJ obj = freeChunk;
	freeChunk += HEADER_WORDS + wordCount;
	for (OBJ p = obj; p < freeChunk; ) *p++ = (int) fill;
	unsigned header = HEADER(typeID, wordCount);
	obj[0] = header;
	return obj;
}

OBJ newObj(int type, int wordCount, OBJ fill) {
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
	while (ptr < end) { *ptr++ = fill; }
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
	*(oldObj - 1) = (uint32) result; // point forwarding field of oldObj to result
	applyForwarding();
	*(oldObj - 1) = 0; // clear forwarding field
	*oldObj = WORDS(oldObj); // mark old chunk free
}

// String Primitives

OBJ newStringFromBytes(uint8 *bytes, int byteCount) {
	// Create a new string object with the given bytes.
	// Round up to an even number of words and pad with nulls.

	int wordCount = ((byteCount + 1) + 3) / 4; // leave room for terminator byte
	OBJ result = newObj(StringType, wordCount, 0);
	if (!result) return falseObj; // insufficient room to allocate string

	char *dst = (char *) &result[HEADER_WORDS];
	for (int i = 0; i < byteCount; i++) *dst++ = *bytes++;
	*dst = 0; // null terminator byte
	return result;
}

char* obj2str(OBJ obj) {
	if (isInt(obj)) return "<Integer>";
	if (isBoolean(obj)) return ((trueObj == obj) ? "true" : "false");
	if (IS_TYPE(obj, StringType)) return (char *) &obj[HEADER_WORDS];
	if (IS_TYPE(obj, ArrayType)) return "<Array>";
	return "<Object>";
}

// Debugging

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

// OBJ Forwarding

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

void applyForwarding() {
	// Update all forwarded references.

	uint32 *end = (uint32 *) &objstore[OBJSTORE_WORDS];
	uint32 *next = (uint32 *) objstore + 1;
	while (next < end) {
		int info = TYPE(next);
		if (info && (StringType != info)) { // non-free chunk with OBJ fields (not a string)
			for (int i = WORDS(next); i > 0; i--) {
				OBJ child = (OBJ) next[i];
				if (!isInt(child) && *(child - 1)) { // child has a non-zero forwarding field
					next[i] = *(child - 1); // update the forwarded OBJ
				}
			}
		}
		next += WORDS(next) + 2;
	}
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
		sprintf(s, "%s: Array (%d fields)", msg, WORDS(obj));
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
		int info = TYPE(next);
		if (info) {
			uint32 *fwd = (uint32 *) *(next - 1);
			if (fwd) {
				if (fwd > base) fwd = (uint32 *) (fwd - base); // word offset in objstore
				sprintf(s, "%d type: %d words: %d fwd: %d", (next - base), info, wordCount, (int) fwd);
			} else {
				sprintf(s, "%d type: %d words: %d", (next - base), info, wordCount);
			}
		} else {
			sprintf(s, "%d FREE %d", (next - base), wordCount);
		}
		outputString(s);
		next = next + wordCount + 2;
	}
	outputString("----------");
}

// Mark-Sweep-Compact Garbage Collector

#define SET_MARK(obj) ((*(((uint32 *) (obj)) - 1)) = 1)
#define IS_MARKED(obj) (*(((uint32 *) (obj)) - 1))

void mark(OBJ root) {
	// Mark all objects reachable from the given root.

	if (isInt(root) || isBoolean(root) || IS_MARKED(root)) return;

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
		if (!isInt(child) && !isBoolean(child) && !IS_MARKED(child) && (StringType != TYPE(child))) { // child is not an integer, String, or marked
			// reverse pointers before processing child
			current[i] = *child; // store child's header it ith field of current
			*(current - 1) = i; // store i in forwarding field of current
			i = WORDS(child); // scan backwards from last field of child
			*child = (int) current; // backpointer to current
			current = child; // process child
		} else {
			i--;
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
			// mark chunk as free by clearing its info field
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
	uint32 freeWords = (end - dst) - 2;
	*dst = HEADER(FREE_CHUNK, freeWords);
	freeChunk = (OBJ) dst;
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
