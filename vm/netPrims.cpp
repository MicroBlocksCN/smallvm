/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018
// Revised by John Maloney, November 2018
// Revised by Bernat Romagosa & John Maloney, March 2020

#include <stdio.h>
#include <stdlib.h>
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

static char connecting = false;
static char serverStarted = false;

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
STRING_OBJ_CONST("") noDataString;

// Empty byte array constant
uint32 emptyByteArray = HEADER(ByteArrayType, 0);

static OBJ primHasWiFi(int argCount, OBJ *args) { return trueObj; }

static OBJ primStartWiFi(int argCount, OBJ *args) {
	// Start a WiFi connection attempt. The client should call wifiStatus until either
	// the connection is established or the attempt fails.

	if (argCount < 2) return fail(notEnoughArguments);

	char *networkName = obj2str(args[0]);
	char *password = obj2str(args[1]);

	serverStarted = false;

	if (argCount > 3) { // static IP
		IPAddress ip;
		IPAddress gateway;
		IPAddress subnet;
		ip.fromString(obj2str(args[3]));
		gateway.fromString(obj2str(args[4]));
		subnet.fromString(obj2str(args[5]));
		WiFi.config(ip, gateway, subnet);
	}

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

	connecting = true;
	return falseObj;
}

static OBJ primStopWiFi(int argCount, OBJ *args) {
	#ifndef USE_WIFI101
		WiFi.mode(WIFI_OFF);
	#endif
	connecting = false;
	return falseObj;
}

static OBJ primWiFiStatus(int argCount, OBJ *args) {
	if (!connecting) return (OBJ) &statusNotConnected;

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

static int isConnectedToWiFi() {
	if (!connecting) return false;
	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
		if (WIFI_AP == WiFi.getMode()) return true; // acting as a hotspot
	#endif
	return WL_CONNECTED == WiFi.status();
}

static OBJ primGetIP(int argCount, OBJ *args) {
	#ifdef USE_WIFI101
		IPAddress ip = WiFi.localIP();
	#else
		IPAddress ip = (WIFI_AP == WiFi.getMode()) ? WiFi.softAPIP() : WiFi.localIP();
	#endif

	// Clear IP address if not connected
	if (!isConnectedToWiFi()) {
		ip[0] = ip[1] = ip[2] = ip[3] = 0;
	}

	sprintf(ipStringObject.body, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
	ipStringObject.header = HEADER(StringType, (strlen(ipStringObject.body) + 4) / 4);
	return (OBJ) &ipStringObject;
}

// HTTP Server

static void startHttpServer() {
	// Start the server the first time and *never* stop/close it. If the server is stopped
	// on the ESP32 then all future connections are refused until the board is reset.
	// It is fine for the server to continue running even if the WiFi is restarted.

	if (!serverStarted) {
		server.begin();
		serverStarted = true;
	}
}

static int serverHasClient() {
	// Return true when the HTTP server has a client and the client is connected.
	// Continue to return true if any data is available from the client even if the client
	// has closed the connection. Start the HTTP server the first time this is called.

	if (!isConnectedToWiFi()) return false;
	if (!serverStarted) startHttpServer();

	if (!client) client = server.available(); // attempt to accept a client connection
	if (!client) return false; // no client connection
	return (client.connected() || client.available());
}

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) {
	// Return some data from the current HTTP request. Return the empty string if no
	// data is available. If there isn't currently a client connection, and a client
	// is waiting, accept the new connection. If the optional first argument is true,
	// return a ByteArray (binary data) instead of a string.
	// Fail if there isn't enough memory to allocate the result object.

	int useBinary = ((argCount > 0) && (trueObj == args[0]));
	OBJ noData = useBinary ? (OBJ) &emptyByteArray : (OBJ) &noDataString;

	if (!serverHasClient()) return noData; // no client connection

	int byteCount = client.available();
	if (!byteCount) return noData;
	if (byteCount > 800) byteCount = 800; // limit to 800 bytes per chunk

	OBJ result;
	if (useBinary) {
		result = newObj(ByteArrayType, (byteCount + 3) / 4, falseObj);
		while (falseObj == result) {
			if (byteCount < 4) return falseObj; // out of memory
			byteCount = byteCount / 2;
			result = newObj(ByteArrayType, (byteCount + 3) / 4, falseObj); // try to allocate half the previous amount
		}
		if (IS_TYPE(result, ByteArrayType)) setByteCountAdjust(result, byteCount);
	} else {
		result = newString(byteCount);
		while (falseObj == result) {
			if (byteCount < 4) return falseObj; // out of memory
			byteCount = byteCount / 2;
			result = newString(byteCount); // try to allocate half the previous amount
		}
	}

	fail(noError); // clear memory allocation error, if any
	client.readBytes((uint8 *) &FIELD(result, 0), byteCount);
	return result;
}

static OBJ primRespondToHttpRequest(int argCount, OBJ *args) {
	// Send a response to the client with the status. optional extra headers, and optional body.

	if (!client) return falseObj;

	// send headers
	char *status = ((argCount > 0) && IS_TYPE(args[0], StringType)) ?
		obj2str(args[0]) : (char *) "200 OK";
	client.print("HTTP/1.0 ");
	client.println(status);
	client.println("Access-Control-Allow-Origin: *");
	if ((argCount > 2) && IS_TYPE(args[2], StringType)) {
		char *headers = obj2str(args[2]);
		client.print(headers);
	}
	client.print("\r\n\r\n"); // end of headers

	// send body, if any
	if (argCount > 1) {
		if (IS_TYPE(args[1], StringType)) {
			char *body = obj2str(args[1]);
			client.write(body, strlen(body));
			client.println();
		} else if (IS_TYPE(args[1], ByteArrayType)) {
			uint8 *body = (uint8 *) &FIELD(args[1], 0);
			client.write(body, BYTES(args[1]));
		}
	}

	delay(20); // allow time for data to get sent
	client.stop(); // close the connection
	return falseObj;
}

// HTTP Client

WiFiClient httpClient;

static OBJ primHttpConnect(int argCount, OBJ *args) {
	// Connect to an HTTP server and port.

	char* host = obj2str(args[0]);
	int port = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 80;
	uint32 start = millisecs();
	const int timeout = 800;
	int ok;
	#ifdef ARDUINO_ARCH_ESP32
		ok = httpClient.connect(host, port, timeout);
	#else
		httpClient.setTimeout(timeout);
		ok = httpClient.connect(host, port);
	#endif

	while (ok && !httpClient.connected()) { // wait for connection to be fully established
		processMessage(); // process messages now
		uint32 now = millisecs();
		uint32 elapsed = (now >= start) ? (now - start) : now; // handle clock wrap
		if (elapsed > timeout) break;
		delay(1);
	}
	processMessage(); // process messages now
	return falseObj;
}

static OBJ primHttpIsConnected(int argCount, OBJ *args) {
	// Return true when connected to an HTTP server. Continue to return true if more data
	// is available even if the connection has been closed by the server.

	return (httpClient.connected() || httpClient.available()) ? trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	// Send an HTTP request. Must have first connected to the server.

	char* reqType = obj2str(args[0]);
	char* host = obj2str(args[1]);
	char* path = obj2str(args[2]);
	char request[256];
	sprintf(request,
			"%s /%s HTTP/1.0\r\n\
Host: %s\r\n\
Connection: close\r\n\
User-Agent: MicroBlocks\r\n\
Accept: */*\r\n",
			reqType,
			path,
			host);
	httpClient.write(request, strlen(request));
	if ((argCount > 3) && IS_TYPE(args[3], StringType)) {
		char length_str[50];
		char* body = obj2str(args[3]);
		int content_length = strlen(body);
		httpClient.write("Content-Type: text/plain\r\n", 26);
		sprintf(length_str, "Content-Length: %i\r\n\r\n", content_length);
		httpClient.write(length_str, strlen(length_str));
		httpClient.write(body, content_length);
	} else {
		httpClient.write("\r\n", 2);
	}
	return falseObj;
}

static OBJ primHttpResponse(int argCount, OBJ *args) {
	// Read some HTTP request data, if any is available, otherwise return the empty string.

	int byteCount = httpClient.available();
	if (!byteCount) return (OBJ) &noDataString;
	if (byteCount > 800) byteCount = 800; // max length string that can be reported to IDE

	OBJ result = newString(byteCount);
	while (falseObj == result) {
		if (byteCount < 4) return (OBJ) &noDataString; // out of memory
		byteCount = byteCount / 2;
		result = newString(byteCount); // try to allocate half the previous amount
	}
	fail(noError); // clear memory allocation error, if any
	httpClient.read((uint8 *) obj2str(result), byteCount);
	return result;
}

#else // not ESP8266 or ESP32

static OBJ primHasWiFi(int argCount, OBJ *args) { return falseObj; }
static OBJ primStartWiFi(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStopWiFi(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWiFiStatus(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetIP(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpServerGetRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primRespondToHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpConnect(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpIsConnected(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpResponse(int argCount, OBJ *args) { return fail(noWiFi); }

#endif

static PrimEntry entries[] = {
	{"hasWiFi", primHasWiFi},
	{"startWiFi", primStartWiFi},
	{"stopWiFi", primStopWiFi},
	{"wifiStatus", primWiFiStatus},
	{"myIPAddress", primGetIP},
	{"httpServerGetRequest", primHttpServerGetRequest},
	{"respondToHttpRequest", primRespondToHttpRequest},
	{"httpConnect", primHttpConnect},
	{"httpIsConnected", primHttpIsConnected},
	{"httpRequest", primHttpRequest},
	{"httpResponse", primHttpResponse},
};

void addNetPrims() {
	addPrimitiveSet("net", sizeof(entries) / sizeof(PrimEntry), entries);
}
