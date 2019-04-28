// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

//Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksConnector.gp - An HTTP server that runs as a helper application, allowing a
// MicroBlocks IDE running in the browser to communicate with boards connected to USB ports.
// John Maloney, December, 2018

defineClass MicroBlocksConnector serverSocket clients port

method clients MicroBlocksConnector { return clients }

to newMicroBlocksConnector {
	result = (initialize (new 'MicroBlocksConnector'))
	return result
}

method initialize MicroBlocksConnector {
	serverSocket = nil
	clients = (list)
	return this
}

method restart MicroBlocksConnector {
	stop this
	serverSocket = (openServerSocket 8080)
	print (dateString) 'MicroBlocks Connector listening on port 8080'
	run this
}

method stop MicroBlocksConnector {
	if (notNil serverSocket) { closeSocket serverSocket }
	serverSocket = nil
	for c clients { closeConnection c }
	clients = (list)
}

method step MicroBlocksConnector {
	// accept a new client connection if there is one
	clientSock = (acceptConnection serverSocket)
	if (notNil clientSock) {
		print (dateString) 'Connection from' (remoteAddress clientSock)
		add clients (newMicroBlocksConnection this clientSock)
	}

	// serve clients
	connectionWasClosed = false
	for c clients {
		serveClient c
		if (not (isOpen c)) { connectionWasClosed = true }
	}
	if connectionWasClosed {
		clients = (filter 'isOpen' clients)
	}
}

method run MicroBlocksConnector {
	while true {
		step this
		waitMSecs 1 // chill for a bit to avoid burning CPU time
	}
}

// Serial Port Management

// http://127.0.0.1:8080/portList
// http://127.0.0.1:8080/openPort/cu.usbmodem1421
// http://127.0.0.1:8080/closePort/cu.usbmodem1421
// http://127.0.0.1:8080/ping

method openPort MicroBlocksConnector path {
	portName = (join '/dev/' (substring path ((count '/openPort/') + 1)))
	if (notNil port) { closeSerialPort port }
	port = (openSerialPort portName 115200)
print 'openPort' portName port
	return (toString port)
}

method closePort MicroBlocksConnector path {
	portID = (substring path ((count '/closePort/') + 1)) // not used yet
	if (notNil port) { closeSerialPort port }
	return 'closed'
}

method ping MicroBlocksConnector {
	if (isNil port) { return 'Port not open' }
	startT = (msecsSinceStart)

	writeSerialPort port (toBinaryData (array 250 26 0))
tries = (waitForResponse this 1)
print 'tries: ' tries
return (join '' ((msecsSinceStart) - startT) ' msecs ' tries ' tries')

	writeSerialPort port (toBinaryData (array 250 7 0))
	data = (waitForResponse this 10)
	return (toString (copyFromTo (toArray data) 7))
//
// 	// wait for a response
// 	timeout = 2000
// 	msecs = 0
// 	while (msecs < timeout) {
// 		s = (readSerialPort port true)
// 		if (notNil s) { return (join 'ping ' msecs ' msecs') }
// 		waitMSecs 1
// 		msecs = ((msecsSinceStart) - startT)
// 	}
// 	return 'ping timeout'
}

method waitForResponse MicroBlocksConnector byteCount {
	// Wait for byteCount bytes to arrive from the board, then return them.

tries = 0
	recvBuf = (newBinaryData)
	timeout = 2000
	start = (msecsSinceStart)
	while (((msecsSinceStart) - start) < timeout) {
		tries += 1
		s = (readSerialPort port true)
		if (notNil s) {
			recvBuf = (join recvBuf s)
//			if ((byteCount recvBuf) >= byteCount) { return recvBuf }
if ((byteCount recvBuf) >= byteCount) { return tries }
		}
		waitMSecs 1
	}
	return 0
}

defineClass MicroBlocksClient connector sock inBuf outBuf done

method socket MicroBlocksClient { return sock }

to newMicroBlocksConnection connector sock {
	return (initialize (new 'MicroBlocksClient') connector sock)
}

method initialize MicroBlocksClient aMicroBlocksConnector aSocket {
	connector = aMicroBlocksConnector
	sock = aSocket
	inBuf = (newBinaryData 0)
	outBuf = (newBinaryData 0)
	done = false
	return this
}

method closeConnection MicroBlocksClient {
print 'closeConnection'
	if (notNil sock) { closeSocket sock }
	sock = nil
}

method isOpen MicroBlocksClient {
	return (notNil sock)
}

method serveClient MicroBlocksClient {
	// This is where data is actually received and transmited.

	if (isNil sock) { return }
	if (isNil (socketStatus sock)) { // connection closed by other end
		closeConnection this
		return
	}
	data = (readSocket sock true)
	if ((byteCount data) > 0) {
//print 'got' (byteCount data) 'bytes'
//print (toString data)
		inBuf = (join inBuf data)
	}
	if ((byteCount outBuf) > 0) {
		n = (writeSocket sock outBuf)
// print 'sent' n 'bytes'
		if (n < 0) { // connection closed by other end
			closeConnection this
		} (n > 0) {
			outBuf = (copyFromTo outBuf (n + 1))
		}
	} done {
		closeConnection this // connection closed by this end
	}
	processNext this
}

method processNext MicroBlocksClient {
	// Process the next HTTP request in inBuf. Do nothing if the request is not complete.

	headers = (extractHeaders this)
	if (isNil headers) { return } // incomplete headers
	contentLength = (contentLength this headers)
	requestEnd = (+ (count headers) 4 contentLength)
	if ((byteCount inBuf) < requestEnd) { return } // incomplete body

	body = (copyFromTo inBuf ((count headers) + 5) requestEnd)
	inBuf = (copyFromTo inBuf (requestEnd + 1))
	handleRequest this headers body
}

method extractHeaders MicroBlocksClient {
	// Extract the header fields from inBuf. Return nil if a complete set of header has not been received.

	bufLen = (byteCount inBuf)
	if (bufLen <= 4) { return nil }
	for i (bufLen - 3) {
		if (and (13 == (byteAt inBuf i))
				(10 == (byteAt inBuf (i + 1)))
				(13 == (byteAt inBuf (i + 2)))
				(10 == (byteAt inBuf (i + 3)))) {
			return (toString (copyFromTo inBuf 1 (i - 1)))
		}
	}
	return nil // did not find end of headers; incomplete request
}

method contentLength MicroBlocksClient headers {
	// Return the value of the Content-Length: header or zero if there isn't one.

	s = (getHeader this headers 'Content-Length:')
	if (and (notNil s) (representsANumber s)) { return (toNumber s) }
	return 0
}

method getHeader MicroBlocksClient headers headerName {
	// Return the (string) value of the header line with the given name or nil if there isn't one'

	headerName = (toLowerCase headerName)
	for line (lines (toLowerCase headers)) {
		if (beginsWith line headerName) {
			i = ((count headerName) + 1)
			while (and (i < (count line)) ((at line i) <= ' ')) { i += 1 }
			return (substring line i)
		}
	}
	return nil
}

method handleRequest MicroBlocksClient header body {
	path = (at (words (first (lines header))) 2)
	if ('/' == path) {
		responseBody = (helpString this)
	} ('/portList' == path) {
		responseBody = (portList this)
	} (beginsWith path '/openPort/') {
		responseBody = (openPort connector path)
	} (beginsWith path '/closePort/') {
		responseBody = (closePort connector path)
	} ('/test' == path) {
		responseBody = 'Hello!'
	} ('/testLong' == path) {
		responseBody = (longString this)
	} ('/ping' == path) {
		responseBody = (ping connector)
	} else {
		responseBody = 'Unrecognized command'
	}
	responseHeaders = (list)
	add responseHeaders 'HTTP/1.1 200 OK'
	add responseHeaders 'Access-Control-Allow-Origin: *'
	add responseHeaders 'Access-Control-Allow-Methods: PUT'
	add responseHeaders (join 'Content-Length: ' (count responseBody))
	add responseHeaders ''
	add responseHeaders (toString responseBody)
	outBuf = (join outBuf (joinStrings responseHeaders (string 13 10)))
}

method helpString MicroBlocksClient {
	result = (list)
	add result '<head> <meta charset="UTF-8"> </head>'
	add result '<html>'
	add result '<h4>MicroBlocks Connector Commands</h4>'
	add result '/ - print this help text'
	add result '/portList - return a list of serial port names'
	add result '/openPort <portName> - open the given serial port and return a port ID'
	add result '/closePort <portID> - close the port with the given ID'
	add result '/portStatus <portID> - return a string with status and stats for the port with the given ID'
	add result '/port/<portID> - a HTTP PUT request that sends the body and returns available serial port data'
	add result '/test - return the string "hello!"'
	add result '/testLong - return a 1000 character string'
	add result '</html>'
	return (joinStrings result '<br>')
}

method portList MicroBlocksClient {
	portList = (serialPortNames this)
	if (isEmpty portList) { return 'No ports available; is your board plugged in?' }
	return (joinStrings portList (string 13 10))
}

method serialPortNames MicroBlocksClient {
	portList = (list)
	if ('Win' == (platform)) {
		portList = (toList (listSerialPorts))
		remove portList 'COM1'
	} ('Browser' == (platform)) {
		listSerialPorts // first call triggers callback
		waitMSecs 50
		portList = (list)
		for portName (listSerialPorts) {
			if (not (beginsWith portName '/dev/tty.')) {
				add portList portName
			}
		}
	} else {
		for fn (listFiles '/dev') {
			if (or (notNil (nextMatchIn 'usb' (toLowerCase fn) )) // MacOS
				   (notNil (nextMatchIn 'acm' (toLowerCase fn) ))) { // Linux
				add portList fn
			}
		}
		// Mac OS (and perhaps Linuxes) list a port as both cu.<name> and tty.<name>
		for s (copy portList) {
			if (beginsWith s 'tty.') {
				if (contains portList (join 'cu.' (substring s 5))) {
					remove portList s
				}
			}
		}
		names = (dictionary)
		addAll names portList

	}
	return portList
}

method longString MicroBlocksClient {
	result = (list)
	repeat 100 { add result '0123456789' }
	return (joinStrings result)
}

// WebSocket stuff (not currently used)

method handleHandshake MicroBlocksClient {
	// are headers complete? if not, return
	// check headers
	// send upgrade response or error
	blankLine = (string 13 10 13 10)
	headers = (toString inBuf)
	if (isNil (nextMatchIn (string 13 10 13 10) headers)) { return } // incomplete request
	i = (nextMatchIn 'Sec-WebSocket-Key: ' headers)
	if (isNil i) {
		state = 'error: missing Sec-WebSocket-Key header'
		done = true
	}
	key = (at (parseHeaders this headers) 'Sec-WebSocket-Key')
print 'key:' key

	response = (list)
	add response 'HTTP/1.1 101 Switching Protocols'
	add response 'Upgrade: websocket'
	add response 'Connection: Upgrade'
	add response 'Sec-WebSocket-Protocol: chat'
	add response 'Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo='
	add response ''
	add response ''
	outBuf = (join outBuf (toBinaryData (joinStrings response (string 13 10))))
	state = 'request received'
}

method parseHeaders MicroBlocksClient headerString {
	result = (dictionary)
	for line (lines headerString) {
		i = (findFirst line ':')
		if (notNil i) {
			key = (substring line 1 (i - 1))
			val = (substring line (i + 2)) // skip colon and space
			atPut result key val
		}
	}
	return result
}
