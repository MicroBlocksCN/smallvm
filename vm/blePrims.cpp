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

#if defined(BLE_NUS_PRIMS)

// Experimental! Optional BLE UART support (compile with -D BLE_NUS_PRIMS)
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

#endif // BLE_NUS_PRIMS

#if defined(OCTO_PRIMS)

#include <NimBLEDevice.h>
#include <set>

BLEServer* pServer = NULL;
BLEAdvertising* pAdvertising = NULL;
BLEScan* pBLEScan;
bool BLEScanning = false;

const char* octoUUIDs[] = {
	"2540b6b0-0002-4538-bcd7-7ecfb51297c1", // iOS
	"2540b6b0-0001-4538-bcd7-7ecfb51297c1" // Android
};

int shape_id = 0;
int scanTime = 1; // Compared with 5, 1 can improve the response speed of iPhone OctoStudio
bool hasOctoMessage = false;
std::set<std::string> receivedOctoDatas;
int receivedOctoDatasMaxLength = 100;

static OBJ primOctoGetBLEInitialized(int argCount, OBJ *args) {
	return BLEDevice::getInitialized() ? trueObj : falseObj;
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
					if (receivedOctoDatas.size() > receivedOctoDatasMaxLength) {
						receivedOctoDatas.erase(receivedOctoDatas.begin());
					}
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
					if (receivedOctoDatas.size() > receivedOctoDatasMaxLength) {
						receivedOctoDatas.erase(receivedOctoDatas.begin());
					}
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
	pBLEScan->setWindow(99); // less or equal setInterval value

	pAdvertising = BLEDevice::getAdvertising();
	pAdvertising->addServiceUUID(BLEUUID(octoUUIDs[0]));
	pAdvertising->setScanResponse(true);
	pAdvertising->setMinPreferred(0x06); // functions that help with iPhone connections issue
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
	return BLEScanning ? trueObj : falseObj;
}

#endif // OCTO_PRIMS

#if defined(BLE_KEYBOARD)

// Experimental! Optional BLE keyboard support (compile with -D BLE_KEYBOARD)
// Code provided by Wenji Wu
// remixed primitives from hidPrims.cpp

#include <BleKeyboard.h>

BleKeyboard bleKeyboard;
int bleKeyboardInitialized = false;

void initBLEKeyboard () {
	if (!bleKeyboardInitialized) {
		char kbName[40];
		sprintf(kbName, "%s KB", boardType());
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

	#if defined(BLE_NUS_PRIMS)
		{"BLE_UART_Start", primBLE_UART_Start},
		{"BLE_UART_Stop", primBLE_UART_Stop},
		{"BLE_UART_Connected", primBLE_UART_Connected},
		{"BLE_UART_LastEvent", primBLE_UART_LastEvent},
		{"BLE_UART_Write", primBLE_UART_Write},
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

	#if defined(BLE_KEYBOARD)
		{"startKeyboard", primStartBLEKeyboard},
		{"PressKey", primBLEPressKey},
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
