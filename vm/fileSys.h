/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// fileSys.c - File system selection.
// John Maloney, December 2021

#include <FS.h>

// always use LittleFS
#include <LittleFS.h>
#define myFS LittleFS

void closeIfOpen(char *fileName);
void closeAndDeleteFile(char *fileName);
