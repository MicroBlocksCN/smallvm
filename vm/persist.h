// persist.h - Persistent memory
// John Maloney, December 2017

#ifdef __cplusplus
extern "C" {
#endif

// Persistent Memory Records

// Records in persistent memory start with two header words. They have the form:
//	<'R'><record type><id of chunk/variable/comment><type> (8-bits for each field)
//	word count (32-bits)
//	... word count data words ...
//
// Not all record types use all the header fields.

#define PERSISTENT_HEADER_WORDS 2

typedef enum {
	chunkCode = 10,
	chunkPosition = 11,
	chunkSource = 12,
	chunkDeleted = 19,

	varValue = 20,
	varName = 21,
	varDeleted = 29,

	comment = 30,
	commentPosition = 31,
	commentDeleted = 39,
} RecordType_t;

// Persistent Memory Operations

int * appendPersistentRecord(int recordType, int id, int extra, int byteCount, char *data);
void clearPersistentMemory();
void restoreScripts();

#ifdef __cplusplus
}
#endif
