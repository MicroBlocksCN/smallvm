/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// blePrims.cpp - MicroBlocks network primitives
// Wenjie Wu, December 2023

#include <stdio.h>
#include <stdlib.h>
#include "mem.h"
#include "interp.h" // must be included *after* ESP8266WiFi.h

#if defined(BLE_UART)

// Experimental! Optional BLE UART support (compile with -D BLE_UART)
// Code provided by Wenji Wu

// https://registry.platformio.org/libraries/nkolban/ESP32%20BLE%20Arduino/examples/BLE_uart/BLE_uart.ino
// https://github.com/h2zero/NimBLE-Arduino/blob/release/1.4/examples/Refactored_original_examples/BLE_uart/BLE_uart.ino
// client debug: chrome://bluetooth-internals/

#include <NimBLEDevice.h>

static bool bleUARTStarted = false;
BLEServer *pUARTServer = NULL;
BLECharacteristic * pUARTTxCharacteristic;
BLECharacteristic * pUARTRxCharacteristic;
bool deviceConnected = false;

static char lastBLE_UART_Message[100];
static bool hasBLE_UART_Message = false;

// UUIDs for the Nordic UART Service (NUS)
#define SERVICE_UUID			"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX	"6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX	"6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

class UARTServerCallbacks: public BLEServerCallbacks {
	void onConnect(BLEServer* pUARTServer) {
		outputString("UART connected");
		pUARTServer->stopAdvertising();
		deviceConnected = true;
	}

	void onDisconnect(BLEServer* pUARTServer) {
		outputString("UART disconnected");
		pUARTServer->startAdvertising();
		deviceConnected = false;
	}
};

class UARTCallbacks: public BLECharacteristicCallbacks {
	void onWrite(BLECharacteristic *pCharacteristic) {
		const char *rxValue = pCharacteristic->getValue().c_str();

		int len = strlen(rxValue);
		if (len > 0) {
			if (len > 99) len = 99;
			memcpy(lastBLE_UART_Message, rxValue, len);
			lastBLE_UART_Message[len] = '\0';
			hasBLE_UART_Message = true;
		}
	}
};

static OBJ primBLE_UART_Start(int argCount, OBJ *args) {
	const char* name = (argCount > 0) ? obj2str(args[0]) : "NimBLE UART";

	if (bleUARTStarted) {
		return falseObj;
	}
	bleUARTStarted = true;

	// Create BLE Device
	BLEDevice::init(name);

	// Create BLE Server
	pUARTServer = BLEDevice::createServer();
	pUARTServer->setCallbacks(new UARTServerCallbacks());

	// Create BLE Service
	BLEService *pService = pUARTServer->createService(SERVICE_UUID);

	// Create BLE Characteristics
	pUARTTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ);
	pUARTRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, NIMBLE_PROPERTY::WRITE);
	pUARTRxCharacteristic->setCallbacks(new UARTCallbacks());

	// Start the service
	pService->start();

	// Add the service to the advertisment data
	pUARTServer->getAdvertising()->addServiceUUID(pService->getUUID());

	// Start advertising
	pUARTServer->getAdvertising()->start();

	return falseObj;
}

static OBJ primBLE_UART_Stop(int argCount, OBJ *args) {
	if (bleUARTStarted) {
		BLEDevice::stopAdvertising();
		BLEDevice::deinit(false);
		bleUARTStarted = false;
	}
	return falseObj;
}

static OBJ primBLE_UART_Connected(int argCount, OBJ *args) {
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
	pUARTTxCharacteristic->setValue((uint8_t*) message, strlen(message));
	pUARTTxCharacteristic->notify();
	delay(10); // bluetooth stack will go into congestion, if too many packets are sent
	return falseObj;
}

#endif // BLE_UART

#if defined(BLE_IDE) //Octo primtives; included in standard BLE release

#include <NimBLEDevice.h>

NimBLEUUID ANDROID_OCTO_UUID	= NimBLEUUID("2540b6b0-0001-4538-bcd7-7ecfb51297c1");
NimBLEUUID iOS_OCTO_UUID		= NimBLEUUID("2540b6b0-0002-4538-bcd7-7ecfb51297c1");

static BLEScan* pOctoScanner = NULL;
static BLEAdvertising* pAdvertising = NULL;

static bool bleScannerRunning = false;
static bool hasOctoMessage = false;
static int shape_id = 0;

// record last scan payload
#define MAX_SCAN_PAYLOAD 100
static int lastScanPayloadLen = 0;
static uint8 *lastScanPayload[MAX_SCAN_PAYLOAD];

// octoIDHistory is an array of recently seen Octo ID's used for duplicate suppression.
// Its size must be a power of 2. Searching for an ID starts at searchStartIndex.
// When an ID is not found, searchStartIndex is decremented (mod the array size)
// and the new ID is added at that index. Thus, the most recently added ID
// is at searchStartIndex, the second most recent at searchStartIndex+1, etc.
// The first time an ID is seen, the entire history must be searched but after
// that, the ID will be found in one or, at most, a few steps. The common case
// is testing for an ID that has already been seen since OctoStudio often sends
// the same message 50-60 times.

typedef long long unsigned int octoMsgID;
octoMsgID allZeroMessageID;

#define OCTO_ID_HISTORY_SIZE 32
octoMsgID octoIDHistory[OCTO_ID_HISTORY_SIZE];
int searchStartIndex = 0;

static int octoIDNotYetSeen(octoMsgID id) {
int steps = 0;
	int endIndex = (searchStartIndex - 1) & (OCTO_ID_HISTORY_SIZE - 1);
	for (int i = searchStartIndex; i != endIndex; i = ((i + 1) % OCTO_ID_HISTORY_SIZE)) {
		if (octoIDHistory[i] == id) return false;
		steps++;
	}
	return true;
}

static void addIDToOctoHistory(octoMsgID id) {
	searchStartIndex = (searchStartIndex - 1) & (OCTO_ID_HISTORY_SIZE - 1);
	octoIDHistory[searchStartIndex] = id;
}

class BLEScannerCallbacks : public BLEAdvertisedDeviceCallbacks {
	void onResult(BLEAdvertisedDevice* advertisedDevice) {
		if (advertisedDevice->haveServiceUUID()) {
			// iOS
			BLEUUID uuid = advertisedDevice->getServiceUUID();
			if (iOS_OCTO_UUID.equals(uuid)) {
				std::string deviceName = advertisedDevice->getName();
				if (deviceName.length() == 16) {
					octoMsgID id;
					memcpy(&id, deviceName.c_str(), 8);
					if ((id != allZeroMessageID) && octoIDNotYetSeen(id)) {
						addIDToOctoHistory(id);
						shape_id = deviceName.back() - '0';
						if (shape_id < 0) shape_id = 255; // ensure shape_id is positive
						hasOctoMessage = true;
					}
				}
			}
		} else if (advertisedDevice->haveServiceData()) {
			// Android
			BLEUUID uuid = advertisedDevice->getServiceDataUUID();
			if (ANDROID_OCTO_UUID.equals(uuid)) {
				std::string serviceData = advertisedDevice->getServiceData();
				if (serviceData.length() == 16) {
					octoMsgID id;
					memcpy(&id, serviceData.c_str(), 8);
					if (octoIDNotYetSeen(id)) {
						addIDToOctoHistory(id);
						shape_id = serviceData[7];
						hasOctoMessage = true;
					}
				}
			}
		}

		// capture scan payload
		lastScanPayloadLen = advertisedDevice->getPayloadLength();
		if (lastScanPayloadLen > MAX_SCAN_PAYLOAD) lastScanPayloadLen = MAX_SCAN_PAYLOAD;
		memcpy(lastScanPayload, advertisedDevice->getPayload(), lastScanPayloadLen);
	}
};

static void scanComplete(BLEScanResults scanResults) {
	// Restarts the scanner so that we scan continuously.

	pOctoScanner->clearResults();
	pOctoScanner->start(1, scanComplete, false);
}

static void startBLEScanner() {
	if (!bleScannerRunning) {
		// initialize allZeroMessageID; ignore messages with that ID sent by iOS OctoStudio
		memcpy(&allZeroMessageID, "00000000", 8);

		pOctoScanner = BLEDevice::getScan();
		pOctoScanner->setAdvertisedDeviceCallbacks(new BLEScannerCallbacks());
		pOctoScanner->setMaxResults(0); // don't save results; use callback only
		pOctoScanner->setActiveScan(true); // required by Octo
		pOctoScanner->setDuplicateFilter(false); // good ???
		pOctoScanner->start(1, scanComplete, false);
		bleScannerRunning = true;
	}
}

static OBJ primOctoStartBeam(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], StringType)) return falseObj;

	char *msg = obj2str(args[0]);

	// Mimic iOS beam; data is encoded in name
	BLE_pauseAdvertising();
	pAdvertising = BLEDevice::getAdvertising();
	pAdvertising->reset();
	pAdvertising->addServiceUUID(iOS_OCTO_UUID);
	pAdvertising->setName(msg);
	pAdvertising->setMinInterval(32);
	pAdvertising->setMaxInterval(32);
	pAdvertising->start();
	return falseObj;
}

static OBJ primOctoStopBeam(int argCount, OBJ *args) {
	if (!pAdvertising) return falseObj; // not initialized thus not beaming

	BLEDevice::getAdvertising()->removeServiceUUID(iOS_OCTO_UUID);
	BLE_resumeAdvertising();
	return falseObj;
}

static OBJ primOctoReceive(int argCount, OBJ *args) {
	if (!bleScannerRunning) startBLEScanner();

	if (hasOctoMessage) {
		hasOctoMessage = false;
		return int2obj(shape_id);
	} else {
		return falseObj;
	}
}

static OBJ primScanReceive(int argCount, OBJ *args) {
	if (!bleScannerRunning) startBLEScanner();
	if (!lastScanPayloadLen) return falseObj; // no data

	int byteCount = lastScanPayloadLen;
	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (!result) return fail(insufficientMemoryError);
	memcpy((uint8 *) &FIELD(result, 0), lastScanPayload, byteCount);
	setByteCountAdjust(result, byteCount);
	lastScanPayloadLen = 0;

	return result;
}

#endif // Octo primitives

#if defined(BLE_KEYBOARD)

// BLE keyboard support
// Code provided by Wenji Wu based on hidPrims.cpp API

#include <BleKeyboard.h>

BleKeyboard bleKeyboard;
int bleKeyboardInitialized = false;

void initBLEKeyboard () {
	if (!bleKeyboardInitialized) {
		char kbName[40];
		sprintf(kbName, "MicroBlocks KB %s", BLE_ThreeLetterID);
		bleKeyboard.setName(kbName);
		bleKeyboard.begin();
		bleKeyboardInitialized = true;
	}
}

OBJ primBLEPressKey(int argCount, OBJ *args) {
	initBLEKeyboard();
	OBJ key = args[0];
	int modifier = (argCount > 1) ? obj2int(args[1]) : 0;
	if (modifier) {
		switch (modifier) {
			case 1: // shift
				bleKeyboard.press(KEY_LEFT_SHIFT);
				break;
			case 2: // control
				bleKeyboard.press(KEY_LEFT_CTRL);
				break;
			case 3: // alt (option on Mac)
				bleKeyboard.press(KEY_LEFT_ALT);
				break;
			case 4: // meta (command on Mac)
				bleKeyboard.press(KEY_LEFT_GUI);
				break;
			case 5: // AltGr (option on Mac)
				bleKeyboard.press(KEY_RIGHT_ALT);
				break;
		}
	}

	// accept both characters and ASCII values
	if (IS_TYPE(key, StringType)) {
		bleKeyboard.write(obj2str(key)[0]);
	} else if (isInt(key)) {
		bleKeyboard.write(obj2int(key));
	}

	if (modifier) bleKeyboard.releaseAll();
	return falseObj;
}

OBJ primBLEHoldKey(int argCount, OBJ *args) {
	initBLEKeyboard();
	OBJ key = args[0];

	// accept both characters and ASCII values
	if (IS_TYPE(key, StringType)) {
		bleKeyboard.press(obj2str(key)[0]);
	} else if (isInt(key)) {
		bleKeyboard.press(obj2int(key));
	}
	return falseObj;
}

OBJ primBLEReleaseKey(int argCount, OBJ *args) {
	initBLEKeyboard();
	OBJ key = args[0];

	// accept both characters and ASCII values
	if (IS_TYPE(key, StringType)) {
		bleKeyboard.release(obj2str(key)[0]);
	} else if (isInt(key)) {
		bleKeyboard.release(obj2int(key));
	}
	return falseObj;
}

OBJ primBLEReleaseAllKeys(int argCount, OBJ *args) {
	bleKeyboard.releaseAll();
	return falseObj;
}

static OBJ primStartBLEKeyboard(int argCount, OBJ *args) {
	if (BLE_connected_to_IDE) return falseObj; // can't use BLE keyboard while connected over BLE

	initBLEKeyboard();
	return falseObj;
}

#endif // BLE_KEYBOARD

#if defined(ESP_NOW_PRIMS)

// Experimental! Optional ESP Now support (compile with -D ESP_NOW_PRIMS)
// Code provided by Wenji Wu

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
		ESP.restart(); //
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

	#if defined(BLE_UART)
		{"BLE_UART_Start", primBLE_UART_Start},
		{"BLE_UART_Stop", primBLE_UART_Stop},
		{"BLE_UART_Connected", primBLE_UART_Connected},
		{"BLE_UART_LastEvent", primBLE_UART_LastEvent},
		{"BLE_UART_Write", primBLE_UART_Write},
	#endif

	#if defined(BLE_IDE)
		{"octoStartBeam", primOctoStartBeam},
		{"octoStopBeam", primOctoStopBeam},
		{"octoReceive", primOctoReceive},
		{"scanReceive", primScanReceive},
	#endif

	#if defined(BLE_KEYBOARD)
		{"startKeyboard", primStartBLEKeyboard},
		{"pressKey", primBLEPressKey},
		{"holdKey", primBLEHoldKey},
		{"releaseKey", primBLEReleaseKey},
		{"releaseKeys", primBLEReleaseAllKeys},
	#endif

	#if defined(ESP_NOW_PRIMS)
		{"EspNowLastEvent", primEspNowLastEvent},
		{"EspNowBroadcast", primEspNowBroadcast},
	#endif

};

void addBLEPrims() {
	addPrimitiveSet("ble", sizeof(entries) / sizeof(PrimEntry), entries);
}
