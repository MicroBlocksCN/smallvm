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

char connecting = false;

void primWifiConnect(OBJ *args) {
  // don't cancel ongoing connection attempts
  if (!connecting) {
    connecting = true;
    char s[100];
    char *essid = obj2str(args[0]);
    char *psk = obj2str(args[1]);

    WiFi.disconnect();
    WiFi.begin(essid, psk);
  }
}

int wifiStatus() {
  //  WiFi.status() codes:
  //  WL_CONNECTED        = 3
  //  WL_CONNECT_FAILED   = 4
  //  WL_CONNECTION_LOST  = 5
  //  WL_DISCONNECTED     = 6
  int status = WiFi.status();
  if (status >= 3) connecting = false;
  return status;
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

#endif
