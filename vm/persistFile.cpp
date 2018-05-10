/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// persistFile.cpp - Persistent file memory for code and variables
// Bernat Romagosa

#include <stdio.h>
#include <FS.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

File codeFile;

extern "C" {
    void initCodeFile(uint8 *flash, int flashByteCount) {
        char s[100];
       SPIFFS.begin();

sprintf(s, "initCodeFile flash address is %d, flash bytes: %d", flash, flashByteCount);
outputString(s);

//SPIFFS.format(); // xxx
        codeFile = SPIFFS.open("ublockscode", "a+");

int fileSize = codeFile.size();
sprintf(s, "file size: %d, position: %d", fileSize, codeFile.position());
outputString(s);

		codeFile.seek(0, SeekSet);

sprintf(s, "position after seek: %d", codeFile.position());
outputString(s);

        // read code file straight into memory
//int bytesRead = 0;
        long int bytesRead = codeFile.readBytes((char*) flash, flashByteCount);

        sprintf(s, "read %d bytes into memory (file size %d)\n", bytesRead, fileSize);
        outputString(s);
    }


    void writeCodeFile(uint8 *code, int byteCount) {
char s[100];
outputString("writeCodeFile...");
int oldSize = codeFile.size();

		int bytesWritten = codeFile.write(code, byteCount);
		codeFile.flush();

sprintf(s, "  %d bytes of %d appended to code file; size: %d -> %d\n",
	bytesWritten, byteCount, oldSize, codeFile.size());
outputString(s);
    }

    void clearCodeFile() {
        char s[100];
outputString("clearing code file");
        codeFile.close();
        SPIFFS.remove("ublockscode");
        codeFile = SPIFFS.open("ublockscode", "a+");
        uint32 cycleCount = ('S' << 24) | 1;
        int bytesWritten = codeFile.write((uint8 *) &cycleCount, 4);
		codeFile.flush();

sprintf(s, "   wrote %d header bytes", bytesWritten);
outputString(s);
        clearPersistentMemory();
outputString("clearCodeFile done");
   }
}
