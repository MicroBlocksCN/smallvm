/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// boardieNetPrims.c - MicroBlocks network primitives
// Bernat Romagosa, November 2022

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "mem.h"
#include "interp.h"

#include <emscripten.h>

// These make no sense in the context of Boardie, but we'll do what we can
static OBJ primHasWiFi(int argCount, OBJ *args) { return trueObj; }
static OBJ primStartWiFi(int argCount, OBJ *args) { return trueObj; }
static OBJ primStopWiFi(int argCount, OBJ *args) { return trueObj; }

static OBJ primWiFiStatus(int argCount, OBJ *args) {
	char status[9] = "Connected";
	return newStringFromBytes(status, 9);
}

static OBJ primGetIP(int argCount, OBJ *args) {
	char ip[7] = "0.0.0.0";
	return newStringFromBytes(ip, 7);
}

static OBJ primGetMAC(int argCount, OBJ *args) {
	char addressString[17] = "00:00:00:00:00:00";
	return newStringFromBytes(addressString, 17);
}

// Impossible server functionality

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primRespondToHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStartSSIDscan(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetSSID(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketStart(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketLastEvent(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketSendToClient(int argCount, OBJ *args) { return fail(noWiFi); }

// HTTP Client

static OBJ primHttpConnect(int argCount, OBJ *args) {
	EM_ASM_({
		window.httpRequest = new XMLHttpRequest();
		window.httpRequest.port = $0;
		window.httpRequest.currentIndex = 0;
	}, ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 80);
	return trueObj;
}

static OBJ primHttpIsConnected(int argCount, OBJ *args) {
	return EM_ASM_INT({ return window.httpRequest !== undefined; }) ? trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	char* reqType = obj2str(args[0]);
	char* host = obj2str(args[1]);
	char* path = obj2str(args[2]);
	EM_ASM_({
		var req = window.httpRequest;
		req.open(
			UTF8ToString($0), // method
			window.location.protocol + "//" + UTF8ToString($1) +
				":" + req.port + "/" + UTF8ToString($2) // URL
		);
		req.send(UTF8ToString($3)); // body
	},
	reqType,
	host,
	path,
	((argCount > 3) && IS_TYPE(args[3], StringType)) ? obj2str(args[3]) : "");
	return falseObj;
}

static OBJ primHttpResponse(int argCount, OBJ *args) {
	OBJ response;
	char buffer[799];
	int byteCount = EM_ASM_INT({
		var req = window.httpRequest;
		if (req.readyState == 4 && req.status == 200) {
			var byteCount = Math.min(
				req.responseText.length - req.currentIndex,
				799
			);
			var chunk = req.responseText.substring(req.currentIndex, byteCount);
			stringToUTF8(chunk, $0, byteCount);
			req.currentIndex += byteCount;
		}
		return byteCount;
	}, buffer);
	response = newString(byteCount);
	memcpy(obj2str(response), buffer, byteCount);
	return response;
}

static PrimEntry entries[] = {
	{"hasWiFi", primHasWiFi},
	{"startWiFi", primStartWiFi},
	{"stopWiFi", primStopWiFi},
	{"wifiStatus", primWiFiStatus},
	{"myIPAddress", primGetIP},
	{"startSSIDscan", primStartSSIDscan},
	{"getSSID", primGetSSID},
	{"myMAC", primGetMAC},
	{"httpServerGetRequest", primHttpServerGetRequest},
	{"respondToHttpRequest", primRespondToHttpRequest},
	{"httpConnect", primHttpConnect},
	{"httpIsConnected", primHttpIsConnected},
	{"httpRequest", primHttpRequest},
	{"httpResponse", primHttpResponse},
	{"webSocketStart", primWebSocketStart},
	{"webSocketLastEvent", primWebSocketLastEvent},
	{"webSocketSendToClient", primWebSocketSendToClient},
};

void addNetPrims() {
	addPrimitiveSet("net", sizeof(entries) / sizeof(PrimEntry), entries);
}
