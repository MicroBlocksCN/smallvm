/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// websocket.h - Websocket bridge for ESP8266
// Bernat Romagosa, July 2018

#ifdef ESP8266

#include <ESP8266WiFi.h>
#include <ESP8266WiFiMulti.h>
#include <WebSocketsServer.h>
#include <ESP8266WebServer.h>
#include <Hash.h>

#include "mem.h"
#include "interp.h"

// You can either specify your network configuration here or use a
// computer to connect to the ESP8266 access point (essid will be
// ESP_XXXXXX), then head to http://192.168.4.1 in your browser.

char ESSID[32] = ""; // Your network ESSID
char PSK[63] = "";   // Your network PSK

#define USE_SERIAL Serial;

ESP8266WiFiMulti WiFiMulti;
ESP8266WebServer server(80);

char websocketEnabled = 0;
int connectionId;

static uint8 messageBuffer[1024];
static int msgBufIndex = 0;

WebSocketsServer websocket = WebSocketsServer(9999);

void websocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  int msgStart = 0;
  char *message = (char*) payload;
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

extern "C" int websocketSendByte(char payload) {
  messageBuffer[msgBufIndex] = payload;
  // only send out the actual websockets message when it's complete
  if ((0xFA == messageBuffer[0] && 2 == msgBufIndex) ||
    (0xFB == messageBuffer[0] && msgBufIndex > 4 &&
    (messageBuffer[4] << 8) | messageBuffer[3] == msgBufIndex - 4)) {
    websocket.sendBIN(connectionId, messageBuffer, msgBufIndex + 1);
    msgBufIndex = 0;
  } else {
    msgBufIndex ++;
  }
  return 1;
}

void websocketConnect() {
  char s[100];
  outputString("\nAttempting to connect to WiFi network\n");
  sprintf(s, "ESSID: %s - PSK: %s\n", ESSID, PSK);
  outputString(s);
  WiFiMulti.addAP(ESSID, PSK);

  for (int retries = 20; retries > 0; retries --) {
    if (WiFiMulti.run() != WL_CONNECTED) {
      delay(500);
    }
  }

  if (WiFiMulti.run() == WL_CONNECTED) {
    char s[300];
    IPAddress ip = WiFi.localIP();
    sprintf(s, "Connected to WiFi\nIP: %d.%d.%d.%d\n", ip[0], ip[1], ip[2], ip[3]);
    outputString(s);
    sprintf(
      s,
      "<html><body>"
        "<h1>microBlocks network configuration</h1>"
        "<p>ESSID set to <strong>%s</strong></p>"
        "<p>PSK set to <strong>%s</strong></p>"
        "<p>IP is now <strong>%d.%d.%d.%d</strong></p>"
      "</body></html>",
      ESSID,
      PSK,
      ip[0], ip[1], ip[2], ip[3]
    );
    server.send(200, "text/html", s);
    server.stop();
  } else {
    outputString("Failed to connect to network\nPlease check your ESSID and PSK\n");
  }

  websocket.begin();
  websocket.onEvent(websocketEvent);
}

void handleRootPath() {
  server.send(
    200,
    "text/html",
    "<html><body>"
      "<h1>microBlocks network configuration</h1>"
      "<form action=\"/config\">"
        "<strong>ESSID</strong><input type=\"text\" name=\"essid\" value=\"Your_Network_ESSID\"><br>"
        "<strong>PSK</strong><input type=\"text\" name=\"psk\" value=\"Your_Network_Password\"><br>"
        "<input type=\"submit\" value=\"Connect\">"
      "</form>"
    "</body></html>"
    );
}

void handleConfigPath() {
  char s[300];
  for (int i = 0; i < server.args(); i++) {
    if (strcmp(server.argName(i).c_str(), "essid") == 0) {
      strcpy(ESSID, server.arg(i).c_str());
    } else if (strcmp(server.argName(i).c_str(), "psk") == 0) {
      strcpy(PSK, server.arg(i).c_str());
    }
  }

  websocketConnect();
}

extern "C" void websocketInit() {
  if (strlen(ESSID) > 0) {
    websocketConnect();
  } else {
    outputString("ESSID unspecified.\n");
  }

  server.on("/", handleRootPath);
  server.on("/config", handleConfigPath);
  server.begin();
  outputString("Web server listening\n");
}

extern "C" void websocketLoop() {
  websocket.loop();
  server.handleClient();
}

#endif
