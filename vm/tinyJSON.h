/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// tinyJSON.h - A tiny JSON reader for embedded systems
// John Maloney, September 2018

#ifdef __cplusplus
extern "C" {
#endif

// JSON Types returned by tjr_type()

enum {
	tjr_Error = -1,
	tjr_End = 0,	// end of JSON string
	tjr_Array = 1,
	tjr_Object = 2,
	tjr_Number = 3,
	tjr_String = 4,
	tjr_True = 5,
	tjr_False = 6,
	tjr_Null = 7
};

// JSON structure access and value extraction by path

char * tjr_atPath(char *p, char *pathString);
char * tjr_valueAt(char *p, int index);
char * tjr_keyAt(char *p, int index, char *key, int keySize);

int tjr_type(char *p);
int tjr_readInteger(char *p);
void tjr_readStringInto(char *p, char *dstString, int dstSize);
char * tjr_endOfItem(char *p);

// Object/Array enumeration

int tjr_count(char *p);
char * tjr_atIndex(char *p, int index);

char * tjr_nextElement(char *p);
char * tjr_nextProperty(char *p, char *propertyName, int propertyNameSize);

#ifdef __cplusplus
}
#endif
