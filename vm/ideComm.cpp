/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// ideComm.cpp - Primitives to communicate with the MicroBlocks IDE.
// John Maloney, December 2023

#include <Arduino.h>

#include "mem.h"
#include "interp.h"

int BLE_connected_to_IDE = false;
char BLE_ThreeLetterID[4];

#if defined(BLE_IDE)

// BLE Communications

#include <NimBLEDevice.h>

// BLE_SEND_MAX - maximum bytes to send in a single attribute write (max is 512)
// INTER_SEND_TIME - don't send data more often than this to avoid NimBLE error & disconnect
#define BLE_SEND_MAX 250
#define INTER_SEND_TIME 20

static BLEServer *pServer = NULL;
static BLEService *pService = NULL;
static BLECharacteristic *pTxCharacteristic;
static BLECharacteristic *pRxCharacteristic;
static char uniqueName[32];
static bool bleRunning = false;
static bool serviceOnline = false;
static uint16_t connID = -1;

static uint32 lastSendTime = 0;
static int lastRC = 0;

#define RECV_BUF_MAX 1024
static uint8_t bleRecvBuf[RECV_BUF_MAX];
static int bleBytesAvailable = 0;
static int overRuns = 0;

#define SERVICE_UUID			"6E400001-B5A3-F393-E0A9-E50E24DCCA9E" // Nordic UART service
#define CHARACTERISTIC_UUID_RX	"6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX	"6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// BLE Helper Functions

static void reportNum2(const char *label, int n) {
	Serial.print(label);
	Serial.print(": ");
	Serial.println(n);
}

static void flashUserLED() {
	OBJ on = trueObj;
	OBJ off = falseObj;
	primSetUserLED(&on);
	updateMicrobitDisplay();
	delay(10);
	primSetUserLED(&off);
	updateMicrobitDisplay();
}

static void initName() {
	unsigned char mac[6] = {0, 0, 0, 0, 0, 0};
	getMACAddress(mac);
	int machineNum = (mac[4] << 8) | mac[5]; // 16 least signifcant bits

	BLE_ThreeLetterID[0] = 65 + (machineNum % 26);
	machineNum = machineNum / 26;
	BLE_ThreeLetterID[1] = 65 + (machineNum % 26);
	machineNum = machineNum / 26;
	BLE_ThreeLetterID[2] = 65 + (machineNum % 26);
	BLE_ThreeLetterID[3] = 0;

	sprintf(uniqueName, "MicroBlocks %s", BLE_ThreeLetterID);
}

static void displayFor(int msecs) {
	uint32 endMSecs = millisecs() + msecs;
	while (millisecs() < endMSecs) {
		processMessage();
		updateMicrobitDisplay();
		delay(1);
	}
}

static void show_BLE_ID() {
	OBJ args[5]; // used to call primitives

	int nameLen = strlen(uniqueName);
	for (int iters = 0; iters < 2; iters++) {
		for (int i = nameLen - 4; i < nameLen; i++) {
			args[0] = newStringFromBytes(&uniqueName[i], 1);
			OBJ letterShape = primMBShapeForLetter(1, args);

			args[0] = letterShape;
			args[1] = int2obj(1);
			args[2] = int2obj(1);
			primMBDrawShape(3, args);
			displayFor(400);
		}
		primMBDisplayOff(0, args);
		displayFor(300);
	}
}

static int gotSerialPing() {
	char buf[20];
	int byteCount = Serial.available();
	if (byteCount < 3) return false;
	delay(5); // wait for a few more bytes
	byteCount = Serial.available();
	if (byteCount > (int) sizeof(buf)) byteCount = sizeof(buf);
	byteCount = Serial.readBytes((char *) buf, byteCount);
	for (int i = 0; i < byteCount - 2; i++) {
		if ((buf[i] == 0xFA) && (buf[i+1] == 0x1A) && (buf[i+2] == 0)) {
			return true; // receive ping message from IDE
		}
	}
	return false;
}

static void updateConnectionMode() {
	if (BLE_connected_to_IDE) {
		if (gotSerialPing()) {
			// new serial connection; disconnect BLE
			if (connID != -1) { pServer->disconnect(connID); }
			connID = -1;
			pServer->removeService(pService);
			BLE_connected_to_IDE = false;
			serviceOnline = false;
			return;
		}
	} else {
		if (!serviceOnline && !ideConnected()) {
			// lost serial connection; restore service and advertising
			pServer->addService(pService);
			pServer->getAdvertising()->start();
			serviceOnline = true;
		}
	}
}

static void bleReceiveData(const uint8_t *data, int byteCount) {
	int available = RECV_BUF_MAX - bleBytesAvailable;
	if (byteCount > available) {
		overRuns++;
		byteCount = available;
	}

	memcpy(&bleRecvBuf[bleBytesAvailable], data, byteCount);
	bleBytesAvailable += byteCount;
}

static int bleSendData(uint8_t *data, int byteCount) {
	// do not send more often than INTER_SEND_TIME msecs
	uint32 now = millisecs();
	if (lastSendTime > now) lastSendTime = 0; // clock wrap
	if ((now - lastSendTime) < INTER_SEND_TIME) return 0;

	if (byteCount <= 0) return 0;

	// send byteCount bytes
	if (byteCount > BLE_SEND_MAX) byteCount = BLE_SEND_MAX;
	lastRC = 0; // will be set to non-zero if notify() call fails
	pTxCharacteristic->setValue(data, byteCount);
	pTxCharacteristic->indicate();
	if (lastRC != 0) {
		byteCount = 0; // write+notify failed; retry later
	}

	lastSendTime = now;
	return byteCount;
}

class MyServerCallbacks: public BLEServerCallbacks {
	void onConnect(BLEServer* pServer, ble_gap_conn_desc* desc) {
		pServer->getAdvertising()->stop(); // don't advertise while connected
		connID = desc->conn_handle;
		BLE_connected_to_IDE = true;
	}
	void onDisconnect(BLEServer* pServer) {
		pServer->getAdvertising()->start(); // restart advertising
		connID = -1;
		BLE_connected_to_IDE = false;
	}
};

class MyCallbacks: public BLECharacteristicCallbacks {
	void onWrite(BLECharacteristic *pCharacteristic, ble_gap_conn_desc* desc) {
		// Handle incoming BLE data.

		NimBLEAttValue value = pCharacteristic->getValue();
		bleReceiveData(value.data(), value.length());
	}
	void onStatus(NimBLECharacteristic* pCharacteristic, Status s, int code) {
		// Record the last return code. This is used to tell when a notify() has failed
		// (because there are no buffers) so that it can be re-tried later.

		lastRC = code;
	}
};

// Start/Stop BLE

void startBLE() {
	if (bleRunning) return; // BLE already running

	// Create BLE Device
	initName();
	BLEDevice::init(uniqueName);

	// Create BLE Server
	pServer = BLEDevice::createServer();
	pServer->setCallbacks(new MyServerCallbacks());

	// Create BLE Service
	pService = pServer->createService(SERVICE_UUID);

	// Create BLE Characteristics
	pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, NIMBLE_PROPERTY::NOTIFY);
	pTxCharacteristic->setCallbacks(new MyCallbacks());
	pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, NIMBLE_PROPERTY::WRITE_NR);
	pRxCharacteristic->setCallbacks(new MyCallbacks());

	// Start the service
	pService->start();

	// Add the service to the advertisment data
	pServer->getAdvertising()->addServiceUUID(pService->getUUID());

	// Start advertising
	pServer->getAdvertising()->setName(uniqueName);
	pServer->getAdvertising()->start();
	serviceOnline = true;
	bleRunning = true;
	show_BLE_ID();
}

void stopBLE() {
	if (!bleRunning) return; // BLE already stopped

	if (connID != -1) { pServer->disconnect(connID); }
	connID = -1;
	BLE_connected_to_IDE = false;
	serviceOnline = false;

	pServer->getAdvertising()->stop();
	pServer->removeService(pService);
	BLEDevice::deinit();

	pServer = NULL;
	pService = NULL;
	pTxCharacteristic = NULL;
	pRxCharacteristic = NULL;

	bleRunning = false;
}

int recvBytes(uint8 *buf, int count) {
	int bytesRead;

	updateConnectionMode();

	if (!BLE_connected_to_IDE) { // no BLE connection; use Serial
		bytesRead = Serial.available();
		if (bytesRead > count) bytesRead = count; // there is only enough room for count bytes
		return Serial.readBytes((char *) buf, bytesRead);
	}

	// use BLE connection
	bytesRead = (count < bleBytesAvailable) ? count : bleBytesAvailable;
	if (bytesRead == 0) return 0;

	memcpy(buf, bleRecvBuf, bytesRead); // copy bytes to buf

	int remainingBytes = bleBytesAvailable - bytesRead;
	if (remainingBytes > 0) {
		// remove bytesRead bytes from bleRecvBuf
		memcpy(bleRecvBuf, &bleRecvBuf[bytesRead], remainingBytes);
	}
	bleBytesAvailable = remainingBytes;

	return bytesRead;
}

int sendBytes(uint8 *buf, int start, int end) {
	// Send bytes buf[start] through buf[end - 1] and return the number of bytes sent.

	if (!BLE_connected_to_IDE) { // no BLE connection; use Serial
		return Serial.write(&buf[start], end - start);
	}

	// use BLE connection
	return bleSendData(&buf[start], end - start);
}

#else

// Serial Communications Only

int recvBytes(uint8 *buf, int count) {
	int bytesRead = Serial.available();
	if (bytesRead > count) bytesRead = count; // there is only enough room for count bytes
	return Serial.readBytes((char *) buf, bytesRead);
}

int sendBytes(uint8 *buf, int start, int end) {
	// Send bytes buf[start] through buf[end - 1] and return the number of bytes sent.

	return Serial.write(&buf[start], end - start);
}

void stopBLE() { } // stub

#endif

void restartSerial() {
	// Needed to work around a micro:bit issue that Serial can lock up during Flash compaction.

	Serial.end();
	Serial.begin(115200);
}
