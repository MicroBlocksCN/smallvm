/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018

#include "mem.h"

#ifdef ESP8266

#include <ESP8266WiFi.h>
#include "interp.h" // must be included *after* ESP8266WiFi.h

// Buffer for Mozilla Web of Things JSON definition
#define WEBTHING_BUF_SIZE 1024
static char webThingBuffer[WEBTHING_BUF_SIZE];

static char connecting = false;
static uint32 initTime;

WiFiServer server(80);

void primWifiConnect(OBJ *args) {
  // don't cancel ongoing connection attempts
  if (!connecting) {
    WiFi.disconnect();
    connecting = true;
    initTime = millisecs();
    WiFi.mode(WIFI_STA);
    char *essid = obj2str(args[0]);
    char *psk = obj2str(args[1]);
    WiFi.begin(essid, psk);
  }
}

void initWebServer() {
  server.stop();
  server.begin();
}

void webServerLoop() {
  WiFiClient client = server.available();
  if (!client) {
    return;
  }
  while (!client.available()) {
    delay(1);
  }
  String req = client.readStringUntil('\r');
  client.flush();
  if (req.indexOf("/things/ub") != -1) {
    client.flush();
    client.print(webThingBuffer);
  } else {
    client.stop();
  }
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

OBJ primGetIP(OBJ *args) {
  IPAddress ip = WiFi.localIP();
  char ipString[16];
  sprintf(ipString, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
  return newStringFromBytes((uint8*) ipString, 16);
}

OBJ primMakeWebThing(int argCount, OBJ *args) {
  char* thingType = obj2str(args[0]);
  char* thingName = obj2str(args[1]);
  int bytesWritten = sprintf(
    webThingBuffer,
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
    "{\"name\":\"%s\","
    "\"href\":\"/things/ub\","
    "\"@type\":[\"%s\"],"
    "\"properties\":{",
    thingName,
    thingType
  );
  for (int i = 2; i < argCount; i += 4) {
    char* propertyType = obj2str(args[i]);
    char* propertyThingType = obj2str(args[i+1]);
    char* propertyLabel = obj2str(args[i+2]);
    char* propertyVar = obj2str(args[i+3]);
    bytesWritten += sprintf(
      webThingBuffer + bytesWritten,
      "\"%s\":"
        "{\"type\":\"%s\","
         "\"@type\":\"%s\","
         "\"label\":\"%s\","
         "\"href\":\"/things/ub/properties/%s\""
        "},",
      propertyVar,
      propertyType,
      propertyThingType,
      propertyLabel,
      propertyVar
    );
  }
  if (argCount > 2) {
    // we subtract one position to overwrite the last comma
    bytesWritten --;
  }
  sprintf(webThingBuffer + bytesWritten, "}}\0");
  outputString(webThingBuffer);
}

#else

#include "interp.h"

void primWifiConnect(OBJ *args) {
  fail(noNetwork);
}

int wifiStatus() {
  return 4; // WL_CONNECT_FAILED = 4
}

OBJ primGetIP(OBJ *args) {
  fail(noNetwork);
  return int2obj(0);
}

OBJ primMakeWebThing(int argCount, OBJ *args) {
  fail(noNetwork);
}

#endif
