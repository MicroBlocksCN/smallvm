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
	char ip[9] = "127.0.0.1";
	return newStringFromBytes(ip, 9);
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
	return EM_ASM_INT({ return window.httpRequest !== undefined; }) ?
		trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	char* reqType = obj2str(args[0]);
	char* host = obj2str(args[1]);
	char* path = obj2str(args[2]);
	EM_ASM_({
		window.httpRequest = new XMLHttpRequest();
		var req = window.httpRequest;
		req.currentIndex = 0;
		req.open(
			UTF8ToString($0), // method
			window.location.protocol + "//" + UTF8ToString($1) +
				"/" + UTF8ToString($2) // URL
		);
		req.onreadystatechange = function () {
			if (req.readyState == 4){
				req.fullResponse = "HTTP/1.1 " + req.status + " " +
					req.statusText + "\r\n" + req.getAllResponseHeaders() +
					"\r\n\r\n" + req.responseText;
			}
		};
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
	char buffer[800];
	int byteCount = EM_ASM_INT({
		var req = window.httpRequest;
		var byteCount = 0;
		if (req && req.fullResponse) {
			byteCount = Math.min(
				req.fullResponse.length - req.currentIndex,
				799
			);
			var chunk = req.fullResponse.substr(req.currentIndex, byteCount);
			stringToUTF8(chunk, $0, byteCount + 1);
			req.currentIndex += byteCount;
			if (byteCount == 0) { delete(window.httpRequest); }
		}
		return byteCount;
	}, buffer);
	response = newString(byteCount);
	memcpy(obj2str(response), buffer, byteCount);
	return response;
}


// MQTT support, untested and disabled for now, until we figure out how to deal
// with external JS libraries that get minified by the closure compiler...

/*
static OBJ primMQTTConnect(int argCount, OBJ *args) {
	// args[1] is buffer size, which we ignore for Boardie
	printf("connecting...\n");
	EM_ASM_({
		var brokerURI = UTF8ToString($0);
		var clientId = UTF8ToString($1);
		var username = UTF8ToString($2);
		var password = UTF8ToString($3);
		var opts = {};
		var client;
		if (username) { opts.username = username };
		if (password) { opts.password = password };
		if (clientId) { opts.clientId = clientId };
		client = window.mqtt.connect(brokerURI, opts);
		window.mqttClient = client;
		client.messages = [];
		client.on('message', function (topic, msg) {
			client.messages.push(msg);
		});
	},
	obj2str(args[0]), // broker_uri
	(argCount > 2) ? obj2str(args[2]) : (char *) "", // client_id
	(argCount > 4) ? obj2str(args[3]) : (char *) "", // username
	(argCount > 4) ? obj2str(args[4]) : (char *) "" // password
	);
	return falseObj;
}

static OBJ primMQTTIsConnected(int argCount, OBJ *args) {
	return EM_ASM_INT({
		return window.mqttClient && window.mqttClient.connected;
	}) ? trueObj : falseObj;
}

static OBJ primMQTTDisconnect(int argCount, OBJ *args) {
	EM_ASM_({
		if (window.mqttClient && window.mqttClient.connected) {
			window.mqttClient.end(true);
			delete(window.mqttClient);
		}
	});
	return trueObj;
}
static OBJ primMQTTLastEvent(int argCount, OBJ *args) {
	return falseObj;
}
static OBJ primMQTTPub(int argCount, OBJ *args) {
	return falseObj;
}
static OBJ primMQTTSub(int argCount, OBJ *args) {
	// slightly ugly because of the async nature of the success callback

	EM_ASM_({
		var client = window.mqttClient;
		client.callbackCalled = false;
		client.subSuccess = false;
		if (client && client.connected) {
			var topic = UTF8ToString($0);
			var qos = $1 === 1;
			client.subscribe(
				topic,
				{ qos : qos },
				function (err, granted) {
					client.callbackCalled = true;
					client.subSuccess = err != undefined;
				}
			);
		}
	}, obj2str(args[0]));

	// TODO add a timeout
	while (!EM_ASM_INT({ return window.mqttClient.callbackCalled })) { }

	return EM_ASM_INT({
		var client = window.mqttClient;
		var success = client.subSuccess;
		delete client.callbackCalled;
		delete client.subSuccess;
		return success;
	}) ? trueObj : falseObj;
}

static OBJ primMQTTUnsub(int argCount, OBJ *args) {
	// slightly ugly because of the async nature of the success callback

	EM_ASM_({
		var client = window.mqttClient;
		client.callbackCalled = false;
		client.unsubSuccess = false;
		if (client && client.connected) {
			var topic = UTF8ToString($0);
			client.unsubscribe(
				topic,
				function (err) {
					client.callbackCalled = true;
					client.unsubSuccess = err != undefined;
				}
			);
		}
	}, obj2str(args[0]));

	// TODO add a timeout
	while (!EM_ASM_INT({ return window.mqttClient.callbackCalled })) { }

	return EM_ASM_INT({
		var client = window.mqttClient;
		var success = client.unsubSuccess;
		delete client.callbackCalled;
		delete client.unsubSuccess;
		return success;
	}) ? trueObj : falseObj;
}
*/

static OBJ primMQTTConnect(int argCount, OBJ *args) { return falseObj; }
static OBJ primMQTTIsConnected(int argCount, OBJ *args) { return falseObj; }
static OBJ primMQTTDisconnect(int argCount, OBJ *args) { return falseObj; }
static OBJ primMQTTLastEvent(int argCount, OBJ *args) { return falseObj; }
static OBJ primMQTTPub(int argCount, OBJ *args) { return falseObj; }
static OBJ primMQTTSub(int argCount, OBJ *args) { return falseObj; }
static OBJ primMQTTUnsub(int argCount, OBJ *args) { return falseObj; }

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

	{"MQTTConnect", primMQTTConnect},
	{"MQTTIsConnected", primMQTTIsConnected},
	{"MQTTDisconnect", primMQTTDisconnect},
	{"MQTTLastEvent", primMQTTLastEvent},
	{"MQTTPub", primMQTTPub},
	{"MQTTSub", primMQTTSub},
	{"MQTTUnsub", primMQTTUnsub},
};

void addNetPrims() {
	addPrimitiveSet(NetPrims, "net", sizeof(entries) / sizeof(PrimEntry), entries);
}
