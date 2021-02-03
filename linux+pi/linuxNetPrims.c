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

#include "mem.h"
#include "tinyJSON.h"
#include "interp.h"

#include <ifaddrs.h>
#include <arpa/inet.h>

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
	}

    freeifaddrs(address);
	return result;
}

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) { return falseObj; }
static OBJ primRespondToHttpRequest(int argCount, OBJ *args) { return falseObj; }
static OBJ primHttpConnect(int argCount, OBJ *args) { return falseObj; }
static OBJ primHttpIsConnected(int argCount, OBJ *args) { return falseObj; }
static OBJ primHttpRequest(int argCount, OBJ *args) { return falseObj; }
static OBJ primHttpResponse(int argCount, OBJ *args) { return falseObj; }

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
