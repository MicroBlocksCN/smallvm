/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// filePrims.c - File system primitives for Linux boards.
// John Maloney, April 2020

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

// TBD. These are just stubs for now.

static OBJ primOpen(int argCount, OBJ *args) { return falseObj; }
static OBJ primClose(int argCount, OBJ *args) { return falseObj; }
static OBJ primDelete(int argCount, OBJ *args) { return falseObj; }

static OBJ primEndOfFile(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primReadBytes(int argCount, OBJ *args) { return falseObj; }

static OBJ primAppendLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primAppendBytes(int argCount, OBJ *args) { return falseObj; }

static OBJ primStartFileList(int argCount, OBJ *args) { return falseObj; }
static OBJ primNextFileInList(int argCount, OBJ *args) { return falseObj; }

static OBJ primSystemInfo(int argCount, OBJ *args) { return falseObj; }

// Primitives

static PrimEntry entries[] = {
	{"open", primOpen},
	{"close", primClose},
	{"delete", primDelete},

	{"endOfFile", primEndOfFile},
	{"readLine", primReadLine},
	{"readBytes", primReadBytes},

	{"appendLine", primAppendLine},
	{"appendBytes", primAppendBytes},

	{"startList", primStartFileList},
	{"nextInList", primNextFileInList},

	{"systemInfo", primSystemInfo},
};

void addFilePrims() {
	addPrimitiveSet("file", sizeof(entries) / sizeof(PrimEntry), entries);
}
