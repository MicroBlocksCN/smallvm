/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018

#include "mem.h"
#include "interp.h"

#ifdef ESP8266

#include <ESP8266WiFi.h>

void primWifiConnect(OBJ *args) {
  char s[100];

  char *essid = obj2str(args[0]);
  char *psk = obj2str(args[1]);

  sprintf(s, "Connecting to %s\n", essid);
  outputString(s);

  WiFi.disconnect();
  WiFi.begin(essid, psk);
  for (int retries = 20; retries > 0; retries--) {
    if (WiFi.status() != WL_CONNECTED) {
      sprintf(s, "Will retry %d more times\n", retries);
      outputString(s);
      delay(500);
    }
  }
  if (WiFi.status() != WL_CONNECTED) {
    fail(noNetwork);
    outputString("\nFailed to connect to network.\n");
  } else {
    IPAddress ip = WiFi.localIP();
    sprintf(s, "Connected to %s\nIP is: %d.%d.%d.%d\n", essid, ip[0], ip[1], ip[2], ip[3]);
    outputString(s);
  }
}

OBJ primGetIP(OBJ *args) {
  char ipString[16];
  IPAddress ip;
  if (WiFi.status() == WL_CONNECTED) {
    ip = WiFi.localIP();
    sprintf(ipString, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
    return newStringFromBytes((uint8*) ipString, 16);
  } else {
    fail(noNetwork);
  }
}

#else

void primWifiConnect(OBJ *args) {
  fail(noNetwork);
}

OBJ primGetIP(OBJ *args) {
  fail(noNetwork);
  return int2obj(0);
}

#endif
