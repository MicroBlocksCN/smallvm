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
uint32 initTime;

WiFiServer server(80);

void primWifiConnect(OBJ *args) {
  // don't cancel ongoing connection attempts
  if (!connecting) {
    connecting = true;
    WiFi.disconnect();
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
  if (req.indexOf("/things/microblocks") != -1) {
    client.flush();
    client.print(
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
      "{\"name\":\"My MicroBlocks Thingie\","
      "\"href\":\"/things/microblocks\","
      "\"@context\":\"https://iot.mozilla.org/schemas\","
      "\"@type\":[\"OnOffSwitch\",\"Light\"],"
      "\"properties\":"
        "{\"on\":"
          "{\"type\":\"boolean\","
          "\"@type\":\"OnOffProperty\","
          "\"href\":\"/things/microblocks/properties/on\""
      "}}}"
    );
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
  if (WiFi.localIP()[0] != 0) {
    // Got an IP. We're online.
    connecting = false;
    initWebServer();
  } else if (status != 3 && millisecs() > initTime + 10000) {
    // We time out after 10s
    WiFi.disconnect();
    status = WL_DISCONNECTED;
    connecting = false;
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
