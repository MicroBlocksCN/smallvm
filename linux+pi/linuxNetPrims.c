/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// netPrims.cpp - MicroBlocks network primitives
// Bernat Romagosa, August 2018
// Revised by John Maloney, November 2018
// Revised by Bernat Romagosa & John Maloney, March 2020
// Adapted to Linux VM by Bernat Romagosa, February 2021

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "mem.h"
#include "tinyJSON.h"
#include "interp.h"

#include <ifaddrs.h>
#include <arpa/inet.h>
#include <sys/socket.h>

//#include <sys/types.h>

//#include <netinet/in.h>
//#include <netdb.h>

// These primitives make no sense in a Linux system, since the connection is
// handled at the operating system level, but we're simulating them to ensure
// compatibility with microcontrollers

char connected = 0;

static OBJ primHasWiFi(int argCount, OBJ *args) { return trueObj; }

static OBJ primStartWiFi(int argCount, OBJ *args) {
	connected = 1;
	return trueObj;
}

static OBJ primStopWiFi(int argCount, OBJ *args) {
	connected = 0;
	return trueObj;
}

static OBJ primWiFiStatus(int argCount, OBJ *args) {
	OBJ result;
	if (connected) {
		result = newString(9);
		memcpy(obj2str(result), "Connected", 9);
	} else {
		result = newString(13);
		memcpy(obj2str(result), "Not connected", 13);
	}
	return result;
}

static OBJ primGetIP(int argCount, OBJ *args) {
	OBJ result = newString(16);
	char ip[16];
    struct ifaddrs *address, *each;

	if (!connected || getifaddrs(&address) == -1) {
		memcpy(obj2str(result), "0.0.0.0", 7);
	} else {
		for (each = address; each != NULL; each = each->ifa_next) {
			// iterate until we find an iface different than "lo" with an address
			if ((each->ifa_addr != NULL) &&
					(strcmp(each->ifa_name, "lo") != 0) &&
					(each->ifa_addr->sa_family == AF_INET)) {
				sprintf(ip, "%s", inet_ntoa(((struct sockaddr_in *)each->ifa_addr)->sin_addr));
				memcpy(obj2str(result), ip, strlen(ip));
				break;
			}
		}
		freeifaddrs(address);
	}

	return result;
}

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) { return falseObj; }
static OBJ primRespondToHttpRequest(int argCount, OBJ *args) { return falseObj; }

// HTTP Client

int clientSocket = 0;

static OBJ primHttpConnect(int argCount, OBJ *args) {
	char* host = obj2str(args[0]);
	int port = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 80;

	if (clientSocket) shutdown(clientSocket, 2);

	clientSocket = socket(AF_INET, SOCK_STREAM, 0);	
	struct sockaddr_in remoteAddress;

	memset(&remoteAddress, '0', sizeof(remoteAddress));

	remoteAddress.sin_family = AF_INET;
	remoteAddress.sin_port = htons(port);
	remoteAddress.sin_addr.s_addr = inet_addr(host);

	if (inet_pton(AF_INET, host, &remoteAddress.sin_addr) <= 0) {
		shutdown(clientSocket, 2);
		clientSocket = 0;
		return falseObj;
	}

	int connectResult = connect(
			clientSocket,
			(struct sockaddr *)&remoteAddress,
			sizeof(remoteAddress));

	if (connectResult < 0) {
		shutdown(clientSocket, 2);
		clientSocket = 0;
	}

	processMessage(); // process messages now
	return falseObj;
}

char httpClientConnected() {
	// TODO we're not detecting when the server closes the connection
	int error = 0;
	socklen_t len = sizeof (error);
	int retval = getsockopt(clientSocket, SOL_SOCKET, SO_ERROR, &error, &len);
	return ((clientSocket > 0) && (retval == 0) && (error == 0));
}

static OBJ primHttpIsConnected(int argCount, OBJ *args) {
	return httpClientConnected() ? trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	// Send an HTTP request. Must have first connected to the server.

	if (!httpClientConnected()) return falseObj;

	char* reqType = obj2str(args[0]);
	char* host = obj2str(args[1]);
	char* path = obj2str(args[2]);
	char request[1024];
	sprintf(request,
			"%s /%s HTTP/1.0\r\n\
			Host: %s\r\n\
			Connection: close\r\n\
			User-Agent: MicroBlocks\r\n\
			Accept: */*\r\n",
			reqType,
			path,
			host);

	write(clientSocket, request, strlen(request));

	if ((argCount > 3) && IS_TYPE(args[3], StringType)) {
		char length_str[50];
		char* body = obj2str(args[3]);
		int content_length = strlen(body);
		write(clientSocket, "Content-Type: text/plain\r\n", 26);
		sprintf(length_str, "Content-Length: %i\r\n\r\n", content_length);
		write(clientSocket, length_str, strlen(length_str));
		write(clientSocket, body, content_length);
	} else {
		write(clientSocket, "\r\n", 2);
	}

	return falseObj;
}

static OBJ primHttpResponse(int argCount, OBJ *args) {
	// Read some HTTP request data, if any is available, otherwise return the empty string.
	OBJ response;
	char buffer[800];
	int n, byteCount = 0;

	while ((n = (read(clientSocket, buffer, 64))) > 0 && byteCount <= 800) {
		buffer[n] = '\0';
		byteCount += n;
		processMessage(); // process messages now
	}
	response = newString(byteCount);
	memcpy(obj2str(response), buffer, byteCount > 800 ? 800 : byteCount);
	return response;
}

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
