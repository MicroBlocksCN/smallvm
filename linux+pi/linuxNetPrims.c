/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxNetPrims.c - MicroBlocks network primitives
// Bernat Romagosa, August 2018
// Revised by John Maloney, November 2018
// Revised by Bernat Romagosa & John Maloney, March 2020
// Adapted to Linux VM by Bernat Romagosa, February 2021

#define _XOPEN_SOURCE 500
#define _POSIX_C_SOURCE 200112L
#define _DEFAULT_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "mem.h"
#include "tinyJSON.h"
#include "interp.h"

#include <ifaddrs.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/tcp.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/errno.h>
#include <time.h>


// These primitives make no sense in a Linux system, since the connection is
// handled at the operating system level, but we're simulating them to ensure
// compatibility with microcontrollers

char connected = 0;
static char serverStarted = false;

int clientSocket = -1;
int serverSocket = -1;
int serverRequestSocket = -1; // Client currently connected to the server.
int serverPort = 8080; // Default port. Can be changed on a request basis.

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
	OBJ result = newString(0);
	char ip[16];
    struct ifaddrs *address, *each;

	if (!connected || getifaddrs(&address) == -1) {
		result = newString(7);
		memcpy(obj2str(result), "0.0.0.0", 7);
	} else {
		for (each = address; each != NULL; each = each->ifa_next) {
			// iterate until we find an iface different than "lo" with an address
			if ((each->ifa_addr != NULL) &&
					(strcmp(each->ifa_name, "lo") != 0) &&
					(each->ifa_addr->sa_family == AF_INET)) {
				sprintf(ip, "%s", inet_ntoa(((struct sockaddr_in *)each->ifa_addr)->sin_addr));
				result = newString(strlen(ip));
				memcpy(obj2str(result), ip, strlen(ip));
				break;
			}
		}
		freeifaddrs(address);
	}

	return result;
}

static void macAddressForInterface(const char* interfaceName, unsigned char* macAddr) {
	struct ifreq ifinfo;
	memset(macAddr, 0, 6); // clear result

	int sd = socket(AF_INET, SOCK_DGRAM, 0);
	if (sd < 0) return; // failed to create socket

	// use ioctl on the socket to get the MAC address of the given interface
	strcpy(ifinfo.ifr_name, interfaceName);
	int err = ioctl(sd, SIOCGIFHWADDR, &ifinfo);
	if (err) printf("ioctl error: %s\n", strerror(errno));
	close(sd);

	// if successful, copy the MAC address into the result
	if (!err && (ifinfo.ifr_hwaddr.sa_family == 1)) {
		memcpy(macAddr, ifinfo.ifr_hwaddr.sa_data, IFHWADDRLEN);
	}
}

static OBJ primGetMAC(int argCount, OBJ *args) {
	OBJ result = newString(17);
	char addressString[18] = "00:00:00:00:00:00\0";
	unsigned char macAddr[IFHWADDRLEN] = {0,0,0,0,0,0};

	struct ifaddrs *ifaddrList;

	if (!getifaddrs(&ifaddrList)) {
		for (struct ifaddrs *ifa = ifaddrList; ifa != NULL; ifa = ifa->ifa_next) {
			if (ifa->ifa_addr == NULL) continue;

			int family = ifa->ifa_addr->sa_family;
			int isLoopback = (strstr(ifa->ifa_name, "lo") != NULL);
			if ((family == AF_INET) && !isLoopback) {
				macAddressForInterface(ifa->ifa_name, macAddr);
				sprintf(addressString, "%X:%X:%X:%X:%X:%X",
						macAddr[0], macAddr[1], macAddr[2], macAddr[3], macAddr[4], macAddr[5]);
				break;
			}
		}
		freeifaddrs(ifaddrList);
	}

	memcpy(obj2str(result), addressString, 17);
	return result;
}

// Socket utils

static void setNonBlocking(int socket) {
	sigignore(SIGPIPE); // prevent program from terminating when attempting to write to a closed socket
	fcntl(socket, F_SETFL, SOCK_NONBLOCK); // make non-blocking
}

char socketConnected(int socket) {
	char buf[1];
	int n = recv(socket, (void *) buf, 1, MSG_PEEK);
	return (n > 0) || ((n < 0) && (errno == EWOULDBLOCK));
}

// HTTP Server

static void closeServerSocket() {
	shutdown(serverSocket, SHUT_RDWR);
	close(serverSocket);
	serverSocket = -1;
	serverStarted = false;
}

static int openServerSocket() {
	// Return a non-blocking server socket on the given port, or -1 if failed.

	int serverSocket = socket(AF_INET, SOCK_STREAM, 0);

	if (serverSocket < 0) { return -1; }

	setNonBlocking(serverSocket);

	// allow the server to reuse the port immediately if this program is restarted, even
	// though the old server socket stays around in a timeout state for about four minutes
	int flag = 1;
	setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, (void *) &flag, sizeof(flag));

	// bind the server socket to our port
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET; // IPv4
	addr.sin_port = htons(serverPort);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if (bind(serverSocket, (struct sockaddr*) &addr, sizeof(addr)) >= 0) {
		listen(serverSocket, 10); // queue length = 10 (probably overkill)
	} else {
		closeServerSocket();
	}
	return serverSocket;
}

static void startHttpServer() {
	// Start the server the first time and *never* stop/close it, unless the
	// port changes
	if (!serverStarted) {
		// Start the server
		serverSocket = openServerSocket();
		serverStarted = (serverSocket > -1);
	}
}

static void acceptConnection() {
	// Attempt to accept an incoming connection on the given server socket.
	// If successful, return the socket for the new connect, otherwise return -1.

	if (serverSocket > -1) {
		struct sockaddr_in clientAddr;
		socklen_t size = sizeof(clientAddr);

		serverRequestSocket = accept(serverSocket, (void *) &clientAddr, &size);
		if (serverRequestSocket >= 0) {
			setNonBlocking(serverRequestSocket);
			// transmit data immediately (i.e. don't use the Nagle algorithm)
			int flag = 1;
			setsockopt(serverRequestSocket, IPPROTO_TCP, TCP_NODELAY, (void *) &flag, sizeof(flag));
		}
	}
}

static int serverHasClient() {
	// Return true when the HTTP server has a client and the client is connected.
	// Continue to return true if any data is available from the client even if the client
	// has closed the connection. Start the HTTP server the first time this is called.

	if (!serverStarted) startHttpServer();
	if (-1 == serverRequestSocket) acceptConnection();

	return (serverRequestSocket > -1);
}

static OBJ primHttpServerGetRequest(int argCount, OBJ *args) {
	// Return some data from the current HTTP request. Return the empty string if no
	// data is available. If there isn't currently a client connection, and a client
	// is waiting, accept the new connection. If the optional first argument is true,
	// return a ByteArray (binary data) instead of a string. The optional second arg
	// can specify a port. Changing ports stops and restarts the server.
	// Fail if there isn't enough memory to allocate the result object.

	int useBinary = ((argCount > 0) && (trueObj == args[0]));
	if (argCount > 1) {
		int port = obj2int(args[1]);
		// If we're changing port, stop the server. It will be restarted further
		// down by serverHasClient()
		if (port != serverPort) {
			serverPort = port;
			if (serverSocket > -1) closeServerSocket();
		}
	}

	OBJ result = useBinary ? newObj(ByteArrayType, 0, falseObj) : newString(0);

	if (serverHasClient() && socketConnected(serverRequestSocket)) {
		char buf[800];
		int byteCount = recv(serverRequestSocket, buf, 800, 0);
		if (byteCount > 0) {
			if (useBinary) {
				result = newObj(ByteArrayType, (byteCount + 3) / 4, falseObj);
				memcpy(&FIELD(result, 0), buf, byteCount);
			} else {
				result = newString(byteCount);
				memcpy(obj2str(result), buf, byteCount);
			}
		}
	}

	return result;
}

static OBJ primRespondToHttpRequest(int argCount, OBJ *args) {
	// Send a response to the client with the status. optional extra headers, and optional body.
	char response[8096];

	if (serverRequestSocket < 0) return falseObj;

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
	sprintf(response, "HTTP/1.0 %s\r\n", status);
	strcat(response, "Access-Control-Allow-Origin: *\r\n");
	strcat(response, "Access-Control-Allow-Methods: *\r\n");
	if (keepAlive) strcat(response, "Connection: keep-alive\r\n");
	if (extraHeaders) {
		strcat(response, extraHeaders);
		if (10 != extraHeaders[strlen(extraHeaders) - 1]) {
			strcat(response, "\r\n");
		}
	}
	if (contentLength >= 0) {
		char contentLenghtHeader[100];
		sprintf(contentLenghtHeader, "Content-Length: %d", contentLength);
		strcat(response, contentLenghtHeader);
	}
	strcat(response, "\r\n\r\n"); // end of headers

	int byteCount = strlen(response);

	// send body, if any
	if (argCount > 1) {
		if (IS_TYPE(args[1], StringType)) {
			char *body = obj2str(args[1]);
			strcat(response, body);
			byteCount += strlen(body);
		} else if (IS_TYPE(args[1], ByteArrayType)) {
			uint8 *body = (uint8 *) &FIELD(args[1], 0);
			memcpy(&response[strlen(response)], body, BYTES(args[1]));
			byteCount += BYTES(args[1]);
		}
	}

	send(serverRequestSocket, response, byteCount, 0);

	if (!keepAlive) {
		close(serverRequestSocket);
		serverRequestSocket = -1;
	}

	return falseObj;
}

// HTTP Client

static int lookupHost(char *hostName, struct sockaddr_in *result) {
	// Convert the given host name (or ip address) to a socket address. Return zero if successful.
	struct addrinfo *info;
	int err = getaddrinfo(hostName, NULL, NULL, &info);
	if (!err) {
		*result = *((struct sockaddr_in *) info->ai_addr);
		freeaddrinfo(info);
	}
	return err;
}

static OBJ primHttpConnect(int argCount, OBJ *args) {
	char* host = obj2str(args[0]);
	int port = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 80;

	if (clientSocket > -1) shutdown(clientSocket, 2);

	struct sockaddr_in remoteAddress;

	memset(&remoteAddress, '0', sizeof(remoteAddress));

	if (lookupHost(host, &remoteAddress) != 0) {
		shutdown(clientSocket, 2);
		clientSocket = -1;
		return falseObj;
	}

	remoteAddress.sin_port = htons(port);

	clientSocket = socket(AF_INET, SOCK_STREAM, 0);

	int connectResult = connect(
			clientSocket,
			(struct sockaddr *)&remoteAddress,
			sizeof(remoteAddress));

	if (connectResult < 0) {
		shutdown(clientSocket, 2);
		clientSocket = 0;
	}

	setNonBlocking(clientSocket);

	int flag = 1;
	setsockopt(clientSocket, IPPROTO_TCP, TCP_NODELAY, (void *) &flag, sizeof(flag));

	processMessage(); // process messages now
	return falseObj;
}


static OBJ primHttpIsConnected(int argCount, OBJ *args) {
	return socketConnected(clientSocket) ? trueObj : falseObj;
}

static OBJ primHttpRequest(int argCount, OBJ *args) {
	// Send an HTTP request. Must have first connected to the server.

	if (clientSocket < 0) return falseObj;

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

	while ((byteCount < (799 - 64)) && (n = (read(clientSocket, &buffer[byteCount], 64))) > 0) {
		byteCount += n;
		processMessage(); // process messages now
	}
	buffer[byteCount] = '\0';
	response = newString(byteCount);
	memcpy(obj2str(response), buffer, byteCount);
	return response;
}

// Not yet implemented

static OBJ primStartSSIDscan(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primGetSSID(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketStart(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketLastEvent(int argCount, OBJ *args) { return fail(noWiFi); }
static OBJ primWebSocketSendToClient(int argCount, OBJ *args) { return fail(noWiFi); }

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
