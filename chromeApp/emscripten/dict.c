// dict.c - Dictionary operations for the virtual machine
// John Maloney, February 2014

#include <stdio.h>
#include <string.h>
#include "mem.h"
#include "dict.h"
#include "interp.h"

// ***** Helper Functions *****

static inline int scanForKeyOrNil(OBJ keys, OBJ k) {
	int keysSize = objWords(keys);
	int i = obj2int(primHash(1, &k)) % keysSize;
	int end = (i == 0) ? keysSize : i - 1;
	char *keyString = IS_CLASS(k, StringClass) ? obj2str(k) : NULL;
	while (true) {
		OBJ thisKey = FIELD(keys, i);
		if (!thisKey || (thisKey == k)) return i; // found nil or a key identical to k
		if (keyString && IS_CLASS(thisKey, StringClass)) {
			if (strcmp(keyString, obj2str(thisKey)) == 0) return i; // found an equal string key
		}
		if (i == end) return -1; // should never happen since dict grows before 100% full
		i = (i + 1) % keysSize;
	}
	return -1; // never gets here
}

static void grow(OBJ dict) {
	OBJ oldKeys = FIELD(dict, 1);
	OBJ oldValues = FIELD(dict, 2);
	int oldSize = WORDS(oldKeys);
	FIELD(dict, 0) = int2obj(0);
	FIELD(dict, 1) = newArray(2 * oldSize);
	FIELD(dict, 2) = newArray(2 * oldSize);
	for (int i = 0; i < oldSize; i++) {
		OBJ k = FIELD(oldKeys, i);
		if (k) dictAtPut(dict, k, FIELD(oldValues, i));
	}
}

// ***** Entry Points *****

OBJ newDict(int capacity) {
	if (capacity < 4) capacity = 4;
	OBJ dict = newObj(DictionaryClass, 3, nilObj);
	FIELD(dict, 0) = int2obj(0);
	FIELD(dict, 1) = newArray(capacity);
	FIELD(dict, 2) = newArray(capacity);
	return dict;
}

int dictCount(OBJ dict) {
	if (NOT_CLASS(dict, DictionaryClass)) return 0;
	return obj2int(FIELD(dict, 0));
}

OBJ dictAt(OBJ dict, OBJ k) {
	if (NOT_CLASS(dict, DictionaryClass)) return nilObj;
	OBJ keys = FIELD(dict, 1);
	OBJ values = FIELD(dict, 2);
	int i = scanForKeyOrNil(keys, k);
	if (i < 0) return nilObj;
	return FIELD(values, i);
}

OBJ dictAtPut(OBJ dict, OBJ k, OBJ newValue) {
	if (NOT_CLASS(dict, DictionaryClass)) return nilObj;
	OBJ keys = FIELD(dict, 1);
	OBJ values = FIELD(dict, 2);
	int i = scanForKeyOrNil(keys, k);
	if (i < 0) return nilObj;
	FIELD(values, i) = newValue;
	if (FIELD(keys, i) == nilObj) { // adding a new key
		FIELD(keys, i) = k;
		int n = obj2int(FIELD(dict, 0)) + 1;
		FIELD(dict, 0) = int2obj(n);
		if ((3 * WORDS(keys)) < (4 * n)) grow(dict);
	}
	return newValue;
}

gp_boolean dictHasKey(OBJ dict, OBJ k) {
	if (NOT_CLASS(dict, DictionaryClass)) return false;
	OBJ keys = FIELD(dict, 1);
	int i = scanForKeyOrNil(keys, k);
	return (FIELD(keys, i) != nilObj);
}
