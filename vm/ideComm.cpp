/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// ideComm.cpp - Primitives to communicate with the MicroBlocks IDE.
// John Maloney, December 2023

#include <Arduino.h>

#include "mem.h"
#include "interp.h"
#include "persist.h"

char BLE_ThreeLetterID[4];
int BLE_connected_to_IDE = false;
int USB_connected_to_IDE = false;

#if defined(BLE_IDE)

// BLE Communications

#include <NimBLEDevice.h>

extern uint32 lastRcvTime;

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

// MicroBlocks IDE Service UUIDs:
#define MB_SERVICE_UUID				"bb37a001-b922-4018-8e74-e14824b3a638"
#define MB_CHARACTERISTIC_UUID_RX	"bb37a002-b922-4018-8e74-e14824b3a638"
#define MB_CHARACTERISTIC_UUID_TX	"bb37a003-b922-4018-8e74-e14824b3a638"

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

void BLE_initThreeLetterID() {
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
		captureIncomingBytes();
		updateMicrobitDisplay();
		delay(1);
	}
}

static void show_BLE_ID() {
	OBJ args[5]; // used to call primitives

	int nameLen = strlen(uniqueName);
	for (int i = nameLen - 4; i < nameLen; i++) {
		args[0] = newStringFromBytes(&uniqueName[i], 1);
		OBJ letterShape = primMBShapeForLetter(1, args);

		args[0] = letterShape;
		args[1] = int2obj(1);
		args[2] = int2obj(1);
		primMBDrawShape(3, args);
		displayFor(300);
		primMBDisplayOff(0, args);
		displayFor(100);
	}
	primMBDisplayOff(0, args);
}

static int gotSerialPing() {
	char buf[8];
	int byteCount = Serial.available();
	if (byteCount < 3) return false;
	byteCount = Serial.readBytes((char *) buf, sizeof(buf));
	for (int i = 0; i < byteCount - 2; i++) {
		if ((buf[i] == 0xFA) && (buf[i+1] == 0x1A) && (buf[i+2] == 0)) {
			return true; // receive ping message from IDE
		}
	}
	return false;
}

static void updateConnectionState() {
	if (USB_connected_to_IDE && !ideConnected()) {
		// resume BLE service and advertisting
		if (pServer) pServer->addService(pService);
		USB_connected_to_IDE = false;
	}
	if (!USB_connected_to_IDE) { // either not connected or connected via BLE
		if (gotSerialPing()) {
			// new serial connection; disconnect BLE if it is connected
			if (pServer) {
				if (connID != -1) { pServer->disconnect(connID); }
				connID = -1;
				// remove IDE BLE service
				pServer->removeService(pService);
			}
			BLE_connected_to_IDE = false;
			// tell runtime that we've gotten a ping
			lastRcvTime = microsecs();
			USB_connected_to_IDE = true;
		}
	}
}

// BLE Operation

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
		connID = desc->conn_handle;
		BLE_connected_to_IDE = true;
	}
	void onDisconnect(BLEServer* pServer, ble_gap_conn_desc* desc) {
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

void BLE_start() {
	if (bleRunning) return; // BLE already running

	// Create BLE Device
	BLE_initThreeLetterID();
	BLEDevice::init(uniqueName);

	// Create BLE Server
	pServer = BLEDevice::createServer();
	pServer->setCallbacks(new MyServerCallbacks());

	// Create BLE Service
	pService = pServer->createService(MB_SERVICE_UUID);

	// Create BLE Characteristics
	pTxCharacteristic = pService->createCharacteristic(MB_CHARACTERISTIC_UUID_TX, NIMBLE_PROPERTY::NOTIFY);
	pTxCharacteristic->setCallbacks(new MyCallbacks());
	pRxCharacteristic = pService->createCharacteristic(MB_CHARACTERISTIC_UUID_RX, NIMBLE_PROPERTY::WRITE_NR);
	pRxCharacteristic->setCallbacks(new MyCallbacks());

	// Start the service
	pService->start();
	serviceOnline = true;
	bleRunning = true;

	BLE_resumeAdvertising();
	show_BLE_ID();
}

void BLE_stop() {
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

// Stop and resume advertising (for use by Octo primitives)

void BLE_pauseAdvertising() {
	if (!pServer) return;
	pServer->getAdvertising()->stop();
	pServer->getAdvertising()->removeServiceUUID(NimBLEUUID(MB_SERVICE_UUID));
}

void BLE_resumeAdvertising() {
	if (!pServer) return;

	NimBLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
	pAdvertising->reset();
	if (!BLE_connected_to_IDE && !USB_connected_to_IDE) {
		pAdvertising->addServiceUUID(MB_SERVICE_UUID);
	}
	pAdvertising->setName(uniqueName);
	pAdvertising->setMinInterval(100);
	pAdvertising->setMaxInterval(200);
	if (serviceOnline) pAdvertising->start();
}

// Stop and resume IDE service (used by BLE UART

void BLE_suspendIDEService() {
	pServer->removeService(pService);
	pServer->setCallbacks(NULL);
}

void BLE_resumeIDEService() {
	pServer->addService(pService);
	pServer->setCallbacks(new MyServerCallbacks());
	pService->start();
	BLE_resumeAdvertising();
}

// IDE receive and send

int recvBytes(uint8 *buf, int count) {
	int bytesRead;

	updateConnectionState();

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

#define BLE_DISABLED_FILE "/_BLE_DISABLED_"

void BLE_setEnabled(int enableFlag) {
	#if defined(ARDUINO_ARCH_ESP32) || defined(RP2040_PHILHOWER)
		// Disable BLE connections from IDE if BLE_DISABLED_FILE file exists.

		if (enableFlag) {
			deleteFile(BLE_DISABLED_FILE);
		} else {
			createFile(BLE_DISABLED_FILE);
		}
	#elif defined(NRF52)
		// xxx todo: use user settings registers or Flash page just before persistent code store
	#endif

	if (enableFlag) {
		BLE_start();
	} else {
		BLE_stop();
	}
}

int BLE_isEnabled() {
	#if defined(ARDUINO_ARCH_ESP32)
		return !fileExists(BLE_DISABLED_FILE);
	#elif defined(NRF52)
		// xxx todo: use user settings registers or Flash page just before persistent code store
		return true;
	#endif
	return false;
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

// stubs for non-BLE:
void BLE_initThreeLetterID() { BLE_ThreeLetterID[0] = 0; }
void BLE_start() { }
void BLE_stop() { }
void BLE_pauseAdvertising() { }
void BLE_resumeAdvertising() { }
void BLE_setEnabled(int enableFlag) { }
int BLE_isEnabled() {return false; }

#endif

void restartSerial() {
	// Needed to work around a micro:bit issue that Serial can lock up during Flash compaction.

	Serial.end();
	Serial.begin(115200);
}
