/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2024 John Maloney, Bernat Romagosa, and Jens Mönig

// blePrims.cpp - MicroBlocks Bluetooth Low Energy (BLE) primitives
// Wenjie Wu, December 2023
// Modified by John Maloney, April 2024
// Modified by John Maloney, July 2024

// To do: implement group filtering for incoming OctoStudio beams

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

#if defined(BLE_IDE)
	#include <NimBLEDevice.h>

	// include UART and OCTO primitives when BLE_IDE is enabled
	#define BLE_OCTO 1
	#define BLE_UART 1
#endif

#if defined(BLE_PICO)
	#include <BTstackLib.h>
	#include <ble/att_server.h>

	// include UART and OCTO primitives when BLE_PICO is enabled
	#define BLE_OCTO 1
	#define BLE_UART 1
#endif

static OBJ primBLE_connected(int argCount, OBJ *args) {
	// BLE_connected_to_IDE is true if *any* BLE client is connected to the board,
	// regardless of which service they are using.

	return BLE_connected_to_IDE ? trueObj : falseObj;
}

#if defined(BLE_OCTO) //Octo primtives; included in standard BLE release

#define iOS_OCTO_UUID_STRING		"2540b6b0-0002-4538-bcd7-7ecfb51297c1"
#define ANDROID_OCTO_UUID_STRING	"2540b6b0-0001-4538-bcd7-7ecfb51297c1"
#define MICROBLOCK_MANUFACTURER_ID	0xDE00  // in decimal, LSB first: [0, 222]

static bool bleScannerRunning = false;
static bool hasOctoMessage = false;
static int octoGroupID = 0;
static int octoShapeID = 0;

// Empty byte array
static uint32 noRadioMsg = HEADER(ByteArrayType, 0);

// record last scan payload
#define MAX_SCAN_PAYLOAD 100
static int lastScanPayloadLen = 0;
static uint8 lastScanPayload[MAX_SCAN_PAYLOAD];
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

typedef long long unsigned int MsgID;
MsgID allZeroMessageID;

#define OCTO_ID_HISTORY_SIZE 32
MsgID octoIDHistory[OCTO_ID_HISTORY_SIZE];
int searchStartIndex = 0;

static int octoIDNotYetSeen(MsgID id) {
	int endIndex = (searchStartIndex - 1) & (OCTO_ID_HISTORY_SIZE - 1);
	for (int i = searchStartIndex; i != endIndex; i = ((i + 1) % OCTO_ID_HISTORY_SIZE)) {
		if (octoIDHistory[i] == id) return false;
	}
	return true;
}

static void addIDToOctoHistory(MsgID id) {
	searchStartIndex = (searchStartIndex - 1) & (OCTO_ID_HISTORY_SIZE - 1);
	octoIDHistory[searchStartIndex] = id;
}

// Helper functions

static int hexDigit(char ch) {
	// Return the hex value of the given hexadecimal digit or zero for a non-hex character.
	// Accepts upper or lower case letters A-F.

	if (('0' <= ch) && (ch <= '9')) return ch - '0';
	if (('A' <= ch) && (ch <= 'F')) return 10 + (ch - 'A');
	if (('a' <= ch) && (ch <= 'f')) return 10 + (ch - 'a');
	return 0;
}

// BLE Radio Support

// A BLE radio message is a 31-byte advertisting packet containing a manufacturer data entry:
//	<len>
//	255
//	<MICROBLOCK_MANUFACTURER_ID (2 bytes, LSB)>
//	<group number>
//	<sequence number>
//	<payload (remainder of packet, max 25 bytes)

// last BLE radio message, including its RSSI and address
#define MAX_RADIO_MSG 32
#define MAX_RADIO_PAYLOAD 25  // maximum that fits in a 31-byte legacy advertising packet
static uint8 lastRadioMsg[MAX_RADIO_MSG];
static int lastRadioMsgLen = 0;

static uint8 radioGroup = 0;
static uint8 radioSequenceNumber = 0;

static void initRadioMsgHeader(uint8 *adv_data, int payloadBytes) {
	if (payloadBytes > MAX_RADIO_PAYLOAD) payloadBytes = MAX_RADIO_PAYLOAD;

	// send data as manufacturer ID tag
	adv_data[0] = payloadBytes + 5;
	adv_data[1] = 255;
	adv_data[2] = MICROBLOCK_MANUFACTURER_ID & 255;
	adv_data[3] = (MICROBLOCK_MANUFACTURER_ID >> 8) & 255;
	adv_data[4] = radioGroup;
	adv_data[5] = radioSequenceNumber;
	radioSequenceNumber = (radioSequenceNumber + 1) & 255; // increment sequence number
}

static int isBLERadioMsgToGroup(const uint8_t *advertData) {
	if (!advertData) return false;
	if (advertData[0] < 5) return false; // first entry is too small to be start of a radio message
	if (advertData[1] != 255) return false; // first entry is not manufacturer data
	if ((advertData[2] != (MICROBLOCK_MANUFACTURER_ID & 255)) ||
		(advertData[3] != ((MICROBLOCK_MANUFACTURER_ID >> 8) & 255))) {
			return false; // not the MicroBlocks manufacturer ID
	}
	if (advertData[4] != radioGroup) return false; // group does not match
	return true;
}

static void saveRadioMsg(MsgID radioMsgID, const uint8_t *advertData) {
	// If it is not a duplicate, extract and save the radio message from the advertising data.

	if (octoIDNotYetSeen(radioMsgID)) {
		addIDToOctoHistory(radioMsgID);
		int byteCount = advertData[0] - 5;
		if (byteCount > MAX_RADIO_MSG) byteCount = MAX_RADIO_MSG;
		memcpy(lastRadioMsg, &advertData[6], byteCount);
		lastRadioMsgLen = byteCount;
	}
}

#if defined(BLE_PICO) // Pico OCTO primitive support

static void stopBeaming() {
	BLE_pauseAdvertising();
	BLE_resumeAdvertising();
}

static void startOctoBeam(char *msg) {
	// Note: This does not work with the current BTstack library because it limits
	// advertisements to 31 bytes and an Octo beam requires at at least 34 bytes
	// for the name and the UUID fields.
	// It should work once BTstack supports extended advertising.

	BLE_pauseAdvertising();
	BLE_setPicoAdvertisingData(msg, iOS_OCTO_UUID_STRING);
}

void setAdvertisingInterval(int minInterval, int maxInterval);

static void startRadioBeam(uint8 *msg, int msgByteCount) {
	uint8_t adv_data[32];

	// truncate to fit in 31-byte legacy advertising packet
	if (msgByteCount > MAX_RADIO_PAYLOAD) msgByteCount = MAX_RADIO_PAYLOAD;

	memset(adv_data, 0, sizeof(adv_data));
	initRadioMsgHeader(adv_data, msgByteCount);
	memcpy(&adv_data[6], msg, msgByteCount);

	BTstack.setAdvData(msgByteCount + 6, adv_data);
	setAdvertisingInterval(32, 32);
	BTstack.startAdvertising();
}

static int advertLength(const uint8_t *advertData) {
	// Return the length of the given advertisment by scanning for a zero length entry.
	// Note: There does not appear to a way to get the actual length using the BTStack API.

	int maxLen = LE_ADVERTISING_DATA_SIZE + 10; // from BTstack.h (41 bytes)
	int i = 0;
	while (i < maxLen) {
		if (!advertData[i]) return i; // entry with zero length indicates end of data
		int nextEntry = i + advertData[i] + 1; // start of next entry
		if (nextEntry >= maxLen) return i; // next entry has bad length so must be past end
		i += advertData[i] + 1; // jump to next entry
	}
	return maxLen;
}

static int isOctoName(const uint8_t *sixteenBytes) {
	// Return true if the given 16-byte string contains only digits 0-9 and capital letters A-F.

	for (int i = 0; i < 16; i++) {
		int ch = sixteenBytes[i];
		if (!((('0' <= ch) && (ch <= '9')) ||
			  (('A' <= ch) && (ch <= 'F')))) {
			 	return false;
		}
	}
	return true;
}

static int hasOctoName(const uint8_t *advertData, char *octoName) {
	// Return true and fill in octoName if the given advertisment has a 16-character
	// hexadecimal name field.

	int maxLen = LE_ADVERTISING_DATA_SIZE + 10; // from BTstack.h (41 bytes)
	int i = 0;
	while (i < maxLen) {
		if (!advertData[i]) return false; // entry with zero length indicates end of data
		if ((17 == advertData[i]) &&
			(9 == advertData[i+1]) &&
			isOctoName(&advertData[i+2])) {
				memcpy(octoName, &advertData[i+2], 16);
				return true;
		}
		i += advertData[i] + 1; // jump to next entry
	}
	return false;
}

// Android Octo UUID bytes (in little-endian order)
static uint8 octoUUID[] = {
	0xc1, 0x97, 0x12, 0xb5, 0xcf, 0x7e, 0xd7, 0xbc,
	0x38, 0x45, 0x1, 0x0, 0xb0, 0xb6, 0x40, 0x25};

static int isAndroidOcto(const uint8_t *advertData) {
	if (!((advertData[0] == 30) && (advertData[1] == 33))) return false;
	// first 16 bytes must match Android Octo service UUID
	for (int i = 0; i < 16; i++) {
		if (advertData[i + 2] != octoUUID[i]) return false;
	}
	return true;
}

static void BLEScannerCallback(BLEAdvertisement *advert) {
	char octoName[20];
	const uint8_t *advData = advert->getAdvData();

	if (hasOctoName(advData, octoName)) {
		// Since BTstack does not yet support extended advertisements, we do not have
		// the UUID available (because it doesn't fit). Instead, we just assume that any
		// advertistement with a 16-character hexadecimal name is an Octo beam message.

		MsgID id;
		memcpy(&id, octoName, 8);
		if ((id != allZeroMessageID) && octoIDNotYetSeen(id)) {
			addIDToOctoHistory(id);
			octoGroupID = (hexDigit(octoName[12]) << 4) + hexDigit(octoName[13]);
			octoShapeID = (hexDigit(octoName[14]) << 4) + hexDigit(octoName[15]);
			hasOctoMessage = true;
		}
	}

	if (isAndroidOcto(advData)) {
		MsgID id;
		memcpy(&id, &advData[19], 8);
		if (octoIDNotYetSeen(id)) {
			addIDToOctoHistory(id);
			octoGroupID = advData[24];
			octoShapeID = advData[25];
			hasOctoMessage = true;
		}
	}

	if (isBLERadioMsgToGroup(advData)) {
		MsgID radioMsgID; // radioMsgID is 6-byte address + sequence number + group
		memcpy(&radioMsgID, advert->getBdAddr()->getAddress(), 6);
		memcpy(((uint8 *) &radioMsgID) + 6, &advData[4], 2);
		saveRadioMsg(radioMsgID, advData);
	}

	if (lastScanPayloadLen != 0) return; // last capture has not been consumed

	// capture scan payload
	lastScanPayloadLen = advertLength(advData);
	if (lastScanPayloadLen > MAX_SCAN_PAYLOAD) lastScanPayloadLen = MAX_SCAN_PAYLOAD;
	memcpy(lastScanPayload, advData, lastScanPayloadLen);

	// capture RSSI and address
	lastScanRSSI = advert->getRssi();
	BD_ADDR *bdAddr = advert->getBdAddr();
	lastScanAddressType = bdAddr->getAddressType();
	memcpy(lastScanAddress, bdAddr->getAddress(), 6);
}

static void startBLEScanner() {
	// initialize allZeroMessageID; ignore messages with that ID sent by iOS OctoStudio
	memcpy(&allZeroMessageID, "00000000", 8);

	BTstack.setBLEAdvertisementCallback(BLEScannerCallback);
	BTstack.bleStartScanning();
}

static void stopBLEScanner() {
	BTstack.bleStopScanning();
}

#else // NimBLE OCTO primitive support

NimBLEUUID ANDROID_OCTO_UUID	= NimBLEUUID(ANDROID_OCTO_UUID_STRING);
NimBLEUUID iOS_OCTO_UUID		= NimBLEUUID(iOS_OCTO_UUID_STRING);

static void stopBeaming() {
	BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
	if (pAdvertising->isAdvertising()) pAdvertising->stop();
	pAdvertising->removeServiceUUID(iOS_OCTO_UUID);
	BLE_resumeAdvertising();
}

static void startOctoBeam(char *msg) {
	// Mimic iOS beam; data is encoded in name

	BLE_pauseAdvertising();
	BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
	pAdvertising->reset();
	pAdvertising->addServiceUUID(iOS_OCTO_UUID);
	pAdvertising->setName(msg);
	pAdvertising->setMinInterval(32);
	pAdvertising->setMaxInterval(32);
	pAdvertising->start();
}

static void startRadioBeam(uint8 *msg, int msgByteCount) {
	uint8_t adv_data[32];

	// truncate to fit in 31-byte legacy advertising packet
	if (msgByteCount > MAX_RADIO_PAYLOAD) msgByteCount = MAX_RADIO_PAYLOAD;

	memset(adv_data, 0, sizeof(adv_data));
	initRadioMsgHeader(adv_data, msgByteCount);
	memcpy(&adv_data[6], msg, msgByteCount);

	BLE_pauseAdvertising();
	BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
	pAdvertising->reset();

	// advertise using manufacturer data with msg payload
	NimBLEAdvertisementData advertData;
	advertData.addData((char *) adv_data, msgByteCount + 6);
	pAdvertising->setAdvertisementData(advertData);
	pAdvertising->setMinInterval(32);
	pAdvertising->setMaxInterval(32);
	pAdvertising->start();
}

class BLEScannerCallbacks : public BLEAdvertisedDeviceCallbacks {
	void onResult(BLEAdvertisedDevice* advertisedDevice) {
		if (advertisedDevice->haveServiceUUID()) {
			// iOS
			BLEUUID uuid = advertisedDevice->getServiceUUID();
			if (iOS_OCTO_UUID.equals(uuid)) {
				std::string deviceName = advertisedDevice->getName();
				if (deviceName.length() == 16) {
					MsgID id;
					memcpy(&id, deviceName.c_str(), 8);
					if ((id != allZeroMessageID) && octoIDNotYetSeen(id)) {
						addIDToOctoHistory(id);
						octoGroupID = (hexDigit(deviceName[12]) << 4) + hexDigit(deviceName[13]);
						octoShapeID = (hexDigit(deviceName[14]) << 4) + hexDigit(deviceName[15]);
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
					MsgID id;
					memcpy(&id, serviceData.c_str(), 8);
					if (octoIDNotYetSeen(id)) {
						addIDToOctoHistory(id);
						octoGroupID = serviceData[6];
						octoShapeID = serviceData[7];
						hasOctoMessage = true;
					}
				}
			}
		}

		const uint8_t *advData = advertisedDevice->getPayload();
		NimBLEAddress addr = advertisedDevice->getAddress();

		if (isBLERadioMsgToGroup(advData)) {
			MsgID radioMsgID; // radioMsgID is 6-byte address + sequence number + group
			memcpy(&radioMsgID, addr.getNative(), 6);
			memcpy(((uint8 *) &radioMsgID) + 6, &advData[4], 2);
			saveRadioMsg(radioMsgID, advData);
		}

		if (lastScanPayloadLen != 0) return; // last capture has not been consumed

		// capture scan payload
		lastScanPayloadLen = advertisedDevice->getPayloadLength();
		if (lastScanPayloadLen > MAX_SCAN_PAYLOAD) lastScanPayloadLen = MAX_SCAN_PAYLOAD;
		memcpy(lastScanPayload, advData, lastScanPayloadLen);

		// capture RSSI and address
		lastScanRSSI = -advertisedDevice->getRSSI(); // make it positive
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

#endif

static OBJ primOctoStartBeam(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], StringType)) return falseObj;

	startOctoBeam(obj2str(args[0]));
	return falseObj;
}

static OBJ primOctoStopBeam(int argCount, OBJ *args) {
	stopBeaming();
	return falseObj;
}

static OBJ primOctoReceive(int argCount, OBJ *args) {
	// If a new OctoStudio message has been receved return a 16-bit integer with
	// the groupID in the high 8 bits and the shapeID in the low 8 bits.
	// Return false if no message has been received.

	if (!bleScannerRunning) startBLEScanner();

	if (hasOctoMessage) {
		hasOctoMessage = false;
		return int2obj((octoGroupID << 8) | octoShapeID);
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

static OBJ primStopScanning(int argCount, OBJ *args) {
	stopBLEScanner();
	return falseObj;
}

// BLE Radio Primitives (similar to Octo but different format)

static OBJ primRadioSetGroup(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return falseObj;

	int newGroup = obj2int(args[0]);
	if (newGroup < 0) newGroup = 0;
	if (newGroup > 255) newGroup = 255;
	radioGroup = newGroup;
	return falseObj;
}

static OBJ primRadioStartBeam(int argCount, OBJ *args) {
	if ((argCount < 1) || !IS_TYPE(args[0], ByteArrayType)) return falseObj;

	startRadioBeam((uint8 *) &FIELD(args[0], 0), BYTES(args[0]));
	return falseObj;
}

static OBJ primRadioStopBeam(int argCount, OBJ *args) {
	stopBeaming();
	return falseObj;
}

static OBJ primRadioReceive(int argCount, OBJ *args) {
	if (!bleScannerRunning) startBLEScanner();

	if (lastRadioMsgLen > 0) {
		int wordCount = (lastRadioMsgLen + 3) / 4;
		OBJ result = newObj(ByteArrayType, wordCount, falseObj);
		if (!result) return fail(insufficientMemoryError);
		setByteCountAdjust(result, lastRadioMsgLen);
		memcpy(&FIELD(result, 0), lastRadioMsg, lastRadioMsgLen);
		lastRadioMsgLen = 0;
		return result;
	} else {
		return (OBJ) &noRadioMsg;
	}
}

#endif // BLE_OCTO

#if defined(BLE_UART)

// Original UART code was provided by Wenji Wu. Thanks!

// A board is a BLE Peripheral, so it can connect to only one BLE Central
// at at time. Thus, if the board is connected to the IDE then it is not
// available for connection as a BLE UART (except in Chrome/Edge, which
// seems to share a single BLE connection between tabs).

// Empty byte array and string constants
static uint32 emptyByteArray = HEADER(ByteArrayType, 0);
static uint32 emptyMBString[2] = { HEADER(StringType, 1), 0 };

// Receive buffer
static uint8 uartRecvBuf[256];
static int uartBytesReceived = 0;

void BLE_UART_ReceiveCallback(uint8 *data, int byteCount) {
	int spaceAvailable = sizeof(uartRecvBuf) - uartBytesReceived;
	if (byteCount > spaceAvailable) byteCount = spaceAvailable;
	memcpy(&uartRecvBuf[uartBytesReceived], data, byteCount);
	uartBytesReceived += byteCount;
}

static OBJ primUART_read(int argCount, OBJ *args) {
	// If optional argument is true, return a byte array. Otherwise, return a string.

	if (!BLE_connected_to_IDE) uartBytesReceived = 0;

	int returnBytes = (argCount > 0) && (trueObj == args[0]);
	if (uartBytesReceived <= 0) return (returnBytes ? (OBJ) &emptyByteArray : (OBJ) &emptyMBString);

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

	if (!BLE_connected_to_IDE) return zeroObj;

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
	BLE_UART_Send(((uint8_t *) &FIELD(arg, 0)) + startIndex, byteCount);
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

	{"bleConnected", primBLE_connected},

	#if defined(BLE_OCTO)
		{"octoStartBeam", primOctoStartBeam},
		{"octoStopBeam", primOctoStopBeam},
		{"octoReceive", primOctoReceive},
		{"scanReceive", primScanReceive},
		{"stopScanning", primStopScanning},
		{"radioSetGroup", primRadioSetGroup},
		{"radioStartBeam", primRadioStartBeam},
		{"radioStopBeam", primRadioStopBeam},
		{"radioReceive", primRadioReceive},
	#endif

	#if defined(BLE_UART)
		{"uartConnected", primBLE_connected},
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
	addPrimitiveSet(BLEPrims, "ble", sizeof(entries) / sizeof(PrimEntry), entries);
}
