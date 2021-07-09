// socketPrims.c
// John Maloney, April 2014

#ifdef _WIN32

// enable winwock2 calls:
#define _WIN32_WINNT 0x0501

// Note: winsock2.h must be included before windows.h
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>

#define EWOULDBLOCK WSAEWOULDBLOCK
#define EAGAIN WSAEWOULDBLOCK
#define SHUT_RDWR SD_BOTH

// Winsock2 state
WSADATA wsaData;

#else

#define _XOPEN_SOURCE 500
#define _POSIX_C_SOURCE 200112L

#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <sys/socket.h>

#endif // _WIN32

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "mem.h"
#include "interp.h"

#define BUF_SIZE 10000
#define NAME_SIZE 1000

// ***** Variables *****

static int initialized = false;

// ***** Helper Primitives *****

static void init() {
	if (initialized) return;
  #ifdef _WIN32
	int err = WSAStartup(MAKEWORD(2, 2), &wsaData);
	if (err) {
		printf("WSAStartup failed: %d\n", err);
		return;
	}
  #endif
	initialized = true;
}

static void setNonBlocking(int socket) {
  #ifdef _WIN32
	unsigned long flag = true;
	ioctlsocket(socket, FIONBIO, &flag);
  #else
	sigignore(SIGPIPE); // prevent program from terminating when attempting to write to a closed socket
	fcntl(socket, F_SETFL, O_NONBLOCK); // make non-blocking
  #endif
}

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

static int openClientSocket(char *hostName, int portNum) {
	// Return a non-blocking client socket on the given port of the given host, or -1 if not successful.
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));

	if (!initialized) init();

	int err = lookupHost(hostName, &addr);
	if (err) {
		printf("Error: Unknown host %s\n", hostName);
		return -1;
	}
	addr.sin_port = htons(portNum);
	int clientSocket = socket(AF_INET, SOCK_STREAM, 0);
	if (connect(clientSocket, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
		printf("Error: Could not connect to %s:%d\n", hostName, portNum);
		return -1;
	}
	setNonBlocking(clientSocket);

	// transmit data immediately (i.e. don't use the Nagle algorithm)
	int flag = 1;
	setsockopt(clientSocket, IPPROTO_TCP, TCP_NODELAY, (void *) &flag, sizeof(flag));

	return clientSocket;
}

static int openServerSocket(int portNum) {
	// Return a non-blocking server socket on the given port, or -1 if failed.

	if (!initialized) init();

	int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
	if (serverSocket < 0) {
		printf("Error: Could not create server socket\n");
		return -1;
	}
	setNonBlocking(serverSocket);

	// allow the server to reuse the port immediately if this program is restarted, even
	// though the old server socket stays around in a timeout state for about four minutes
	int flag = 1;
	setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, (void *) &flag, sizeof(flag));

	// bind the server socket to our port
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET; // IPv4
	addr.sin_port = htons(portNum);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if (bind(serverSocket, (struct sockaddr*) &addr, sizeof(addr)) >= 0) {
		listen(serverSocket, 10); // queue length = 10 (probably overkill)
	} else {
		printf("Error: Could not bind server socket; port may be in use\n");
		shutdown(serverSocket, SHUT_RDWR);
		close(serverSocket);
		serverSocket = -1;
	}
	return serverSocket;
}

static int socketHasData(int s) {
	// Return 1 if the socket has data available, 0 if it waiting for data,
	// and -1 if the connection has been shutdown normally or aborted.

	char buf[1];
	int n = recv(s, (void *) buf, 1, MSG_PEEK);
	if (n > 0) return 1; // data available
	if (n == 0) return -1; // normal shutdown
  #ifdef _WIN32
	errno = WSAGetLastError();
  #endif
	if ((n < 0) && (errno == EWOULDBLOCK)) return 0; // no data, but socket is still open
	return -1;	// error
}

static int acceptConnection(int serverSocket) {
	// Attempt to accept an incoming connection on the given server socket.
	// If successful, return the socket for the new connect, otherwise return -1.

	if (serverSocket < 0) return -1;

	struct sockaddr_in clientAddr;
	socklen_t size = sizeof(clientAddr);

	int newSocket = accept(serverSocket, (void *) &clientAddr, &size);
	if (newSocket >= 0) {
		setNonBlocking(newSocket);
		// transmit data immediately (i.e. don't use the Nagle algorithm)
		int flag = 1;
		setsockopt(newSocket, IPPROTO_TCP, TCP_NODELAY, (void *) &flag, sizeof(flag));
		return newSocket;
	}
	return -1;
}

static int obj2socket(OBJ refObj);

static void finalizeSocket(OBJ refObj) {
	int socket = obj2socket(refObj);
	if (socket < 0) { return; }
	if (socket >= 0) {
		shutdown(socket, SHUT_RDWR);
		close(socket);
	}
	ADDR *a = (ADDR*)BODY(refObj);
	a[0] = (ADDR) -1; // -1 means that the socket is closed
}

static OBJ socket2obj(int socket) {
	if (socket < 0) return nilObj;
	OBJ ref = newBinaryObj(ExternalReferenceClass, ExternalReferenceWords);

	ADDR *a = (ADDR*)BODY(ref);
	a[0] = (ADDR) ((long) socket);
	a[1] = (ADDR) finalizeSocket;
	return ref;
}

static int obj2socket(OBJ refObj) {
	// Return the socket from the given external reference or -1 if it is not a valid socket.

	ADDR *a = (ADDR*)BODY(refObj);
	if (NOT_CLASS(refObj, ExternalReferenceClass) ||
		(objWords(refObj) < ExternalReferenceWords) ||
			(a[1] != (ADDR) finalizeSocket)) {
			printf("Error: Invalid socket\n");
			return -1;
	}
	return (long) a[0];
}

// ***** Socket Primitives *****

OBJ primOpenClientSocket(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Host name must be a string");
	if (!isInt(args[1])) return primFailed("Port number must be an integer");

	int socket = openClientSocket(obj2str(args[0]), obj2int(args[1]));
	if (socket < 0) return nilObj;
	return socket2obj(socket);
}

OBJ primOpenServerSocket(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return primFailed("Port number must be an integer");
	int socket = openServerSocket(obj2int(args[0]));
	if (socket < 0) return nilObj;
	return socket2obj(socket);
}

OBJ primAcceptConnection(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	int socket = acceptConnection(obj2socket(args[0]));
	if (socket < 0) return nilObj;
	return socket2obj(socket);
}

OBJ primRemoteAddress(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	int socket = obj2socket(args[0]);
	if (socket < 0) return nilObj;

	struct sockaddr_storage addr;
	socklen_t len = sizeof(addr);
	int err = getpeername(socket, (struct sockaddr*) &addr, &len);
	if (err < 0) return newString(""); // getpeername failed

	char name[NAME_SIZE];
	if (addr.ss_family == AF_INET) {
		struct sockaddr_in *s = (struct sockaddr_in *) &addr;
		#ifdef _WIN32
			unsigned char *ip = (void *) &s->sin_addr;
			sprintf(name, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
		#else
			inet_ntop(AF_INET, &s->sin_addr, name, sizeof(name));
		#endif
	} else { // v6 address
		struct sockaddr_in6 *s = (struct sockaddr_in6 *) &addr;
		#ifdef _WIN32
			// Note: I'm not sure if this byte ordering is correct,
			// but v6 peername addresses are rare so haven't tested...
			unsigned short *ip = (void *) &s->sin6_addr;
			sprintf(name, "%.4x:%.4x:%.4x:%.4x:%.4x:%.4x:%.4x:%.4x",
				ip[0], ip[1], ip[2], ip[3], ip[4], ip[5], ip[6], ip[7]);
		#else
			inet_ntop(AF_INET6, &s->sin6_addr, name, sizeof(name));
		#endif
	}
	name[NAME_SIZE - 1] = 0; // ensure null termination
	return newString(name);
}

OBJ primReadSocket(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	int socket = obj2socket(args[0]);
	if (socket < 0) return nilObj;

	int binaryFlag = (nargs > 1) && (args[1] == trueObj);

	char buf[BUF_SIZE];
	int byteCount = recv(socket, buf, BUF_SIZE, 0);
	if (byteCount < 0) byteCount = 0;

	OBJ result;
	if (binaryFlag) {
		int wordCount = ((byteCount + 3) / 4);
		result = newBinaryObj(BinaryDataClass, wordCount);
		int extraBytes = (4 * wordCount) - byteCount;
		*(O2A(result)) |= extraBytes << EXTRA_BYTES_SHIFT;
	} else {
		int wordCount = (byteCount / 4) + 1;
		result = newBinaryObj(StringClass, wordCount);
	}
	char *src = buf;
	char *dst = (char *)BODY(result);
	for (int i = 0; i < byteCount; i++) *dst++ = *src++;
	return result;
}

OBJ primWriteSocket(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	int socket = obj2socket(args[0]);
	if (socket < 0) return nilObj;

	char *data = NULL;
	int byteCount = 0;

	if (IS_CLASS(args[1], StringClass)) {
		data = obj2str(args[1]);
		byteCount = strlen(data);
	} else if (IS_CLASS(args[1], BinaryDataClass)) {
		data = (char *)BODY(args[1]);
		byteCount = objBytes(args[1]);
	}
	if (!byteCount) return int2obj(0);

	int bytesWritten = send(socket, data, byteCount, 0);
	if (bytesWritten < 0) {
  #ifdef _WIN32
		errno = WSAGetLastError();
  #endif
		if ((errno != EAGAIN) && (errno != EWOULDBLOCK)) {
			printf("write error %s (%d); socket closed\n", strerror(errno), errno);
			finalizeSocket(args[0]); // other end has exited or closed the socket
		} else {
			bytesWritten = 0;
		}
	}
	return int2obj(bytesWritten);
}

OBJ primCloseSocket(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	finalizeSocket(args[0]);
	return nilObj;
}

OBJ primSocketStatus(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	int socket = obj2socket(args[0]);
	if (socket < 0) return nilObj;
	return (socketHasData(socket) >= 0) ? trueObj : nilObj;
}

// ***** Socket Primitives *****

PrimEntry socketPrimList[] = {
	{"-----", NULL, "Networking"},
	{"openClientSocket",	primOpenClientSocket,	"Open a new client socket for the given host and port. Arguments: hostName portNumber"},
	{"openServerSocket",	primOpenServerSocket,	"Open and return a new server socket. Arguments: portNumber"},
	{"acceptConnection",	primAcceptConnection,	"Accept an incoming connection on a server socket. Return the new connection socket, or nil if there isn't one. Arguments: serverSocket"},
	{"remoteAddress",		primRemoteAddress,		"Return the remote IP address of the given socket. Arguments: aSocket"},
	{"readSocket",			primReadSocket,			"Read and return a String (or BinaryData, if isBinary is true) from a socket. Arguments: aSocket [isBinary]"},
	{"writeSocket",			primWriteSocket,		"Write data to a socket and return the number of bytes written. Arguments: aSocket aStringOrBinaryData"},
	{"closeSocket",			primCloseSocket,		"Close a socket. Arguments: aSocket"},
	{"socketStatus",		primSocketStatus,		"Return true if the socket is open, nil otherwise. Arguments: aSocket"}
};

PrimEntry* socketPrimitives(int *primCount) {
	*primCount = sizeof(socketPrimList) / sizeof(PrimEntry);
	return socketPrimList;
}
