/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018
// Revised by John Maloney, November 2018
// Revised by Bernat Romagosa & John Maloney, March 2020
// MQTT primitives added by Wenjie Wu with help from Tom Ming

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"

#if defined(NRF51)
	#include <nrf51.h>
	#include <nrf51_bitfields.h>
#elif defined(NRF52)
	#include <nrf52.h>
	#include <nrf52_bitfields.h>
#endif

#define NO_WIFI() (false)

#if defined(ESP8266)
	#include <ESP8266WiFi.h>
	#include <WiFiUdp.h>
#elif defined(ARDUINO_ARCH_ESP32)
	#include <WiFi.h>
	#include <WebSocketsServer.h>
#elif defined(PICO_WIFI)
	#include <WiFi.h>
	#include <WebSocketsServer.h>
	extern bool __isPicoW;
	#undef NO_WIFI
	#define NO_WIFI() (!__isPicoW)
#elif defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_SAMD_MKR1000)
	#define USE_WIFI101
	#define uint32 wifi_uint32
	#include <WiFi101.h>
	#include <WiFiUdp.h>
	#undef uint32
#endif

#include "interp.h" // must be included *after* ESP8266WiFi.h

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(USE_WIFI101) || defined(PICO_WIFI)

static char connecting = false;
static char serverStarted = false;
static char allowBLE_and_WiFi = true;

int serverPort = 80;
WiFiServer server(serverPort);
WiFiClient client;

// MAC Address

void getMACAddress(uint8 *sixBytes) {
	unsigned char mac[6] = {0, 0, 0, 0, 0, 0};
	if (!NO_WIFI()) WiFi.macAddress(mac);
	memcpy(sixBytes, mac, 6);
}

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

static OBJ primHasWiFi(int argCount, OBJ *args) {
	return NO_WIFI() ? falseObj : trueObj;
}

static OBJ primAllowWiFiAndBLE(int argCount, OBJ *args) {
	allowBLE_and_WiFi = (argCount > 0) && (trueObj == args[0]);
	if (allowBLE_and_WiFi) BLE_start();
	return falseObj;
}

static OBJ primStartWiFi(int argCount, OBJ *args) {
	// Start a WiFi connection attempt. The client should call wifiStatus until either
	// the connection is established or the attempt fails.

	if (argCount < 2) return fail(notEnoughArguments);
	if (NO_WIFI()) return fail(noWiFi);

	if (!allowBLE_and_WiFi) {
		if (BLE_connected_to_IDE) return fail(cannotUseWithBLE);
		BLE_stop();
	}

	char *networkName = obj2str(args[0]);
	char *password = obj2str(args[1]);

	serverStarted = false;

	if ((argCount > 5) &&
		(obj2str(args[3])[0] != 0) &&
		(obj2str(args[4])[0] != 0) &&
		(obj2str(args[5])[0] != 0)) { // use static IP (all parameters must be non-empty strings)
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

		#if !defined(PICO_WIFI)
			WiFi.persistent(false); // don't save network info to Flash
		#endif
		WiFi.mode(WIFI_OFF); // Kill the current connection, if any
		if (createHotSpot) {
			WiFi.mode(WIFI_AP); // access point & station mode
			WiFi.softAP(networkName, password);
		} else {
			WiFi.mode(WIFI_STA);
			if (strlen(password) > 0) {
				WiFi.begin(networkName, password);
			} else {
				WiFi.begin(networkName);
			}
		}
	#endif

	connecting = true;
	return falseObj;
}

static OBJ primStopWiFi(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	WiFi.disconnect();
	#ifndef USE_WIFI101
		WiFi.mode(WIFI_OFF);
	#endif
	connecting = false;
	return falseObj;
}

static OBJ primWiFiStatus(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

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
	if (NO_WIFI()) return fail(noWiFi);

	#if defined(USE_WIFI101) || defined(PICO_WIFI)
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

static OBJ primStartSSIDscan(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	return int2obj(WiFi.scanNetworks());
}

static OBJ primGetSSID(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	char ssid[100];
	ssid[0] = '\0'; // clear string
	#if defined(USE_WIFI101) || defined(PICO_WIFI)
		strncat(ssid, WiFi.SSID(obj2int(args[0]) - 1), 31);
	#else
		strncat(ssid, WiFi.SSID(obj2int(args[0]) - 1).c_str(), 31);
	#endif
	return newStringFromBytes(ssid, strlen(ssid));
}

static OBJ primGetMAC(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	#ifdef USE_WIFI101
		unsigned char mac[6] = {0, 0, 0, 0, 0, 0};
		// Note: WiFi.macAddress() returns incorrect MAC address before first connection.
		// Make it return all zeros rather than random garbage.
		if (isConnectedToWiFi()) WiFi.macAddress(mac);
		char s[32];
		sprintf(s, "%.2X:%.2X:%.2X:%.2X:%.2X:%.2X",
			mac[5], mac[4], mac[3], mac[2], mac[1], mac[0]);
		return newStringFromBytes(s, strlen(s));
	#else
		return newStringFromBytes(WiFi.macAddress().c_str(), 18);
	#endif
}

// HTTP Server

static void startHttpServer() {
	// Start the server the first time and *never* stop/close it. If the server is stopped
	// on the ESP32 then all future connections are refused until the board is reset.
	// It is fine for the server to continue running even if the WiFi is restarted.

	if (!serverStarted) {
		#ifdef USE_WIFI101
			server.begin(); // setting server port in begin() not supported by WiFi101 library
		#else
			server.begin(serverPort);
		#endif
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

	#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32)
		client.setNoDelay(true);
	#endif

	return (client.connected() || client.available());
}

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) {
	// Return some data from the current HTTP request. Return the empty string if no
	// data is available. If there isn't currently a client connection, and a client
	// is waiting, accept the new connection. If the optional first argument is true,
	// return a ByteArray (binary data) instead of a string. The optional second arg
	// can specify a port. Changing ports stops and restarts the server.
	// Fail if there isn't enough memory to allocate the result object.

	if (NO_WIFI()) return fail(noWiFi);

	int useBinary = ((argCount > 0) && (trueObj == args[0]));
	OBJ noData = useBinary ? (OBJ) &emptyByteArray : (OBJ) &noDataString;

	if ((argCount > 1) && isInt(args[1])) {
		int port = obj2int(args[1]);
		// If we're changing port, stop and restart the server
		if (port != serverPort) {
			#ifdef USE_WIFI101
				outputString("WiFi101 does not support changing the server port");
			#else
				char s[100];
				sprintf(s, "Changing server port from %d to %d", serverPort, port);
				outputString(s);
				server.stop();
				server.begin(port);
			#endif
			serverPort = port;
		}
	}

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

	if (NO_WIFI()) return fail(noWiFi);
	if (!client) return falseObj;

	// status
	char *status = (char *) "200 OK";
	if ((argCount > 0) && IS_TYPE(args[0], StringType)) status = obj2str(args[0]);

	// body
	int contentLength = -1; // no body
	if (argCount > 1) {
		if (IS_TYPE(args[1], StringType)) {
			contentLength = strlen(obj2str(args[1]));
		} else if (IS_TYPE(args[1], ByteArrayType)) {
			contentLength = BYTES(args[1]);
		}
	}

	// additional headers
	char *extraHeaders = NULL;
	if ((argCount > 2) && IS_TYPE(args[2], StringType)) {
		extraHeaders = obj2str(args[2]);
		if (0 == strlen(extraHeaders)) extraHeaders = NULL; // empty string
	}

	// keep alive flag
	int keepAlive = ((argCount > 3) && (trueObj == args[3]));

	// send headers
	client.print("HTTP/1.0 ");
	client.println(status);
	client.println("Access-Control-Allow-Origin: *");
	if (keepAlive) client.println("Connection: keep-alive");
	if (extraHeaders) {
		client.print(extraHeaders);
		if (10 != extraHeaders[strlen(extraHeaders) - 1]) client.println();
	}
	if (contentLength >= 0) {
		client.print("Content-Length: ");
		client.print(contentLength);
	}
	client.print("\r\n\r\n"); // end of headers

	// send body, if any
	if (argCount > 1) {
		if (IS_TYPE(args[1], StringType)) {
			char *body = obj2str(args[1]);
			client.write(body, strlen(body));
		} else if (IS_TYPE(args[1], ByteArrayType)) {
			uint8 *body = (uint8 *) &FIELD(args[1], 0);
			client.write(body, BYTES(args[1]));
		}
	}
	delay(1); // allow some time for data to be sent
	if (!keepAlive) client.stop(); // close the connection
	taskSleep(10);
	return falseObj;
}

// HTTP Client

WiFiClient httpClient;

static OBJ primHttpConnect(int argCount, OBJ *args) {
	// Connect to an HTTP server and port.

	if (NO_WIFI()) return fail(noWiFi);

	char* host = obj2str(args[0]);
	int port = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 80;
	uint32 start = millisecs();
	const int timeout = 3000;
	int ok;
	#ifdef ARDUINO_ARCH_ESP32
		ok = httpClient.connect(host, port, timeout);
	#else
		httpClient.setTimeout(timeout);
		ok = httpClient.connect(host, port);
	#endif

	#if defined(ESP8266) // || defined(ARDUINO_ARCH_ESP32)
		// xxx fais on ESP32 due to an error in their code
		client.setNoDelay(true);
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

	if (NO_WIFI()) return fail(noWiFi);

	return (httpClient.connected() || httpClient.available()) ? trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	// Send an HTTP request. Must have first connected to the server.

	if (NO_WIFI()) return fail(noWiFi);

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
	if ((argCount > 3) && IS_TYPE(args[3], StringType)) {
		httpClient.write(request, strlen(request));
		char length_str[50];
		char* body = obj2str(args[3]);
		int content_length = strlen(body);
		httpClient.write("Content-Type: text/plain\r\n", 26);
		sprintf(length_str, "Content-Length: %i\r\n\r\n", content_length);
		httpClient.write(length_str, strlen(length_str));
		httpClient.write(body, content_length);
	} else {
		strcat(request, "\r\n");
		httpClient.write(request, strlen(request));
	}
	return falseObj;
}

static OBJ primHttpResponse(int argCount, OBJ *args) {
	// Read some HTTP request data, if any is available, otherwise return the empty string.

	if (NO_WIFI()) return fail(noWiFi);

	uint8_t buf[800];
	int byteCount = httpClient.read(buf, 800);
	if (!byteCount) return (OBJ) &noDataString;

	OBJ result = newString(byteCount);
	if (falseObj == result) return (OBJ) &noDataString; // out of memory
	memcpy((uint8_t *) obj2str(result), buf, byteCount);
	return result;
}

// UDP

WiFiUDP udp;

static OBJ primUDPStart(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);
	if (!isConnectedToWiFi()) return falseObj;

	if (argCount < 1) return fail(notEnoughArguments);
	int port = evalInt(args[0]);
	if (port > 0) {
		udp.begin(port);
	}
	return falseObj;
}

static OBJ primUDPStop(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);
	if (!isConnectedToWiFi()) return falseObj;

	udp.stop();
	return falseObj;
}

static OBJ primUDPSendPacket(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);
	if (!isConnectedToWiFi()) return fail(wifiNotConnected);

	if (argCount < 3) return fail(notEnoughArguments);
	OBJ data = args[0];
	char* ipAddr = obj2str(args[1]);
	int port = evalInt(args[2]);
	if (port <= 0) return falseObj; // bad port number

	udp.beginPacket(ipAddr, port);
	if (isInt(data)) {
		udp.print(obj2int(data));
	} else if (isBoolean(data)) {
		udp.print((trueObj == data) ? "true" : "false");
	} else if (StringType == TYPE(data)) {
		char *s = obj2str(data);
		udp.write((uint8_t *) s, strlen(s));
	} else if (ByteArrayType == TYPE(data)) {
		udp.write((uint8_t *) &data[HEADER_WORDS], BYTES(data));
	}
	udp.endPacket();
	return falseObj;
}

static OBJ primUDPReceivePacket(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);
	if (!isConnectedToWiFi()) return (OBJ) &noDataString;

	int useBinary = ((argCount > 0) && (trueObj == args[0]));
	int byteCount = udp.parsePacket();
	if (!byteCount) return (OBJ) &noDataString;

	OBJ result = falseObj;
	if (useBinary) {
		result = newObj(ByteArrayType, (byteCount + 3) / 4, falseObj);
		if (IS_TYPE(result, ByteArrayType)) setByteCountAdjust(result, byteCount);
	} else {
		result = newString(byteCount);
	}
	if (falseObj == result) { // allocation failed
		udp.flush(); // discard packet
		result = (OBJ) &noDataString;
	} else {
		udp.read((char *) &FIELD(result, 0), byteCount);
	}
	return result;
}

static OBJ primUDPRemoteIPAddress(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);
	if (!isConnectedToWiFi()) return fail(wifiNotConnected);

	char s[100];
	IPAddress ip = udp.remoteIP();
	sprintf(s, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
	return newStringFromBytes(s, strlen(s));
}

static OBJ primUDPRemotePort(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);
	if (!isConnectedToWiFi()) return fail(wifiNotConnected);

	return int2obj(udp.remotePort());
}

// Websocket support for ESP32

#if defined(ARDUINO_ARCH_ESP32) || defined(PICO_WIFI)

#define WEBSOCKET_MAX_PAYLOAD 1024

static WebSocketsServer websocketServer = WebSocketsServer(81);
static int websocketEvtType = -1;
static int websocketClientId;
static int websocketPayloadLength;
static char websocketPayload[WEBSOCKET_MAX_PAYLOAD];

static void webSocketEventCallback(uint8_t client_id, WStype_t type, uint8_t *payload, size_t length) {
	websocketEvtType = type;
	websocketClientId = client_id;
	websocketPayloadLength = length;
	if (websocketPayloadLength > WEBSOCKET_MAX_PAYLOAD) websocketPayloadLength = WEBSOCKET_MAX_PAYLOAD;
	memcpy(websocketPayload, payload, websocketPayloadLength);
}

static OBJ primWebSocketStart(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	websocketServer.begin();
	websocketServer.onEvent(webSocketEventCallback);
	websocketEvtType = -1;
	return falseObj;
}

static OBJ primWebSocketLastEvent(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	websocketServer.loop();
	if (websocketEvtType > -1) {
		tempGCRoot = newObj(ListType, 4, zeroObj); // use tempGCRoot in case of GC
		if (!tempGCRoot) return falseObj; // allocation failed
		FIELD(tempGCRoot, 0) = int2obj(3);
		FIELD(tempGCRoot, 1) = int2obj(websocketEvtType);
		FIELD(tempGCRoot, 2) = int2obj(websocketClientId);
		if (WStype_TEXT == websocketEvtType) {
			FIELD(tempGCRoot, 3) = newStringFromBytes(websocketPayload, websocketPayloadLength);
		} else {
			int wordCount = (websocketPayloadLength + 3) / 4;
			FIELD(tempGCRoot, 3) = newObj(ByteArrayType, wordCount, falseObj);
			OBJ payload = FIELD(tempGCRoot, 3);
			if (!payload) return fail(insufficientMemoryError);
			memcpy(&FIELD(payload, 0), websocketPayload, websocketPayloadLength);
			setByteCountAdjust(payload, websocketPayloadLength);
		}
		websocketEvtType = -1;
		return tempGCRoot;
	} else {
		return falseObj;
	}
}

static OBJ primWebSocketSendToClient(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (NO_WIFI()) return fail(noWiFi);

	int clientID = obj2int(args[1]);
	if (StringType == objType(args[0])) {
		char *msg = obj2str(args[0]);
		websocketServer.sendTXT(clientID, msg, strlen(msg));
	} else if (ByteArrayType == objType(args[0])) {
		uint8_t *msg = (uint8_t *) &FIELD(args[0], 0);
		websocketServer.sendBIN(clientID, msg, BYTES(args[0]));
	}
	return falseObj;
}

#endif

#else // WiFi is not supported

void getMACAddress(uint8 *sixBytes) {
	// Store up to six bytes of unique chip ID into the argument array
	unsigned char mac[6] = {0, 0, 0, 0, 0, 0};
	#if defined(NRF51) || defined(NRF52)
		uint32 deviceID = NRF_FICR->DEVICEID[0];
		mac[5] = deviceID & 255;
		mac[4] = (deviceID >> 8) & 255;
		mac[3] = (deviceID >> 16) & 255;
		mac[2] = (deviceID >> 24) & 255;
		deviceID = NRF_FICR->DEVICEID[1];
		mac[1] = deviceID & 255;
		mac[0] = (deviceID >> 8) & 255;
	#endif
	memcpy(sixBytes, mac, 6);
}

static OBJ primHasWiFi(int argCount, OBJ *args) { return falseObj; }
static OBJ primAllowWiFiAndBLE(int argCount, OBJ *args) { return falseObj; }
static OBJ primStartWiFi(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStopWiFi(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWiFiStatus(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetIP(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primStartSSIDscan(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetSSID(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetMAC(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpServerGetRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primRespondToHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpConnect(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpIsConnected(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpRequest(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primHttpResponse(int argCount, OBJ *args) { return fail(noWiFi); }

static OBJ primUDPStart(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primUDPStop(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primUDPSendPacket(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primUDPReceivePacket(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primUDPRemoteIPAddress(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primUDPRemotePort(int argCount, OBJ *args) { return fail(noWiFi); }

#endif

#if !(defined(ARDUINO_ARCH_ESP32) || defined(PICO_WIFI))

static OBJ primWebSocketStart(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketLastEvent(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketSendToClient(int argCount, OBJ *args) { return fail(noWiFi); }

#endif

#if defined(ESP8266) || defined(ARDUINO_ARCH_ESP32) || defined(PICO_WIFI)

// MQTT support for ESP32 and ESP8266
// Code provided by Wenji Wu with help from Tom Ming

#include <MQTT.h>

static MQTTClient* pmqtt_client = NULL;
static int mqttBufferSize = -1;

static char hasMQTTMessage = false;
static char *lastMQTTTopic = NULL;
static char *lastMQTTPayload = NULL;
static int payloadByteCount = 0;

static void MQTTmessageReceived(MQTTClient *client, char *topic, char *bytes, int length) {
	// Incoming MQTT message callback.

	if (!pmqtt_client || !lastMQTTTopic || !lastMQTTPayload || (mqttBufferSize <= 1)) {
		return; // not initialized
	}

	hasMQTTMessage = true;
	payloadByteCount = 0; // default
	int maxLen = mqttBufferSize - 1;

	int len = strlen(topic);
	if (len > maxLen) len = maxLen;
	memcpy(lastMQTTTopic, topic, len);
	lastMQTTTopic[len] = '\0';

	payloadByteCount = length;
	if (payloadByteCount > (maxLen - 1)) payloadByteCount = (maxLen - 1); // leave room for terminator
	memcpy(lastMQTTPayload, bytes, payloadByteCount);
	lastMQTTPayload[payloadByteCount] = '\0'; // add string teriminator
}

static OBJ primMQTTSetWill(int argCount, OBJ *args) {
	// remix from primMQTTPub
	if (NO_WIFI()) return fail(noWiFi);

	char *topic = obj2str(args[0]);
	OBJ payloadObj = args[1];
	const char *payload;
	// int payloadByteCount = 0;
	if (IS_TYPE(payloadObj, StringType)) { // string
		payload = obj2str(payloadObj);
		// payloadByteCount = strlen(payload);
	} else if (IS_TYPE(payloadObj, ByteArrayType)) { // byte array
		payload = (char *) &FIELD(payloadObj, 0);
		// payloadByteCount = BYTES(payloadObj);
	} else if (isBoolean(payloadObj)) {
		payload = (char *) (trueObj == payloadObj) ? "true" : "false";
		// payloadByteCount = strlen(payload);
	} else if (isInt(payloadObj)) {
		char s[20];
		sprintf(s, "%d", obj2int(payloadObj));
		payload = s;
		// payloadByteCount = strlen(payload);
	} else {
		return falseObj; // must be string or byte array
	}

	int retained = (argCount > 2) && (trueObj == args[2]);
	int qos = (argCount > 3) ? obj2int(args[3]) : 0;

	// if (!pmqtt_client || !pmqtt_client->connected()) return falseObj;
	int buffer_size = (argCount > 4) ? obj2int(args[4]) : 128;

	// copy from primMQTTConnect
	if (buffer_size != mqttBufferSize) {
		if (lastMQTTTopic) free(lastMQTTTopic);
		if (lastMQTTPayload) free(lastMQTTPayload);
		lastMQTTTopic = lastMQTTPayload = NULL;

		delete pmqtt_client;
		pmqtt_client = new MQTTClient(buffer_size);
		if (!pmqtt_client) return falseObj;

		lastMQTTTopic = (char *) malloc(buffer_size);
		lastMQTTPayload = (char *) malloc(buffer_size);
		mqttBufferSize = buffer_size;
	}

	pmqtt_client->setWill(topic, payload, retained, qos);
	return trueObj;
}

static OBJ primMQTTConnect(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	char *broker_uri = obj2str(args[0]);
	int buffer_size = (argCount > 1) ? obj2int(args[1]) : 128;
	char *client_id = (argCount > 2) ? obj2str(args[2]) : (char *) "";
	char connected = false;

	// constrain the buffer size
	// Note: buffers consume 4 x buffer_size bytes of RAM
	if (buffer_size < 32) buffer_size = 32;
	if (buffer_size > 16384) buffer_size = 16384;

	if (buffer_size != mqttBufferSize) {
		if (lastMQTTTopic) free(lastMQTTTopic);
		if (lastMQTTPayload) free(lastMQTTPayload);
		lastMQTTTopic = lastMQTTPayload = NULL;

		delete pmqtt_client;
		pmqtt_client = new MQTTClient(buffer_size);
		if (!pmqtt_client) return falseObj;

		lastMQTTTopic = (char *) malloc(buffer_size);
		lastMQTTPayload = (char *) malloc(buffer_size);
		mqttBufferSize = buffer_size;
	}

	pmqtt_client->begin(broker_uri, client);
	if (argCount >= 5) {
		char *username = obj2str(args[3]);
		char *password = obj2str(args[4]);
		connected = pmqtt_client->connect(client_id, username, password);
	} else {
		connected = pmqtt_client->connect(client_id);
	}
	if (connected) {
		pmqtt_client->onMessageAdvanced(MQTTmessageReceived);
	}
	return falseObj;
}

static OBJ primMQTTIsConnected(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	if (!pmqtt_client) return falseObj;

	return (pmqtt_client->connected()) ? trueObj : falseObj;
}

static OBJ primMQTTDisconnect(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	if (!pmqtt_client) return falseObj;
	pmqtt_client->disconnect();
	return trueObj;
}

static OBJ primMQTTLastEvent(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	if (!pmqtt_client || !pmqtt_client->connected()) return falseObj;
	int useBinary = (argCount > 0) && (trueObj == args[0]);

	pmqtt_client->loop();
	if (hasMQTTMessage) {
		// allocate a result list (stored in tempGCRoot so it will be processed by the
		// garbage collector if a GC happens during a later allocation)
		tempGCRoot = newObj(ListType, 3, zeroObj);
		if (!tempGCRoot) return tempGCRoot; // allocation failed

		FIELD(tempGCRoot, 0) = int2obj(2); //list size
		FIELD(tempGCRoot, 1) = newStringFromBytes(lastMQTTTopic, strlen(lastMQTTTopic));

		if (useBinary) {
			int wordCount = (payloadByteCount + 3) / 4;
			OBJ payload = newObj(ByteArrayType, wordCount, falseObj);
			if (!payload) return fail(insufficientMemoryError);
			memcpy(&FIELD(payload, 0), lastMQTTPayload, payloadByteCount);
			setByteCountAdjust(payload, payloadByteCount);
			FIELD(tempGCRoot, 2) = payload;
		} else {
			FIELD(tempGCRoot, 2) = newStringFromBytes(lastMQTTPayload, strlen(lastMQTTPayload));
		}

		hasMQTTMessage = false;
		return tempGCRoot;
	} else {
		return falseObj;
	}
}

static OBJ primMQTTPub(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	if (!pmqtt_client || !pmqtt_client->connected()) return falseObj;

	char *topic = obj2str(args[0]);
	OBJ payloadObj = args[1];
	const char *payload;
	int payloadByteCount = 0;
	if (IS_TYPE(payloadObj, StringType)) { // string
		payload = obj2str(payloadObj);
		payloadByteCount = strlen(payload);
	} else if (IS_TYPE(payloadObj, ByteArrayType)) { // byte array
		payload = (char *) &FIELD(payloadObj, 0);
		payloadByteCount = BYTES(payloadObj);
	} else if (isBoolean(payloadObj)) {
		payload = (char *) (trueObj == payloadObj) ? "true" : "false";
		payloadByteCount = strlen(payload);
	} else if (isInt(payloadObj)) {
		char s[20];
		sprintf(s, "%d", obj2int(payloadObj));
		payload = s;
		payloadByteCount = strlen(payload);
	} else {
		return falseObj; // must be string or byte array
	}

	int retained = (argCount > 2) && (trueObj == args[2]);
	int qos = (argCount > 3) ? obj2int(args[3]) : 0;
	int success = pmqtt_client->publish(topic, payload, payloadByteCount, retained, qos);
	return success ? trueObj : falseObj;
}

static OBJ primMQTTSub(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	if (!pmqtt_client || !pmqtt_client->connected()) return falseObj;

	char *topic = obj2str(args[0]);
	int qos = (argCount > 1) ? obj2int(args[1]) : 0;
	int success = pmqtt_client->subscribe(topic, qos);
	return success ? trueObj : falseObj;
}

static OBJ primMQTTUnsub(int argCount, OBJ *args) {
	if (NO_WIFI()) return fail(noWiFi);

	if (!pmqtt_client || !pmqtt_client->connected()) return falseObj;

	char *topic = obj2str(args[0]);
	int success = pmqtt_client->unsubscribe(topic);
	return success ? trueObj : falseObj;
}

#else

static OBJ primMQTTSetWill(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTConnect(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTIsConnected(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTDisconnect(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTLastEvent(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTPub(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTSub(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primMQTTUnsub(int argCount, OBJ *args) { return fail(noWiFi); }

#endif

// Experimental! Optional BLE support (compile with -D BLE_PRIMS)
// Code provided by Wenji Wu

#if defined(BLE_PRIMS)

//https://registry.platformio.org/libraries/nkolban/ESP32%20BLE%20Arduino/examples/BLE_uart/BLE_uart.ino
// client debug: chrome://bluetooth-internals/
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
static bool BLEServerStarted = false;
BLEServer *pServer = NULL;
BLECharacteristic * pTxCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;
uint8_t txValue = 0;
static char lastBLE_UART_Message[1000];
static bool hasBLE_UART_Message = false;

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" // UART service UUID
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string rxValue = pCharacteristic->getValue();

	  if (rxValue.length() > 0) {
		hasBLE_UART_Message = true;
		int len = strlen(rxValue.c_str());
		if (len > 999) len = 999;
		memcpy(lastBLE_UART_Message, rxValue.c_str(), len);
	  	lastBLE_UART_Message[len] = '\0';
		// char s[100]; sprintf(s, "lastBLE_UART_Message:  %s", lastBLE_UART_Message); outputString(s);
      }
    }
};


static OBJ primBLE_UART_ServerStart(int argCount, OBJ *args) {
  //Serial.begin(115200);
  char* name = obj2str(args[0]);

  if (BLEServerStarted) {
	return falseObj;
  }

  BLEServerStarted = true;
  // Create the BLE Device
  BLEDevice::init(name);

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create a BLE Characteristic
  pTxCharacteristic = pService->createCharacteristic(
										CHARACTERISTIC_UUID_TX,
										BLECharacteristic::PROPERTY_NOTIFY
									);

  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic * pRxCharacteristic = pService->createCharacteristic(
											 CHARACTERISTIC_UUID_RX,
											BLECharacteristic::PROPERTY_WRITE
										);

  pRxCharacteristic->setCallbacks(new MyCallbacks());

  // Start the service
  pService->start();

  // Start advertising
  pServer->getAdvertising()->start();
  outputString("Waiting a client connection...");
  // char s[100]; sprintf(s, "rxValue:  %s", rxValue); outputString(s);
  //Serial.println("Waiting a client connection to notify...");

  return falseObj;
}

static OBJ primStartAdvertisingAndReconnectLoop(int argCount, OBJ *args) {
	// disconnecting
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // give the bluetooth stack the chance to get things ready
        pServer->startAdvertising(); // restart advertising
        // Serial.println("start advertising");
        oldDeviceConnected = deviceConnected;
    }
    // connecting
    if (deviceConnected && !oldDeviceConnected) {
		// do stuff here on connecting
        oldDeviceConnected = deviceConnected;
    }
	return falseObj;
}

static OBJ primBLE_DeviceConnected(int argCount, OBJ *args) {
	return deviceConnected ? trueObj : falseObj;
}

static OBJ primBLE_UART_LastEvent(int argCount, OBJ *args) {
	if (hasBLE_UART_Message == true) {
		OBJ event = newObj(ListType, 2, zeroObj);
		FIELD(event, 0) = int2obj(1); //list size
		FIELD(event, 1) = newStringFromBytes(lastBLE_UART_Message, strlen(lastBLE_UART_Message));
		hasBLE_UART_Message = false;
		return event;
	} else {
		return falseObj;
	}
}

static OBJ primBLE_UART_Write(int argCount, OBJ *args) {
	char* message = obj2str(args[0]);
	pTxCharacteristic->setValue(message);
    pTxCharacteristic->notify();
	delay(10); // bluetooth stack will go into congestion, if too many packets are sent
	return falseObj;
}

static OBJ primBLE_UART_ServerStop(int argCount, OBJ *args)
{
	BLEDevice::stopAdvertising();
	BLEDevice::deinit(false);
	BLEServerStarted = false;
	return falseObj;
}

#endif // BLE_PRIMS

#if defined(OCTO_PRIMS)
/*
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEAdvertisedDevice.h>
*/
#include <NimBLEDevice.h>
#include <NimBLEServer.h>
#include <NimBLEAdvertisedDevice.h>
#include <set>
#include <string>

BLEServer* pServer = NULL;
BLEAdvertising* pAdvertising = NULL;
BLEScan* pBLEScan;
bool BLEScanning = false;

const char* octoUUIDs[] = {
  "2540b6b0-0002-4538-bcd7-7ecfb51297c1", // iOS
  "2540b6b0-0001-4538-bcd7-7ecfb51297c1" // Android
};
int shape_id;
int scanTime=1; // Compared with 5, 1 can improve the response speed of iPhone OctoStudio
bool hasOctoMessage = false;
std::set<std::string> receivedOctoDatas;
int receivedOctoDatasMaxLength = 100;
// static char OctoLastMessage[20];

static OBJ primOctoGetBLEInitialized(int argCount, OBJ *args) {
  if (BLEDevice::getInitialized()) {
	return trueObj;
  } else {
	return falseObj;
  }
}


class OctoAdvertisedDeviceCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice* advertisedDevice) {
    if (advertisedDevice->haveServiceUUID()) {
      // iOS
      BLEUUID serviceUUID = advertisedDevice->getServiceUUID();
      std::string UUID_string = serviceUUID.toString().c_str();
      if (UUID_string == octoUUIDs[0]) {
        std::string deviceName = advertisedDevice->getName();
		if ((deviceName != "0000000000000000") && (receivedOctoDatas.find(deviceName) == receivedOctoDatas.end())) {
			shape_id = deviceName.back() - '0';
			hasOctoMessage = true;
			receivedOctoDatas.insert(deviceName);
			if (receivedOctoDatas.size() > receivedOctoDatasMaxLength) {receivedOctoDatas.erase(receivedOctoDatas.begin());};
        }
      }
    }

    if (advertisedDevice->haveServiceData()) {
      // Android
      std::string serviceData = advertisedDevice->getServiceData();
      BLEUUID serviceUUID = advertisedDevice->getServiceDataUUID();
      std::string UUID_string = serviceUUID.toString().c_str();
      if (UUID_string == octoUUIDs[1]) {
		if (receivedOctoDatas.find(serviceData) == receivedOctoDatas.end()) {
			shape_id = serviceData[7];
			hasOctoMessage = true;
			receivedOctoDatas.insert(serviceData);
			if (receivedOctoDatas.size() > receivedOctoDatasMaxLength) {receivedOctoDatas.erase(receivedOctoDatas.begin());};
        }
      }
    }
  }
};

static OBJ primOctoInitBLE(int argCount, OBJ *args) {
  outputString("primInitBLE...");
  BLEDevice::init("MicroBlocks OctoStudio");

  pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new OctoAdvertisedDeviceCallbacks());
  pBLEScan->setActiveScan(true); //active scan uses more power, but get results faster
  pBLEScan->setInterval(100);
  pBLEScan->setWindow(99);  // less or equal setInterval value

  pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(BLEUUID(octoUUIDs[0]));
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections issue
  receivedOctoDatas.clear();

  return falseObj;
}

static OBJ primOctoDeinitBLE(int argCount, OBJ *args) {
	receivedOctoDatas.clear();
	BLEDevice::deinit(false);
	return falseObj;
}

static OBJ primOctoSetDeviceName(int argCount, OBJ *args) {
  // Mimic iOS
  uint8 *DeviceNam = (uint8 *) &FIELD(args[0], 0);
  pAdvertising->setName((char*)DeviceNam);
  return falseObj;
}

static OBJ primOctoStartAdvertising(int argCount, OBJ *args) {
	pAdvertising->start();
	return falseObj;
}

static OBJ primOctoStopAdvertising(int argCount, OBJ *args) {
	pAdvertising->stop();
	return falseObj;
}

static OBJ primOctoGetOctoShapeId(int argCount, OBJ *args) {
	if (hasOctoMessage) {
		hasOctoMessage = false;
		return int2obj(shape_id);
	} else {
		return falseObj;
	}
}

void EndofBLEScan(BLEScanResults scanResults) {
	outputString("EndofBLEScan, restart...");
	pBLEScan->clearResults();
	if (BLEScanning){
		pBLEScan->start(scanTime, EndofBLEScan, false);
	}
    
}

static OBJ primOctoStartScanning(int argCount, OBJ *args) {
	BLEScanning = true;
	pBLEScan->start(scanTime, EndofBLEScan, false);
	return falseObj;
}

static OBJ primOctoStopScanning(int argCount, OBJ *args) {
  outputString("primOctoStopScanning");
  pBLEScan->stop(); // NimBLE: not working
  BLEScanning = false;
  pBLEScan->clearResults();
  return falseObj;
}

static OBJ primOctoScanning(int argCount, OBJ *args) {
  if (BLEScanning) {
	return trueObj;
  } else {
	return falseObj;
  }
}

#endif // OCTO_PRIMS

// Experimental! Optional ESP Now support (compile with -D ESP_NOW_PRIMS)
// Code provided by Wenji Wu

#if defined(ESP_NOW_PRIMS)
//https://registry.platformio.org/libraries/yoursunny/WifiEspNow/examples/EspNowBroadcast/EspNowBroadcast.ino

#include <WifiEspNowBroadcast.h>

static char receiveBuffer[1000];
static bool EspNoWInitialized = false;
static bool hasEspNowMessage = false;

static void processRx(const uint8_t mac[WIFIESPNOW_ALEN], const uint8_t* buf, size_t count, void* arg) {
	char* data = (char*) buf;
	int len = strlen(data);
	if (len > 999) len = 999;
	memcpy(receiveBuffer, data, len);
	receiveBuffer[len] = '\0';
  	hasEspNowMessage = true;
}

static void initializeEspNoW() {
	if (EspNoWInitialized) return;

	WiFi.persistent(false);
 	bool ok = WifiEspNowBroadcast.begin("ESPNOW", 3);
  	if (!ok) {
		// outputString("WifiEspNowBroadcast.begin() failed");
    	ESP.restart();
 	 }
	// outputString("WifiEspNowBroadcast.begin() success");
	WifiEspNowBroadcast.onReceive(processRx, nullptr);
	EspNoWInitialized = true;
}

static OBJ primEspNowLastEvent(int argCount, OBJ *args) {
	if (!EspNoWInitialized) initializeEspNoW();

	WifiEspNowBroadcast.loop();
	delay(10);

	if (hasEspNowMessage) {
		OBJ event = newObj(ListType, 2, zeroObj);
		FIELD(event, 0) = int2obj(1); //list size
		FIELD(event, 1) = newStringFromBytes(receiveBuffer, strlen(receiveBuffer));
		hasEspNowMessage = false;
		return event;
	} else {
		return falseObj;
	}
}

static OBJ primEspNowBroadcast(int argCount, OBJ *args) {
	if (!EspNoWInitialized) initializeEspNoW();

	char* message = obj2str(args[0]);
	WifiEspNowBroadcast.send(reinterpret_cast<const uint8_t*>(message), strlen(message));
	WifiEspNowBroadcast.loop();
	return falseObj;
}

#endif // ESP_NOW_PRIMS

static PrimEntry entries[] = {
	{"hasWiFi", primHasWiFi},
	{"allowWiFiAndBLE", primAllowWiFiAndBLE},
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

	{"udpStart", primUDPStart},
	{"udpStop", primUDPStop},
	{"udpSendPacket", primUDPSendPacket},
	{"udpReceivePacket", primUDPReceivePacket},
	{"udpRemoteIPAddress", primUDPRemoteIPAddress},
	{"udpRemotePort", primUDPRemotePort},

	{"webSocketStart", primWebSocketStart},
	{"webSocketLastEvent", primWebSocketLastEvent},
	{"webSocketSendToClient", primWebSocketSendToClient},

	{"MQTTConnect", primMQTTConnect},
	{"MQTTIsConnected", primMQTTIsConnected},
	{"MQTTDisconnect", primMQTTDisconnect},
	{"MQTTLastEvent", primMQTTLastEvent},
	{"MQTTPub", primMQTTPub},
	{"MQTTSetWill", primMQTTSetWill},
	{"MQTTSub", primMQTTSub},
	{"MQTTUnsub", primMQTTUnsub},

  #if defined(BLE_PRIMS)
	{"BLE_UART_ServerStart", primBLE_UART_ServerStart},
	{"BLE_UART_ServerStop", primBLE_UART_ServerStop},
	{"BLE_DeviceConnected", primBLE_DeviceConnected},
	{"BLE_UART_LastEvent", primBLE_UART_LastEvent},
	{"BLE_UART_Write", primBLE_UART_Write},
	{"StartAdvertisingAndReconnectLoop", primStartAdvertisingAndReconnectLoop},
  #endif

  #if defined(OCTO_PRIMS)
	{"OctoGetBLEInitialized", primOctoGetBLEInitialized},
	{"OctoInitBLE", primOctoInitBLE},
	{"OctoDeinitBLE", primOctoDeinitBLE},
	{"OctoStartAdvertising", primOctoStartAdvertising},
	{"OctoStopAdvertising", primOctoStopAdvertising},
	{"OctoStartScanning", primOctoStartScanning},
	{"OctoStopScanning", primOctoStopScanning},
	{"OctoScanning", primOctoScanning},
	
	{"OctoSetDeviceName", primOctoSetDeviceName},
	{"OctoGetOctoShapeId", primOctoGetOctoShapeId},
  #endif

  #if defined(ESP_NOW_PRIMS)
	{"EspNowLastEvent", primEspNowLastEvent},
	{"EspNowBroadcast", primEspNowBroadcast},
  #endif

};

void addNetPrims() {
	addPrimitiveSet(NetPrims, "net", sizeof(entries) / sizeof(PrimEntry), entries);
}
