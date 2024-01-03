/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

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

#if defined(NRF51) || defined(NRF52) || defined(ARDUINO_NRF52_PRIMO)
	#include "nrf.h" // nRF51 and nRF52

	// to check available FLASH, build with -Wl,-Map,output.map and make sure __etext < START
	#if defined(NRF51)
		// BBC micro:bit and Calliope: App: 0-96k; Persistent Mem: 96k-256k
		#define START (96 * 1024)
		#define HALF_SPACE (80 * 1024)
	#elif defined(ARDUINO_NRF52_PRIMO)
		// Primo: SoftDevice: 0-112k; App: 112k-210k; Persistent Mem: 210k-488k; Boot: 488k-512k
		#define START (210 * 1024)
		#define HALF_SPACE (100 * 1024)
	#elif defined(NRF52)
		// nrf52832: SoftDevice + app: 0-316k; Persistent Mem: 316-436k; User data: 436k-464k; Boot: 464k-512k
		#define START (316 * 1024)
		#define HALF_SPACE (60 * 1024)
	#endif

	static void flashErase(int *startAddr, int *endAddr) {
		uint32 pageSize = NRF_FICR->CODEPAGESIZE / 4; // page size in words
		NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Een; // enable Flash erase
		while (startAddr < endAddr) {
			while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
			NRF_NVMC->ERASEPAGE = (int) startAddr;
			startAddr += pageSize;
			#if defined(BLE_IDE)
				delay(30);
			#endif
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
		for ( ; wordCount > 0; wordCount--) {
			int n = *src++;
			n |= *src++ << 8;
			n |= *src++ << 16;
			n |= *src++ << 24;
			while (NRF_NVMC->READY == NVMC_READY_READY_Busy){}
			*dst++ = n;
		}
		NRF_NVMC->CONFIG = 0; // disable Flash write
	}

#elif defined(ARDUINO_ARCH_SAMD) || \
	defined(ARDUINO_SAMD_MKRZERO) || defined(ARDUINO_SAMD_ZERO) || defined(ARDUINO_SAM_ZERO) || \
	defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ADAFRUIT_ITSYBITSY_M0)

	#include "samr.h" // SAM21D

	// SAMD: App: 0-96k; Persistent Mem: 96k-256k
	#define START (136 * 1024)
	#define HALF_SPACE (60 * 1024)

	// SAM21 Non-Volatile Memory Controller Registers
	#define NVMC_CTRLA		((volatile int *) 0x41004000)
	#define NVMC_CTRLB		((volatile int *) 0x41004004)
	#define NVMC_INTFLAG	((volatile int *) 0x41004014)
	#define NVMC_ADDR		((volatile int *) 0x4100401C)

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
	#define EFC1_CMD	((volatile int *) 0x400E0C04) // Command register for second 256k bank
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

#elif defined(__MK20DX256__)

#include <kinetis.h>

// Teensy 3.2 - 32K Data Flash, 2K FlexRAM, 1K sectors, 32 bit word size
#define START (0x10000000)
#define HALF_SPACE (16 * 1024)

static void flashErase(int *startAddr, int *endAddr) {
	uint32_t addr = (uint32_t)startAddr & 0xFFFFFC00;
	uint16_t cmd[] = {0x2380, 0x7003, 0x7803, 0xb25b, 0x2b00, 0xdafb, 0x4770};
	if (!(FTFL_FCNFG & FTFL_FCNFG_RAMRDY)) return;
	while (addr < (uint32_t)endAddr) {
		__disable_irq();
		*(uint32_t *)&FTFL_FCCOB3 = 0x09800000 | (addr & 0x007FFFFC);
		FTFL_FSTAT = 0x70;
		(*((void (*)(volatile uint8_t *))((uint32_t)cmd | 1)))(&FTFL_FSTAT);
		__enable_irq();
		addr = addr + 1024;
	}
}

void flashWriteData(int *dst, int wordCount, uint8_t *src) {
	uint32_t addr = (uint32_t)dst & 0xFFFFFFFC;
	uint16_t cmd[] = {0x2380, 0x7003, 0x7803, 0xb25b, 0x2b00, 0xdafb, 0x4770};
	if (!(FTFL_FCNFG & FTFL_FCNFG_RAMRDY)) return;
	while (wordCount > 0) {
		uint32_t n = wordCount;
		if (n > 256) n = 256;
		memcpy((void *)0x14000000, src, n * 4);
		__disable_irq();
		*(uint32_t *)&FTFL_FCCOB3 = 0x0B800000 | (addr & 0x007FFFFC);
		*(uint32_t *)&FTFL_FCCOB7 = n << 16;
		FTFL_FSTAT = 0x70;
		(*((void (*)(volatile uint8_t *))((uint32_t)cmd | 1)))(&FTFL_FSTAT);
		__enable_irq();
		addr = addr + n * 4;
		wordCount -= n;
	}
}

void flashWriteWord(int *addr, int value) {
	flashWriteData(addr, 1, (uint8_t *)&value);
}

#elif defined(__MK64DX512__)
// Teensy 3.5 - 128K Data Flash, 4K FlexRAM, 4K sectors, 64 bit word size
#define START (0x10000000)
#define HALF_SPACE (64 * 1024)

#elif defined(__MK66FX1M0__)
// Teensy 3.6 - 256K Data Flash, 4K FlexRAM, 4K sectors, 64 bit word size, can't write in HSRUN mode
#define START (0x10000000)
#define HALF_SPACE (128 * 1024)

#elif defined(__IMXRT1062__)

#include <imxrt.h>

#if defined(ARDUINO_TEENSY40)
// Teensy 4.0 - 60K Data Flash, 4K sectors, 256 byte pages
#define START (0x601F0000)
#define HALF_SPACE (30 * 1024)

#elif defined(ARDUINO_TEENSY41)
// Teensy 4.1 - 252K Data Flash, 4K sectors, 256 byte pages
#define START (0x607F0000)
#define HALF_SPACE (124 * 1024)
#endif // Teensy 4.x

#define LUT0(opcode, pads, operand) (FLEXSPI_LUT_INSTRUCTION((opcode), (pads), (operand)))
#define LUT1(opcode, pads, operand) (FLEXSPI_LUT_INSTRUCTION((opcode), (pads), (operand)) << 16)
#define CMD_SDR         FLEXSPI_LUT_OPCODE_CMD_SDR
#define ADDR_SDR        FLEXSPI_LUT_OPCODE_RADDR_SDR
#define READ_SDR        FLEXSPI_LUT_OPCODE_READ_SDR
#define WRITE_SDR       FLEXSPI_LUT_OPCODE_WRITE_SDR
#define PINS1           FLEXSPI_LUT_NUM_PADS_1
#define PINS4           FLEXSPI_LUT_NUM_PADS_4

static void teensy4_flash_wait() {
	FLEXSPI_LUT60 = LUT0(CMD_SDR, PINS1, 0x05) | LUT1(READ_SDR, PINS1, 1); // 05 = read status
	FLEXSPI_LUT61 = 0;
	uint8_t status;
	do {
		FLEXSPI_IPRXFCR = FLEXSPI_IPRXFCR_CLRIPRXF; // clear rx fifo
		FLEXSPI_IPCR0 = 0;
		FLEXSPI_IPCR1 = FLEXSPI_IPCR1_ISEQID(15) | FLEXSPI_IPCR1_IDATSZ(1);
		FLEXSPI_IPCMD = FLEXSPI_IPCMD_TRG;
		while (!(FLEXSPI_INTR & FLEXSPI_INTR_IPCMDDONE)) {
			asm("nop");
		}
		FLEXSPI_INTR = FLEXSPI_INTR_IPCMDDONE;
		status = *(uint8_t *)&FLEXSPI_RFDR0;
	} while (status & 1);
	FLEXSPI_MCR0 |= FLEXSPI_MCR0_SWRESET; // purge stale data from FlexSPI's AHB FIFO
	while (FLEXSPI_MCR0 & FLEXSPI_MCR0_SWRESET) ; // wait
	__enable_irq();
}

// write bytes into flash memory (which is already erased to 0xFF)
static void teensy4_flash_write(void *addr, const void *data, uint32_t len) {
	__disable_irq();
	FLEXSPI_LUTKEY = FLEXSPI_LUTKEY_VALUE;
	FLEXSPI_LUTCR = FLEXSPI_LUTCR_UNLOCK;
	FLEXSPI_IPCR0 = 0;
	FLEXSPI_LUT60 = LUT0(CMD_SDR, PINS1, 0x06); // 06 = write enable
	FLEXSPI_LUT61 = 0;
	FLEXSPI_LUT62 = 0;
	FLEXSPI_LUT63 = 0;
	FLEXSPI_IPCR1 = FLEXSPI_IPCR1_ISEQID(15);
	FLEXSPI_IPCMD = FLEXSPI_IPCMD_TRG;
	arm_dcache_delete(addr, len); // purge old data from ARM's cache
	while (!(FLEXSPI_INTR & FLEXSPI_INTR_IPCMDDONE)) ; // wait
	FLEXSPI_INTR = FLEXSPI_INTR_IPCMDDONE;
	FLEXSPI_LUT60 = LUT0(CMD_SDR, PINS1, 0x32) | LUT1(ADDR_SDR, PINS1, 24); // 32 = quad write
	FLEXSPI_LUT61 = LUT0(WRITE_SDR, PINS4, 1);
	FLEXSPI_IPTXFCR = FLEXSPI_IPTXFCR_CLRIPTXF; // clear tx fifo
	FLEXSPI_IPCR0 = (uint32_t)addr & 0x007FFFFF;
	FLEXSPI_IPCR1 = FLEXSPI_IPCR1_ISEQID(15) | FLEXSPI_IPCR1_IDATSZ(len);
	FLEXSPI_IPCMD = FLEXSPI_IPCMD_TRG;
	const uint8_t *src = (const uint8_t *)data;
	uint32_t n;
	while (!((n = FLEXSPI_INTR) & FLEXSPI_INTR_IPCMDDONE)) {
		if (n & FLEXSPI_INTR_IPTXWE) {
			uint32_t wrlen = len;
			if (wrlen > 8) wrlen = 8;
			if (wrlen > 0) {
				memcpy((void *)&FLEXSPI_TFDR0, src, wrlen);
				src += wrlen;
				len -= wrlen;
			}
			FLEXSPI_INTR = FLEXSPI_INTR_IPTXWE;
		}
	}
	FLEXSPI_INTR = FLEXSPI_INTR_IPCMDDONE | FLEXSPI_INTR_IPTXWE;
	teensy4_flash_wait();
}

// erase a 4K sector
static void teensy4_flash_erase_sector(void *addr) {
	__disable_irq();
	FLEXSPI_LUTKEY = FLEXSPI_LUTKEY_VALUE;
	FLEXSPI_LUTCR = FLEXSPI_LUTCR_UNLOCK;
	FLEXSPI_LUT60 = LUT0(CMD_SDR, PINS1, 0x06); // 06 = write enable
	FLEXSPI_LUT61 = 0;
	FLEXSPI_LUT62 = 0;
	FLEXSPI_LUT63 = 0;
	FLEXSPI_IPCR0 = 0;
	FLEXSPI_IPCR1 = FLEXSPI_IPCR1_ISEQID(15);
	FLEXSPI_IPCMD = FLEXSPI_IPCMD_TRG;
	arm_dcache_delete((void *)((uint32_t)addr & 0xFFFFF000), 4096); // purge data from cache
	while (!(FLEXSPI_INTR & FLEXSPI_INTR_IPCMDDONE)) ; // wait
	FLEXSPI_INTR = FLEXSPI_INTR_IPCMDDONE;
	FLEXSPI_LUT60 = LUT0(CMD_SDR, PINS1, 0x20) | LUT1(ADDR_SDR, PINS1, 24); // 20 = sector erase
	FLEXSPI_IPCR0 = (uint32_t)addr & 0x007FF000;
	FLEXSPI_IPCR1 = FLEXSPI_IPCR1_ISEQID(15);
	FLEXSPI_IPCMD = FLEXSPI_IPCMD_TRG;
	while (!(FLEXSPI_INTR & FLEXSPI_INTR_IPCMDDONE)) ; // wait
	FLEXSPI_INTR = FLEXSPI_INTR_IPCMDDONE;
	teensy4_flash_wait();
}

static void flashErase(int *startAddr, int *endAddr) {
	uint32_t addr = (uint32_t)startAddr & 0xFFFFF000;
	while (addr < (uint32_t)endAddr) {
		teensy4_flash_erase_sector((void *)addr);
		addr = addr + 4096;
	}
}

void flashWriteData(int *dst, int wordCount, uint8_t *src) {
	uint32_t n, count, addr = (uint32_t)dst;

	if (wordCount < 1) return;
	count = wordCount * 4;
	if ((addr & 0xFF) > 0) {
		n = 256 - (addr & 0xFF);
		if (n > count) n = count;
		teensy4_flash_write(addr, src, n);
		addr += n;
		count -= n;
	}
	while (count > 0) {
		n = count;
		if (n > 256) n = 256;
		teensy4_flash_write(addr, src, n);
		addr += n;
		count -= n;
	}
}

void flashWriteWord(int *addr, int value) {
	flashWriteData(addr, 1, (uint8_t *)&value);
}

#else
	// Simulate Flash operations using a RAM code store; allows MicroBlocks to run in RAM
	// on platforms that do not support Flash-based persistent memory. On systems with
	// a file system, the RAM code store is stored in a file to provide persistence.

	#define RAM_CODE_STORE true

	#if defined(ESP8266)
		#define USE_CODE_FILE true
		#define HALF_SPACE (18 * 1024) // ESP8266 is unreliable at 24
	#elif defined(ARDUINO_ARCH_ESP32) || defined(GNUBLOCKS)
		#define USE_CODE_FILE true
		#define HALF_SPACE (45 * 1024)
	#elif defined(ARDUINO_ARCH_RP2040)
		#define USE_CODE_FILE RP2040_PHILHOWER
		#define HALF_SPACE (40 * 1024)
	#else
		#define HALF_SPACE (10 * 1024)
	#endif

	#define START (&flash[0])
	static uint8 flash[HALF_SPACE] __attribute__ ((aligned (32))); // simulated Flash memory

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

#ifdef USE_CODE_FILE
	static int suspendFileUpdates = false;	// suspend slow file updates when loading a project/library
#endif

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

	#ifdef RAM_CODE_STORE
		// Use a single persistent memory; HALF_SPACE is the total amount of RAM to use
		// Make starts and ends the same to allow the same code to work for either RAM or Flash
		start0 = start1 = (int *) START;
		end0 = end1 = (int *) (START + HALF_SPACE);
	#endif

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
			outputString("Bad record found during initialization");
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

void outputRecordHeaders() {
	// For debugging. Output all the record headers of the current half-space.

	int recordCount = 0;
	int wordCount = 0;
	int maxID = 0;

	char s[200];
	int *p = recordAfter(NULL);
	while (p) {
		recordCount++;
		wordCount += 2 + *(p + 1);
		int id = (*p >> 8) & 0xFF;
		if (id > maxID) maxID = id;
		sprintf(s, "%d %d %d (%d words)",
			(*p >> 16) & 0xFF, (*p >> 8) & 0xFF, *p & 0xFF, *(p + 1));
		outputString(s);

// xxx debug: dump contents
// int chunkWords = *(p + 1);
// sprintf(s, "\t%x (%d words)", *p, chunkWords);
// outputString(s);
// int *w = p + 2;
// for (int i = 0; i < chunkWords; i++) {
// 	int word = *w;
// 	sprintf(s, "\t\t%d: %d %d %d %d ", i,
// 	(word & 255), ((word >> 8) & 255), ((word >> 16) & 255), ((word >> 24) & 255));
// 	outputString(s);
// 	w++;
// }

		p = recordAfter(p);
	}
	sprintf(s, "%d records, %d words, maxID %d, compaction cycles %d",
		recordCount, wordCount, maxID, cycleCount(current));
	outputString(s);

	int bytesUsed = 4 * (freeStart - ((0 == current) ? start0 : start1));
	sprintf(s, "%d bytes used (%d%%) of %d",
		bytesUsed, (100 * bytesUsed) / HALF_SPACE, HALF_SPACE);
	outputString(s);
}

void eraseCheck() {
	int badCount = 0;
	int *start = (0 == current) ? start1 : start0; // inactive half space
	int *end = (0 == current) ? end1 : end0;
	for (int *p = start; p < end; p++) {
		if (*p != 0xFFFFFFFF) badCount++;
		if (*p != 0xFFFFFFFF) {
			char s[200];
			sprintf(s, "bad %d: %x", (p - start), *p);
			outputString(s);
		}
	}
	reportNum("Non-erased words:", badCount);
}

void dumpHex() {
	int *start = (0 == current) ? start0 : start1;
	int *end = freeStart + 5000;
	for (int *p = start; p <= end; ) {
		char s[200];
		sprintf(s, "%d: %x %x %x %x %x %x %x %x %x %x",
			(p - start), p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9]);
		outputString(s);
		p += 10;
	}
}

static int * compactionStartRecord() {
	// Return a pointer to the first record at which to start compaction or script restoration
	// at startup.

	int *ptr = recordAfter(NULL);
	int *result = ptr; // first record in half-space; default if no 'deleteAll' records found
	while (ptr) {
		int type = (*ptr >> 16) & 0xFF;
		ptr = recordAfter(ptr);
		if (deleteAll == type) result = ptr;
	}
	return result;
}

static int * copyChunk(int *dst, int *src) {
	// Copy the chunk record at src to dst and return the new value of dst.

	int wordCount = *(src + 1) + 2;
	flashWriteData(dst, wordCount, (uint8 *) src);
	return dst + wordCount;
}

static void updateChunkTable() {
	memset(chunks, 0, sizeof(chunks)); // clear chunk table

	int *p = compactionStartRecord();
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

	// update code pointers for tasks
	for (int i = 0; i < MAX_TASKS; i++) {
		if (tasks[i].status) { // task entry is in use
			tasks[i].code = chunks[tasks[i].taskChunkIndex].code;
		}
	}
}

// Flash Compaction

#ifndef RAM_CODE_STORE

static char chunkProcessed[256];
static char varProcessed[256];

static int * copyChunkInfo(int id, int *src, int *dst) {
	// Copy the most recent data about the chunk with the given ID to dst and return
	// the new dst pointer. If the given chunk id has been processed do nothing.

	if (chunkProcessed[id]) return dst;

	int *chunkSrc = 0;

	// scan rest of the records to get the most recent info about this chunk
	while (src) {
		if (id == ((*src >> 8) & 0xFF)) { // id field matches
			int type = (*src >> 16) & 0xFF;
			switch (type) {
			case chunkCode:
				chunkSrc = src;
				break;
			case chunkDeleted:
				chunkSrc = 0;
				break;
			}
		}
		src = recordAfter(src);
	}
	if (chunkSrc) {
		dst = copyChunk(dst, chunkSrc);
	}
	chunkProcessed[id] = true;
	return dst;
}

static int * copyVarInfo(int id, int *src, int *dst) {
	if (varProcessed[id]) return dst;

	// record info from first reference to this variable
	int type = (*src >> 16) & 0xFF;
	int *nameRec = (varName == type) ? src : NULL;

	// scan rest of the records to get the most recent info about this variable
	while (src) {
		int type = (*src >> 16) & 0xFF;
		switch (type) {
		case varName:
			if (id == ((*src >> 8) & 0xFF)) nameRec = src;
			break;
		case varsClearAll:
			nameRec = NULL;
			break;
		}
		src = recordAfter(src);
	}
	if (nameRec) dst = copyChunk(dst, nameRec);
	varProcessed[id] = true;
	return dst;
}

static void compactFlash() {
	// Copy only the most recent chunk and variable records to the other half-space.
	// Details:
	//	1. erase the other half-space
	//	2. clear the chunk and variable processed flags
	//	3. find the start point for the scan (half space start or after latest 'deleteAll' record)
	//	4. for each chunk and variable record in the current half-space
	//		a. if the chunk or variable has been processed, skip it
	//		b. gather the most recent information about that chunk or variable
	//		c. copy that information into the other half-space
	//		d. mark the chunk or variable as processed
	//	5. switch to the other half-space
	//	6. remember the free pointer for the new half-space

	uint32_t startT = millisecs();

	// clear the processed flags
	memset(chunkProcessed, 0, sizeof(chunkProcessed));
	memset(varProcessed, 0, sizeof(varProcessed));

	// clear the destination half-space and init dst pointer
	clearHalfSpace(!current);
	int *dst = ((0 == !current) ? start0 : start1) + 1;

	int *src = compactionStartRecord(NULL);
	while (src) {
		int header = *src;
		int type = (header >> 16) & 0xFF;
		int id = (header >> 8) & 0xFF;
		if ((chunkCode <= type) && (type <= chunkDeleted)) {
			dst = copyChunkInfo(id, src, dst);
		} else if ((varName <= type) && (type <= varsClearAll)) {
			dst = copyVarInfo(id, src, dst);
		}
		src = recordAfter(src);
	}

	// increment the cycle counter and switch to the other half-space
	setCycleCount(!current, cycleCount(current) + 1); // this commits the compaction
	current = !current;
	freeStart = dst;

	updateChunkTable();

	#if defined(NRF51) || defined(ARDUINO_BBC_MICROBIT_V2)
		// Compaction messes up the serial port on the micro:bit v1 and v2 and Calliope
		restartSerial();
	#endif

	char s[100];
	int bytesUsed = 4 * (freeStart - ((0 == current) ? start0 : start1));
	sprintf(s, "Compacted Flash code store (%lu msecs)\n%d bytes used (%d%%) of %d",
		millisecs() - startT,
		bytesUsed, (100 * bytesUsed) / HALF_SPACE, HALF_SPACE);
	outputString(s);
}

#endif // compactFlash

// RAM compaction

#ifdef RAM_CODE_STORE

static int keepCodeChunk(int id, int header, int *start) {
	// Return true if this code chunk should be kept when compacting RAM.

	if (unusedChunk == chunks[id].chunkType) return false; // code chunk was deleted

	int *rec = start;
	while (rec) {
		if (*rec == header) return false; // superceded
		rec = recordAfter(rec);
	}
	return true;
}

static void compactRAM(int printStats) {
	// Compact a RAM-based code store in place. In-place compaction is possible in RAM since,
	// unlike Flash memory, RAM can be re-written without first erasing it. This approach
	// allows twice as much space for code as the half-space design.
	//
	// In-place compaction differs from half-space compaction because the destination of the
	// copying operations cannot overlap with the unprocessed portion of the code store. This
	// constraint is ensured by maintaining record order and "sliding down" all the surviving
	// records to so that all unused space is left at the end of the code store. where it is
	// available for storing new records.
	//
	// Details:
	//	1. find the start point for the scan (half space start or after latest 'deleteAll' record)
	//	2. find the most recent "varsClearAll" record
	//	3. for each chunk and variable record in the current half-space
	//		a. deterimine if the record should be kept or skipped
	//		b. if kept, copy the record down to the destination pointer
	//	4. update the free pointer
	//	5. clear the rest of the code store
	//	6. update the compaction count
	//	7. re-write the code file

	uint32_t startT = millisecs();

	int *dst = ((0 == !current) ? start0 : start1) + 1;
	int *src = compactionStartRecord();

	if (!src) return; // nothing to compact

	// find the most recent varsClearAll record
	int *varsStart = src;
	int *rec = src;
	while (rec) {
		if (varsClearAll == ((*rec >> 16) & 0xFF)) varsStart = rec;
		rec = recordAfter(rec);
	}

	while (src) {
		int *next = recordAfter(src);
		int header = *src;
		int type = (header >> 16) & 0xFF;
		int id = (header >> 8) & 0xFF;
		if ((type == chunkCode) && keepCodeChunk(id, header, next)) {
			dst = copyChunk(dst, src);
		} else if ((varName == type) && (src >= varsStart)) {
			dst = copyChunk(dst, src);
		} else {
		}
		src = next;
	}

	freeStart = dst;
	memset(freeStart, 0, (4 * (end0 - freeStart))); // clear everything following freeStart

	updateChunkTable();

	// re-write the code file
	#if USE_CODE_FILE
		setCycleCount(current, cycleCount(current) + 1);
		clearCodeFile(cycleCount(current));
		int *codeStart = ((0 == current) ? start0 : start1) + 1; // skip half-space header
		writeCodeFile((uint8 *) codeStart, 4 * (freeStart - codeStart));
	#endif

	if (printStats) {
		char s[100];
		int bytesUsed = 4 * (freeStart - ((0 == current) ? start0 : start1));

		sprintf(s, "Compacted RAM code store (%lu msecs)\n%d bytes used (%d%%) of %d",
			millisecs() - startT,
			bytesUsed, (100 * bytesUsed) / HALF_SPACE, HALF_SPACE);
		outputString(s);
	}
}
#endif

#ifdef EMSCRIPTEN
int *ramStart() { return start0; }
int ramSize() { return 4 * (freeStart - start0); }
#endif


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
		compactCodeStore();
		end = (0 == current) ? end0 : end1;
		if ((freeStart + 2 + wordCount) > end) {
			outputString("Not enough room even after compaction");
			return NULL;
		}
	}
	// write the record
	int header = ('R' << 24) | ((recordType & 0xFF) << 16) | ((id & 0xFF) << 8) | (extra & 0xFF);

// xxx debug: dump contents
// char s[500];
// sprintf(s, "Appending type %d id %d (%d words)", recordType, id, wordCount);
// outputString(s);
// char *p = data;
// for (int i = 0; i < wordCount; i++) {
// 	sprintf(s, "\t%d: %d %d %d %d ", i, *p, *(p + 1), *(p + 2), *(p + 3));
// 	outputString(s);
// 	p += 4;
// }

	#if USE_CODE_FILE
		if (!suspendFileUpdates) {
			writeCodeFileWord(header);
			writeCodeFileWord(wordCount);
			writeCodeFile(data, 4 * wordCount);
		}
	#endif

	int *result = freeStart;
	flashWriteWord(freeStart++, header);
	flashWriteWord(freeStart++, wordCount);
	if (wordCount) flashWriteData(freeStart, wordCount, data);
	freeStart += wordCount;
	return result;
}

void compactCodeStore() {
	#ifdef RAM_CODE_STORE
		compactRAM(true);
	#else
		compactFlash();
	#endif
}

void restoreScripts() {
	initPersistentMemory();

	#if USE_CODE_FILE
		int codeFileBytes = initCodeFile(flash, HALF_SPACE);
		int *start = current ? start1 : start0;
		freeStart = start + (codeFileBytes / 4);
	#endif

	updateChunkTable();

	// Give feedback:
	int chunkCount = 0;
	for (int i = 0; i < MAX_CHUNKS; i++) {
		if (chunks[i].code) chunkCount++;
	}
	char s[100];
	sprintf(s, "Restored %d scripts", chunkCount);
	outputString(s);
	outputString("Started");
}

int *scanStart() {
	// Return a pointer to the first record at which to start scanning the current code.

	int *ptr = recordAfter(NULL);
	int *result = ptr; // default if no 'deleteAll' records found
	while (ptr) {
		int type = (*ptr >> 16) & 0xFF;
		ptr = recordAfter(ptr);
		if (deleteAll == type) result = ptr;
	}
	return result;
}

void suspendCodeFileUpdates() {
	#ifdef USE_CODE_FILE
		suspendFileUpdates = true;
	#endif
}

void resumeCodeFileUpdates() {
	#ifdef USE_CODE_FILE
		if (suspendFileUpdates) {
			compactRAM(false); // also updates code file
		}
		suspendFileUpdates = false;
	#endif
}

// testing

static void dumpWords(int halfSpace, int count) {
	// Dump the first count words of the given half-space.

	char s[100];
	int *p = (current == 0) ? start0 : start1;
	for (int i = 0; i < count; i++) {
		sprintf(s, "%d %d %d %d",
			(*p >> 24) & 0xFF,
			(*p >> 16) & 0xFF,
			(*p >> 8) & 0xFF,
			*p & 0xFF);
		outputString(s);
		p++;
	}
}

static void showRecordHeaders() {
	// Dump the record headers of the current half-space.

	char s[100];
	int *p = recordAfter(NULL);
	while (p) {
		sprintf(s, "Record at offset %d: %d %d %d %d (%d words)",
			(p - start0),
			(*p >> 24) & 0xFF, (*p >> 16) & 0xFF, (*p >> 8) & 0xFF, *p & 0xFF, *(p + 1));
		outputString(s);
		p = recordAfter(p);
	}
}

void basicTest() {
	int testData[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
	uint8 charData[] = {
		0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0,
		5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 8, 0, 0, 0, 9, 0, 0, 0};

	#define PAGE ((int *) START)

	flashErase(PAGE, PAGE + 100);
	dumpWords(0, 35);
	outputString("-----");
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
	int dummyData[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};

	outputString("Persistent Memory Test\n");
	basicTest();

	outputString("\nInitializing Memory");
	initPersistentMemory();
	initPersistentMemory();
	clearPersistentMemory();
	outputString("Memory intitialized; writing records...");

	for (int i = 0; i < 3000; i++) {
		appendPersistentRecord(chunkCode, i % 100, 0, (i % 5) * 4, (uint8 *) dummyData);
	}
	compactCodeStore();

	dumpWords(current, 150);
	showRecordHeaders();

	char s[100];
	sprintf(s, "Final: current %d used %d c0 %d c1 %d",
		current,
		freeStart - ((0 == current) ? start0 : start1),
		cycleCount(0), cycleCount(1));
	outputString(s);
}
