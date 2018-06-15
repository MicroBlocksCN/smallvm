/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// websocket.h - Websocket bridge for ESP8266
// Bernat Romagosa, May 2018

#ifdef __cplusplus
extern "C" {
#endif

extern char websocketEnabled;

void websocketInit();
void websocketLoop();
int readWebsocketBytes(uint8 *buf);
int websocketSendByte(uint8 payload);

#ifdef __cplusplus
}
#endif
