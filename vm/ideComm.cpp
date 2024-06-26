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

// MicroBlocks IDE Service UUIDs

#define MB_SERVICE_UUID				"bb37a001-b922-4018-8e74-e14824b3a638"
#define MB_CHARACTERISTIC_UUID_RX	"bb37a002-b922-4018-8e74-e14824b3a638"
#define MB_CHARACTERISTIC_UUID_TX	"bb37a003-b922-4018-8e74-e14824b3a638"

// BLE Variables

int BLE_connected_to_IDE = false;
int USB_connected_to_IDE = false;

char BLE_ThreeLetterID[4];
static char bleDeviceName[32];

extern uint32 lastRcvTime; // xxx put in header

// Generic helper functions

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
}

static void initBLEDeviceName(const char *prefix) {
	// Create BLE name from three letter ID.

	BLE_initThreeLetterID();
	sprintf(bleDeviceName, "%s %s", prefix, BLE_ThreeLetterID);
}

static void showShapeForMSecs(int msecs) {
	uint32 endMSecs = millisecs() + msecs;
	while (millisecs() < endMSecs) {
		captureIncomingBytes();
		updateMicrobitDisplay();
		delay(1);
	}
}

static void show_BLE_ID() {
	OBJ args[5]; // used to call primitives

	int nameLen = strlen(bleDeviceName);
	for (int i = nameLen - 4; i < nameLen; i++) {
		args[0] = newStringFromBytes(&bleDeviceName[i], 1);
		OBJ letterShape = primMBShapeForLetter(1, args);

		args[0] = letterShape;
		args[1] = int2obj(1);
		args[2] = int2obj(1);
		primMBDrawShape(3, args);
		showShapeForMSecs(300);
		primMBDisplayOff(0, args);
		showShapeForMSecs(100);
	}
	primMBDisplayOff(0, args);
}

static void flashUserLED() {
	// used for debugging
	OBJ on = trueObj;
	OBJ off = falseObj;
	primSetUserLED(&on);
	updateMicrobitDisplay();
	delay(10);
	primSetUserLED(&off);
	updateMicrobitDisplay();
}

#if defined(BLE_IDE)

// BLE Communications

#include <NimBLEDevice.h>

// BLE_SEND_MAX - maximum bytes to send in a single attribute write (max is 512)
// INTER_SEND_TIME - don't send data more often than this to avoid NimBLE error & disconnect
#define BLE_SEND_MAX 250
#define INTER_SEND_TIME 20

static BLEServer *pServer = NULL;
static BLEService *pService = NULL;
static BLEService *pUARTService = NULL;
static BLECharacteristic *pTxCharacteristic;
static BLECharacteristic *pRxCharacteristic;
static bool bleRunning = false;
static bool serviceOnline = false;
static uint16_t connID = -1;

static uint32 lastSendTime = 0;
static int lastRC = 0;

#define RECV_BUF_MAX 1024
static uint8_t bleRecvBuf[RECV_BUF_MAX];
static int bleBytesAvailable = 0;
static int overRuns = 0;

static void updateConnectionState() {
	if (USB_connected_to_IDE && !ideConnected()) {
		// lost USB connection; resume BLE service and advertisting
		if (pServer) pServer->addService(pService);
		USB_connected_to_IDE = false;
	}
	if (BLE_connected_to_IDE && pServer && (pServer->getConnectedCount() == 0)) {
		// lost BLE connection
		if (pServer) {
			if (connID != -1) { pServer->disconnect(connID); }
			connID = -1;
		}
		BLE_connected_to_IDE = false;
	}
	if (!USB_connected_to_IDE) { // either not connected or connected via BLE
		if (Serial.available()) {
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
		lastRcvTime = microsecs();
		BLE_connected_to_IDE = true;
	}
	void onDisconnect(BLEServer* pServer, ble_gap_conn_desc* desc) {
		connID = -1;
		BLE_connected_to_IDE = false;
		BLE_resumeAdvertising();
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

BLEService * BLE_createUARTService(); // imported from blePrims.cpp

void BLE_start() {
	if (bleRunning) return; // BLE already running

	// Initialize three letter ID and name
	initBLEDeviceName("MicroBlocks");

	// Create BLE Device
	BLEDevice::init(bleDeviceName);

	// Create BLE Server
	pServer = BLEDevice::createServer();
	pServer->setCallbacks(new MyServerCallbacks());

	// Create IDE Service
	pService = pServer->createService(MB_SERVICE_UUID);
	pTxCharacteristic = pService->createCharacteristic(MB_CHARACTERISTIC_UUID_TX, NIMBLE_PROPERTY::NOTIFY);
	pTxCharacteristic->setCallbacks(new MyCallbacks());
	pRxCharacteristic = pService->createCharacteristic(MB_CHARACTERISTIC_UUID_RX, NIMBLE_PROPERTY::WRITE_NR);
	pRxCharacteristic->setCallbacks(new MyCallbacks());

	// Create UART Service
	pUARTService = BLE_createUARTService();

	// Start Services
	pService->start();
	pUARTService->start();

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
	pAdvertising->stop();
	pAdvertising->reset();
	if (BLE_connected_to_IDE || USB_connected_to_IDE) {
		return; // don't advertise if connected to IDE
	}
	pAdvertising->addServiceUUID(MB_SERVICE_UUID);
	pAdvertising->setName(bleDeviceName);
	pAdvertising->setMinInterval(50);
	pAdvertising->setMaxInterval(100);
	if (serviceOnline) pAdvertising->start();
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

#elif PICO_BLUETOOTH

// uncomment these to test BLE
// #include <BTstackLib.h>
// #include <ble/att_server.h>
// #include <ble/att_db_util.h>

static int bleRunning = false;
static hci_con_handle_t connectionHandle = 0;
static uint16_t txCharacteristic = 0;

#define BUF_SIZE 250 // 360 works, 380 fails; making both charactistics dynamic allows larger buffers

// incoming BLE buffer
#define RECV_BUF_MAX 1024
static uint8_t bleRecvBuf[RECV_BUF_MAX];
static int bleBytesAvailable = 0;
static int overRuns = 0;

// Pico advertising

static uint8_t adv_data[32]; // advertisting data is limited to 31 bytes on Pico
static int adv_data_len = 0;

void setAdvertisingData(const char *name, UUID uuid) {
	// See Common Data Types in:
	// https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/Assigned_Numbers.pdf?v=1716217306904

	int pos = 0;

	// flags
	const uint8_t flags[] = { 2, 1, 6 };
	memcpy(&adv_data[pos], flags, sizeof(flags));
	pos += sizeof(flags);

	// service UUID (low byte first)
	adv_data[pos++] = 17; // field size
	adv_data[pos++] = 7; // "Complete List of 128-bit Service Class UUIDs"
	const uint8_t *uuidBytes = uuid.getUuid();
	for (int i = 0; i < 16; i++) {
		adv_data[pos++] = uuidBytes[15 - i];
	}

	// name
	int nameBytes = strlen(name);
	if (nameBytes > (29 - pos)) nameBytes = 29 - pos; // truncate name to fit
	adv_data[pos++] = nameBytes + 1; // field size
	adv_data[pos++] = 9; // "Complete Local Name"
	memcpy(&adv_data[pos], name, nameBytes);
	pos += nameBytes;

	adv_data_len = pos;
	BTstack.setAdvData(adv_data_len, adv_data);
}

// Pico connect/disconnect callbacks

static void deviceConnectedCallback(BLEStatus status, BLEDevice *device) {
	if (BLE_STATUS_OK == status) {
		connectionHandle = device->getHandle();
		BLE_connected_to_IDE = true;
	}
}

static void deviceDisconnectedCallback(BLEDevice *device) {
	connectionHandle = 0;
	BLE_connected_to_IDE = false;
}

// Pico data receive callback

static int gattWriteCallback(uint16_t attribute_handle, uint8_t *data, uint16_t byteCount) {
	int available = RECV_BUF_MAX - bleBytesAvailable;
	if (byteCount > available) {
		overRuns++;
		byteCount = available;
	}
	memcpy(&bleRecvBuf[bleBytesAvailable], data, byteCount);
	bleBytesAvailable += byteCount;
	return 0;
}

int recvBytes(uint8 *buf, int count) {
	int bytesRead;

//	updateConnectionState(); // xxx todo for Pico

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

// 	if (!BLE_connected_to_IDE || !connectionHandle) { // no BLE connection; use Serial
// 		return Serial.write(&buf[start], end - start);
// 	}

	int byteCount = end - start;
	if (byteCount > BUF_SIZE) byteCount = BUF_SIZE;
	int status = att_server_notify(connectionHandle, txCharacteristic, &buf[start], byteCount);
	return (status ? 0 : byteCount);
}

void att_db_util_add_client_characteristic_configuration(uint16_t flags);

void BLE_start() {
	if (bleRunning) return; // BLE already running

	// Initialize three letter ID and name
	initBLEDeviceName("Pico");

	// setup GATT database
	BTstack.addGATTService(new UUID(MB_SERVICE_UUID));

	txCharacteristic = BTstack.addGATTCharacteristicDynamic(new UUID(MB_CHARACTERISTIC_UUID_TX), ATT_PROPERTY_READ | ATT_PROPERTY_NOTIFY, BUF_SIZE);
//	BTstack.addGATTCharacteristicDynamic(new UUID(MB_CHARACTERISTIC_UUID_RX), ATT_PROPERTY_WRITE | ATT_PROPERTY_WRITE_WITHOUT_RESPONSE, BUF_SIZE);
	BTstack.addGATTCharacteristicDynamic(new UUID(MB_CHARACTERISTIC_UUID_RX), ATT_PROPERTY_WRITE_WITHOUT_RESPONSE, BUF_SIZE);

	// set callbacks
	BTstack.setBLEDeviceConnectedCallback(deviceConnectedCallback);
	BTstack.setBLEDeviceDisconnectedCallback(deviceDisconnectedCallback);
	BTstack.setGATTCharacteristicWrite(gattWriteCallback);

	// start BLE and advertising
	BTstack.setup();
	setAdvertisingData(bleDeviceName, UUID(MB_SERVICE_UUID));
	BTstack.startAdvertising();

	bleRunning = true;
}

void BLE_stop() {
	// xxx to do
	bleRunning = false;
	BLE_connected_to_IDE = false;
}

#else

// BLE not supported -- use serial communications only

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
void BLE_start() { }
void BLE_stop() { }
void BLE_pauseAdvertising() { }
void BLE_resumeAdvertising() { }

#endif

void restartSerial() {
	// Needed to work around a micro:bit issue that Serial can lock up during Flash compaction.

	Serial.end();
	Serial.begin(115200);
}

// BLE enable/disable functions (do nothing on non-BLE boards)

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
	#if defined(ARDUINO_ARCH_ESP32) || defined(RP2040_PHILHOWER)
		return !fileExists(BLE_DISABLED_FILE);
	#elif defined(NRF52)
		// xxx todo: use user settings registers or Flash page just before persistent code store
		return true;
	#endif
	return false;
}
