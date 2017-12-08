// persist.c - Persistent memory for code and variables
// John Maloney, December 2017

// Porting:
// Different boards have different Flash sizes and memory layouts. In addition,
// different processors require different code to modify their Flash memory.
//
// To add a new board, add a case to the #ifdef for that board and define the constants:
//
//		START - starting address of persistent memory
//		HALF_SPACE - size (in bytes) of each half-space; must be a multiple of Flash page size
//
// and implement the platform-specific Flash functions:
//
//		void eraseFlash(int *startAddr, int *endAddr)
//		void finishFlashWrite(int *dst)
//		void lockFlash()
//		void unlockFlash()

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// flash operations for supported platforms

#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_NRF52_PRIMO)
	#include "nrf.h" // nRF51 and nRF52

	#ifdef ARDUINO_BBC_MICROBIT
		// BBC micro:bit: App: 0-36k; Persistent Mem: 36k-256k
		#define START (36 * 1024)
		#define HALF_SPACE (110 * 1024)
	#else
		// Primo: SoftDevice: 0-112k; App: 112k-148k; Persistent Mem: 148k-488k; Boot: 488k-511k
		#define START (148 * 1024)
		#define HALF_SPACE (170 * 1024)
	#endif

	static void eraseFlash(int *startAddr, int *endAddr) {
		NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Een;
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}

		while (startAddr < endAddr) {
			NRF_NVMC->ERASEPAGE = (int) startAddr;
			startAddr += 256; // page size is 256 words (1024 bytes)
		}

		NRF_NVMC->CONFIG = 0; // clear erase enable bit
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
	}

	static void finishFlashWrite(int *dst) { } // not needed on nRF processors

	static void lockFlash() {
		NRF_NVMC->CONFIG = 0; // clear write enable bit
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
	}

	static void unlockFlash() {
		NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen;
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
	}

#elif defined(ARDUINO_SAMD_MKRZERO)
	#include "samr.h" // SAM21D

	#define START (40 * 1024)
	#define HALF_SPACE (108 * 1024)

	#define NVMCTRL_CTRLA ((int *) 0x41004000)
	#define NVMCTRL_CTRLB ((int *) 0x41004004)
	#define NVMCTRL_ADDR  ((int *) 0x4100401C)
	#define MANW 128 // manual write bit in NVMCTRL_CTRLB

	static void eraseFlash(int *startAddr, int *endAddr) {
		while (startAddr < endAddr) {
			*NVMCTRL_ADDR = ((int) startAddr) >> 1; // must shift address right by 1-bit (see processor data sheet)
			*NVMCTRL_CTRLA = 0xA502; // cmd: erase page
			startAddr += 64; // erasure unit (a "row") is 4 * 64 bytes = 64 words
		}
	}

	static void finishFlashWrite(int *dst) {
		// Finish a Flash write operation where the last word written is *(dst - 1).
		// Details: Atmel SAM processors only write to Flash when the last word of a 64 byte
		// Flash page buffer is written. To force that to happen, write -1 words (i.e. all 1 bits)
		// until dst reaches the start of the next page. (Writing "1" bits has no effect on any
		// previous contents of Flash.)

		while (((int) dst) & 0x3F) *dst++ = -1;
	}

	static void lockFlash() {
		// Protect Flash against accidental modification. (Require an explicit write command.)
		*NVMCTRL_CTRLB = *NVMCTRL_CTRLB | MANW;
	}

	static void unlockFlash() {
		// Allow Flash modification by sequentially writing into it.
		*NVMCTRL_CTRLB = *NVMCTRL_CTRLB & ~MANW;
	}

// #elif defined(ARDUINO_SAM_DUE)
// 	#include "samr.h" // AT91SAM3X8E
//
// 	// Not yet implemented!
//
#else
	// Simulate Flash operations when testing on a laptop.

	#define START (&flash[0])
	#define HALF_SPACE (5 * 1024)
	static unsigned char flash[2 * HALF_SPACE]; // simulated Flash memory (10k)

	static void eraseFlash(int *startAddr, int *endAddr) {
		int *dst = (int *) startAddr;
		while (dst < endAddr) { *dst++ = -1; }
	}

	static void finishFlashWrite(int *dst) { }
	static void lockFlash() { }
	static void unlockFlash() { }

#endif

// variables

// persistent memory half-space ranges:
static int *start0 = (int *) START;
static int *end0 = (int *) (START + HALF_SPACE);
static int *start1 = (int *) (START + HALF_SPACE);
static int *end1 = (int *) (START + (2 * HALF_SPACE));;

static int current;		// current half-space (0 or 1)
static int *freeStart;	// first free word

// helper functions

static void clearHalfSpace(int halfSpace) {
	int *startAddr = (0 == halfSpace) ? start0 : start1;
	int *endAddr = (0 == halfSpace) ? end0 : end1;
	eraseFlash(startAddr, endAddr);
}

static int cycleCount(int halfSpace) {
	// Return the cycle count for the given half-space or zero if not initialized.
	// Details: Each half-space begins with a word of the form <'S'><cycle count (24 bits)>.
	// The cycle count is incremented each time persistent memory is compacted.

	int *p = (0 == halfSpace) ? start0 : start1;
	return ('S' == ((*p >> 24) & 0xFF)) ? (*p & 0xFFFFFF) : 0;
}

static void setCycleCount(int halfSpace, int cycleCount) {
	// Store the given cycle count at the given address.

	unlockFlash();
	int *p = (0 == halfSpace) ? start0 : start1;
	*p = ('S' << 24) | (cycleCount & 0xFFFFFF);
	finishFlashWrite(p + 1);
	lockFlash();
}

static void initPersistentMemory() {
	// Figure out which is the current half-space and find freeStart.
	// If neither half-space has a valid cycle counter, initialize persistent memory.

	int c0 = cycleCount(0);
	int c1 = cycleCount(1);

	if (!c0 && !c1) { // neither half-space has a valid counter
		// Flash hasn't been used for uBlocks yet; erase it all.
		eraseFlash(start0, end1);
		setCycleCount(0, 1);
		current = 0;
		freeStart = start0 + 1;
		return;
	}

	int *end;
	if (c0 > c1) {
		current = 0;
		freeStart = start0 + 1;
		end = end0;
	} else {
		current = 1;
		freeStart = start1 + 1;
		end = end1;
	}

	while ((freeStart < end) && (-1 != *freeStart)) {
		int header = *freeStart;
		if ('R' != ((header >> 24) & 0xFF)) {
			printf("Bad record found during initialization!\n");
			clearPersistentMemory();
			return;
		}
		freeStart += *(freeStart + 1) + 2; // increment by the record length plus 2-word header
	}
	if (freeStart >= end) freeStart = end;
}

static int * recordAfter(int *lastRecord) {
	// Return a pointer to the record following the given record, or NULL if there are
	// no more records. Pass NULL to get the first record.

	int *start, *end;
	if (0 == current) {
		start = start0;
		end = end0;
	} else {
		start = start1;
		end = end1;
	}

	int *p = lastRecord;
	if (NULL == lastRecord) { // return the first record
		p = (start + 1);
		return ('R' == ((*p >> 24) & 0xFF)) ? p : NULL;
	}

	if ((p >= end) || ('R' != ((*p >> 24) & 0xFF))) return NULL; // should not happen
	p += *(p + 1) + 2; // increment by the record length plus 2-word header
	if ((p >= end) || 'R' != ((*p >> 24) & 0xFF)) return NULL; // bad header; probably start of free space
	return p;
}

// compaction

struct {
	int *chunkCodeRec;
	int *positionRec;
	int *sourceCodeRec;
} chunkData;

struct {
	int *valueRec;
	int *nameRec;
} varData;

static char chunkProcessed[256];
static char varProcessed[256];

static int * copyChunk(int *dst, int *src) {
	// Copy the chunk record at src to dst and return the new value of dst.

	int wordCount = *(src + 1) + 2;
	while (wordCount-- > 0) *dst++ = *src++;
	return dst;
}

static int * copyChunkInfo(int id, int *src, int *dst) {
	// Copy the most recent data about the chunk with the given ID to dst and return
	// the new dst pointer. If the given chunk id has been processed do nothing.

	if (chunkProcessed[id]) return dst;

	// clear chunkData
	memset(&chunkData, 0, sizeof(chunkData));

	// scan rest of the records to get the most recent info about this chunk
	while (src) {
		if (id == ((*src >> 8) & 0xFF)) { // id field matche
			int type = (*src >> 16) & 0xFF;
			switch (type) {
			case chunkCode:
				chunkData.chunkCodeRec = src;
				break;
			case chunkPosition:
				chunkData.positionRec = src;
				break;
			case chunkSource:
				chunkData.sourceCodeRec = src;
				break;
			case chunkDeleted:
				memset(&chunkData, 0, sizeof(chunkData)); // clear chunkData
				break;
			}
		}
		src = recordAfter(src);
	}
	if (chunkData.chunkCodeRec) {
		dst = copyChunk(dst, chunkData.chunkCodeRec);
		if (chunkData.positionRec) dst = copyChunk(dst, chunkData.positionRec);
		if (chunkData.sourceCodeRec) dst = copyChunk(dst, chunkData.sourceCodeRec);
	}
	chunkProcessed[id] = true;
	return dst;
}

static int * copyVarInfo(int id, int *src, int *dst) {
	if (varProcessed[id]) return dst;

	// clear varData
	memset(&varData, 0, sizeof(varData));

	// scan rest of the records to get the most recent info about this variable
	while (src) {
		if (id == ((*src >> 8) & 0xFF)) {
			int type = (*src >> 16) & 0xFF;
			switch (type) {
			case varValue:
				varData.valueRec = src;
				break;
			case varName:
				varData.nameRec = src;
				break;
			case varDeleted:
				memset(&varData, 0, sizeof(varData)); // clear varData
				break;
			}
		}
		src = recordAfter(src);
	}
	if (varData.valueRec) {
		dst = copyChunk(dst, varData.valueRec);
		if (varData.nameRec) dst = copyChunk(dst, varData.nameRec);
	}
	varProcessed[id] = true;
	return dst;
}

static void compact() {
	// Copy only the most recent chunk and variable records to the other half-space.
	// Details:
	//   1. erase the other half-space
	//   2. clear the chunk and variable processed flags
	//   3. for each chunk and variable record the current half-space
	//		a. if the chunk or variable has been processed, skip it
	//		b. gather the most recent information about that chunk or variable
	//		c. write that information into the other half-space
	//		d. mark the chunk or variable as processed
	//   4. switch to the other half-space
	//   5. remember the free pointer for the new half-space

	// clear the processed flags
	memset(chunkProcessed, 0, sizeof(chunkProcessed));
	memset(varProcessed, 0, sizeof(varProcessed));

	// clear the destination half-space and init dst pointer
	clearHalfSpace(!current);
	int *dst = (0 == !current) ? start0 + 1 : start1 + 1;

	unlockFlash();
	int *src = recordAfter(NULL);
	while (src) {
		int header = *src;
		int type = (header >> 16) & 0xFF;
		int id = (header >> 8) & 0xFF;
		if ((chunkCode <= type) && (type <= chunkDeleted)) {
			dst = copyChunkInfo(id, src, dst);
		} else if ((varValue <= type) && (type <= varDeleted)) {
			dst = copyVarInfo(id, src, dst);
		}
		src = recordAfter(src);
	}
	finishFlashWrite(dst);
	lockFlash();

	// increment the cycle counter and switch to the other half-space
	setCycleCount(!current, cycleCount(current) + 1); // this commits the compaction
	current = !current;
	freeStart = dst;
}

// entry points

void clearPersistentMemory() {
	int c0 = cycleCount(0);
	int c1 = cycleCount(1);
	int count = (c0 > c1) ? c0 : c1;
	current = !current;
	clearHalfSpace(current);
	freeStart = (0 == current) ? start0 + 1 : start1 + 1;
	setCycleCount(current, count + 1);
}

int * appendPersistentRecord(int recordType, int id, int extra, int byteCount, char *data) {
	// Append the given record at the end of the current half-space and return it's address.
	// Header word: <tag = 'R'><record type><id of chunk/variable/comment><type> (8-bits each)
	// Perform a compaction if necessary.

	int wordCount = (byteCount + 3) / 4;
	int *end = (0 == current) ? end0 : end1;
	if ((freeStart + 2 + wordCount) > end) {
		compact();
		end = (0 == current) ? end0 : end1;
		if ((freeStart + 2 + wordCount) > end) {
			printf("Not enough room even after compaction\n");
			return NULL;
		}
	}

	// write the record
	int *result = freeStart;
	unlockFlash();
	int header = ('R' << 24) | ((recordType & 0xFF) << 16) | ((id & 0xFF) << 8) | (extra & 0xFF);
	*freeStart++ = header;
	*freeStart++ = wordCount;
	for (int i = 0; i < wordCount; i++) {
		int w = *data++;
		w |= (*data++ << 8);
		w |= (*data++ << 16);
		w |= (*data++ << 24);
		*freeStart++ = w;
	}
	finishFlashWrite(freeStart);
	lockFlash();

	return result;
}

void restoreScripts() {
	initPersistentMemory();
	memset(chunks, 0, sizeof(chunks));
	int *p = recordAfter(NULL);
	while (p) {
		int recType = (*p >> 16) & 0xFF;
		if (chunkCode == recType) {
			int chunkIndex = (*p >> 8) & 0xFF;
			if (chunkIndex < MAX_CHUNKS) {
				chunks[chunkIndex].chunkType = *p & 0xFF;
				chunks[chunkIndex].code = p;
			}
		}
		p = recordAfter(p);
	}

	// Give feedback:
	int chunkCount = 0;
	for (int i = 0; i < MAX_CHUNKS; i++) {
		if (chunks[i].code) chunkCount++;
	}
	char s[100];
	sprintf(s, "Restored %d scripts", chunkCount);
	outputString(s);
}

// testing

static int dummyData[] = {
	  1,  2,  3,  4,  5,  6,  7,  8,  9, 10,
	 11, 12, 13, 14, 15, 16, 17, 18, 19, 20};

static void dumpWords(int halfSpace, int count) {
	// Dump the first count words of the given half-space.

	int *p = (current == 0) ? start0 : start1;
	for (int i = 0; i < count; i++) {
		printf("%d %d %d %d\n",
			(*p >> 24) & 0xFF,
			(*p >> 16) & 0xFF,
			(*p >> 8) & 0xFF,
			*p & 0xFF);
		p++;
	}
}

static void showRecordHeaders() {
	// Dump the record headers of the current half-space.

	int *p = recordAfter(NULL);
	while (p) {
		printf("Record at offset %d: %d %d %d %d (%d words)\n",
			(p - start0),
			(*p >> 24) & 0xFF, (*p >> 16) & 0xFF, (*p >> 8) & 0xFF, *p & 0xFF, *(p + 1));
		p = recordAfter(p);
	}
}

void persistTest() {
	printf("Persistent Memory Test\n\n");

	initPersistentMemory();
 	clearPersistentMemory();
	printf("Memory intitialized; writing records...\n");

	for (int i = 0; i < 3000; i++) {
		appendPersistentRecord(chunkCode, i % 100, 0, (i % 5) * 4, dummyData);
	}
	compact();

 	dumpWords(current, 100);
	showRecordHeaders();

	printf("Final: current %d used %d c0 %d c1 %d\n",
		current,
		freeStart - ((0 == current) ? start0 : start1),
		cycleCount(0), cycleCount(1));
}
