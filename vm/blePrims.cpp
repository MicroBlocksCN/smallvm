/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// blePrims.cpp - MicroBlocks Bluetooth Low Energy (BLE) primitives
// Wenjie Wu, December 2023

#include <stdio.h>
#include <stdlib.h>
#include "mem.h"
#include "interp.h" // must be included *after* ESP8266WiFi.h

#if defined(BLE_IDE)
	// include UART and OCTO primitives when BLE_IDE is enabled
	#define BLE_OCTO 1
	#define BLE_UART 1
#endif

#if defined(BLE_OCTO) //Octo primtives; included in standard BLE release

#include <NimBLEDevice.h>

NimBLEUUID ANDROID_OCTO_UUID	= NimBLEUUID("2540b6b0-0001-4538-bcd7-7ecfb51297c1");
NimBLEUUID iOS_OCTO_UUID		= NimBLEUUID("2540b6b0-0002-4538-bcd7-7ecfb51297c1");

static BLEAdvertising* pAdvertising = NULL;

static bool bleScannerRunning = false;
static bool hasOctoMessage = false;
static int shape_id = 0;

// record last scan payload
#define MAX_SCAN_PAYLOAD 100
static int lastScanPayloadLen = 0;
static uint8 *lastScanPayload[MAX_SCAN_PAYLOAD];
static uint8 lastScanRSSI = 0;
static uint8 lastScanAddressType = 0;
static uint8 lastScanAddress[6];

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
				if (serviceData.length() == 13) {
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

		if (lastScanPayloadLen != 0) return; // last capture has not been consumed

		// capture scan payload
		lastScanPayloadLen = advertisedDevice->getPayloadLength();
		if (lastScanPayloadLen > MAX_SCAN_PAYLOAD) lastScanPayloadLen = MAX_SCAN_PAYLOAD;
		memcpy(lastScanPayload, advertisedDevice->getPayload(), lastScanPayloadLen);

		// capture RSSI and address
		lastScanRSSI = -advertisedDevice->getRSSI(); // make it positive
		NimBLEAddress addr = advertisedDevice->getAddress();
		lastScanAddressType = addr.getType();
		memcpy(lastScanAddress, addr.getNative(), 6);
	}
};

static void startBLEScanner() {
	if (!bleScannerRunning) {
		// initialize allZeroMessageID; ignore messages with that ID sent by iOS OctoStudio
		memcpy(&allZeroMessageID, "00000000", 8);

		BLEScan *pScanner = BLEDevice::getScan();
		pScanner->setAdvertisedDeviceCallbacks(new BLEScannerCallbacks());
		pScanner->setMaxResults(0); // don't save results; use callback only
		pScanner->setActiveScan(true); // required by Octo
		pScanner->setDuplicateFilter(false); // good ???
		pScanner->start(0, NULL, false);
		bleScannerRunning = true;
	}
}

static void stopBLEScanner() {
	if (bleScannerRunning) {
		BLEDevice::getScan()->stop();
		bleScannerRunning = false;
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

	int payloadLen = lastScanPayloadLen;
	int byteCount = payloadLen + 8;
	int wordCount = (byteCount + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (!result) return fail(insufficientMemoryError);
	setByteCountAdjust(result, byteCount);

	// Result format is:
	//	absolute value of RSSI (one byte)
	//	address type (one byte)
	//	address (six bytes)
	//	payload (remaining bytes)
	uint8 *byteArray = (uint8 *) &FIELD(result, 0);
	byteArray[0] = lastScanRSSI;
	byteArray[1] = lastScanAddressType;
	memcpy(byteArray + 2, lastScanAddress, 6);
	memcpy(byteArray + 8, lastScanPayload, payloadLen);
	lastScanPayloadLen = 0;

	return result;
}

#endif // BLE_OCTO

#if defined(BLE_UART)

// Original UART code was provided by Wenji Wu. Thanks!

// BLE UART service and IDE service are mutually incompatible:
// * When the board is connected to the IDE via BLE, then the UART cannot be started.
// * When the UART is in use you cannot connect the IDE to the board via BLE.
// However, can always connect the the board using a USB cable.

#include <NimBLEDevice.h>

static BLEService *pUARTService = NULL;
static BLECharacteristic * pUARTTxCharacteristic;
static BLECharacteristic * pUARTRxCharacteristic;
static int uartConnectionID = -1;
static bool bleUARTStarted = false;

// Empty byte array and string constants
static uint32 emptyByteArray = HEADER(ByteArrayType, 0);
static uint32 emptyString[2] = { HEADER(StringType, 1), 0 };

// Receive buffer
static uint8 uartRecvBuf[256];
static int uartBytesReceived = 0;

// UUIDs for the Nordic UART Service (NUS)
#define UART_SERVICE_UUID	"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define UART_UUID_RX		"6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define UART_UUID_TX		"6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

class UARTServerCallbacks: public BLEServerCallbacks {
	void onConnect(BLEServer* server, ble_gap_conn_desc* desc) {
		uartConnectionID = desc->conn_handle;
	}
	void onDisconnect(BLEServer* server) {
		uartConnectionID = -1;
	}
};

class UARTCallbacks: public BLECharacteristicCallbacks {
	void onWrite(BLECharacteristic *pCharacteristic, ble_gap_conn_desc* desc) {
		const char *rxValue = pCharacteristic->getValue().c_str();
		int byteCount = strlen(rxValue);
		int spaceAvailable = sizeof(uartRecvBuf) - uartBytesReceived;
		if (byteCount > spaceAvailable) byteCount = spaceAvailable;
		memcpy(&uartRecvBuf[uartBytesReceived], rxValue, byteCount);
		uartBytesReceived += byteCount;
	}
	void onStatus(NimBLECharacteristic* pCharacteristic, Status s, int code) {
		// noop
	}
};

static OBJ primUART_start(int argCount, OBJ *args) {
	if (BLE_connected_to_IDE) return fail(cannotUseWithBLE);

	if (bleUARTStarted) return falseObj;
	bleUARTStarted = true;
	BLEServer *pServer = BLEDevice::getServer();

	// Workaround: Stop the scanner, if running, to avoid a fatal NimBLE error
	stopBLEScanner();

	BLE_suspendIDEService();

	if (!pUARTService) {
		// Create UART service (first time only)
		pUARTService = pServer->createService(UART_SERVICE_UUID);
		pUARTTxCharacteristic = pUARTService->createCharacteristic(UART_UUID_TX, NIMBLE_PROPERTY::NOTIFY); // NIMBLE_PROPERTY::READ);
		pUARTTxCharacteristic->setCallbacks(new UARTCallbacks());
		pUARTRxCharacteristic = pUARTService->createCharacteristic(UART_UUID_RX, NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::WRITE);
		pUARTRxCharacteristic->setCallbacks(new UARTCallbacks());
	} else {
		// Add existing UART service
		pServer->addService(pUARTService);
	}

	pServer->setCallbacks(new UARTServerCallbacks());
	pUARTService->start();
	BLEDevice::getAdvertising()->addServiceUUID(UART_SERVICE_UUID);
 	BLEDevice::startAdvertising();

	return falseObj;
}

static OBJ primUART_stop(int argCount, OBJ *args) {
	if (bleUARTStarted) {
		bleUARTStarted = false;
		BLEServer *pServer = BLEDevice::getServer();

		// Workaround: Stop the scanner, if running, to avoid a NimBLE assertion failure
		stopBLEScanner();

		if (uartConnectionID != -1) {
			// disconnect UART connection
			pServer->disconnect(uartConnectionID);
			uartConnectionID = -1;
		}

		pServer->removeService(pUARTService); // remove but don't deallocate
		BLE_resumeIDEService();
	}
	return falseObj;
}

static OBJ primUART_connected(int argCount, OBJ *args) {
	return (uartConnectionID != -1) ? trueObj : falseObj;
}

static OBJ primUART_read(int argCount, OBJ *args) {
	// If optional argument is true, return a byte array. Otherwise, return a string.

	if (uartConnectionID == -1) uartBytesReceived = 0;
	int returnBytes = (argCount > 0) && (trueObj == args[0]);
	if (uartBytesReceived <= 0) return (returnBytes ? (OBJ) &emptyByteArray : (OBJ) &emptyString);

	OBJ result = falseObj;
	if (returnBytes) { // return a ByteArray
		int wordCount = (uartBytesReceived + 3) / 4;
		result = newObj(ByteArrayType, wordCount, falseObj);
		if (!result) return fail(insufficientMemoryError);
		setByteCountAdjust(result, uartBytesReceived);
		memcpy(&FIELD(result, 0), uartRecvBuf, uartBytesReceived);
	} else { // return a string
		const char *s = (const char *) uartRecvBuf;
		result = newStringFromBytes(s, uartBytesReceived);
		if (!result) return fail(insufficientMemoryError);
	}
	uartBytesReceived = 0;
	return result;
}

static OBJ primUART_write(int argCount, OBJ *args) {
	OBJ arg = args[0];
	int startIndex = 0;

	if (uartConnectionID == -1) return zeroObj;

	if ((argCount > 1) && isInt(args[1])) { // optional second argument: startIndex
		startIndex = obj2int(args[1]) - 1; // convert to zero based index
		if (startIndex < 0) startIndex = 0;
	}

	int byteCount = 0;
	if (IS_TYPE(arg, StringType)) {
		byteCount = strlen(obj2str(arg)) - startIndex;
	} else if (IS_TYPE(arg, ByteArrayType)) {
		byteCount = BYTES(arg) - startIndex;
	} else {
		return fail(needsByteArray);
	}
	if (byteCount <= 0) return zeroObj;

	if (byteCount > 240) byteCount = 240; // maximum payload for efficient transfer
	pUARTTxCharacteristic->setValue(((uint8_t *) &FIELD(arg, 0)) + startIndex, byteCount);
	pUARTTxCharacteristic->notify();
	taskSleep(15); // data will be dropped if sent too fast
	return int2obj(byteCount);
}

#endif // BLE_UART


#if defined(BLE_KEYBOARD)

// BLE keyboard support
// Code provided by Wenji Wu based on hidPrims.cpp API

#include <BleKeyboard.h>

BleKeyboard bleKeyboard;
int bleKeyboardInitialized = false;

void initBLEKeyboard () {
	if (!bleKeyboardInitialized) {
		char kbName[40];
		BLE_initThreeLetterID();
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

	#if defined(BLE_OCTO)
		{"octoStartBeam", primOctoStartBeam},
		{"octoStopBeam", primOctoStopBeam},
		{"octoReceive", primOctoReceive},
		{"scanReceive", primScanReceive},
	#endif

	#if defined(BLE_UART)
		{"uartStart", primUART_start},
		{"uartStop", primUART_stop},
		{"uartConnected", primUART_connected},
		{"uartRead", primUART_read},
		{"uartWrite", primUART_write},
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
