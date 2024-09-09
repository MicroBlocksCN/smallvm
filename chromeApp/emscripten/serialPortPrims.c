#include <stdio.h>
#include <string.h>
#include "mem.h"
#include "interp.h"

#define READ_BUF_SIZE 10000
#define PORT_COUNT 33
#define NOT_IMPLEMENTED -2

// ***** Platform Dependent Operations *****

// MacOS, iOS, and Linux

#if defined(MAC) || defined(IOS) || defined(__linux__)

#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

typedef int PortHandle;
#define CLOSED (-1)

// The original termios settings for open ports; retored when port is closed.
static struct termios originalSettings[PORT_COUNT];

static OBJ serialPortList() {
	return (newArray(0));
}

static PortHandle openPort(int portID, char *portName, int baudRate) {
	PortHandle h = open(portName, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (h < 0) return CLOSED;

	// save old port settings so we can restore them later
	if (tcgetattr(h, &originalSettings[portID]) == -1) {
		close(h);
		return CLOSED;
	}

	// set the baud rate and other settings
	struct termios settings;
	memset(&settings, 0, sizeof(settings));
	tcgetattr(h, &settings); // get the current settings
	cfmakeraw(&settings);
	settings.c_cflag |= CLOCAL; // ignore modem control lines
	settings.c_cflag &= ~CRTSCTS; // don't do RTS/CTS control flow
	cfsetspeed(&settings, baudRate);
	settings.c_cc[VMIN] = 0; // non-blocking read, even if no bytes available
	settings.c_cc[VTIME] = 0; // read returns immediately even if no bytes are available
	tcsetattr(h, TCSANOW, &settings);

	return h;
}

static void closePort(int portID, PortHandle h) {
	if (CLOSED == h) return;

	// restore the serial port settings to their original state
	tcsetattr(h, TCSANOW, &originalSettings[portID]);
	close(h);
}

static int readPort(PortHandle port, char *buf, int bufSize) {
	return read(port, buf, bufSize);
}

static int writePort(PortHandle port, char *buf, int bufSize) {
	int n = write(port, buf, bufSize);
	if ((n < 0) && (errno == EAGAIN)) n = 0;
	return n;
}

static void setDTR(PortHandle port, int flag) {
	int DTR_bit = TIOCM_DTR;
	if (flag) {
		ioctl(port, TIOCMBIS, &DTR_bit);
	} else {
		ioctl(port, TIOCMBIC, &DTR_bit);
	}
}

static void setRTS(PortHandle port, int flag) {
	int RTS_bit = TIOCM_RTS;
	if (flag) {
		ioctl(port, TIOCMBIS, &RTS_bit);
	} else {
		ioctl(port, TIOCMBIC, &RTS_bit);
	}
}

#elif defined(_WIN32)

#include <ctype.h>
#include <windows.h>
#include <initguid.h>
#include <devguid.h>
#include <setupapi.h>

typedef HANDLE PortHandle;
#define CLOSED NULL

// static OBJ serialPortListOld() {
// 	char buf[400]; // result of QueryDosDevice; ignored, since we only care if query succeeds
// 	char portName[10];
//
// 	OBJ portList = newArray(255);
// 	int count = 0;
// 	for (int i = 0; i < 256; i++) {
// 		sprintf(portName, "COM%d", i);
// 		if (QueryDosDevice(portName, (void *) &buf, sizeof(buf) / 2)) {
// 			FIELD(portList, count++) = newString(portName);
// 		}
// 	}
// 	return copyObj(portList, count, 1);
// }

static OBJ serialPortList() {
	OBJ portList = newArray(256);
	int count = 0;
	SP_DEVINFO_DATA devInfoData = {};
	devInfoData.cbSize = sizeof(devInfoData);
	char friendlyName[256];

	// get device info for the available COM ports
	HDEVINFO hDeviceInfo = SetupDiGetClassDevs(&GUID_DEVCLASS_PORTS, NULL, NULL, DIGCF_PRESENT);
	if (hDeviceInfo == INVALID_HANDLE_VALUE) copyObj(portList, 0, 1);

	// iterate over COM ports
	int deviceIndex = 0;
	while (SetupDiEnumDeviceInfo(hDeviceInfo, deviceIndex++, &devInfoData)) {
		if (SetupDiGetDeviceRegistryProperty(
			hDeviceInfo, &devInfoData, SPDRP_FRIENDLYNAME, NULL,
			(BYTE *) friendlyName, sizeof(friendlyName), NULL))
		{
			FIELD(portList, count++) = newString(friendlyName);
		}
	}
	SetupDiDestroyDeviceInfoList(hDeviceInfo);
	return copyObj(portList, count, 1);
}

static PortHandle openPort(int portID, char *portName, int baudRate) {
	char comPort[8];
	TCHAR name[20];
	HANDLE portPtr;
	COMMTIMEOUTS timeouts;
	DCB dcb;

	char *start = strstr(portName, "COM");
	if (!start) return CLOSED;
	char *end = start + 3; // end of "COM"
	if (!isdigit(*end)) return CLOSED; else end++; // need at list one digit
	if (isdigit(*end)) end++; // two digit COM port
	if (isdigit(*end)) end++; // three digit COM port
	comPort[0] = '\0';
	strncat(comPort, start, (end - start));

	wsprintf(name, TEXT("\\\\.\\%s"), comPort);
	// MessageBox(NULL, name, "Debug: port name", 0);
	portPtr = CreateFile(
		name,
		GENERIC_READ | GENERIC_WRITE,
		0,				// comm devices must be opened with exclusive access
		NULL,			// no security attrs
		OPEN_EXISTING,	// comm devices must use OPEN_EXISTING
		0,				// no overlapped I/O
		NULL			// hTemplate must be NULL for comm devices
	);
	if (portPtr == INVALID_HANDLE_VALUE) return CLOSED;

	// purge the driver
	PurgeComm(portPtr, PURGE_TXABORT | PURGE_RXABORT | PURGE_TXCLEAR | PURGE_RXCLEAR);

	// Set input and output buffer sizes
	SetupComm(portPtr, 4096, 4096);

	// Set the timeouts so that reads do not block
	timeouts.ReadIntervalTimeout= 0xFFFFFFFF;
	timeouts.ReadTotalTimeoutMultiplier = 0;
	timeouts.ReadTotalTimeoutConstant = 0;
	timeouts.WriteTotalTimeoutMultiplier = 0;
	timeouts.WriteTotalTimeoutConstant = 0;
	SetCommTimeouts(portPtr, &timeouts);

	// Set default DCB settings
	ZeroMemory(&dcb, sizeof(dcb));
	dcb.DCBlength = sizeof(dcb);
	if (!GetCommState(portPtr, &dcb)) {
		CloseHandle(portPtr);
		return CLOSED;
	}

	// the basics
	dcb.BaudRate = baudRate;
	dcb.ByteSize = 8;
	dcb.StopBits = ONESTOPBIT;
	dcb.Parity = NOPARITY;

	// no control flow
	dcb.fOutxCtsFlow = false;
	dcb.fOutxDsrFlow = false;
	dcb.fDsrSensitivity = false;
	dcb.fDtrControl = DTR_CONTROL_ENABLE;	// turn on DTR line
	dcb.fRtsControl = RTS_CONTROL_ENABLE;	// turn on RTS line
	dcb.fOutX = false;
	dcb.fInX = false;
	dcb.fNull = false;
	dcb.XonChar = 17;
	dcb.XoffChar = 19;
	if (!SetCommState(portPtr, &dcb)) {
		CloseHandle(portPtr);
		return CLOSED;
	}

	return (PortHandle) portPtr;
}

static void closePort(int portID, PortHandle port) {
	if (CLOSED == h) return;

	PurgeComm((HANDLE) port, PURGE_TXABORT | PURGE_RXABORT | PURGE_TXCLEAR | PURGE_RXCLEAR);
	CloseHandle((HANDLE) port);
}

static int readPort(PortHandle port, char *buf, int bufSize) {
	DWORD bytesRead = 0;
	ReadFile((HANDLE) port, (void *) buf, bufSize, &bytesRead, NULL);
	return (int) bytesRead;
}

static int writePort(PortHandle port, char *buf, int bufSize) {
	DWORD bytesWritten = 0;
	BOOL ok = WriteFile((HANDLE) port, (void *) buf, bufSize, &bytesWritten, NULL);
	if (!ok && (ERROR_IO_PENDING != GetLastError())) return -1;
	return (int) bytesWritten;
}

static void setDTR(PortHandle port, int flag) {
	if (flag) {
		EscapeCommFunction(port, SETDTR);
	} else {
		EscapeCommFunction(port, CLRDTR);
	}
}

static void setRTS(PortHandle port, int flag) {
	if (flag) {
		EscapeCommFunction(port, SETRTS);
	} else {
		EscapeCommFunction(port, CLRRTS);
	}
}

#elif defined(EMSCRIPTEN)

#include <emscripten.h>

typedef int PortHandle;
#define CLOSED (-1)

static OBJ serialPortList() {
	int count = EM_ASM_INT({
		GP_getSerialPorts();
		return GP_serialPortNames.length;
	}, 0);
	OBJ result = newArray(count);

	for (int i = 0; i < count; i++) {
		int len = EM_ASM_INT({
			return GP_serialPortNames[$0].length;
		}, i);
		OBJ s = allocateString(len);
		EM_ASM_({
			var src = GP_serialPortNames[$0];
			var dst = $1;
			var len = $2;
			for (var j = 0; j < len; j++) {
				Module.HEAPU8[dst++] = src[j];
			}
		}, i, obj2str(s), len);
		FIELD(result, i) = s;
	}
	return result;
}

static PortHandle openPort(int portID, char *portName, int baudRate) {
	int success = EM_ASM_INT({
		var id = $0;
		var path = UTF8ToString($1);
		var rate = $2;
		return GP_openSerialPort(id, path, rate);
	}, portID, portName, baudRate);
	if (!success) return CLOSED;
	return portID; // since GP_openSerialPort is async, assume it will succeed
}

static void closePort(int portID, PortHandle h) {
	// Always call GP_closeSerialPort()
	EM_ASM({
		GP_closeSerialPort();
	}, 0);
}

static int readPort(PortHandle port, char *buf, int bufSize) {
	int bytesRead = EM_ASM_INT({
		var dst = $0;
		var bufSize = $1;
		var data = GP_readSerialPort(bufSize);
		var count = data.length;
		if (count > bufSize) count = bufSize;
		for (var i = 0; i < count; i++) {
			Module.HEAPU8[dst++] = data[i];
		}
		return count;
	}, buf, bufSize);
	return bytesRead;
}

static int writePort(PortHandle port, char *buf, int bufSize) {
	int bytesWritten = EM_ASM_INT({
		var src = $0;
		var count = $1;
		var data = new Uint8Array(new ArrayBuffer(count));
		for (var i = 0; i < count; i++) {
			data[i] = Module.HEAPU8[src++];
		}
		return GP_writeSerialPort(data);
	}, buf, bufSize);
	return bytesWritten;
}

static void setDTR(PortHandle port, int flag) {
	EM_ASM_({
		GP_setSerialPortDTR($0);
	}, flag);
}

static void setRTS(PortHandle port, int flag) {
	EM_ASM_({
		GP_setSerialPortRTS($0);
	}, flag);
}

static void setDTRandRTS(PortHandle port, int dtrFlag, int rtsFlag) {
	EM_ASM_({
		GP_setSerialPortDTRandRTS($0, $1);
	}, dtrFlag, rtsFlag);
}

#else // stubs for platforms without serial port support

typedef int PortHandle;
#define CLOSED (-1)

static OBJ serialPortList() { return (newArray(0)); }
static PortHandle openPort(int portID, char *portName, int baudRate) { return NOT_IMPLEMENTED; }
static void closePort(int portID, PortHandle h) { }
static int readPort(PortHandle port, char *buf, int bufSize) { return -1; }
static int writePort(PortHandle port, char *buf, int bufSize) { return -1; }
static void setDTR(PortHandle port, int flag) { }
static void setRTS(PortHandle port, int flag) { }

#endif

// ***** Serial port data structures *****

// This table maps GP serial port ID's in the range [0..PORT_COUNT)
// to the underlying file descriptor. -1 marks unused entries in this table.
static PortHandle portHandle[PORT_COUNT] = {
	CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED,
	CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED,
	CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED,
	CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED, CLOSED};

// ***** Helper Functions *****

static int unusedPortID() {
	// Return an unused port ID (index in portHandle[]) or -1 if all ports are in use.
	// Note: Skip portID zero; valid portID's are 1 to (PORT_COUNT - 1).

	for (int id = 1; id < PORT_COUNT; id++) {
		if (portHandle[id] == CLOSED) return id;
	}
	return -1;
}

static PortHandle getPortHandle(int portID) {
	if ((portID < 0) || (portID >= PORT_COUNT)) {
		primFailed("Bad serial port ID");
		return CLOSED;
	}
	return portHandle[portID];
}

// ***** Serial Port Primitives *****

OBJ badPortIDFailure() { return primFailed("Serial port ID must be an integer"); }

OBJ primListSerialPorts(int nargs, OBJ args[]) {
	return (serialPortList());
}

OBJ primOpenSerialPort(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Serial port name must be a string");
	char *portName = obj2str(args[0]);

	if (!isInt(args[1])) return primFailed("Serial port baud rate must be an integer");
	int baudRate = obj2int(args[1]);

	int portID = unusedPortID();
	if (portID < 0) return primFailed("All serial port entries are in use");

	PortHandle h = openPort(portID, portName, baudRate);
	if (h == (PortHandle) CLOSED) return primFailed("Could not open serial port");
	if (h == (PortHandle) NOT_IMPLEMENTED) return primFailed("Serial port primitives not implemented on this platform");

	portHandle[portID] = h;
	return int2obj(portID);
}

OBJ primIsOpenSerialPort(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	int portID = obj2int(args[0]);

	#ifdef EMSCRIPTEN
		int isOpen = EM_ASM_INT({
			return GP_isOpenSerialPort();
		});
		return isOpen ? trueObj : falseObj;
	#endif

	return (CLOSED != getPortHandle(portID)) ? trueObj : falseObj;
}

OBJ primCloseSerialPort(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	int portID = obj2int(args[0]);

	PortHandle h = getPortHandle(portID);
	closePort(portID, h);
	portHandle[portID] = CLOSED;
	return nilObj;
}

OBJ primReadSerialPort(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	int portID = obj2int(args[0]);

	int isBinary = (nargs > 1) && (args[1] == trueObj);

	PortHandle h;
	#ifdef EMSCRIPTEN
		h = 1;
	#else
		h = getPortHandle(portID);
		if (h == CLOSED) return nilObj;
	#endif

	char buf[READ_BUF_SIZE];
	int n = readPort(h, buf, READ_BUF_SIZE);
	if (n == 0) return nilObj; // no data available
	if (n < 0) {
		printf("Read error, serial port %d\n", portID);
		closePort(portID, h);
		portHandle[portID] = CLOSED;
		return nilObj;
	}

	unsigned int wordCount = ((n + 3) / 4);
	if (!canAllocate(wordCount)) return outOfMemoryFailure();
	OBJ result = isBinary ? newBinaryObj(BinaryDataClass, wordCount) : allocateString(n);

	memcpy(&FIELD(result, 0), buf, n);

	if (isBinary) {
		int extraBytes = 4 - (n % 4);
		*(O2A(result)) |= extraBytes << EXTRA_BYTES_SHIFT;
	}
	return result;
}

OBJ primWriteSerialPort(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	int portID = obj2int(args[0]);

	PortHandle h;
	#ifdef EMSCRIPTEN
		h = 1;
	#else
		h = getPortHandle(portID);
		if (h == CLOSED) return int2obj(0);
	#endif

	OBJ data = args[1];
	if (!(IS_CLASS(data, BinaryDataClass) || IS_CLASS(data, StringClass))) {
		return primFailed("Can only write a String or BinaryData to a serial port");
	}
	char *buf = (char *) &FIELD(data, 0);
	int bufSize = IS_CLASS(data, StringClass) ? stringBytes(data) : objBytes(data);

	int n = writePort(h, buf, bufSize);
	if (n < 0) {
		printf("Write error, serial port %d\n", portID);
		closePort(portID, h);
		portHandle[portID] = CLOSED;
		return int2obj(0);
	}
	return int2obj(n); // return bytes written
}

OBJ primSetSerialPortDTR(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	PortHandle h = getPortHandle(obj2int(args[0]));
	if (h != CLOSED) setDTR(h, (trueObj == args[1]));
	return nilObj;
}

OBJ primSetSerialPortRTS(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	PortHandle h = getPortHandle(obj2int(args[0]));
	if (h != CLOSED) setRTS(h, (trueObj == args[1]));
	return nilObj;
}

OBJ primSetSerialPortDTRandRTS(int nargs, OBJ args[]) {
	if (nargs < 3) return notEnoughArgsFailure();
	if (!isInt(args[0])) return badPortIDFailure();
	PortHandle h = getPortHandle(obj2int(args[0]));
	#ifdef EMSCRIPTEN
		if (h != CLOSED) setDTRandRTS(h, (trueObj == args[1]), (trueObj == args[2]));
	#else
		if (h != CLOSED) {
			setDTR(h, (trueObj == args[1]));
			setRTS(h, (trueObj == args[2]));
		}
	#endif
	return nilObj;
}

PrimEntry serialPortPrimList[] = {
	{"-----", NULL, "Serial Port"},
	{"listSerialPorts",		primListSerialPorts,	"Return an array of serial port names."},
	{"openSerialPort",		primOpenSerialPort,		"Open a serial port. Return the portID or nil on failure. Arguments: portName, baudRate"},
	{"isOpenSerialPort",	primIsOpenSerialPort,	"Return true if the given serial port is open. Arguments: portID"},
	{"closeSerialPort",		primCloseSerialPort,	"Close the given serial port. Arguments: portID"},
	{"readSerialPort",		primReadSerialPort,		"Read data from a serial port. Return a String or BinaryData object or nil. Arguments: portID [binaryFlag]"},
	{"writeSerialPort",		primWriteSerialPort,	"Write data to a serial port. Arguments: portID stringOrBinaryData"},
	{"setSerialPortDTR",	primSetSerialPortDTR,	"Set the DTR line of a serial port. Arguments: portID dtrFlag"},
	{"setSerialPortRTS",	primSetSerialPortRTS,	"Set the RTS line of a serial port. Arguments: portID rtsFlag"},
	{"setSerialPortDTRandRTS",	primSetSerialPortDTRandRTS,	"Set the DTR and RTS lines of a serial port. Arguments: portID dtrFlag"},
};

PrimEntry* serialPortPrimitives(int *primCount) {
	*primCount = sizeof(serialPortPrimList) / sizeof(PrimEntry);
	return serialPortPrimList;
}
