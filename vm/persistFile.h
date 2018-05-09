/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.h - Persistent file memory for code and variables
// Bernat Romagosa

#ifdef __cplusplus
extern "C" {
#endif

void initCodeFile(uint8 *flash);
void writeCodeFile(uint8 *code, int byteCount);
void clearCodeFile();

#ifdef __cplusplus
}
#endif
