/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018
// Revised by John Maloney, November 2018

#include <stdio.h>
#include <string.h>
#include "mem.h"
#include "tinyJSON.h"

#if defined(ESP8266)
	#include <ESP8266WiFi.h>
#elif defined(ARDUINO_ARCH_ESP32)
	#include <WiFi.h>
#elif defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_SAMD_MKR1000)
	#define USE_WIFI101
	#define uint32 wifi_uint32
	#include <WiFi101.h>
	#undef uint32
#endif

#include "interp.h" // must be included *after* ESP8266WiFi.h

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(USE_WIFI101)

// Buffers for HTTP requests and responses
#define REQUEST_SIZE 1024
static uint8 request[REQUEST_SIZE];
static char response[REQUEST_SIZE];

#define JSON_HEADER \
"HTTP/1.1 200 OK\r\n" \
"Access-Control-Allow-Origin: *\r\n" \
"Content-Type: application/json\r\n\r\n"

#define NOT_FOUND_RESPONSE \
"HTTP/1.1 404 Not Found\r\n" \
"Access-Control-Allow-Origin: *\r\n" \
"Content-Type: application/json\r\n\r\n" \
"{ \"error\":\"Resource not found\" }"

#define OPTIONS_HEADER \
"HTTP/1.1 200 OK\r\n" \
"Access-Control-Allow-Origin: *\r\n" \
"Access-Control-Allow-Methods: PUT, GET, OPTIONS\r\n" \
"Access-Control-Allow-Headers: Content-Type\r\n\r\n"

static char connecting = false;

int serverStarted = false;
WiFiServer server(80);
WiFiClient client;

// WiFi Connection

// Macro for creating MicroBlocks string object constants
#define STRING_OBJ_CONST(s) \
	struct { uint32 header = HEADER(StringType, ((sizeof(s) + 4) / 4)); char body[sizeof(s)] = s; }

// Status strings that can be returned by WiFiStatus primitive

STRING_OBJ_CONST("Not connected") statusNotConnected;
STRING_OBJ_CONST("Trying...") statusTrying;
STRING_OBJ_CONST("Connected") statusConnected;
STRING_OBJ_CONST("Failed; bad password?") statusFailed;
STRING_OBJ_CONST("Unknown network") statusUnknownNetwork;
STRING_OBJ_CONST("Can't reach URL") statusCantReachURL;

#ifdef ESP8266
	static int firstTime = true;
#endif

static OBJ primHasWiFi(int argCount, OBJ *args) { return trueObj; }

static OBJ primStartWiFi(int argCount, OBJ *args) {
	// Start a WiFi connection attempt. The client should call wifiStatus until either
	// the connection is established or the attempt fails.

	if (argCount < 2) return fail(notEnoughArguments);

	char *networkName = obj2str(args[0]);
	char *password = obj2str(args[1]);

	#ifdef USE_WIFI101
		WiFi.begin(networkName, password);
	#else
		int createHotSpot = (argCount > 2) && (trueObj == args[2]);

		WiFi.persistent(false); // don't save network info to Flash
		WiFi.mode(WIFI_OFF); // Kill the current connection, if any

		if (createHotSpot) {
			WiFi.mode(WIFI_AP); // access point & station mode
			WiFi.softAP(networkName, password);
		} else {
			WiFi.mode(WIFI_STA);
			WiFi.begin(networkName, password);
		}
	#endif

	#ifdef ESP8266
		// workaround for an apparent ESP8266 WiFi startup bug: calling WiFi.status() during
		// the first few seconds after starting WiFi for the first time results in strange
		// behavior (task just stops without either error or completion; memory corruption?)
		if (firstTime) {
			delay(3000); // 3000 works, 2500 does not
			firstTime = false;
		}
	#endif
	connecting = true;
	return falseObj;
}

static OBJ primStopWiFi(int argCount, OBJ *args) {
	#ifndef USE_WIFI101
		server.stop();
		WiFi.mode(WIFI_OFF);
		serverStarted = false;
	#endif
	connecting = false;
	return falseObj;
}

static OBJ primWiFiStatus(int argCount, OBJ *args) {
	int status = WiFi.status();

	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
		if (WIFI_AP == WiFi.getMode()) {
			status = WL_CONNECTED; // acting as a hotspot
		}
	#else
		// todo: handle station mode for SAMW25_XPRO and MKR1000, if possible
	#endif

	if (WL_NO_SHIELD == status) return (OBJ) &statusNotConnected; // reported on ESP32
	if (WL_NO_SSID_AVAIL == status) return (OBJ) &statusUnknownNetwork; // reported only on ESP8266
	if (WL_CONNECT_FAILED == status) return (OBJ) &statusFailed; // reported only on ESP8266

	if (WL_DISCONNECTED == status) {
		return connecting ? (OBJ) &statusTrying : (OBJ) &statusNotConnected;
	}
	if (WL_CONNECTION_LOST == status) {
		primStopWiFi(0, NULL);
		return (OBJ) &statusNotConnected;
	}
	if (WL_IDLE_STATUS == status) {
	#ifdef USE_WIFI101
		return connecting ? (OBJ) &statusTrying : (OBJ) &statusNotConnected;
	#else
		return connecting ? (OBJ) &statusTrying : (OBJ) &statusNotConnected;
	#endif
	}
	if (WL_CONNECTED == status) {
		return (OBJ) &statusConnected;
	}
	return int2obj(status); // should not happen
}

struct {
	uint32 header;
	char body[16];
} ipStringObject;

static OBJ primGetIP(int argCount, OBJ *args) {
	#ifdef USE_WIFI101
		IPAddress ip = WiFi.localIP();
	#else
		IPAddress ip = (WIFI_AP == WiFi.getMode()) ? WiFi.softAPIP() : WiFi.localIP();
	#endif
	sprintf(ipStringObject.body, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
	ipStringObject.header = HEADER(StringType, (strlen(ipStringObject.body) + 4) / 4);
	return (OBJ) &ipStringObject;
}

static OBJ primStartHttpServer(int argCount, OBJ *args) {
	server.begin();
	return falseObj;
}

static OBJ primStopHttpServer(int argCount, OBJ *args) {
	server.close();
	return falseObj;
}

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) {
	if (!client) client = server.available(); // attempt to accept a client connection
	if (!client) return falseObj; // no client connection

	// read an HTTP request
	int bytesAvailable = client.available();
	if (!bytesAvailable) return falseObj;
	client.readBytes(request, bytesAvailable);
	request[bytesAvailable] = 0; // null terminate

	return newStringFromBytes(request, bytesAvailable);
}

static OBJ primRespondToHttpRequest(int argCount, OBJ *args) {
	if (!client) return falseObj;
	char* status = obj2str(args[0]);
	char* body = obj2str(args[1]);
	char* headers = obj2str(args[2]);
	client.print("HTTP/1.1 ");
	client.print(status);
	if (argCount > 2) {
		client.print("\r\n");
		client.print(headers);
	}
	client.print("\r\n\r\n");
	if (argCount > 1) {
		client.print(body);
		client.print("\n");
	}
	client.flush();
	client.stop();
	return falseObj;
}

WiFiClient httpClient;

static OBJ primHttpConnect(int argCount, OBJ *args) {
	int port = 80;
	char* host = obj2str(args[0]);
	if ((argCount > 1) && isInt(args[1])) port = obj2int(args[1]);
	httpClient.connect(host, port);
	return falseObj;
}

static OBJ primHttpIsConnected(int argCount, OBJ *args) {
	return httpClient.connected() ? trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	char* reqType = obj2str(args[0]);
	char* host = obj2str(args[1]);
	char* path = obj2str(args[2]);
	char request[256];
	sprintf(request,
			"%s /%s HTTP/1.1\r\n\
Host: %s\r\n\
Connection: close\r\n\
User-Agent: MicroBlocks\r\n\
Accept: */*\r\n",
			reqType,
			path,
			host);
	httpClient.write(request, strlen(request));
	if (argCount > 3) {
		char length_str[50];
		char* body = obj2str(args[3]);
		int content_length = strlen(body);
		httpClient.write("Content-Type: text/plain\r\n", 26);
		sprintf(length_str, "Content-Length: %i\r\n\r\n", content_length);
		httpClient.write(length_str, strlen(length_str));
		httpClient.write(body, strlen(body));
	} else {
		httpClient.write("\r\n", 2);
	}
	httpClient.flush();
	return falseObj;
}

static OBJ primHttpResponse(int argCount, OBJ *args) {
	int byteCount = httpClient.available();
	if (byteCount) {
		if (byteCount > 1023) byteCount = 1023;
		httpClient.read((uint8 *) response, byteCount);
		return newStringFromBytes((uint8 *) response, byteCount);
	} else {
		return falseObj;
	}
}

static OBJ primHttpClose(int argCount, OBJ *args) {
	httpClient.stop();
	return falseObj;
}

#else // not ESP8266 or ESP32

static OBJ primHasWiFi(int argCount, OBJ *args) { return falseObj; }
static OBJ primStartWiFi(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStopWiFi(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWiFiStatus(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetIP(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStartHttpServer(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStopHttpServer(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpServerGetRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primRespondToHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpConnect(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpIsConnected(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpResponse(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpClose(int argCount, OBJ *args) { return fail(noWiFi); }

#endif

static PrimEntry entries[] = {
	{"hasWiFi", primHasWiFi},
	{"startWiFi", primStartWiFi},
	{"stopWiFi", primStopWiFi},
	{"wifiStatus", primWiFiStatus},
	{"myIPAddress", primGetIP},
	{"startHttpServer", primStartHttpServer},
	{"stoptHttpServer", primStopHttpServer},
	{"httpServerGetRequest", primHttpServerGetRequest},
	{"respondToHttpRequest", primRespondToHttpRequest},
	{"httpConnect", primHttpConnect},
	{"httpIsConnected", primHttpIsConnected},
	{"httpRequest", primHttpRequest},
	{"httpResponse", primHttpResponse},
	{"httpClose", primHttpClose},
};

void addNetPrims() {
	addPrimitiveSet("net", sizeof(entries) / sizeof(PrimEntry), entries);
}
