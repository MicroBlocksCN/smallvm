// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// ESPTool.gp - Uploader for ESP8266 and ESP32
// See https://github.com/espressif/esptool/wiki/Serial-Protocol#reading-flash
// John Maloney, September, 2019

defineClass ESPTool port recvBuf closeWhenDone status success allInOneBinary chipType

to newESPTool { return (initialize (new 'ESPTool')) }

to espTest {
	espTool = (newESPTool)
// openPort espTool '/dev/cu.usbmodem01' 'ESP32-S2'
// vmData = (readFile '../blink_s2.bin' true)

// 	openPort espTool '/dev/cu.usbserial-110' 'ESP32-S3'
// 	vmData = (readFile '../blink_s3.bin' true)

openPort espTool '/dev/cu.usbserial-110' 'ESP32-C3'
vmData = (readFile '../blink_c3.bin' true)

	uploadESP32VM espTool vmData false
	closeSerialPort port
}

method initialize ESPTool {
	status = ''
	port = nil
	recvBuf = (newBinaryData)
	closeWhenDone = true
	success = false
	allInOneBinary = false
	return this
}

method status ESPTool { return status } // return a status/progress string
method success ESPTool { return success } // return true if upload was successful

method setAllInOneBinary ESPTool aBoolean { allInOneBinary = aBoolean }

// Serial Port

method openPort ESPTool portName boardName {
	baudRate = (baudForBoard this boardName)
	closePort this
	port = (safelyRun (action 'openSerialPort' portName baudRate))
	if (not (isClass port 'Integer')) { port = nil } // failed
	if ('Browser' == (platform)) { waitMSecs 100 } // let browser callback complete
	return (notNil port)
}

// Maximum reliable baud rates & upload test results:
// esp8266 - 230400 (26.2; 14.8 compressed) connects, but not reliable at 460800
// d1mini - 921600 (10.2; 8.4 compressed)
// esp32 - 460800 (18.2; 11.3 compressed)
// ed1 - 230400 (26.4; 17.0 compressed) does not connect reliably at 460800
// m5stack - 460800 (18.2; 11.8 compressed)
// m5stick - 230400 (26.1; 15.3 compressed) does not connect reliably at 460800
// m5atom - 115200 (42.5; 28.3 compressed) connects, but not reliable at 230400

method baudForBoard ESPTool boardName {
	if ('ESP8266' == boardName) { return 230400
	} ('D1-Mini' == boardName) { return 921600
	} ('ESP32' == boardName) { return 230400
	} ('handpy' == boardName) { return 230400
	} ('未来科技盒' == boardName) { return 230400
	} ('未来科技盒v2.0' == boardName) { return 230400
	} ('COCUBE' == boardName) { return 230400
	} ('Citilab ED1' == boardName) { return 230400
	} ('M5Stack-Core' == boardName) { return 230400
	} ('M5StickC' == boardName) { return 230400
	} ('M5StickC+' == boardName) { return 230400
	} ('M5Atom-Matrix' == boardName) { return 115200
	} ('Databot' == boardName) { return 230400
	} ('Mbits' == boardName) { return 230400
	} (isOneOf boardName 'ESP32-S2' 'ESP32-S3' 'ESP32-C3') { return 115200 // was 460800
	}
	return 115200
}

method setPort ESPTool portID {
	// Use an existing (open) serial port. Used when invoked from the browser or Chromebook.
	initialize this
	port = portID
	closeWhenDone = false
}

method closePort ESPTool {
	if (notNil port) { closeSerialPort port }
	port = nil
	recvBuf = (newBinaryData)
}

// Connecting

method connect ESPTool {
	// Enter boot mode and connect to the ROM boot loader.

	status = 'Connecting...'
	repeat 30 {
		enterBootMode this
		waitMSecs 30
		recvBuf = (newBinaryData)
		repeat 10 {
			sendSyncMsg this
			waitMSecs 30
			msg = (nextSLIPMsg this)
			if (notNil msg) {
				clearReceiveBuffer this
				print 'Connected'
				return true
			}
		}
	}
	print 'Could not connect. Board did not respond.'
	return false
}

method sendSyncMsg ESPTool {
	// Send an ESPTool SYNC message to allow ESP board to detect the baud rate.

	data = (list 7 7 18 32) // four bytes: 0x07 0x07 0x12 0x20
	repeat 32 { add data (hex '55') } // 32 x 0x55 (to allow ESP to detect baud rate)
	sendCmd this 8 data
}

// Chip Control

method enterBootMode ESPTool {
	// Use the RTS/DTR lines to force the chip into bootloader mode.
	// Set DTR, then toggle RTS to reset the chip.
	// Note: RTS and DTR are inverted by transistors on the board.

	if (isNil port) { return }
	setSerialPortDTR port false		// IO0 = high
	setSerialPortRTS port true		// EN = low (chip in reset)
	waitMSecs 250 					// might need to increase to 220 msecs on some chips
	setSerialPortDTR port true		// IO0 = low
	setSerialPortRTS port false		// EN = high (exit reset)
	waitMSecs 500 					// might need to increase to 450 msecs on some chips
	setSerialPortDTR port false		// IO0 = high
}

method exitBootMode ESPTool {
	// Reset the chip in normal mode so that it runs the MicroBlocks virtual machine.

	setSerialPortDTR port false		// IO0 = high for reset in normal (not boot) mode
	setSerialPortRTS port true		// EN = low (chip in reset)
	waitMSecs 100
	setSerialPortRTS port false		// EN = high (exit reset)
}

// About SLIP:
// Each SLIP packet begins and ends with 0xC0 (192). Within the packet, all occurrences of
// 0xC0 and 0xDB are replaced with 0xDB 0xDC (219 220) and 0xDB 0xDD (219 221), respectively.

// SLIP Message Receiving

method waitForMsg ESPTool timeout {
	if (isNil timeout) { timeout = 10000 }
	startTime = (msecsSinceStart)
	while (((msecsSinceStart) - startTime) < timeout) {
		msg = (nextSLIPMsg this)
		if (notNil msg) { return msg }
		waitMSecs 10
	}
	return nil
}

method nextSLIPMsg ESPTool {
	// Return the next complete SLIP message or nil. The returned message does not
	// include the start and end bytes and escaped byte pairs have been processed.

	if (isNil port) { return nil }
	data = (readSerialPort port true)
	if (notNil data) {
		recvBuf = (join recvBuf data)
	}
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

method errorResponse ESPTool {
	// Return true if we got an error or timed out.

	msg = (waitForMsg this)
	if (isNil msg) {
		print 'No response from board'
		return true
	}
	if ((count msg) < 10) {
		print 'Incomplete response from board'
		return true
	}
	statusByteIndex = ((count msg) - 1) // this must be -3 for ESP32-S3
	if (0 != (at msg statusByteIndex)) {
		print 'Board reported error; msg:' msg
		return true
	}
	return false // all good!
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
}

method add32Int ESPTool msg n {
	// Append the 32-bit integer n to the given message in little-endian byte order.

	repeat 4 {
		add msg (n & 255)
		n = (n >> 8)
	}
}

// Utilities

method chipType ESPTool {
	dateReg1 = (readRegister this '60000078')
	if ('0x00062000' == dateReg1) { return 'ESP8266' }
	if ('0x15122500' == dateReg1) { return 'ESP32' }
	if ('0x00000500' == dateReg1) {
		dateReg2 = (readRegister this '3f400074')
		if ('0x19031400' == dateReg2) { return 'ESP32-S2' }
	}
	if ('0x03700000' == dateReg1) {
		magicReg = (readRegister this '40001000')
		if ('0x00000009' == magicReg) { return 'ESP32-S3' }
		if ('0x1b31506f' == magicReg) { return 'ESP32-C3' }
	}
	return nil // unrecognized chip
}

method eraseFlash ESPTool {
	status = (localized 'Erasing Flash...')
	clearReceiveBuffer this
	sendCmd this (hex 'd0')
	msg = (waitForMsg this 30000) // long timeout because erasing Flash takes time
	ok = (and (notNil msg) ((count msg) > 9) (0 == (at msg 9)))
	return ok
}

method readRegister ESPTool hexAddr {
	// Read the given register (supplied as a hex string such as '3ff0005c').

	clearReceiveBuffer this
	sendCmd this 10 (hexToBytes this hexAddr)
	msg = (waitForMsg this)
	if (or (isNil msg) ((count msg) < 10)) { return -1 } // no response
	if (0 != (at msg 9)) { return (0 - (at msg 10)) } // return error code (negative)
	return (bytesAsHex this (reversed (copyFromTo msg 5 8)))
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

// Installing Firmware

method installFirmware ESPTool boardName eraseFlag downloadFlag vmData {
	// Install the firmware for the current board, erasing Flash if optional eraseFlag is true.
	// If optional downloadFlag is true, download the latest version from the server.
	// Assume the board is connected.

	if (isNil eraseFlag) { eraseFlag = false }
	if (isNil downloadFlag) { downloadFlag = false }

	if (isNil vmData) { vmData = (readVMData this boardName downloadFlag) }
	if (isNil vmData) { return }

	if (or (isOneOf boardName 'ESP8266' 'D1-Mini')
		(notNil (findSubstring 'nodemcu' boardName))
		(notNil (findSubstring '8266' boardName))
	) {
		ok = (uploadESP8266VM this vmData eraseFlag)
	} else {
		ok = (uploadESP32VM this vmData eraseFlag)
	}

	if ok {
		status = (localized 'Done')
		success = true
	} else {
		status = (localized 'Failed')
		if closeWhenDone { closePort this }
		enableAutoConnect (smallRuntime) false
		return
	}

	waitMSecs 200 // allow time for final flash write to complete (40 msecs minimum on d1 mini)
	exitBootMode this
	waitMSecs 1500
	if closeWhenDone { closePort this }
	enableAutoConnect (smallRuntime) success
}

method readVMData ESPTool boardName downloadFlag {
	vmName = (vmNameForBoard this boardName)
	if (isNil vmName) {
		print 'Unknown board:' boardName
		return nil
	}

	if downloadFlag {
		status = 'Fetching...'
		vmData = (httpGetBinary 'microblocks.fun' (join '/downloads/latest/vm/' vmName))
	} else {
		vmData = (readEmbeddedFile (join 'precompiled/' vmName) true)
	}
	if (or (isNil vmData) ((byteCount vmData) < 10000)) {
		print 'Could not fetch or read VM'
		return nil
	}
	return vmData
}

method vmNameForBoard ESPTool boardName {
	if ('ESP8266' == boardName) { return 'vm_nodemcu.bin'
	} ('D1-Mini' == boardName) { return 'vm_nodemcu.bin'
	} ('ESP32' == boardName) { return 'vm_esp32.bin'
	} ('handpy' == boardName) { return 'vm_mpython.bin'
	} ('未来科技盒' == boardName) { return 'vm_cocorobo.bin'
	} ('未来科技盒v2.0' == boardName) { return 'vm_tx_ft_box.bin'
	} ('COCUBE' == boardName) { return 'vm_COCUBE.bin'
	} ('Citilab ED1' == boardName) { return 'vm_citilab-ed1.bin'
	} ('M5Stack-Core' == boardName) { return 'vm_m5stack.bin'
	} ('M5StickC' == boardName) { return 'vm_m5stick.bin'
	} ('M5StickC+' == boardName) { return 'vm_m5stick+.bin'
	} ('M5Atom-Matrix' == boardName) { return 'vm_m5atom.bin'
	} ('Databot' == boardName) { return 'vm_databot.bin'
	} ('Mbits' == boardName) { return 'vm_mbits.bin'
	}
	return nil
}

// Uploading data to the board

method uploadESP8266VM ESPTool vmData eraseFlag {
	if (isNil eraseFlag) { eraseFlag = false }

	ok = (connect this)
	if (not ok) { return false }

	ok = (uploadStub this)
	if (not ok) { return false }

	if eraseFlag { eraseFlash this }

	uploadCompressed this 0 vmData
	return true
}

method uploadESP32VM ESPTool vmData eraseFlag {
	if (isNil eraseFlag) { eraseFlag = false }

	ok = (connect this)
	if (not ok) { return false }

	ok = (uploadStub this)
	if (not ok) { return false }

	ok = (setFlashParameters this)
	if (not ok) { return false }

	if eraseFlag { eraseFlash this }

	if allInOneBinary {
		uploadCompressed this 0 vmData // binary includes all subparts and loads at address 0
		return true
	}

	if ('ESP32-S2' == chipType) {
		bootloaderAddress = (hex '1000')
		data = (readEmbeddedFile (join 'esp32/bootloader_s2.bin') true)
	} ('ESP32-S3' == chipType) {
		bootloaderAddress = 0
		data = (readEmbeddedFile (join 'esp32/bootloader_s3.bin') true)
	} ('ESP32-C3' == chipType) {
		bootloaderAddress = 0
		data = (readEmbeddedFile (join 'esp32/bootloader_c3.bin') true)
	} else {
		bootloaderAddress = (hex '1000')
		data = (readEmbeddedFile (join 'esp32/bootloader_dio_40m.bin') true)
	}

	uploadCompressed this bootloaderAddress data
	print 'uploaded bootloader at' bootloaderAddress (byteCount data) 'bytes'

	data = (readEmbeddedFile (join 'esp32/boot_app0.bin') true)
	uploadCompressed this (hex 'e000') data
	print 'uploaded boot_app0.bin at' (hex 'e000') (byteCount data) 'bytes'

	data = (readEmbeddedFile (join 'esp32/partitionsMicroBlocks.bin') true)
	uploadCompressed this (hex '8000') data
	print 'uploaded partitions.bin at' (hex '8000') (byteCount data) 'bytes'

	uploadCompressed this (hex '10000') vmData
	print 'uploaded vmData at' (hex '10000') (byteCount vmData) 'bytes'
	return true
}

method uploadCompressed ESPTool startAddr data {
	// Upload the given binary data to Flash at the given address with deflate compression.
	// Note: The total packet size after SLIP escaping cannot exceed 1024 bytes.
	// The number of extra bytes for escape sequences depends on the the contents.
	// The packet size 800 was chosen based on testing with all the current VM's
	// and leaves a reasonable margin for data that requires more escape sequences
	// while minimizing the total number of packets sent to minimize upload time.

	start = (msecsSinceStart)

	packetSize = 800 // 800 is good; 900 works; 984 fails
	compressedData = (zlibEncode data)
	compressedBytecount = (byteCount compressedData)
	packetCount = (ceiling (compressedBytecount / packetSize))

	args = (list)
	add32Int this args (byteCount data) // uncompressed size
	add32Int this args packetCount
	add32Int this args packetSize
	add32Int this args startAddr
	sendCmd this (hex '10') args
	if (errorResponse this) { return }

	status = ''
	percentDone = 0

	sent = 0
	seqNum = 0
	while (sent < compressedBytecount) {
		bytesToSend = (min packetSize (compressedBytecount - sent))
		args = (list)
		add32Int this args bytesToSend
		add32Int this args seqNum
		repeat 8 { add args 0 }
		checksum = (hex 'EF')
		for i bytesToSend {
			byte = (byteAt compressedData (sent + i))
			checksum = (checksum ^ byte)
			add args byte
		}
		sendCmd this (hex '11') args checksum
		if (errorResponse this) { return }
		sent += bytesToSend
		percentDone = (round ((100 * sent) / compressedBytecount))
		status = (join '' percentDone '%')
		seqNum += 1
	}
//	print ((msecsSinceStart) - start) 'msecs'
}

method uploadUncompressed ESPTool startAddr flashData {
	// Upload the uncompressed binary data to Flash at the given address.

	totalBytes = (byteCount flashData)
	packetSize = 512
	packetCount = (ceiling (totalBytes / packetSize))
	eraseSize = totalBytes

	args = (list)
	add32Int this args eraseSize
	add32Int this args packetCount
	add32Int this args packetSize
	add32Int this args startAddr
	sendCmd this 2 args
	if (errorResponse this) { return }

	status = ''
	percentDone = 0

	sent = 0
	seqNum = 0
	while (sent < totalBytes) {
		bytesToSend = (min packetSize (totalBytes - sent))
		args = (list)
		add32Int this args bytesToSend
		add32Int this args seqNum
		repeat 8 { add args 0 }
		checksum = (hex 'EF')
		for i bytesToSend {
			byte = (byteAt flashData (sent + i))
			checksum = (checksum ^ byte)
			add args byte
		}
		sendCmd this 3 args checksum
		if (errorResponse this) { return }
		sent += bytesToSend
		percentDone = (round ((100 * sent) / totalBytes))
		status = (join '' percentDone '%')
		seqNum += 1
	}
}

method setFlashParameters ESPTool {
	// Assumes Flash is 4 MB for now. (Later, could detect the actual size.)
	// Of John's boards, all are 4 MB except the M5Stack, which is 16 MB.
	// Other parameters are fixed.

	args = (list)
	add32Int this args 0 // Flash ID
	add32Int this args (4 * (1024 * 1024)) // total size; assume 4 MB
	add32Int this args (64 * 1024) // block size
	add32Int this args (4 * 1024) // sector size
	add32Int this args 256 // page size
	add32Int this args (hex 'ffff') // status mask
	sendCmd this (hex '0b') args
	return (not (errorResponse this))
}

// Stub uploading

method uploadStub ESPTool {
	// Upload and start the RAM bootloader stub. This bootloader includes more features
	// such as compressed data uploading and the ability to erase all of Flash memory.

	chipType = (chipType this)
	print 'Chip type:' chipType

	if ('ESP8266' == chipType) {
		stub = (esp8266_stub this)
	} ('ESP32' == chipType) {
		stub = (esp32_stub this)
	} ('ESP32-S2' == chipType) {
		stub = (esp32_S2_stub this)
	} ('ESP32-S3' == chipType) {
		stub = (esp32_S3_stub this)
	} ('ESP32-C3' == chipType) {
		stub = (esp32_C3_stub this)
	} else {
		print 'Error: Unknown chip type:' chipType
		return false
	}
	uploadToRAM this (at stub 'text_start') (at stub 'text')
	uploadToRAM this (at stub 'data_start') (at stub 'data')
	ok = (startStub this (at stub 'entry'))
	return ok
}

method uploadToRAM ESPTool hexStartAddr ramData {
	// Upload the given binary data to RAM at the given address.

	totalBytes = (byteCount ramData)
	packetSize = 900 // must be well under 1024 to allow for header and SLIP escaping
	packetCount = (ceiling (totalBytes / packetSize))

	args = (list)
	add32Int this args totalBytes
	add32Int this args packetCount
	add32Int this args packetSize
	addAll args (hexToBytes this hexStartAddr)
	sendCmd this 5 args // start RAM upload
	if (errorResponse this) { return }

	sent = 0
	seqNum = 0
	while (sent < totalBytes) {
		bytesToSend = (min packetSize (totalBytes - sent))
		args = (list)
		add32Int this args bytesToSend
		add32Int this args seqNum
		repeat 8 { add args 0 }
		checksum = (hex 'EF')
		for i bytesToSend {
			byte = (byteAt ramData (sent + i))
			checksum = (checksum ^ byte)
			add args byte
		}
		sendCmd this 7 args checksum // send RAM data
		if (errorResponse this) { return }
		sent += bytesToSend
		seqNum += 1
	}
}

method startStub ESPTool hexStartAddr {
	args = (list 0 0 0 0)
	addAll args (hexToBytes this hexStartAddr)
	sendCmd this 6 args
	waitForMsg this // wait for and discard response to start command
	msg = (waitForMsg this) // wait for four byte stub startup message: 'OHAI'
	if (or (isNil msg) (msg != (list 79 72 65 73))) {
		print 'Error: Stub did not respond'
		return false
	}
	print 'Stub started'
	return true
}

// Stub code
// Note: All addresses in these records must be hexadecimal strings!

method esp8266_stub ESPTool {
	result = (dictionary)
	atPut result 'text' (base64Decode '
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
AAAAMqEMAg3wAA==')

	atPut result 'data' (base64Decode '
CIH+PwUFBAACAwcAAwMLAFHnEECH5xBAtecQQFToEEAF9xBAuugQQBDpEEBc6RBABfcQQCLqEECf
6hBAYOsQQAX3EEAF9xBA+OsQQAX3EEDX7hBAn+8QQNjvEEAF9xBABfcQQHXwEEAF9xBAW/EQQAHy
EEBA8xBA//MQQND0EEAF9xBABfcQQAX3EEAF9xBA/vUQQAX3EED09hBAL+0QQCfoEEBC9RBAS+oQ
QJjpEEAF9xBAiPYQQM/2EEAF9xBABfcQQAX3EEAF9xBABfcQQAX3EEAF9xBABfcQQMDpEED/6RBA
WvUQQAEAAAACAAAAAwAAAAQAAAAFAAAABwAAAAkAAAANAAAAEQAAABkAAAAhAAAAMQAAAEEAAABh
AAAAgQAAAMEAAAABAQAAgQEAAAECAAABAwAAAQQAAAEGAAABCAAAAQwAAAEQAAABGAAAASAAAAEw
AAABQAAAAWAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAABAAAAAgAAAAIAAAADAAAAAwAA
AAQAAAAEAAAABQAAAAUAAAAGAAAABgAAAAcAAAAHAAAACAAAAAgAAAAJAAAACQAAAAoAAAAKAAAA
CwAAAAsAAAAMAAAADAAAAA0AAAANAAAAAAAAAAAAAAADAAAABAAAAAUAAAAGAAAABwAAAAgAAAAJ
AAAACgAAAAsAAAANAAAADwAAABEAAAATAAAAFwAAABsAAAAfAAAAIwAAACsAAAAzAAAAOwAAAEMA
AABTAAAAYwAAAHMAAACDAAAAowAAAMMAAADjAAAAAgEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAABAAAAAQAAAAEAAAABAAAAAgAAAAIAAAACAAAAAgAAAAMAAAADAAAA
AwAAAAMAAAAEAAAABAAAAAQAAAAEAAAABQAAAAUAAAAFAAAABQAAAAAAAAAAAAAAAAAAABAREgAI
BwkGCgULBAwDDQIOAQ8AAQEAAAEAAAAEAAAA')

	atPut result 'text_start' '0x4010e000'
	atPut result 'data_start' '0x3fffaca8'
	atPut result 'entry' '0x4010e004'
	return result
}

method esp32_stub ESPTool {
	result = (dictionary)
	atPut result 'text' (base64Decode '
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')

	atPut result 'data' (base64Decode 'CMD8Pw==')
	atPut result 'text_start' '0x400be000'
	atPut result 'data_start' '0x3ffdeba8'
	atPut result 'entry' '0x400be594'
	return result
}

// Note: Addresses must be hexadecimal strings
method esp32_S2_stub ESPTool {
	result = (dictionary)
	atPut result 'entry' '0x40028804'
	atPut result 'text' (base64Decode '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')
	atPut result 'text_start' '0x40028000'
	atPut result 'data' (base64Decode 'WAD9P0uLAkDdiwJA8pACQGaMAkD+iwJAZowCQMWMAkDejQJAUY4CQPmNAkDVigJAd40CQNCNAkDojAJAdI4CQBCNAkB0jgJAy4sCQCqMAkBmjAJAxYwCQOOLAkAXiwJAN48CQKqQAkDqiQJA0ZACQOqJAkDqiQJA6okCQOqJAkDqiQJA6okCQOqJAkDqiQJA1I4CQOqJAkDJjwJAqpACQA==')
	atPut result 'data_start' '0x3ffe2bfc'
	return result
}

// Note: Addresses must be hexadecimal strings
method esp32_S3_stub ESPTool {
	result = (dictionary)
	atPut result 'entry' '0x40378a80'
	atPut result 'text' (base64Decode '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')
	atPut result 'text_start' '0x40378000'
	atPut result 'data' (base64Decode 'XADKP16ON0AzjzdAR5Q3QL2PN0BTjzdAvY83QB2QN0A6kTdArJE3QFWRN0DpjTdA0JA3QCyRN0BAkDdA0JE3QGiQN0DQkTdAIY83QH6PN0C9jzdAHZA3QDmPN0AqjjdAkJI3QA2UN0AAjTdALZQ3QACNN0AAjTdAAI03QACNN0AAjTdAAI03QACNN0AAjTdAKpI3QACNN0AlkzdADZQ3QAQInwAAAAAAAAAYAQQIBQAAAAAAAAAIAQQIBgAAAAAAAAAAAQQIIQAAAAAAIAAAEQQI3AAAAAAAIAAAEQQIDAAAAAAAIAAAAQQIEgAAAAAAIAAAESAoDAAQAQAA')
	atPut result 'data_start' '0x3fcb2bfc'
	return result
}

// Note: Addresses must be hexadecimal strings
method esp32_C3_stub ESPTool {
	result = (dictionary)
	atPut result 'entry' '0x403806d0'
	atPut result 'text' (base64Decode 'QREixCbCBsa3NwRgEUc3RMg/2Mu3NARgEwQEANxAkYuR57JAIkSSREEBgoCIQBxAE3X1D4KX3bcBEbcHAGBOxoOphwBKyDdJyD8mylLEBs4izLcEAGB9WhMJCQDATBN09D8N4PJAYkQjqDQBQknSRLJJIkoFYYKAiECDJwkAE3X1D4KXfRTjGUT/yb8TBwAMlEGqh2MY5QCFR4XGI6AFAHlVgoAFR2OH5gAJRmONxgB9VYKAQgUTB7ANQYVjlecCiUecwfW3kwbADWMW1QCYwRMFAAyCgJMG0A19VWOV1wCYwRMFsA2CgLd1yT9BEZOFxboGxmE/Y0UFBrd3yT+Th0eyA6cHCAPWRwgTdfUPkwYWAMIGwYIjktcIMpcjAKcAA9dHCJFnk4cHBGMe9wI398g/EwdHsqFnupcDpgcItzbJP7d3yT+Th0eyk4ZGtmMf5gAjpscII6DXCCOSBwghoPlX4wb1/LJAQQGCgCOm1wgjoOcI3bc3JwBgfEudi/X/NzcAYHxLnYv1/4KAQREGxt03tycAYCOmBwI3BwAImMOYQ33/yFeyQBNF9f8FiUEBgoBBEQbG2T993TcHAEC3JwBgmMM3JwBgHEP9/7JAQQGCgEERIsQ3xMg/kweEAUrAA6kHAQbGJsJjCgkERTc5xb1HEwSEAYFEY9YnAQREvYiTtBQAfTeFPxxENwaAABOXxwCZ4DcGAAG39v8AdY+3JgBg2MKQwphCff9BR5HgBUczCelAupcjKCQBHMSyQCJEkkQCSUEBgoABEQbOIswlNzcEzj9sABMFRP+XAMj/54Ag8KqHBUWV57JHk/cHID7GiTc3JwBgHEe3BkAAEwVE/9WPHMeyRZcAyP/ngKDtMzWgAPJAYkQFYYKAQRG3x8g/BsaTh4cBBUcjgOcAE9fFAJjHBWd9F8zDyMf5jTqVqpWxgYzLI6oHAEE3GcETBVAMskBBAYKAAREizDfEyD+TB4QBJsrER07GBs5KyKqJEwSEAWPzlQCuhKnAAylEACaZE1nJABxIY1XwABxEY175ArU9fd1IQCaGzoWXAMj/54Ag4RN19Q8BxZMHQAxcyFxAppdcwFxEhY9cxPJAYkTSREJJskkFYYKAaTVtv0ERBsaXAMj/54AA1gNFhQGyQHUVEzUVAEEBgoBBEQbGxTcdyTdHyD8TBwcAXEONxxBHHcK3BgxgmEYNinGbUY+YxgVmuE4TBgbA8Y99dhMG9j9xj9mPvM6yQEEBgoBBEQbGeT8RwQ1FskBBARcDyP9nAIPMQREGxibCIsSqhJcAyP/ngODJrT8NyTdHyD+TBgcAg9fGABMEBwCFB8IHwYMjlvYAkwYADGOG1AATB+ADY3X3AG03IxYEALJAIkSSREEBgoBBEQbGEwcADGMa5QATBbANRTcTBcANskBBAVm/EwewDeMb5f5xNxMF0A31t0ERIsQmwgbGKoSzBLUAYxeUALJAIkSSREEBgoADRQQABQRNP+23NXEmy07H/XKFaf10Is1KyVLFVsMGz5OEhPoWkZOHCQemlxgIs4TnACqJJoUuhJcAyP/ngEAYk4cJBxgIBWq6l7OKR0Ex5AVnfXWTBYX6kwcHBxMFhfkUCKqXM4XXAJMHBweul7OF1wAqxpcAyP/ngAAVMkXBRZU3AUWFYhaR+kBqRNpESkm6SSpKmkoNYYKAooljc4oAhWlOhtaFSoWXAMj/54AAwxN19Q8B7U6G1oUmhZcAyP/ngEAQTpkzBDRBUbcTBTAGVb8TBQAMSb0xcf1yBWdO11LVVtNezwbfIt0m20rZWtFizWbLaslux/13FpETBwcHPpccCLqXPsYjqgf4qokuirKKtovFM5MHAAIZwbcHAgA+hZcAyP/ngOAIhWdj5VcTBWR9eRMJifqTBwQHypcYCDOJ5wBKhZcAyP/ngGAHfXsTDDv5kwyL+RMHBAeTBwQHFAhil+aXgUQzDNcAs4zXAFJNY3xNCWPxpANBqJk/ooUIAY01uTcihgwBSoWXAMj/54BAA6KZopRj9UQDs4ekQWPxdwMzBJpAY/OKAFaEIoYMAU6FlwDI/+eAQLITdfUPVd0CzAFEeV2NTaMJAQBihZcAyP/ngICkffkDRTEB5oWRPGNPBQDj4o3+hWeThwcHopcYCLqX2pcjiqf4BQTxt+MVpf2RR+MF9PYFZ311kwcHB5MFhfoTBYX5FAiqlzOF1wCTBwcHrpezhdcAKsaXAMj/54Bg+XE9MkXBRWUzUT1VObcHAgAZ4ZMHAAI+hZcAyP/ngGD2hWIWkfpQalTaVEpZulkqWppaClv6S2pM2kxKTbpNKWGCgLdXQUkZcZOH94QBRYbeotym2srYztbS1NbS2tDezuLM5srqyO7GPs6XAMj/54BAnLExDc23BAxgnEQ3RMg/EwQEABzEvEx9dxMH9z9cwPmPk+cHQLzMEwVABpcAyP/ngGCSHETxm5PnFwCcxAE5IcG3hwBgN0fYUJOGhwoTBxeqmMIThwcJIyAHADc3HY8joAYAEwenEpOGBwuYwpOHxwqYQzcGAIBRj5jDI6AGALdHyD83d8k/k4cHABMHR7shoCOgBwCRB+Pt5/5BO5FFaAhxOWEzt/fIP5OHR7IhZz6XIyD3CLcHOEA3Scg/k4eHDiMg+QC3eck/UTYTCQkAk4lJsmMJBRC3JwxgRUe414VFRUWXAMj/54Dg37cFOEABRpOFBQBFRZcAyP/ngODgtzcEYBFHmMs3BQIAlwDI/+eAIOCXAMj/54Cg8LdHAGCcXwnl8YvhFxO1FwCBRZcAyP/ngICTwWe3xMg//RcTBwAQhWZBZrcFAAEBRZOEhAG3Ssg/DWqXAMj/54AAjhOLigEmmoOnyQj134OryQiFRyOmCQgjAvECg8cbAAlHIxPhAqMC8QIC1E1HY4HnCFFHY4/nBilHY5/nAIPHOwADxysAogfZjxFHY5bnAIOniwCcQz7UpTmhRUgQUTaDxzsAA8crAKIH2Y8RZ0EHY3T3BBMFsA39NBMFwA3lNBMF4A7NNKkxQbe3BThAAUaThYUDFUWXAMj/54BA0TcHAGBcRxMFAAKT5xcQXMcJt8lHIxPxAk23A8cbANFGY+fmAoVGY+bmAAFMEwTwD4WoeRcTd/cPyUbj6Ob+t3bJPwoHk4aGuzaXGEMCh5MGBwOT9vYPEUbjadb8Ewf3AhN39w+NRmPo5gq3dsk/CgeThkbANpcYQwKHEwdAAmOV5xIC1B1EAUWBNAFFcTRVNk02oUVIEH0UdTR19AFMAUQTdfQPlTwTdfwPvTRZNuMeBOqDxxsASUdjZfcyCUfjdvfq9ReT9/cPPUfjYPfqN3fJP4oHEwdHwbqXnEOChwVEoeu3BwBAA6dHAZlHcBCBRQFFY/3nAJfQzP/ngACzBUQF6dFFaBA9PAFEHaCXsMz/54Bg/e23BUSB75fwx//ngOBwMzSgACmgIUdjhecABUQBTL23A6yLAAOkywCzZ4wA0gf19+/w34B98cFsIpz9HH19MwWMQE3Ys3eVAZXjwWwzBYxAY+aMAv18MwWMQEncMYGX8Mf/54Dga1X5ZpT1tzGBl/DH/+eA4GpV8WqU0bdBgZfwx//ngKBpUfkzBJRBwbchR+OM5+4BTBMEAAzNvUFHzb9BRwVE45zn9oOlywADpYsAXTKxv0FHBUTjkuf2A6cLAZFnY+rnHoOlSwEDpYsA7/AP/DW/QUcFROOS5/SDpwsBEWdjavccA6fLAIOlSwEDpYsAM4TnAu/wj/kjrAQAIySKsDG3A8cEAGMDBxQDp4sAwRcTBAAMYxP3AMBIAUeTBvAOY0b3AoPHWwADx0sAAUyiB9mPA8drAEIHXY+Dx3sA4gfZj+OE9uQTBBAMgbUzhusAA0aGAQUHsY7ht4PHBAD9x9xEY50HFMBII4AEAH21YUdjlucCg6fLAQOniwGDpksBA6YLAYOlywADpYsAl/DH/+eAoFkqjDM0oADFuwFMBUTtsxFHBUTjmufmt5cAYLRDZXd9FwVm+Y7RjgOliwC0w7RHgUX5jtGOtMf0Q/mO0Y70w9RfdY9Rj9jfl/DH/+eAwFcBvRP39wDjFQfqk9xHABOEiwABTH1d43ec2UhEl/DH/+eAQEQYRFRAEED5jmMHpwEcQhNH9/99j9mOFMIFDEEE2b8RR6W1QUcFROOX596Dp4sAA6dLASMq+QAjKOkATbuDJQkBwReR5YnPAUwTBGAMJbsDJ0kBY2b3BhP3NwDjGQfiAyhJAQFGAUczBehAs4blAGNp9wDjBwbQIyqpACMo2QAJszOG6wAQThEHkMIFRum/IUcFROOR59gDJEkBGcATBIAMIyoJACMoCQAzNIAApbMBTBMEIAzBuQFMEwSADOGxAUwTBJAMwbETByANY4PnDBMHQA3jnue2A8Q7AIPHKwAiBF2Ml/DH/+eAIEIDrMQAQRRjc4QBIozjDAy0wEBilDGAnEhjVfAAnERjW/QK7/DPxnXdyEBihpOFiwGX8Mf/54AgPgHFkwdADNzI3EDil9zA3ESzh4dB3MSX8Mf/54AAPTm2CWUTBQVxA6zLAAOkiwCX8Mf/54DALrcHAGDYS7cGAAHBFpNXRwESB3WPvYvZj7OHhwMBRbPVhwKX8Mf/54CgLxMFgD6X8Mf/54BgK8G0g6ZLAQOmCwGDpcsAA6WLAO/wz/dttIPFOwCDxysAE4WLAaIF3Y3BFe/wr9BJvO/wD8A9vwPEOwCDxysAE4yLASIEXYzcREEUzeORR4VLY/+HCJMHkAzcyJ20A6cNACLQBUizh+xAPtaDJ4qwY3P0AA1IQsY6xO/wj7siRzJIN8XIP+KFfBCThooBEBATBQUDl/DH/+eAACw398g/kwiHAYJXA6eIsIOlDQAdjB2PPpyyVyOk6LCqi76VI6C9AJOHigGdjQHFoWdjl/UAWoXv8E/GI6BtAQnE3ESZw+NPcPdj3wsAkwdwDL23hUu3fck/t8zIP5ONTbuTjIwB6b/jkAuc3ETjjQeakweADKm3g6eLAOOWB5rv8A/PCWUTBQVxl/DH/+eAwBjv8M/Jl/DH/+eAABxpsgOkywDjAgSY7/CPzBMFgD6X8Mf/54BgFu/wb8cClK2y7/DvxvZQZlTWVEZZtlkmWpZaBlv2S2ZM1kxGTbZNCWGCgA==')
	atPut result 'text_start' '0x40380000'
	atPut result 'data' (base64Decode 'GEDIP8AKOEAQCzhAaAs4QDYMOECiDDhAUAw4QHIJOEDyCzhAMgw4QHwLOEAiCThAsAs4QCIJOECaCjhA4Ao4QBALOEBoCzhArAo4QNYJOEAgCjhAqAo4QPoOOEAQCzhAug04QLIOOEBiCDhA2g44QGIIOEBiCDhAYgg4QGIIOEBiCDhAYgg4QGIIOEBiCDhAVg04QGIIOEDYDThAsg44QA==')
	atPut result 'data_start' '0x3fc96bb4'
	return result
}
