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
//		void flashErase(int *startAddr, int *endAddr)
//		void flashWriteData(int *dst, int wordCount, uint8 *src)
//		void flashWriteWord(int *addr, int value)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

// flash operations for supported platforms

#if defined(ARDUINO_NRF52_PRIMO) || defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_CALLIOPE)
	#include "nrf.h" // nRF51 and nRF52

	#ifdef ARDUINO_NRF52_PRIMO
		// Primo: SoftDevice: 0-112k; App: 112k-148k; Persistent Mem: 148k-488k; Boot: 488k-511k
		#define START (148 * 1024)
		#define HALF_SPACE (170 * 1024)
	#else
		// BBC micro:bit and Calliope: App: 0-36k; Persistent Mem: 36k-256k
		#define START (36 * 1024)
		#define HALF_SPACE (110 * 1024)
	#endif

	static void flashErase(int *startAddr, int *endAddr) {
		NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Een; // enable Flash erase
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}

		while (startAddr < endAddr) {
			NRF_NVMC->ERASEPAGE = (int) startAddr;
			startAddr += 256; // page size is 256 words (1024 bytes)
		}

		NRF_NVMC->CONFIG = 0; // disable Flash erase
	}

	void flashWriteWord(int *addr, int value) {
		NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen; // enable Flash write
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
		*addr = value;
		NRF_NVMC->CONFIG = 0; // disable Flash write
	}

	void flashWriteData(int *dst, int wordCount, uint8 *src) {
		NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen; // enable Flash write
		while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
		for ( ; wordCount > 0; wordCount--) {
			int n = *src++;
			n |= *src++ << 8;
			n |= *src++ << 16;
			n |= *src++ << 24;
			*dst++ = n;
		}
		NRF_NVMC->CONFIG = 0; // disable Flash write
	}

#elif defined(ARDUINO_SAMD_MKRZERO) || defined(ARDUINO_SAMD_ZERO) || defined(ARDUINO_SAM_ZERO) || defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)
	#include "samr.h" // SAM21D

	#define START (56 * 1024)
	#define HALF_SPACE (100 * 1024)

	// SAM21 Non-Volatile Memory Controller Registers
	#define NVMC_CTRLA   ((volatile int *) 0x41004000)
	#define NVMC_CTRLB   ((volatile int *) 0x41004004)
	#define NVMC_INTFLAG ((volatile int *) 0x41004014)
	#define NVMC_ADDR    ((volatile int *) 0x4100401C)

	// SAM21 Non-Volatile Memory Controller Constants and Commands
	#define MANW 128 // manual write bit in NVMC_CTRLB
	#define READY_BIT 1 // ready bit in NVMC_INTFLAG
	#define CMD_ERASE_PAGE 0xA502
	#define CMD_WRITE_PAGE 0xA504

	static void flashErase(int *startAddr, int *endAddr) {
		while (!(*NVMC_INTFLAG & READY_BIT)){} // wait for previous operation to complete

		while (startAddr < endAddr) {
			*NVMC_ADDR = ((int) startAddr) >> 1; // must shift address right by 1-bit (see processor data sheet)
			*NVMC_CTRLA = CMD_ERASE_PAGE;
			startAddr += 64; // erasure unit (a "row") is 4 * 64 bytes = 64 words
		}
	}

	void flashWriteWord(int *addr, int value) {
 		 while (!(*NVMC_INTFLAG & READY_BIT)){} // wait for previous operation to complete
		*addr = value;
		*NVMC_CTRLA = CMD_WRITE_PAGE;
	}

	void flashWriteData(int *dst, int wordCount, uint8 *src) {
 		 while (!(*NVMC_INTFLAG & READY_BIT)){} // wait for previous operation to complete

		*NVMC_CTRLB = *NVMC_CTRLB & ~MANW; // automatically write pages at page boundaries
		for ( ; wordCount > 0; wordCount--) {
			int n = *src++;
			n |= *src++ << 8;
			n |= *src++ << 16;
			n |= *src++ << 24;
			*dst++ = n;
		}
		*NVMC_CTRLA = CMD_WRITE_PAGE; // write final partial page
		*NVMC_CTRLB = *NVMC_CTRLB | MANW; // stop page auto-write
	}

#elif defined(ARDUINO_SAM_DUE)
	#include "sam.h" // AT91SAM3X8E

	// NOTE: Sam3 does not allow writing into the same Flash bank as the executing program.
	// Since the uBlocks VM runs in the lower bank of Flash, the persistent memory area
	// must be in the upper bank of Flash which starts at 256K.

	#define START (256 * 1024)
	#define HALF_SPACE (128 * 1024)

	// SAM3 Flash Memory Controller Registers
	#define EFC1_CMD    ((volatile int *) 0x400E0C04) // Command register for second 256k bank
	#define EFC1_STATUS ((volatile int *) 0x400E0C08) // IntFlag register for second 256k bank

	// SAM3 Flash Memory Controller Constants and Commands
	#define READY_BIT 1
	#define KEY 0x5A000000 // Flash command key
	#define WRITE_PAGE 1
	#define ERASE_PAGE 3

	static void flashErase(int *startAddr, int *endAddr) {
		while (startAddr < endAddr) {
			*EFC1_CMD = KEY | ((int) startAddr & 0xFFFF00) | ERASE_PAGE;
			while (!(*EFC1_STATUS & READY_BIT)){} // wait for operation to complete
			startAddr += 64; // erasure unit (a "row") is 4 * 64 bytes = 64 words
		}
	}

	void flashWriteWord(int *dst, int value) {
		*dst = value;
		*EFC1_CMD = KEY | ((int) dst & 0xFFFF00) | WRITE_PAGE;
		while (!(*EFC1_STATUS & READY_BIT)){} // wait for operation to complete
	}

	void flashWriteData(int *dst, int wordCount, uint8 *src) {
		// Copy wordCount words into Flash memory starting at dst.
		// The destination address must be word-aligned, but the source need not be.

		dst = (int *) ((int) dst & 0xFFFFFFFC); // ensure that dst is word-aligned
		for ( ; wordCount > 0; wordCount--) {
			*dst++ = *((int *) src);
			src += 4; // increment by 4 bytes
			if (0 == ((int) dst & 0x3F)) { // page boundary
				*EFC1_CMD = KEY | (((int) dst - 4) & 0xFFFF00) | WRITE_PAGE; // write the previous page
				while (!(*EFC1_STATUS & READY_BIT)){} // wait for operation to complete
			}
		}
		*EFC1_CMD = KEY | (((int) dst - 4) & 0xFFFF00) | WRITE_PAGE; // write the final page
		while (!(*EFC1_STATUS & READY_BIT)){} // wait for operation to complete
	}

#else
	// Simulate Flash operations using RAM; allows uBlocks to run in RAM on platforms
	// that do not support Flash-based persistent memory.

	#define START (&flash[0])
	#define HALF_SPACE (8 * 1024)
	static uint8 flash[2 * HALF_SPACE]; // simulated Flash memory (16k)

	static void flashErase(int *startAddr, int *endAddr) {
		int *dst = (int *) startAddr;
		while (dst < endAddr) { *dst++ = -1; }
	}

	void flashWriteWord(int *addr, int value) {
		*addr = value;
	}

	void flashWriteData(int *dst, int wordCount, uint8 *src) {
		for ( ; wordCount > 0; wordCount--) {
			int n = *src++;
			n |= *src++ << 8;
			n |= *src++ << 16;
			n |= *src++ << 24;
			*dst++ = n;
		}
	}

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
	flashErase(startAddr, endAddr);
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

	int *p = (0 == halfSpace) ? start0 : start1;
	flashWriteWord(p, ('S' << 24) | (cycleCount & 0xFFFFFF));
}

static void initPersistentMemory() {
	// Figure out which is the current half-space and find freeStart.
	// If neither half-space has a valid cycle counter, initialize persistent memory.

	int c0 = cycleCount(0);
	int c1 = cycleCount(1);

	if (!c0 && !c1) { // neither half-space has a valid counter
		// Flash hasn't been used for uBlocks yet; erase it all.
		flashErase(start0, end1);
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

int * recordAfter(int *lastRecord) {
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
	int *attributeRecs[ATTRIBUTE_COUNT];
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
	flashWriteData(dst, wordCount, (uint8 *) src);
	return dst + wordCount;
}

static int * copyChunkInfo(int id, int *src, int *dst) {
	// Copy the most recent data about the chunk with the given ID to dst and return
	// the new dst pointer. If the given chunk id has been processed do nothing.

	if (chunkProcessed[id]) return dst;

	// clear chunkData
	memset(&chunkData, 0, sizeof(chunkData));

	// scan rest of the records to get the most recent info about this chunk
	while (src) {
		int attributeID;
		if (id == ((*src >> 8) & 0xFF)) { // id field matche
			int type = (*src >> 16) & 0xFF;
			switch (type) {
			case chunkCode:
				chunkData.chunkCodeRec = src;
				break;
			case chunkAttribute:
				attributeID = *src & 0xFF;
				if (attributeID < ATTRIBUTE_COUNT) {
					chunkData.attributeRecs[attributeID] = src;
				}
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
		for (int i = 0; i < ATTRIBUTE_COUNT; i++) {
			if (chunkData.attributeRecs[i]) dst = copyChunk(dst, chunkData.attributeRecs[i]);
		}
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
		int type = (*src >> 16) & 0xFF;
		switch (type) {
		case varValue:
			if (id == ((*src >> 8) & 0xFF)) varData.valueRec = src;
			break;
		case varName:
			if (id == ((*src >> 8) & 0xFF)) varData.nameRec = src;
			break;
		case varsClearAll:
			memset(&varData, 0, sizeof(varData)); // clear varData
			break;
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

	int *src = recordAfter(NULL);
	while (src) {
		int header = *src;
		int type = (header >> 16) & 0xFF;
		int id = (header >> 8) & 0xFF;
		if ((chunkCode <= type) && (type <= chunkDeleted)) {
			dst = copyChunkInfo(id, src, dst);
		} else if ((varValue <= type) && (type <= varsClearAll)) {
			dst = copyVarInfo(id, src, dst);
		}
		src = recordAfter(src);
	}

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

int * appendPersistentRecord(int recordType, int id, int extra, int byteCount, uint8 *data) {
	// Append the given record at the end of the current half-space and return it's address.
	// Header word: <tag = 'R'><record type><id of chunk/variable/comment><extra> (8-bits each)
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
	int header = ('R' << 24) | ((recordType & 0xFF) << 16) | ((id & 0xFF) << 8) | (extra & 0xFF);
	flashWriteWord(freeStart++, header);
	flashWriteWord(freeStart++, wordCount);
	flashWriteData(freeStart, wordCount, data);
	freeStart += wordCount;
	return result;
}

static void pauseBeforeStarting(int msecs) {
	// Wait a bit before autostarting scripts to give the user a chance
	// to clear any possibly broken scripts before they are auto-started.

	int startT = millisecs();
	while ((millisecs() - startT) < msecs) {
		processMessage();
	}
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
		if (chunkDeleted == recType) {
			int chunkIndex = (*p >> 8) & 0xFF;
			if (chunkIndex < MAX_CHUNKS) {
				chunks[chunkIndex].chunkType = unusedChunk;
				chunks[chunkIndex].code = NULL;
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
	sprintf(s, "Restoring %d scripts...", chunkCount);
	outputString(s);

	pauseBeforeStarting(2000);
	outputString("Started");
}

// testing

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

void basicTest() {
  int testData[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
  uint8 charData[] = {
      0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0,
      5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 8, 0, 0, 0, 9, 0, 0, 0};

  #define PAGE ((int *) START)

  flashErase(PAGE, PAGE + 100);
  dumpWords(0, 35);
  printf("-----\n");
  flashWriteData(PAGE, 10, (uint8 *) testData);
  flashWriteWord(PAGE + 13, 13);
  flashWriteWord(PAGE + 15, 42);
  flashWriteWord(PAGE + 17, 17);
  flashWriteData(PAGE + 19, 3, charData);
  flashWriteData(PAGE + 23, 3, &charData[1]);
  flashWriteData(PAGE + 27, 3, &charData[2]);
  dumpWords(0, 35);
  flashErase(PAGE, PAGE + 100);
  dumpWords(0, 20);
}

void persistTest() {
	int dummyData[] = {1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16};

	printf("Persistent Memory Test\n\n");
	basicTest();

	printf("\nInitializing Memory\n");
	initPersistentMemory();
	initPersistentMemory();
 	clearPersistentMemory();
	printf("Memory intitialized; writing records...\n");

	for (int i = 0; i < 3000; i++) {
		appendPersistentRecord(chunkCode, i % 100, 0, (i % 5) * 4, (uint8 *) dummyData);
	}
	compact();

 	dumpWords(current, 150);
	showRecordHeaders();

	printf("Final: current %d used %d c0 %d c1 %d\n",
		current,
		freeStart - ((0 == current) ? start0 : start1),
		cycleCount(0), cycleCount(1));
}
