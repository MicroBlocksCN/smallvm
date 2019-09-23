// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// ESPTool.gp - Uploader for ESP8266 and ESP32
// John Maloney, September, 2019

defineClass ESPTool port recvBuf boardType

to newESPTool { return (initialize (new 'ESPTool')) }

method initialize ESPTool {
	boardType = ''
	port = nil
	recvBuf = (newBinaryData)
	return this
}

method closePort ESPTool {
	if (notNil port) { closeSerialPort port }
	initialize this
}

method openPort ESPTool portName baudRate {
	if (isNil baudRate) { baudRate = 115200 }
	closePort this
	port = (safelyRun (action 'openSerialPort' portName baudRate))
	if (not (isClass port 'Integer')) { port = nil } // failed
	if ('Browser' == (platform)) { waitMSecs 100 } // let browser callback complete
}

// SLIP framing
// Each SLIP packet begins and ends with 0xC0 (192). Within the packet, all occurrences of
// 0xC0 and 0xDB are replaced with 0xDB 0xDC (219 220) and 0xDB 0xDD (219 221), respectively.

method nextSLIPMsg ESPTool {
	// Return the next complete SLIP message or nil. The returned message does not
	// include the start and end bytes and escaped byte pairs have been processed.

	if (isNil port) { return nil }
	data = (readSerialPort port true)
	if (notNil data) { recvBuf = (join recvBuf data) }
	startIndex = (findMsgStart this 1)
	if (isNil startIndex) {
		recvBuf = (newBinaryData 0) // no message start found; discard entire buffer
		return
	}
	endIndex = (findMsgStart this (startIndex + 1))
	if (isNil endIndex) {
		if (startIndex > 1) { recvBuf = (copyFromTo recvBuf startIndex) } // discard bytes before start
		return nil
	}
	return (unescapeMsg this startIndex endIndex)
}

method findMsgStart ESPTool startIndex {
	// Return the index of the next SLIP message start byte in recvBuf or nil if not found.

	end = (byteCount recvBuf)
	i = startIndex
	while (i <= end) {
		if (192 == (byteAt recvBuf i)) { return i } // SLIP start byte (192 = 0xC0)
		i += 1
	}
	return nil
}

method unescapeMsg ESPTool startIndex endIndex {
	// Return the bytes of the SLIP between  the given indices in recvBuf with any
	// escaped byte pairs replaced with the original byte values.

	result = (list)
	i = (startIndex + 1)
	while (i < endIndex) {
		b = (byteAt recvBuf i)
		if (219 == b) { // SLIP escape byte (219 = 0xDB)
			nextB = (byteAt recvBuf i)
			if (220 == nextB) { add result 192 } // escaped SLIP start byte (192 = 0xC0)
			if (221 == nextB) { add result 219 } // escaped SLIP escape byte (219 = 0xDB)
			i += 2
		} else {
			add result b
			i += 1
		}
	}
	return result
}

method hexBytes ESPTool s {
	// Convert a string containing hex values separated by spaces into a list of byte values.

	result = (list)
	for h (splitWith s ' ') {
		add result (hex h)
	}
	return result
}

method hexToBytes ESPTool s {
	// Convert a hexadecimal value into a list of byte values in little-endian order.

	result = (list)
	i = ((count s) - 1)
	while (i >= 0) {
		if (0 == i) { // single character (odd-length string)
			add result (hex (substring s 1 1))
		} else {
			add result (hex (substring s i (i + 1)))
		}
		i += -2
	}
	return result
}

method sendSyncMsg ESPTool {
	// Send an ESPTool SYNC message.

	msg = (list)
	add msg 192 // SLIP start byte
	addAll msg (list 0 8 36 0 0 0 0 0) // header
	addAll msg (list 7 7 18 32) // four bytes: 0x07 0x07 0x12 0x20
	repeat 32 { add msg (hex '55') } // 32 x 0x55 (to allow ESP to detect baud rate)
	add msg 192 // SLIP end byte
	writeSerialPort port (toBinaryData (toArray msg))
}

method sendReadRegisterMsg ESPTool hexAddr {
	// msg body is 4 byte addr (little endian)

	msg = (list)
	add msg 192 // SLIP  byte
	addAll msg (list 0 10 4 0 0 0 0 0) // header
	addAll msg (hexToBytes hexToBytes)
	// xxx need to SLIP escape the address bytes if any of them equal 192
	add msg 192 // SLIP end byte
print 'sending:' (bytesAsHex this msg)
	writeSerialPort port (toBinaryData (toArray msg))
}

method resetChip ESPTool {
	// Use the RTS/DTR lines to force the chip into bootloader mode.
	// Set DTR, then toggle RTS to reset the chip.
	// Note: RTS and DTR are inverted by transistors on the board.

	if (isNil port) { return }
	setSerialPortDTR port false		// IO0 = high
	setSerialPortRTS port true		// EN = low (chip in reset)
	waitMSecs 100 // might need to increase to 220 msecs on some chips
	setSerialPortDTR port true		// IO0 = low
	setSerialPortRTS port false		// EN = high (exit reset)
	waitMSecs 50 // might need to increase to 450 msecs on some chips
	setSerialPortDTR port false		// IO0 = high
}

method clear ESPTool {
	msg = true
	while (notNil msg) {
		waitMSecs 100
		msg = (nextSLIPMsg this)
	}
}

method bytesAsHex ESPTool bytes {
	if (isNil prefix) { prefix = '' }
	out = (list prefix)
	for b (toArray bytes) {
		hex = (toLowerCase (toStringBase16 b))
		if ((count hex) < 2) { hex = (join '0' hex) }
		add out hex
	}
	return (joinStrings out ' ')
}

method test ESPTool n {
	if (isNil n) { n = 10 }
	recvBuf = (newBinaryData)
	resetChip this
	repeat n {
		sendSyncMsg this
		msg = (nextSLIPMsg this)
		if (notNil msg) {
			clear this
			return
		}
		waitMSecs 100
	}
}

method test2 ESPTool n {
	// Assume connected and sync-ed...

	clear this
	sendReadRegisterMsg this '60000078'
	nextSLIPMsg this
}

//
//         # issue reset-to-bootloader:
//         # RTS = either CH_PD/EN or nRESET (both active low = chip in reset
//         # DTR = GPIO0 (active low = boot to flasher)
//         #
//         # DTR & RTS are active low signals,
//         # ie True = pin @ 0V, False = pin @ VCC.
//         if mode != 'no_reset':
//             self._setDTR(False)  # IO0=HIGH
//             self._setRTS(True)   # EN=LOW, chip in reset
//             time.sleep(0.1)
//             if esp32r0_delay:
//                 # Some chips are more likely to trigger the esp32r0
//                 # watchdog reset silicon bug if they're held with EN=LOW
//                 # for a longer period
//                 time.sleep(1.2)
//             self._setDTR(True)   # IO0=LOW
//             self._setRTS(False)  # EN=HIGH, chip out of reset
//             if esp32r0_delay:
//                 # Sleep longer after reset.
//                 # This workaround only works on revision 0 ESP32 chips,
//                 # it exploits a silicon bug spurious watchdog reset.
//                 time.sleep(0.4)  # allow watchdog reset to occur
//             time.sleep(0.05)
//             self._setDTR(False)  # IO0=HIGH, done
//
