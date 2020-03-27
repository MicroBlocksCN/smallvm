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

OBJ primVarExists (int argCount, OBJ *args) {
	return indexOfVarNamed(obj2str(args[0])) > - 1 ? trueObj : falseObj;
}

OBJ primVarNamed (int argCount, OBJ *args) {
	int index = indexOfVarNamed(obj2str(args[0]));
	if (index > -1) {
		return vars[index];
	}
	return int2obj(0);
}

OBJ primSetVarNamed (int argCount, OBJ *args) {
	int index = indexOfVarNamed(obj2str(args[0]));
	if (index > -1) {
		vars[index] = args[1];
	}
	return falseObj;
}

OBJ primVarNames(int argCount, OBJ *args) {
	/*
	OBJ allVars = newObj(ListType, 1, int2obj(0));
	uint8 *variableName;
	int *p = scanStart();
	while (p) {
		int recType = (*p >> 16) & 0xFF;
		int varID = (*p >> 8) & 0xFF;
		if (recType == varName) {
			// found a var, let's add it to the list
			variableName = (uint8 *) (p + 2);
			int count = obj2int(FIELD(allVars, 0));
			if (count >= (WORDS(allVars) - 1)) { // no more capacity; try to grow
				int growBy = count / 3;
				if (growBy < 4) growBy = 3;
				if (growBy > 100) growBy = 100;
				allVars = resizeObj(allVars, WORDS(allVars) + growBy);
			}
			FIELD(allVars, 0) = int2obj(varID + 1);
			FIELD(allVars, varID + 1) =
				newStringFromBytes(variableName, strlen(variableName));
		}
		p = recordAfter(p);
	}
	return allVars;
	*/
	return newObj(ListType, 1, int2obj(0));
};

// Primitives

static PrimEntry entries[] = {
	{"varExists", primVarExists},
	{"varNames", primVarNames},
	{"varNamed", primVarNamed},
	{"setVarNamed", primSetVarNamed},
};

void addVarPrims() {
	addPrimitiveSet("vars", sizeof(entries) / sizeof(PrimEntry), entries);
}
