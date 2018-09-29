// cache.h - Method and primive caches
// John Maloney, September 2015

extern OBJ methodCache;

void methodCacheAdd(OBJ methodName, OBJ classID, OBJ callingModule, OBJ method);
void methodCacheClear();
void methodCacheClearEntry(OBJ methodName);
OBJ methodCacheLookup(OBJ methodName, OBJ classID, OBJ module);
OBJ methodCacheStats();
