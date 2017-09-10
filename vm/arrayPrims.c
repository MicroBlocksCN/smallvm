// arrayPrims.cpp - Microblocks arrau primitives
// John Maloney, September 2017

#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

// Error Reporting

OBJ sizeFailure() { return failure(needsNonNegativeError, "Size must be a positive integer"); }
OBJ byteValueFailure() { return failure(needs0to255IntError, "A ByteArray can only store integer values between 0 and 255"); }
OBJ indexClassFailure() { return failure(needsIntegerError, "Index must be an integer"); }
OBJ arrayClassFailure() { return failure(needsArrayError, "Must must be an Array or ByteArray"); }
OBJ outOfRangeFailure() { return failure(indexOutOfRangeError, "Index out of range"); }
OBJ nonStringFailure() { return failure(needsStringError, "Must be a string"); }
OBJ intOutOfRangeFailure() { return failure(intOutOfRangeError, "Integer result out of range -536870912 to 536870911"); }

// Platform Agnostic Primitives

OBJ primNewArray(OBJ *args) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return sizeFailure();
	OBJ result = newObj(ArrayClass, obj2int(n), int2obj(0)); // filled with zero integers
	return result;
}

OBJ primNewByteArray(OBJ *args) {
	OBJ n = args[0];
	if (!isInt(n) || ((int) n < 0)) return sizeFailure();
	OBJ result = newObj(ByteArrayClass, (obj2int(n) + 3) / 4, nilObj); // filled with zero bytes
	return result;
}

OBJ primArrayFill(OBJ *args) {
	OBJ array = args[0];
	if (!(IS_CLASS(array, ArrayClass) || IS_CLASS(array, ByteArrayClass))) return arrayClassFailure();
	OBJ value = args[1];

	if (IS_CLASS(array, ArrayClass)) {
		int end = objWords(array) + HEADER_WORDS;
		for (int i = HEADER_WORDS; i < end; i++) ((OBJ *) array)[i] = value;
	} else {
		if (!isInt(value)) return byteValueFailure();
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return byteValueFailure();
		uint8 *dst = (uint8 *) &FIELD(array, 0);
		uint8 *end = dst + (4 * objWords(array));
		while (dst < end) *dst++ = byteValue;
	}
	return nilObj;
}

OBJ primArrayAt(OBJ *args) {
	OBJ array = args[0];
	if (!isInt(args[1])) return indexClassFailure();
	int i = obj2int(args[1]);

	if (IS_CLASS(array, ArrayClass)) {
		if ((i < 1) || (i > objWords(array))) return outOfRangeFailure();
		return FIELD(array, (i - 1));
	} else if (IS_CLASS(array, ByteArrayClass)) {
		if ((i < 1) || (i > (objWords(array) * 4))) return outOfRangeFailure();
		uint8 *bytes = (uint8 *) &FIELD(array, 0);
		return int2obj(bytes[i - 1]);
	} else return arrayClassFailure();
	return nilObj;
}

OBJ primArrayAtPut(OBJ *args) {
	OBJ array = args[0];
	if (!isInt(args[1])) return indexClassFailure();
	int i = obj2int(args[1]);
	OBJ value = args[2];

	if (IS_CLASS(array, ArrayClass)) {
		if ((i < 1) || (i > objWords(array))) return outOfRangeFailure();
		FIELD(array, (i - 1)) = value;
	} else if (IS_CLASS(array, ByteArrayClass)) {
		if ((i < 1) || (i > (objWords(array) * 4))) return outOfRangeFailure();
		if (!isInt(value)) return byteValueFailure();
		uint32 byteValue = obj2int(value);
		if (byteValue > 255) return byteValueFailure();
		((uint8 *) &FIELD(array, 0))[i - 1] = byteValue;
	} else return arrayClassFailure();
	return nilObj;
}

OBJ primHexToInt(OBJ *args) {
	OBJ s = args[0];
	if (NOT_CLASS(s, StringClass)) return nonStringFailure();
	long result = strtol(obj2str(s), NULL, 16);
	if ((result < -536870912) || (result > 536870911)) return intOutOfRangeFailure();
	return int2obj(result);
}

OBJ primPeek(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) return indexClassFailure();
	int *addr = (int *) (((obj2int(args[0]) & 0xFFFF) << 16) | (obj2int(args[1]) & 0xFFFF));
	return int2obj(*addr);
}

OBJ primPoke(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1]) || !isInt(args[2])) return indexClassFailure();
	int *addr = (int *) (((obj2int(args[0]) & 0xFFFF) << 16) | (obj2int(args[1]) & 0xFFFF));
	*addr = obj2int(args[2]);
	return nilObj;
}
