/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// websocket.h - Websocket bridge for ESP8266
// Bernat Romagosa, May 2018

#ifdef ESP8266

#include <ESP8266WiFi.h>
#include <ESP8266WiFiMulti.h>
#include <WebSocketsServer.h>
#include <Hash.h>

#include "mem.h"
#include "interp.h"

#define ESSID "YOUR_NETWORK_ESSID"
#define PSK "YOUR_NETWORK_PASSWORD"
#define USE_SERIAL Serial;

ESP8266WiFiMulti WiFiMulti;

char websocketEnabled = 0;
int connectionId;

WebSocketsServer websocket = WebSocketsServer(9999);

void websocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  int msgStart = 0;
  char *message = (char*)payload;
  switch(type) {
    case WStype_DISCONNECTED:
      outputString("Websocket connection dropped\n");
      websocketEnabled = 0;
      break;
    case WStype_CONNECTED:
      {
        char s[100];
        IPAddress ip = websocket.remoteIP(num);
        sprintf(s, "Client connected from IP: %d.%d.%d.%d\n", ip[0], ip[1], ip[2], ip[3]);
        outputString(s);
        websocketEnabled = 1;
        connectionId = num;
      }
      break;
    case WStype_TEXT:
      outputString("got a text message, ignoring it:\n");
      outputString(message);
      break;
    case WStype_BIN:
      connectionId = num;
      for (int i = 0; i < length; i++) {
        rcvBuf[rcvByteCount + i] = payload[i];
      }
      rcvByteCount += length;
      break;
  }
}

void websocketSend(uint8_t * payload, size_t length) {
  websocket.sendBIN(connectionId, payload, length);
}

extern "C" int websocketSendByte(char payload) {
  // first parameter is the socket connection number
  // we should only accept one connection per device
  uint8 byteToSend[] = { ( char ) payload };
  websocket.sendBIN(connectionId, byteToSend, 1);
  return 1;
}

extern "C" void websocketInit() {
  // delay(4000);
  outputString("Connecting to WiFi network\n");
  
  WiFiMulti.addAP(ESSID, PSK);

  for (int retries = 20; retries > 0; retries --) {
    if (WiFiMulti.run() != WL_CONNECTED) {
      delay(500);
    }
  }

  if (WiFiMulti.run() == WL_CONNECTED) {
    char s[100];
    IPAddress ip = WiFi.localIP();
    sprintf(s, "Connected to WiFi\nIP: %d.%d.%d.%d\n", ip[0], ip[1], ip[2], ip[3]);
    outputString(s);
  } else {
    outputString("Failed to connect to network\nPlease check your ESSID and PSK\n");
  }

  websocket.begin();
  websocket.onEvent(websocketEvent);
}

extern "C" void websocketLoop() {
  websocket.loop();
}

#endif
