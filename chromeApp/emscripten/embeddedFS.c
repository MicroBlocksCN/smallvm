// embeddedFS.c
// John Maloney, April, 2016
//
// An embedded file system is implemented by appending a zip file to the application binary.
// This allows the GP library, modules, user projects, and media files to be packaged into a
// single "application" file.
//
// Embedded file system primitives (implemented in prims.c):
// 	- appPath
//  - listEmbeddedFiles
//	- readEmbeddedFile <fileName>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "mem.h"
#include "embeddedFS.h"
#include "interp.h"
#include "oop.h"
#include "parse.h"

#ifdef MAC
#include <libproc.h> // not available on IOS
#elif defined(_WIN32)
#include <windows.h>
#endif

// Constants

#define APP_PATH_SIZE 4096
#define MAX_FILENAME 1024
#define UNINITIALIZED -2
#define NO_EMBEDDED_FS -1

#define DIR_ENTRY_ID 0x02014b50
#define END_ID 0x06054b50
#define FILE_ENTRY_ID 0x04034b50

// Variables

static long dataStart = UNINITIALIZED;

// Utilities

static int readInt16(FILE *f) {
	int byte1 = fgetc(f);
	int byte2 = fgetc(f);
	return (byte2 << 8) | byte1;
}

static int readInt32(FILE *f) {
	int byte1 = fgetc(f);
	int byte2 = fgetc(f);
	int byte3 = fgetc(f);
	int byte4 = fgetc(f);
	return (byte4 << 24) | (byte3 << 16)| (byte2 << 8) | byte1;
}

static void readStringInto(FILE *f, int byteCount, char *s, int maxSize) {
	// Read a string of the given size into s. If byteCount is greater than maxSize,
	// truncate s, but consume byteCount bytes from f.

	maxSize--; // leave room for string terminator
	char *dst = s;
	for (int i = 0; i < byteCount; i++) {
		char ch = fgetc(f);
		if (i < maxSize) *dst++ = ch;
	}
	*dst = 0; // string terminator
}

static void skip(FILE *f, long byteCount) {
	fseek(f, byteCount, SEEK_CUR);
}

static long findDataStart(FILE *f) {
	// Return the start of the embedded file system (a Zip file), if there is one.
	// The start of the embedded file system is marked by the string 'GPFS'
	// followed by a four-byte Zip file entry ID (0x50, 0x4b, 0x03, 0x04).
	// Return NO_EMBEDDED_FS (-1) if this byte sequence is not found.
	// To avoid repeatedly scanning the GP application file, the result
	// of the scan is cached in the variable dataStart.
	// If the file is a raw Zip file (i.e. it starts with 0x50, 0x4b, 0x03, 0x04),
	// then it does not need to be prefixed with the marker string 'GPFS'.

	if (dataStart > UNINITIALIZED) return dataStart;

	#define ADVANCE 10000
	#define BUF_SIZE (ADVANCE + 10)
	char buf[BUF_SIZE];

	// first check for a raw Zip file
	fseek(f, 0, SEEK_SET);
	int bytesRead = fread(buf, 1, 4, f);
	if ((4 == bytesRead) &&
		(0x50 == buf[0]) && (0x4b == buf[1]) && (3 == buf[2]) && (4 == buf[3])) {
			return 0; // the entire Zip file is the embedded file system
	}

	long bufStart = 0;
	while (true) {
		fseek(f, bufStart, SEEK_SET);
		int bytesRead = fread(buf, 1, BUF_SIZE, f);
		char *ptr = buf;
		char *end = buf + bytesRead;
		while (ptr < end) {
			if (('G' == ptr[0]) && ('P' == ptr[1]) && ('F' == ptr[2]) && ('S' == ptr[3]) &&
				(0x50 == ptr[4]) && (0x4b == ptr[5]) && (0x03 == ptr[6]) && (0x04 == ptr[7])) {
					return bufStart + (ptr - buf) + 4;
			}
			ptr++;
		}
		if (bytesRead < BUF_SIZE) break;
		bufStart += ADVANCE;
	}
	return NO_EMBEDDED_FS;
}

static int getAppPath(char *path, int pathSize) {
	// Copy the full path for the application (up to pathSize - 1 bytes) into path.
	// Return true on success.

	path[0] = 0; // null terminate string in case of failure
#if defined(MAC)
	pid_t pid = getpid();
	if (!proc_pidpath(pid, path, pathSize)) return false;
#elif defined(_WIN32)
	#define RESULT_SIZE 1000
	WCHAR wideResult[RESULT_SIZE];
	int len = GetModuleFileNameW(NULL, wideResult, RESULT_SIZE);
	if ((len == 0) || (len >= RESULT_SIZE)) return false; // failed or result did not fit

	// convert result from wide string to utf8
	len = WideCharToMultiByte(CP_UTF8, 0, wideResult, -1, path, pathSize, NULL, NULL);
	if ((len == 0) || (len >= pathSize)) return false; // failed or result did not fit

	// replace backslashes with GP-standard forward slashes
	for (int i = 0; i < len; i++) {
	  int ch = path[i];
	  if ('\\' == ch) path[i] = '/';
	}
	return true;
#elif defined(__linux__) || defined(IOS)
	if (!realpath(argv0, path)) {
		// try using /proc (may not work on all Linux systems)
		int byteCount = readlink("/proc/self/exe", path, pathSize);
		if (byteCount < 0) return false; // readlink failed
		path[byteCount] = 0; // null terminate result
	}
#else
	return false;
#endif

	path[pathSize - 1] = 0; // ensure null termination
	return true;
}

// Zip file operations

static int findZipDirectory(FILE *f, long *dirStartPos) {
	// If an EndOfCentralDirectory record is found, set dirStartPos to the
	// file position of the directory and return the number of entries.
	// If not found, return -1.

	// Scan backwards from the end of the data to the last EndOfCentralDiretory record.
	fseek(f, 0, SEEK_END);
	long pos = ftell(f) - 4;
	while (pos >= 0) {
		fseek(f, pos, SEEK_SET);
		if (80 == fgetc(f)) { // found first byte of possible endID
			fseek(f, pos, SEEK_SET);
			if (END_ID == readInt32(f)) break;
		}
		pos--;
	}
	if (pos < 0) { // EndOfCentralDiretory record not found
		*dirStartPos = -1;
		return 0;
	}
	int thisDiskNum = readInt16(f);
	int startDiskNum = readInt16(f);
	int entriesOnThisDisk = readInt16(f);
	int totalEntries = readInt16(f);
	readInt32(f); // directorySize
	int directoryOffset = readInt32(f);

	if ((thisDiskNum != startDiskNum) || (entriesOnThisDisk != totalEntries)) {
		*dirStartPos = -1;
		return 0;
	}
	*dirStartPos = directoryOffset;
	return totalEntries;
}

static long readDirEntry(FILE *f, char *name, int nameMax) {
	// Read a directory file entry from f. Assume f is positioned at the start of an entry.
	// Store the file name in name (up to nameMax characters) and return the file size.

	if (DIR_ENTRY_ID != readInt32(f)) {  // bad directory entry
		name[0] = 0; // null terminate
		return -1;
	}
	readInt16(f); // versionMadeBy
	readInt16(f); // versionNeeded
	readInt16(f); // flags
	readInt16(f); // compressionMethod
	readInt32(f); // dosTime
	readInt32(f); // crc
	readInt32(f); // compressedSize
	readInt32(f); // uncompressedSize
	int nameLength = readInt16(f);
	int extraLength = readInt16(f);
	int commentLength = readInt16(f);
	readInt16(f); // diskNum
	readInt16(f); // internalAttributes
	readInt32(f); // externalAttributes
	long offset = (unsigned) readInt32(f);
	readStringInto(f, nameLength, name, nameMax);
	skip(f, extraLength + commentLength);
	return offset;
}

static OBJ extractFileData(FILE *f, long fileEntryPos, int isBinary) {
	// Extract the file from the file entry at the given position, decompressing if necessary.
	// Return the file contents or nil if extraction fails.

	fseek(f, fileEntryPos, SEEK_SET);
	if (FILE_ENTRY_ID != readInt32(f)) return nilObj;  // bad local file header
	readInt16(f); // versionNeeded
	int flags = readInt16(f);
	int compressionMethod = readInt16(f);
	readInt32(f); // dosTime
	int crc = readInt32(f);
	unsigned compressedSize = (unsigned) readInt32(f);
	unsigned uncompressedSize = (unsigned) readInt32(f);
	int nameLength = readInt16(f);
	int extraLength = readInt16(f);
	skip(f, nameLength + extraLength);

	if (flags != 0) return nilObj; // unexpected Zip file format
	if (!((0 == compressionMethod) || (8 == compressionMethod))) return nilObj; // unknown compressionMethod
	if (0 == compressedSize) return nilObj; // no data (e.g. a directory entry)

	OBJ result = isBinary ? newBinaryData(compressedSize) : allocateString(compressedSize);
	if (!result) return nilObj;

	int bytesRead = fread(&FIELD(result, 0), 1, compressedSize, f);
	if (bytesRead != compressedSize) return nilObj;

	if (8 == compressionMethod) { // decompress the data
		OBJ compressed = result;
		if (!canAllocate((uncompressedSize + 3) / 4)) return nilObj;
		result = isBinary ? newBinaryData(uncompressedSize) : allocateString(uncompressedSize);
		if (!result) return nilObj;

		z_stream infstream;
		infstream.zalloc = NULL;
		infstream.zfree = NULL;
		infstream.opaque = NULL;
		infstream.avail_in = compressedSize;
		infstream.next_in = (unsigned char *) &FIELD(compressed, 0);
		infstream.avail_out = uncompressedSize;
		infstream.next_out = (unsigned char *) &FIELD(result, 0);

		int rc = inflateInit2(&infstream, -MAX_WBITS);
		if (rc) return nilObj;
		rc = inflate(&infstream, Z_NO_FLUSH);
		if (Z_STREAM_END != rc) return nilObj;
		rc = inflateEnd(&infstream);
		if (rc) return nilObj;
	}

	// check the CRC
	unsigned int computedCRC = crc32(0, NULL, 0); // initial CRC value
	computedCRC = crc32(computedCRC, (unsigned char *) &FIELD(result, 0), uncompressedSize);
	if (computedCRC != crc) return nilObj;

	return result;
}

// Loading Utilities

static void loadGPFile(char *fileName, OBJ fileContents) {
	if (!fileContents) return;

	parser p;
	parse_setSourceString(&p, fileName, obj2str(fileContents), stringBytes(fileContents));
	while (true) {
		OBJ prog = parse_nextScript(&p, false);
		if (IS_CLASS(prog, CmdClass) || IS_CLASS(prog, ReporterClass)) {
			currentModule = consoleModule;
			run(prog);
		}
		if (parse_atEnd(&p)) {
			if (!p.complete) printf("Premature end of file; missing '}'? %s\n", fileName);
			break;
		}
	}
}

static gp_boolean loadLibraryFrom(FILE *f) {
	dataStart = findDataStart(f);
	if (dataStart < 0) return false; // no embedded FS

	long directoryStart;
	int entryCount = findZipDirectory(f, &directoryStart);
	if (entryCount < 0) return false; // no directory

	// load all files in the /lib folder (including .gp and .gpm)
	gp_boolean hasLibrary = false;
	char fileName[MAX_FILENAME];
	if ((entryCount > 0) && (directoryStart > 0)) {
		fseek(f, dataStart + directoryStart, SEEK_SET);
		for (int i = 0; i < entryCount; i++) {
			long offset = readDirEntry(f, fileName, MAX_FILENAME);
			if ((offset != -1) && (strstr(fileName, "lib/") == fileName)) {
				long p = ftell(f);
				OBJ fileContents = extractFileData(f, dataStart + offset, false);
				loadGPFile(fileName, fileContents);
				fseek(f, p, SEEK_SET);
				hasLibrary = true; // has a lib folder
			}
		}
	}
	if (!hasLibrary) return false;

	// load "startup.gp" if it exists
	OBJ startupFile = extractEmbeddedFile(f, "startup.gp", false);
	if (startupFile) loadGPFile("startup.gp", startupFile);
	return true;
}

// Public Functions

OBJ appPath() {
    char path[APP_PATH_SIZE];
	int ok = getAppPath(path, sizeof(path));
	return ok ? newString(path) : nilObj;
}

OBJ embeddedFileList(FILE *f) {
	dataStart = findDataStart(f);
	if (dataStart < 0) return newArray(0); // no embedded FS

	long directoryStart;
	int entryCount = findZipDirectory(f, &directoryStart);
	if (entryCount < 0) return newArray(0); // no directory

	OBJ result = newArray(entryCount);
	char entryFileName[MAX_FILENAME];
	fseek(f, dataStart + directoryStart, SEEK_SET);
	for (int i = 0; i < entryCount; i++) {
		readDirEntry(f, entryFileName, MAX_FILENAME);
		FIELD(result, i) = newString(entryFileName);
	}
	return result;
}

OBJ extractEmbeddedFile(FILE *f, char *fileName, int isBinary) {
	dataStart = findDataStart(f);
	if (dataStart < 0) return nilObj; // no embedded FS

	long directoryStart;
	int entryCount = findZipDirectory(f, &directoryStart);
	if (entryCount < 0) return nilObj; // no directory

	char entryFileName[MAX_FILENAME];
	if ((entryCount > 0) && (directoryStart > 0)) {
		fseek(f, dataStart + directoryStart, SEEK_SET);
		for (int i = 0; i < entryCount; i++) {
			long offset = readDirEntry(f, entryFileName, MAX_FILENAME);
			if ((offset != -1) && (strcmp(fileName, entryFileName) == 0)) {
				return extractFileData(f, dataStart + offset, isBinary);
			}
		}
	}
	return nilObj;
}

gp_boolean importLibrary() {
	int hasEmbeddedLibrary = false;
	FILE *f = openAppFile();
	if (f) {
		hasEmbeddedLibrary = loadLibraryFrom(f);
		fclose(f);
	}
	return hasEmbeddedLibrary;
}

FILE * openAppFile() {
    char path[APP_PATH_SIZE];
	int ok = getAppPath(path, sizeof(path));
	if (!ok) return NULL; // should not happen

	#ifdef MAC
		// If running in a Mac app bundle, file system is in /Contents/Resources/fs.data
		char *macAppPrefix = strstr(path, ".app/Contents/MacOS/");
		if (macAppPrefix) {
			*(macAppPrefix + 14) = 0; // truncate after ".app/Contents/"
			strncat(path, "Resources/fs.data", APP_PATH_SIZE);
		}
		FILE *f = fopen(path, "rb");
		if (f) {
			return f;
		} else {
			getAppPath(path, sizeof(path)); // could not open fs.data; use app itself
		}
	#endif
	return fopen(path, "rb");
}
