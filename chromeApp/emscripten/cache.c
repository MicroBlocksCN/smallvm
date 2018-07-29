// cache.c
// John Maloney, September 2015

#include <stdio.h>
#include "mem.h"
#include "cache.h"
#include "dict.h"

OBJ methodCache = nilObj;

static int methodCacheHits = 0;
static int methodCacheMisses = 0;
static int methodCacheFullClears = 0;
static int methodCacheEntryClears = 0;

void methodCacheClear() {
	methodCache = newDict(1000);
	methodCacheHits = 0;
	methodCacheMisses = 0;
	methodCacheFullClears++;
}

void methodCacheClearEntry(OBJ methodName) {
	OBJ methodMap = dictAt(methodCache, methodName);
	if (methodMap != nilObj) {
		dictAtPut(methodCache, methodName, newArray(0)); // set entry an empty array
	}
	methodCacheEntryClears++;
}

OBJ methodCacheLookup(OBJ methodName, OBJ classID, OBJ module) {
	// Return a method object for the given method and class called from the given module.
	// Return nil if not found in cache.
	OBJ methodMap = dictAt(methodCache, methodName);
	if (methodMap != nilObj) {
		int n = objWords(methodMap);
		for (int i = 0; i < n; i += 3) {
			if ((FIELD(methodMap, i) == classID) && (FIELD(methodMap, i + 1) == module)) {
				methodCacheHits++;
				return FIELD(methodMap, i + 2);
			}
		}
	}
	methodCacheMisses++;
	return nilObj;
}

void methodCacheAdd(OBJ methodName, OBJ classID, OBJ callingModule, OBJ method) {
	// Add a method with the given name and class to the cache.

	OBJ methodMap = dictAt(methodCache, methodName);
	int oldSize = 0;
	if (methodMap == nilObj) {
		methodMap = newArray(3);
	} else {
		oldSize = objWords(methodMap);
		methodMap = copyObj(methodMap, (oldSize + 3), 1);
	}
	FIELD(methodMap, oldSize) = classID;
	FIELD(methodMap, oldSize + 1) = callingModule;
	FIELD(methodMap, oldSize + 2) = method;
	dictAtPut(methodCache, methodName, methodMap);
}

static void printMethodCacheStats() {
	// for testing
	int total = methodCacheHits + methodCacheMisses;
	if (total == 0) {
		printf("Method cache not in use.\n");
		return;
	}
	printf("method cache hits %d out of %d (%d percent)\n", methodCacheHits, total, (100 * methodCacheHits) / total);
	int oneToThreeClassEntries = 0;
	OBJ keys = FIELD(methodCache, 1);
	OBJ values = FIELD(methodCache, 2);
	for (int i = 0; i < objWords(keys); i++) {
		OBJ k = FIELD(keys, i);
		OBJ v = FIELD(values, i);
		if (IS_CLASS(k, StringClass)) {
			int entryCount = objWords(v) / 3;
			if (entryCount < 4) {
				oneToThreeClassEntries++;
			} else {
				printf("  %s %d\n", obj2str(k), entryCount);
			}
		}
	}
	printf("%d selectors\n", dictCount(methodCache));
	printf("%d selectors with only one to three classes\n----------\n", oneToThreeClassEntries);
}

OBJ methodCacheStats() {
	if (false) printMethodCacheStats(); // make true for testing
	OBJ result = newArray(5);
	FIELD(result, 0) = int2obj(dictCount(methodCache));
	FIELD(result, 1) = int2obj(methodCacheHits);
	FIELD(result, 2) = int2obj(methodCacheMisses);
	FIELD(result, 3) = int2obj(methodCacheFullClears);
	FIELD(result, 4) = int2obj(methodCacheEntryClears);
	return result;
}
