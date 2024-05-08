/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2020 John Maloney, Bernat Romagosa, and Jens Mönig

// varPrims.c - Basic introspection primitives for variables
// Bernat Romagosa, March 2020

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

static OBJ primVarExists (int argCount, OBJ *args) {
	return indexOfVarNamed(obj2str(args[0])) > - 1 ? trueObj : falseObj;
}

static OBJ primVarNamed (int argCount, OBJ *args) {
	int index = indexOfVarNamed(obj2str(args[0]));
	if (index > -1) {
		return vars[index];
	}
	return int2obj(0);
}

static OBJ primSetVarNamed (int argCount, OBJ *args) {
	int index = indexOfVarNamed(obj2str(args[0]));
	if (index > -1) {
		vars[index] = args[1];
	}
	return falseObj;
}

OBJ primVarNameForIndex(int argCount, OBJ *args) {
	// Returns the variable name for the given (one-based) index.
	// If a variable with that index is not found, return the highest index.
	// Pass -1 as the index to get the number of global variables.

	int varIndex = ((argCount > 0) && isInt(args[0])) ? obj2int(args[0]) - 1 : -1;

	int maxVarIndex = -1;
	char *varEntry = NULL;
	int *p = scanStart();
	while (p) {
		int recType = (*p >> 16) & 0xFF;
		int id = (*p >> 8) & 0xFF;
		if (recType == varName) {
			if (id > maxVarIndex) maxVarIndex = id;
			if (varIndex == id) varEntry = (char *) (p + 2);
		} else if (recType == varsClearAll) {
			maxVarIndex = -1;
			varEntry = NULL;
		}
		p = recordAfter(p);
	}
	if (varEntry) return newStringFromBytes(varEntry, strlen(varEntry));
	return int2obj(maxVarIndex + 1);
}

// Primitives

static PrimEntry entries[] = {
	{"varExists", primVarExists},
	{"varNamed", primVarNamed},
	{"setVarNamed", primSetVarNamed},
	{"varNameForIndex", primVarNameForIndex},
};

void addVarPrims() {
	addPrimitiveSet(VarPrims, "vars", sizeof(entries) / sizeof(PrimEntry), entries);
}
