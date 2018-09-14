/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018

#include <stdio.h>
#include <string.h>
#include "mem.h"

#if defined(ESP8266)
  #include <ESP8266WiFi.h>
#elif defined(ARDUINO_ARCH_ESP32)
  #include <WiFi.h>
#endif

#include "interp.h" // must be included *after* ESP8266WiFi.h

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)

// Buffer for HTTP requests
#define REQUEST_SIZE 1024
static char request[REQUEST_SIZE];

#define JSON_HEADER "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"

// Primitives to build a Thing description (interim, until we have string concatenation)

// Hack: Simulate a MicroBlocks object with a C struct. Since this is not a
// dynamically allocated object, it could confuse the garbage collector. But
// we'll replace this interim mechanism once we do have a garbage collector.

#define DESCRIPTION_SIZE 2048

struct {
	uint32 header;
	char body[DESCRIPTION_SIZE];
} descriptionObj;

static char connecting = false;
static uint32 initTime;

WiFiServer server(80);
WiFiClient client;

void primWifiConnect(OBJ *args) {
  // don't cancel ongoing connection attempts
  if (!connecting) {
    connecting = true;
    initTime = millisecs();
    char *essid = obj2str(args[0]);
    char *psk = obj2str(args[1]);
    // Kill active connection, if there was one
    WiFi.persistent(false);
    WiFi.mode(WIFI_OFF);
    WiFi.mode(WIFI_STA);
    WiFi.begin(essid, psk);
  }
}

void initWebServer() {
  server.stop();
  server.begin();
}

void notFoundResponse() {
  client.print(
    "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n\r\n"
    "{\"error\":\"Resource not found\"}"
  );
  client.flush();
}

void webServerLoop() {
  if (!client) client = server.available(); // attempt to accept a client connection
  if (!client) return;

  // read HTTP request
  int bytesAvailable = client.available();
  if (!bytesAvailable) return;
  client.readBytes(request, bytesAvailable);
  request[bytesAvailable] = 0; // null terminate

  char url[100];
  char body[100];
  char property[100];
  char value[100];
  // request looks like "[GET/PUT] /some/url HTTP/1.1"
  // We first find out whether this is a PUT request
  bool isPutRequest = strstr(request, "PUT");
  if (isPutRequest) {
    strcpy(body, strrchr(request, '{'));
    strcpy(property, strtok(body, "{\":}"));
    strcpy(value, strtok(NULL, "{\":}"));
  }

  // The URL lives between the two only spaces in the first line of the request
  strcpy(url, strtok(strchr(request, ' '), " "));

  // We tokenize the URL and walk the tree
  char *part = strtok(url, "/");
  if (part && strcmp(part, "properties") == 0) {
    // We're at /properties
    // next token contains the property name
    int varID = -1;
    char* varName = strtok(NULL, "/");
    if (varName) varID = indexOfVarNamed(varName);
    if (varID < 0) {
      notFoundResponse();
    } else {
      OBJ variable = vars[varID];
      char s[100];
      switch (objClass(variable)) {
        case StringClass:
          if (isPutRequest) {
            vars[varID] = newStringFromBytes((uint8*) value, strlen(value));
          } else {
            sprintf(s, "%s {\"%s\": \"%s\"}", JSON_HEADER, varName, obj2str(variable));
          }
          break;
        case IntegerClass:
          if (isPutRequest) {
            vars[varID] = int2obj(atoi(value));
          } else {
            sprintf(s, "%s {\"%s\": %i}", JSON_HEADER, varName, obj2int(variable));
          }
          break;
        case BooleanClass:
          if (isPutRequest) {
            vars[varID] = (strcmp(value, "true") == 0) ? trueObj : falseObj;
          } else {
            sprintf(s, "%s {\"%s\": %s}", JSON_HEADER, varName, (trueObj == variable ? "true" : "false"));
          }
          break;
        default:
          if (isPutRequest) {
            sprintf(s, "%s {\"%s\": \"unknown variable type\"}", JSON_HEADER, varName);
          }
          break;
      }
      client.print(s);
      client.flush();
    }
  } else {
    // Respond with the Thing description
    client.print(JSON_HEADER);
    client.print(descriptionObj.body);
    client.flush();
  }

  client.flush();
  client.stop();
}

int wifiStatus() {
  //  WL_IDLE_STATUS      = 0
  //  WL_CONNECTED        = 3
  //  WL_CONNECT_FAILED   = 4
  //  WL_CONNECTION_LOST  = 5
  //  WL_DISCONNECTED     = 6
  int status = WiFi.status();
  if (status == 3 && WiFi.localIP()[0] != 0 && millisecs() > initTime + 250) {
    // Got an IP. We're online. We wait at least a quarter second, otherwise
    // we may have read an old state
    connecting = false;
    initWebServer();
  } else if (status != 3 && millisecs() > initTime + 10000) {
    // We time out after 10s
    WiFi.disconnect();
    status = WL_DISCONNECTED;
    connecting = false;
    fail(noNetwork);
  } else {
    // Still waiting
    status = WL_IDLE_STATUS;
  }
  return status;
}

OBJ primGetIP() {
  IPAddress ip = WiFi.localIP();
  char ipString[17];
  sprintf(ipString, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
  return newStringFromBytes((uint8*) ipString, strlen(ipString));
}

OBJ primMakeWebThing(int argCount, OBJ *args) {
  char* thingName = obj2str(args[0]);
  int bytesWritten = sprintf(
    descriptionObj.body,
    "{\"name\":\"%s\","
    "\"@type\":\"MicroBlocks\","
    "\"description\":\"%s\","
    "\"href\":\"/\","
    "\"properties\":{",
    thingName,
    thingName
  );
  for (int i = 1; i < argCount; i += 3) {
    char* propertyType = obj2str(args[i]);
    char* propertyLabel = obj2str(args[i+1]);
    char* propertyVar = obj2str(args[i+2]);
    bytesWritten += sprintf(
      descriptionObj.body + bytesWritten,
      "\"%s\":"
        "{\"type\":\"%s\","
         "\"label\":\"%s\","
         "\"href\":\"/properties/%s\""
        "},",
      propertyVar,
      propertyType,
      propertyLabel,
      propertyVar
    );
  }
  if (argCount > 2) {
    // we subtract one position to overwrite the last comma
    bytesWritten --;
  }
  sprintf(descriptionObj.body + bytesWritten, "}}\0");
}

OBJ primThingDescription() {
	int wordCount = (strlen(descriptionObj.body) + 4) / 4;
	descriptionObj.header = HEADER(StringClass, wordCount);
	return (OBJ) &descriptionObj;
}

void primClearThingDescription() {
	descriptionObj.body[0] = 0;
}

static void appendObjToDescription(OBJ obj) {
	// Append a printed representation of the given object to the descriptionObj.body.
	// Do nothing if obj is not a string, integer, or boolean.

	int currentSize = strlen(descriptionObj.body);
	char *dst = &descriptionObj.body[currentSize];
	int n = (DESCRIPTION_SIZE - currentSize) - 1;

	if (objClass(obj) == StringClass) snprintf(dst, n, "%s", obj2str(obj));
	else if (isInt(obj)) snprintf(dst, n, "%d", obj2int(obj));
	else if (obj == trueObj) snprintf(dst, n, "true");
	else if (obj == falseObj) snprintf(dst, n, "false");
}

void primAppendToThingDescription(int argCount, OBJ *args) {
	for (int i = 0; i < argCount; i++) {
		appendObjToDescription(args[i]);
	}
	int currentSize = strlen(descriptionObj.body);
	if (currentSize < (DESCRIPTION_SIZE - 1)) {
		// add a newline, if there is room
		descriptionObj.body[currentSize] = '\n';
		descriptionObj.body[currentSize + 1] = 0;
	}
}

#else // not ESP8266 or ESP32

int wifiStatus() { return 4; } // WL_CONNECT_FAILED = 4

void primWifiConnect(OBJ *args) { fail(noNetwork); }
OBJ primGetIP() { return fail(noNetwork); }
OBJ primMakeWebThing(int argCount, OBJ *args) { return fail(noNetwork); }

OBJ primThingDescription() { return fail(noNetwork); }
void primClearThingDescription() { fail(noNetwork); }
void primAppendToThingDescription(int argCount, OBJ *args) { fail(noNetwork); }

#endif
