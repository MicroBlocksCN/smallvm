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

// Serial Port

method openPort ESPTool portName baudRate {
	if (isNil baudRate) { baudRate = 115200 }
	closePort this
	port = (safelyRun (action 'openSerialPort' portName baudRate))
	if (not (isClass port 'Integer')) { port = nil } // failed
	if ('Browser' == (platform)) { waitMSecs 100 } // let browser callback complete
}

method closePort ESPTool {
	if (notNil port) { closeSerialPort port }
	initialize this
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

method hardResetChip ESPTool {
	setSerialPortRTS port true		// EN = low (chip in reset)
	waitMSecs 100
	setSerialPortRTS port false		// EN = high (exit reset)
}

// About SLIP:
// Each SLIP packet begins and ends with 0xC0 (192). Within the packet, all occurrences of
// 0xC0 and 0xDB are replaced with 0xDB 0xDC (219 220) and 0xDB 0xDD (219 221), respectively.

// SLIP Message Receiving

method waitForMsg ESPTool {
	timeout = 1000
	startTime = (msecsSinceStart)
	while (((msecsSinceStart) - startTime) < timeout) {
		msg = (nextSLIPMsg this)
		if (notNil msg) { return msg }
	}
	return nil
}

method nextSLIPMsg ESPTool {
	// Return the next complete SLIP message or nil. The returned message does not
	// include the start and end bytes and escaped byte pairs have been processed.

	if (isNil port) { return nil }
	data = (readSerialPort port true)
	if (notNil data) {
		recvBuf = (join recvBuf data) }
	startIndex = (nextFrameByte this 1)
	if (isNil startIndex) {
		recvBuf = (newBinaryData 0) // no message start found; discard entire buffer
		return nil
	}
	endIndex = (nextFrameByte this (startIndex + 1))
	if (isNil endIndex) {
		if (startIndex > 1) { recvBuf = (copyFromTo recvBuf startIndex) } // discard bytes before start
		return nil
	}

	// received a complete message
	result = (unescapeMsg this startIndex endIndex)
	recvBuf = (copyFromTo recvBuf (endIndex + 1))
	return result
}

method nextFrameByte ESPTool startIndex {
	// Return the index of the next SLIP frame byte after startIndex in recvBuf.
	// Return nil if there isn't one.

	end = (byteCount recvBuf)
	i = startIndex
	while (i <= end) {
		if (192 == (byteAt recvBuf i)) { return i } // SLIP frame mark byte (192 = 0xC0)
		i += 1
	}
	return nil
}

method unescapeMsg ESPTool startIndex endIndex {
	// Return a list of the bytes between the given indices in recvBuf
	// with escaped byte pairs replaced with their original byte values.

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

method clearReceiveBuffer ESPTool {
	// Discard any buffered data from the serial port and clear the receive buffer.

	data = true
	while (notNil data) {
		waitMSecs 10 // allow time for any leftover data to arrive
		data = (readSerialPort port true)
	}
	recvBuf = (newBinaryData)
}

// SLIP Message Sending

method sendCmd ESPTool cmd data checksum {
	// Send the given command to the board with the given data.
	// Both data and checksum are optional.

	if (isNil data) { data = (list) }
	if (isClass data 'BinaryData') { data = (toArray data) }

	byteCount = (count data)
	msg = (list 0 cmd (byteCount & 255) ((byteCount >> 8) & 255))
	if (notNil checksum) {
		add32Int this msg checksum
	} else {
		repeat 4 { add msg 0 }
	}
	addAll msg data
	sendSLIPMsg this msg
}

method computeChecksum ESPTool data {
	result = (hex 'EF')
	for n data { result = (result ^ n) }
	return result
}

method sendSLIPMsg ESPTool msg {
	escaped = (list)
	add escaped 192 // SLIP start byte
	for b msg {
		if (192 == b) { // escape SLIP end byte
			add escaped 219
			add escaped 220
		} (219 == b) { // escape SLIP escape byte
			add escaped 219
			add escaped 221
		} else {
			add escaped b
		}
	}
	add escaped 192 // SLIP end byte
	writeSerialPort port (toBinaryData (toArray escaped))
// print 'sent bytes:' (count escaped) // xxx
}

method add32Int ESPTool msg n {
	// Append the 32-bit integer n to the given message in little-endian byte order.

	repeat 4 {
		add msg (n & 255)
		n = (n >> 8)
	}
}

// Utilities

method readRegister ESPTool hexAddr {
	// Read the given register (supplied as a hex string such as '3ff0005c').

	clearReceiveBuffer this
	sendCmd this 10 (hexToBytes this hexAddr)
	msg = (waitForMsg this)
	if (or (isNil msg) ((count msg) < 10)) { return -1 } // no response
	if (0 != (at msg 9)) { return (0 - (at msg 10)) } // return error code (negative)
	return (bytesAsHex this (reversed (copyFromTo msg 5 8)))
}

method attachSPI ESPTool {
	// Send an SPI_ATTACH message to an ESP32.
	// Neither needed nor supported on the ESP8266 but can be sent anyhow.

	clearReceiveBuffer this
	sendCmd this (hex '0d') (array 0 0 0 0)
	msg = (waitForMsg this)
}

method hexToBytes ESPTool s {
	// Convert a hexadecimal value into a list of byte values in little-endian order.

	if (beginsWith s '0x') { s = (substring s 3) } // remove optional leading '0x'
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

method bytesAsHex ESPTool bytes {
	out = (list '0x')
	for b (toArray bytes) {
		hex = (toLowerCase (toStringBase16 b))
		if ((count hex) < 2) { hex = (join '0' hex) }
		add out hex
	}
	return (joinStrings out '')
}

// Synchronization

method sendSyncMsg ESPTool {
	// Send an ESPTool SYNC message to allow ESP board to detect the baud rate.

	data = (list 7 7 18 32) // four bytes: 0x07 0x07 0x12 0x20
	repeat 32 { add data (hex '55') } // 32 x 0x55 (to allow ESP to detect baud rate)
	sendCmd this 8 data
}

method connect ESPTool portName baudRate {
	if (isNil baudRate) { baudRate = 230400 }

	print 'Connecting to' portName 'at' baudRate 'baud'
	openPort this portName baudRate
	if (isNil port) { return false }

	repeat 10 {
		resetChip this
		waitMSecs 10
		recvBuf = (newBinaryData)
		repeat 3 {
			sendSyncMsg this
			waitMSecs 20
			msg = (nextSLIPMsg this)
			if (notNil msg) {
				clearReceiveBuffer this
				print 'Connected!'
				return true
			}
		}
	}
	print 'Could not connect. Board did not respond.'
	return false
}

// Writing to Flash

method beginFlashWrite ESPTool totalBytes startAddr {
	packetSize = 800
	packetCount = (ceiling (totalBytes / packetSize))
	eraseSize = (get_erase_size this startAddr totalBytes)
	data = (list)
	add32Int this data eraseSize
	add32Int this data packetCount
	add32Int this data packetSize
	add32Int this data startAddr
	sendCmd this 2 data
}

method writeFlashData ESPTool packet seqNum {
	if (isClass packet 'BinaryData') { packet = (toArray packet) }
	data = (list)
	add32Int this data (count packet)
	add32Int this data seqNum
	add32Int this data 0
	add32Int this data 0
	addAll data packet
//	for i (count packet) { add data (at packet i) }
	sendCmd this 3 data (computeChecksum this packet)
//print 'checksum' (computeChecksum this packet)
}

method get_erase_size ESPTool offset size {
	// Calculate an erase size given a specific size in bytes.
	// Workaround for the ESP ROM bootloader erase bug.
	// Follows get_erase_size function in esptool.py.

	sectors_per_block = 16
	sector_size = 4096 // minimum unit of erase

	num_sectors = (floor (((size + sector_size) - 1) / sector_size))
	start_sector = (floor (offset / sector_size))

	head_sectors = (sectors_per_block - (start_sector % sectors_per_block))
	if (num_sectors < head_sectors) { head_sectors = num_sectors }

	if (num_sectors < (2 * head_sectors)) {
		return (sector_size * (floor ((num_sectors + 1) / 2)))
	} else {
		return (sector_size * ((num_sectors - head_sectors)))
	}
}

// Tests

method detectChip ESPTool {
	dateReg1 = (readRegister this '60000078')
	if ('0x00062000' == dateReg1) { return 'ESP8266' }
	if ('0x15122500' == dateReg1) { return 'ESP32' }
	if ('0x00000500' == dateReg1) {
		dateReg2 = (readRegister this '3f400074')
		if ('0x19031400' == dateReg2) { return 'ESP32-S2' }
	}
	return nil // unrecognized chip
}

method registerTest ESPTool {
	// Read some registers. Assume connected and sync-ed...

	print '60000078' '->' (readRegister this '60000078') // differentiates ESP8266 vs ESP32*
	print '3f400074' '->' (readRegister this '3f400074') // differentiates ESP32-S2 vs others

	print '3ff0005c' '->' (readRegister this '3ff0005c')
	print '3ff00058' '->' (readRegister this '3ff00058')
	print '3ff00054' '->' (readRegister this '3ff00054')
	print '3ff00050' '->' (readRegister this '3ff00050')

}

method esp8266VM ESPTool {
	return (readEmbeddedFile (join 'precompiled/vm.ino.nodemcu.bin') true)
}

// connect esp '/dev/cu.SLAB_USBtoUART'
// connect esp '/dev/cu.usbserial-1420'

method writeFlashTest ESPTool {
//	ok = (connect this '/dev/cu.SLAB_USBtoUART')
	ok = (connect this '/dev/cu.usbserial-1420')

	if (not ok) { return }

	flashData = (newArray 100)
	for i (count flashData) { atPut flashData i (i & 63) }
fillArray flashData 4

	attachSPI this
	beginFlashWrite this (count flashData) 0
	print (waitForMsg this)
	writeFlashData this flashData 0
	print (waitForMsg this)
}

method writeZeroFile ESPTool {
	flashData = (newArray 1024)
	fillArray flashData 0
	writeFile 'zeros.dat' (toBinaryData flashData)
}

method writeTestFile ESPTool {
	flashData = (newArray 1024)
	for i (count flashData) { atPut flashData i (i & 127) }
	writeFile 'test.dat' (toBinaryData flashData)
}
