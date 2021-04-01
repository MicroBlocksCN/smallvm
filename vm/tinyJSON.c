/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// tinyJSON.c - A tiny JSON reader for embedded systems
// John Maloney, September 2018

/*
Tiny JSON Reader

Tiny JSON Reader (TJR) is a lightweight JSON reader written in C that allows clients to
extract information from a JSON string. The JSON string is scanned in place, so TJR
doesn't need to build data structures or allocate memory, and the JSON string is not
mutated, so it can be stored in read-only or write-once Flash memory. These features make
TJR ideal for embedded applications that run on microcontrollers with very limited RAM.

The simplest way to use TJR is to use the tjr_atPath() function to extract data from the
JSON structure via a dot-delimited path. For example, if jsonData is:

	{ "points":
	  [
		{ "x": 1, "y": 2 },
		{ "x": 3, "y": 4 }
	  ]
	}

then tjr_atPath(jsonData "points.1.x") would get the "x" property of the second element of
the array in the "points" property of the top-level object. What tjr_atPath() returns is a
pointer to the character "3" in the original JSON string. That pointer can be passed to
tjr_type() to discover that the value is a number, then to tjr_readInteger() to extract
its value. In general JSON numbers can be floating point numbers with optional fractions
and exponents, but since TJR is intended for embedded applications where floating point
numbers are expensive, it currently only supports extracting integer values.

TJR also supports enumeration of object properties and array elements, so one can do a
complete traversal of the entire JSON structure if needed. However, using paths to access
parts of the structure is often sufficient.

Limitations:
	* assumes input is legal JSON
	* each property name component of a path must be under 100 characters long
	* floating point numbers are not supported, only integers
	* the \uHHHH hex escape sequence in strings is not supported; it is passed through verbatim
*/

#include <stdio.h>
#include <string.h>
#include "tinyJSON.h"

// helper functions

static inline int isDigit(char ch) {
	return (('0' <= ch) && (ch <= '9'));
}

static inline char * tjr_skipWhitespace(char *p) {
	while ((*p <= ' ') && (*p != 0)) p++;
	return p;
}

static char * tjr_skip(char *p) {
	// Return a pointer to the token or value after the current one.
	// Skip whitespace both before and after the skipped token or value.

	p = tjr_skipWhitespace(p);
	int ch = *p;
	if ('\0' == ch) return p; // end of JSON string
	p++;
	if ('"' == ch) {
		while (*p) {
			ch = *p++;
			if ('"' == ch) return tjr_skipWhitespace(p); // closing quote
			if (('\\' == ch) && *p) p++; // skip escaped character
		}
	} else if ((':' == ch) || (',' == ch)) {
		return tjr_skipWhitespace(p);
	} else if ('{' == ch) {
		p = tjr_skipWhitespace(p);
		while (*p) {
			if ('}' == *p) return tjr_skipWhitespace(p + 1);
			p = tjr_skip(p);
		}
	} else if ('[' == ch) {
		p = tjr_skipWhitespace(p);
		while (*p) {
			if (']' == *p) return tjr_skipWhitespace(p + 1);
			p = tjr_skip(p);
		}
	} else { // number, true, false, or null
		while (*p) {
			ch = *p;
			if (ch <= ' ') return tjr_skipWhitespace(p);
			if ((',' == ch) || ('}' == ch) || (']' == ch) || ('"' == ch)) return p;
			p++;
		}
	}
	return tjr_skipWhitespace(p);
}

static char * tjr_atPropName(char *p, char *propName, int propNameLen) {
	// Return a pointer to the value of the property with the given name or NULL if not found.

	char s[100];
	if ('{' != *p) return NULL;
	p++; // skip '{'
	while (1) {
		p = tjr_nextProperty(p, s, sizeof(s));
		if (!p) return NULL; // no more properties
		if (0 == strncmp(s, propName, propNameLen)) return p;
		p = tjr_skip(p); // skip value
	}
}

// accessing the JSON structure by path or index

char * tjr_atIndex(char *p, int index) {
	// Return a pointer to the index-th element of the (one-based) array at p.
	// Return NULL if p is not the start of an array or if index is out of range.

	if ((index <= 0) || (*p != '[')) return NULL;
	p = tjr_skipWhitespace(p + 1); // skip '['
	int i = 1;
	while (1) {
		if (i == index) return p;
		p = tjr_nextElement(p);
		if (!p) return NULL; // no more elements
		i++;
	}
}

char * tjr_atPath(char *p, char *pathString) {
	// Return a pointer to the value at the given dot-delimited path or NULL if not found.
	// The path string consists of a sequence of property names and/or array indices
	// separated by dots (periods), such as "shape.points.1.x".

	char *propName = pathString;
	while (*propName) {
		char *nextDot = strchr(propName, '.');
		int propNameLen = nextDot ? (nextDot - propName) : strlen(propName);
		if (isDigit(*propName)) {
			int index = tjr_readInteger(propName);
			p = tjr_atIndex(p, index);
		} else {
			p = tjr_atPropName(p, propName, propNameLen);
		}
		if (!p || !nextDot) return p;
		propName += propNameLen + 1; // advance to start of next path component
	}
	return p;
}

char * tjr_valueAt(char *p, int index) {
	// Return the value at the given (one-based) index in the array or object p.
	// Return NULL p is not an array or object or the index is out of range.

	if (index < 1) return NULL;
	int itemType = tjr_type(p);
	if (tjr_Array == itemType) {
		p++; // skip '['
		for (; index > 1; index--) p = tjr_nextElement(p);
		return p;
	}
	if (tjr_Object == itemType) {
		p++; // skip '{'
		p = tjr_nextProperty(p, NULL, 0);
		for (; index > 1; index--) {
			p = tjr_nextElement(p); // skip value
			p = tjr_nextProperty(p, NULL, 0);
		}
		return p;
	}
	return NULL; // not an object or array
}

char * tjr_keyAt(char *p, int index, char *key, int keySize) {
	// Return set the key the return the value at the given (one-based) index in the object p.
	// Return NULL if p is not an object or if the index is out of range.

	if (index < 1) return NULL;
	if (tjr_Object != tjr_type(p)) return NULL;
	p++; // skip '{'
	p = tjr_nextProperty(p, key, keySize);
	for (; index > 1; index--) {
		p = tjr_nextElement(p); // skip value
		p = tjr_nextProperty(p, key, keySize);
	}
	return p;
}

// types and values

int tjr_type(char *p) {
	// Return the type of the value at p (after any leading whitespace).

	if (!p) return tjr_End; // null pointer

	p = tjr_skipWhitespace(p);
	int ch = *p;
	if ('"' == ch) return tjr_String;
	if ('{' == ch) return tjr_Object;
	if ('[' == ch) return tjr_Array;
	if (isDigit(ch) || (('-' == ch) && isDigit(*(p + 1)))) return tjr_Number;
	if ('t' == ch) return tjr_True;
	if ('f' == ch) return tjr_False;
	if ('n' == ch) return tjr_Null;
	if ('\0' == ch) return tjr_End;
	return tjr_Error;
}

int tjr_readInteger(char *p) {
	// Read the number at p as an integer. If the JSON contains a floating point number,
	// the mantissa is read as an integer and the fraction and exponent are ignored.

	p = tjr_skipWhitespace(p);
	int result = 0;
	int sign = 1;
	if ('-' == *p) { sign = -1; p++; }
	while (isDigit(*p)) {
		result = (10 * result) + (*p++ - '0');
	}
	return sign * result;
}

void tjr_readStringInto(char *p, char *dstString, int dstSize) {
	// Read the string at p into dstString.
	// dstString must be a writeable string with size > 0 (i.e. not NULL).

	p = tjr_skipWhitespace(p);
	if ('"' != *p) { // not a string
		*dstString = '\0';
		return;
	}
	int spaceAvailable = dstSize - 1; // reserve space for null terminator
	p++; // skip opening quote
	while (1) {
		int ch = *p++;
		if (('"' == ch) || ('\0' == ch)) {
			*dstString = '\0';
			return;
		}
		if ('\\' == ch) {
			// Note: the \uHHHH escape is not handled; it is passed through unchanged
			ch = *p++;
			if ('b' == ch) ch = '\b';
			if ('f' == ch) ch = '\f';
			if ('n' == ch) ch = '\n';
			if ('r' == ch) ch = '\r';
			if ('t' == ch) ch = '\t';
		}
		if (spaceAvailable <= 0) {
			*dstString = '\0';
			return;
		}
		*dstString++ = ch;
		spaceAvailable--;
	}
}

char * tjr_endOfItem(char *p) {
	// Return a pointer to the first character following the JSON item pointed to by p.

	char *result = tjr_skip(p);
	while ((result > p) && (*result <= 32) && (*result != 0)) result--; // back up over whitespace, if any
	return result;
}

// enumeration

int tjr_count(char *p) {
	// If p is the start of an object, returh the number of properties it has.
	// If p is the start of an array, returh the number of elements it has.
	// If p is not an object or array, return 0.

	if (!p) return 0; // null pointer

	int count = 0;
	p = tjr_skipWhitespace(p);
	if ('{' == *p) {
		p++; // skip '{'
		while (1) {
			p = tjr_nextProperty(p, NULL, 0);
			if (!p) return count;
			p = tjr_skip(p); // skip value
			count++;
		}
	} else if ('[' == *p) {
		p++;  // skip '['
		while (1) {
			p = tjr_nextElement(p);
			if (!p) return count;
			count++;
		}
	}
	return count;
}

char * tjr_nextElement(char *p) {
	// Skip to the next array or object field. Return NULL when there are no more elements.

	if (!p || !*p) return NULL;
	p = tjr_skipWhitespace(p);
	if ((']' == *p) || ('}' == *p)) return NULL;
	p = tjr_skip(p); // skip current element
	if (',' == *p) p++; // skip comma
	p = tjr_skipWhitespace(p);
	return p;
}

char * tjr_nextProperty(char *p, char *propertyName, int propertyNameSize) {
	// Skip to the next object property value and copy the property name into
	// the optional propertyName string. At most propertyNameSize characters will
	// be written to the propertyName string (including the null terminator).
	// Return NULL when there are no more properties.

	if (propertyName) propertyName[0] = '\0'; // clear property name
	if (!p || !*p) return NULL;
	p = tjr_skipWhitespace(p);
	if (',' == *p) p = tjr_skipWhitespace(p + 1); // skip comma after last value
	if ('}' == *p) return NULL;
	if (propertyName) tjr_readStringInto(p, propertyName, propertyNameSize); // record property name
	p = tjr_skip(p); // skip property name
	if (':' == *p) p = tjr_skipWhitespace(p + 1); // skip colon
	return p;
}
