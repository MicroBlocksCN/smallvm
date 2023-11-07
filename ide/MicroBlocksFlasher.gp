// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFlasher.gp - An interface to internal ESPTool to flash Espressif boards
// Bernat Romagosa, September 2019

defineClass MicroBlocksFlasher spinner boardName portName eraseFlag downloadFlag espTool socket fetchID downloadProgress

to newFlasher board serialPortName eraseFlashFlag downloadLatestFlag {
	return (initialize (new 'MicroBlocksFlasher') board serialPortName eraseFlashFlag downloadLatestFlag)
}

method initialize MicroBlocksFlasher board serialPortName eraseFlashFlag downloadLatestFlag {
	boardName = board
	portName = serialPortName
	eraseFlag = eraseFlashFlag
	downloadFlag = downloadLatestFlag
	spinner = (newSpinner (action 'espToolStatus' this) (action 'espToolDone' this))
	return this
}

method spinner MicroBlocksFlasher { return spinner }

method espToolStatus MicroBlocksFlasher {
	if (notNil espTool) { return (status espTool) }
}

method espToolDone MicroBlocksFlasher {
	return (or (isNil (task spinner)) (isTerminated (task spinner)))
}

method destroy MicroBlocksFlasher {
	destroy spinner
	enableAutoConnect (smallRuntime) (success espTool)
}

method startFlasher MicroBlocksFlasher serialPortID {
	espTool = (newESPTool)
	if (notNil serialPortID) {
		setPort espTool serialPortID
		ok = true
	} else {
		ok = (openPort espTool portName boardName)
	}
	if (not ok) {
		destroy this
		inform 'Could not open serial port'
		return
	}
	setTask spinner (launch
		(global 'page')
		(action 'installFirmware' espTool boardName eraseFlag downloadFlag))
}

// Downloading from URL

method installFromURL MicroBlocksFlasher serialPortID url {
url = 'https://microblocks.fun/downloads/pilot/vm/vm_esp32.bin'

	if ('Browser' == (platform)) {
		data = (downloadURLInBrowser this url)
	} else {
		data = (downloadURL this url)
	}
	if ((byteCount data) == 0) { return }

	espTool = (newESPTool)
	if (notNil serialPortID) {
		setPort espTool serialPortID
		ok = true
	} else {
		ok = (openPort espTool portName boardName)
	}
	if (not ok) {
		destroy this
		inform 'Could not open serial port'
		return
	}

    // install the downloaded firmware
	spinner = (newSpinner (action 'espToolStatus' this) (action 'espToolDone' this))
	setTask spinner (launch
		(global 'page')
		(action 'installFirmware' espTool '' false false data))
	addPart (global 'page') spinner
}

// Support for downloading files from URLs

method downloadProgress MicroBlocksFlasher actionLabel {
	if ('Browser' == (platform)) {
		return 'Downloading...'
	} else {
		return (join '' downloadProgress '%' )
	}
}

method abortDownload MicroBlocksFlasher {
	if (notNil socket) {
		closeSocket socket
		socket = nil
	}
	downloadProgress = nil
}

method downloadCompleted MicroBlocksFlasher {
	return (isNil downloadProgress)
}

method downloadURLInBrowser MicroBlocksFlasher url {
	fetchID = (startFetch url)
	result = nil
	while (and (notNil fetchID) (isNil result)) {
		doOneCycle (global 'page')
		waitMSecs 1
		result = (fetchResult fetchID)
	}
	if (or (isNil result) (false == result)) {
		result = (newBinaryData)
	}
	return result
}

method downloadURL MicroBlocksFlasher url {
	// Return the binary data for the given URL or an empty binary data if the download fails.

	i = (findSubstring '://' url)
	if (isNil i) { return (newBinaryData) }
	host = (substring url (i + 3))
	i = (findSubstring '/' host)
	path = (substring host i)
	host = (substring host 1 (i - 1))

	downloadProgress = 0
	spinner = (newSpinner (action 'downloadProgress' this 'downloaded') (action 'downloadCompleted' this))
	setStopAction spinner (action 'abortDownload' this)
	addPart (global 'page') spinner

	socket = (openClientSocket host 80)
	if (isNil socket) { return (newBinaryData) }

	nl = (string 13 10)
	request = (join
		'GET ' path ' HTTP/1.1' nl
		'Host: ' host nl
		'Accept:' 'application/octet-stream' nl nl)
	writeSocket socket request

	data = (newBinaryData)
	headers = ''
	bytesNeeded = -1
	while (or (bytesNeeded < 0) ((byteCount data) < bytesNeeded)) {
		chunk = (readSocket socket true)
		if ((byteCount chunk) > 0) {
			data = (join data chunk)
			if (headers == '') {
				headerEnd = (endOfHeaders this data)
				if (headerEnd > 0) {
					headers = (join '' (copyFromTo data 1 headerEnd))
					data = (copyFromTo data (headerEnd + 1))
					bytesNeeded = (toNumber (contentLength this headers))
				}
			}
			downloadProgress = (floor ((100 * (byteCount data)) / bytesNeeded))
		} else {
			waitMSecs 1
		}
		doOneCycle (global 'page')
	}
	closeSocket socket
	downloadProgress = nil
	return data
}

method endOfHeaders MicroBlocksFlasher data {
	for i (byteCount data) {
		// find the end of the header (byte sequence 13 10 13 10)
		if (and
			(13 == (byteAt data i))
			(10 == (byteAt data (i + 1)))
			(13 == (byteAt data (i + 2)))
			(10 == (byteAt data (i + 3)))
		) {
			// return the byte index of the end of the headers
			return (i + 3)
		}
	}
	return 0 // end of headers not found
}

method contentLength MicroBlocksFlasher httpHeaders {
	for s (lines httpHeaders) {
		if (beginsWith s 'Content-Length:') {
			return (toNumber (substring s 16))
		}
	}
	return 0 // no Content-Length: header
}
