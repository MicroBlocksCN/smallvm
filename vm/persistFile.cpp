/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.cpp - Persistent file memory for code and variables
// Bernat Romagosa

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FS.h"

#include "mem.h"
#include "interp.h"
#include "persist.h"

File codeFile;

extern "C" {
    void initCodeFile(uint8 *flash) {
        outputString("initializing code file");
        SPIFFS.begin();
        codeFile = SPIFFS.open("ublockscode", "a+");
        // dump code file straight into memory
        char s[100];
        codeFile.seek(0, SeekSet);
        long int bytesRead = codeFile.readBytes((char*)flash, codeFile.size());
        sprintf(s, "flash address is %d", flash);
        outputString(s);
        sprintf(s, "wrote %d bytes into memory\n", bytesRead);
        outputString(s);
        codeFile.seek(0, SeekEnd);
    }

    void writeCodeFile(uint8 *code, int byteCount) {
        codeFile.write(code, byteCount);
        outputString("writing code");
        char s[100];
        sprintf(s, "wrote %d bytes into code file\nnew size is %d\n", byteCount, codeFile.position());
        outputString(s);
    }

    void clearCodeFile(){
        outputString("clearing code file");
        codeFile.close();
        SPIFFS.remove("ublockscode");
        codeFile = SPIFFS.open("ublockscode", "a+");
        uint32 cycleCount = ('S' << 24) | 1;
        codeFile.write((uint8*)&cycleCount, 4);
        codeFile.close();
        codeFile = SPIFFS.open("ublockscode", "a+");
        clearPersistentMemory();
    }
}
