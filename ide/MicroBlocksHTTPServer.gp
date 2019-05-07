// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksHTTPServer.gp - An HTTP server that runs as a helper application, allowing a
// MicroBlocks IDE running in the browser to communicate with the MicroBlocks IDE.
// John Maloney, April, 2019

defineClass MicroBlocksHTTPServer serverSocket vars workers

to newMicroBlocksHTTPServer {
	result = (initialize (new 'MicroBlocksHTTPServer'))
	return result
}

method initialize MicroBlocksHTTPServer {
	serverSocket = nil
	vars = (dictionary)
	workers = (list)
	return this
}

method start MicroBlocksHTTPServer {
	stop this
	serverSocket = (openServerSocket 6473)
	print 'MicroBlocks HTTP Server listening on port 6473'
}

method stop MicroBlocksHTTPServer {
	if (notNil serverSocket) { closeSocket serverSocket }
	serverSocket = nil
	for c workers { closeConnection c }
	workers = (list)
}

method step MicroBlocksHTTPServer {
	if (isNil serverSocket) { return }

	// accept a new HTTP connection if there is one
	clientSock = (acceptConnection serverSocket)
	if (notNil clientSock) {
		add workers (newMicroBlocksHTTPWorker this clientSock)
	}

	// process requests
	connectionWasClosed = false
	for c workers {
		stepWorker c
		if (not (isOpen c)) { connectionWasClosed = true }
	}
	if connectionWasClosed {
		workers = (filter 'isOpen' workers)
	}
}

method run MicroBlocksHTTPServer {
	start this
	while true {
		step this
		waitMSecs 1 // chill for a bit to avoid burning CPU time
	}
}

// Broadcasts

method broadcastReceived MicroBlocksHTTPServer msg {
	// Called by the the runtime system when a broadcast is received from the board.
	// Add the broadcast to the queue for each worker.

	for w workers { broadcastReceived w msg }
}

// Variables

method clearVars MicroBlocksHTTPServer {
	vars = (dictionary)
}

method variableIndex MicroBlocksHTTPServer varName {
	// Return the id of the given variable or nil if the variable is not defined.

	varNames = (copyWithout (variableNames (targetModule (scripter (smallRuntime)))) 'extensions')
	return (indexOf varNames varName)
}

method requestVarFromBoard MicroBlocksHTTPServer varName {
	// Request the given variable from the board and return its last known value.
	// Note: This design allows the HTTP request to complete immediately, but the
	// variable value may be out of date. However, if the client is continuously
	// requesting the value of a variable (e.g. for a variable watcher) than it
	// will only lag by one request.

	id = (variableIndex this varName)
	if (isNil id) { return 0 }
	getVar (smallRuntime) (id - 1) // VM uses zero-based index

	if (not (contains vars varName)) { atPut vars varName 0 }
	return (at vars varName)
}

method varValueReceived MicroBlocksHTTPServer varID value {
	varNames = (copyWithout (variableNames (targetModule (scripter (smallRuntime)))) 'extensions')
	if (varID < (count varNames)) {
		varName = (at varNames (varID + 1))
		atPut vars varName value
	}
}

defineClass MicroBlocksHTTPWorker server sock inBuf outBuf broadcastsFromBoard

to newMicroBlocksHTTPWorker aMicroBlocksHTTPServer aSocket {
	return (initialize (new 'MicroBlocksHTTPWorker') aMicroBlocksHTTPServer aSocket)
}

method initialize MicroBlocksHTTPWorker aMicroBlocksHTTPServer aSocket {
	server = aMicroBlocksHTTPServer
	sock = aSocket
	inBuf = (newBinaryData 0)
	outBuf = (newBinaryData 0)
	broadcastsFromBoard = (list)
	return this
}

method closeConnection MicroBlocksHTTPWorker {
	if (notNil sock) { closeSocket sock }
	sock = nil
}

method isOpen MicroBlocksHTTPWorker {
	return (notNil sock)
}

method stepWorker MicroBlocksHTTPWorker {
	// This is where data is actually received and transmited.

	if (isNil sock) { return }
	if (isNil (socketStatus sock)) { // connection closed by other end
		closeConnection this
		return
	}
	data = (readSocket sock true)
	if ((byteCount data) > 0) {
		inBuf = (join inBuf data)
	}
	if ((byteCount outBuf) > 0) {
		n = (writeSocket sock outBuf)
		if (n < 0) { // connection closed by other end
			closeConnection this
		} (n > 0) {
			outBuf = (copyFromTo outBuf (n + 1))
		}
	}
	processNext this
}

method processNext MicroBlocksHTTPWorker {
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

method extractHeaders MicroBlocksHTTPWorker {
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

method contentLength MicroBlocksHTTPWorker headers {
	// Return the value of the Content-Length: header or zero if there isn't one.

	s = (getHeader this headers 'Content-Length:')
	if (and (notNil s) (representsAnInteger s)) { return (toNumber s) }
	return 0
}

method getHeader MicroBlocksHTTPWorker headers headerName {
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

method handleRequest MicroBlocksHTTPWorker header body {
	path = (at (words (first (lines header))) 2)
	if ('/' == path) {
		responseBody = (helpString this)
	} ('/test' == path) {
		responseBody = 'Hello!'
	} ('/testLong' == path) {
		responseBody = (longString this)
	} (beginsWith path '/getBroadcasts') {
		responseBody = (getBroadcasts this path)
	} (beginsWith path '/broadcast') {
		responseBody = (sendBroadcast this path)
	} (beginsWith path '/getVar') {
		responseBody = (getVar this path)
	} (beginsWith path '/setVar') {
		responseBody = (setVar this path)
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

method helpString MicroBlocksHTTPWorker {
	result = (list)
	add result '<html>'
	add result '<head> <meta charset="utf-8"> </meta> </head>'
	add result '<h4>MicroBlocks HTTP Server</h4>'
	add result '/ - return this help text<br>'
	add result '/test - return the string "hello!"<br>'
	add result '/testLong - return a 1000 character string<br>'
	add result '<br>'
	add result '/getBroadcasts - return a list of URL-encoded messages from the board, one per line<br>'
	add result '/broadcast/URL_encoded_message - broadcast the given message to the board<br>'
	add result '/getVar/URL_encoded_var_name - return variable value<br>'
	add result '/setVar/URL_encoded_var_name/value - set variable to value, where value is: true, false, INTEGER, url_encoded_string<br>'
	add result '</html>'
	return (joinStrings result (newline))
}

method longString MicroBlocksHTTPWorker {
	result = (list)
	repeat 100 { add result '0123456789' }
	return (joinStrings result)
}

// Broadcasts

method broadcastReceived MicroBlocksHTTPWorker msg {
	// Add the given message to the list of received broadcasts.

	add broadcastsFromBoard msg
}

method getBroadcasts MicroBlocksHTTPWorker path {
	// Handle URL of form: /getBroadcasts
	// Return a list of URL-encoded broacast strings received from the board, one per line.

	result = (joinStrings broadcastsFromBoard (newline))
	broadcastsFromBoard = (list) // clear list
	return result
}

method sendBroadcast MicroBlocksHTTPWorker path {
	// Handle URL of form: /broadcast/<URL_encoded broadcast string>
	// Send the given broadcast to the board.

	msg = (urlDecode (substring path 12))
	sendBroadcastToBoard (smallRuntime) msg
}

// Variables

method getVar MicroBlocksHTTPWorker path {
	// Handle URL of form: /getVar/<URL_encoded var name>
	// Return the value of the given variable.

	varName = (urlDecode (substring path 9))
	if (endsWith varName '/') { varName = (substring varName 1 ((count varName) - 1)) }
	if ('' == varName) { return 'error: missing var name' }
	value = (requestVarFromBoard server varName)
	return (toString value)
}

method setVar MicroBlocksHTTPWorker path {
	// Handle URL of form: /setVar/<URL_encoded var name>/<value> where value is:
	//	true, false, <integer value>, <url-encoded string>
	// Set the given variable to the given value.
	// A string can be enclosed in optional double-quotes to pass strings that
	// would otherwise be interpreted as booleans or integers.

	i = (indexOf (letters path) '/' 8)
	if (isNil i) { return 'error: unexpected URL format' }
	varName = (urlDecode (substring path 9 (i - 1)))
	valueString = (substring path (i + 1))
	if (representsAnInteger valueString)  {
		value = (toInteger valueString)
	} ('true' == valueString) {
		value = true
	} ('false' == valueString) {
		value = false
	} else {
		value = (urlDecode (substring valueString 2 ((count valueString) - 1)))
		if (and ((count value) >= 2) (beginsWith value '"') (endsWith value '"')) {
			// string enclosed in double quotes: remove quotes
			value = (substring value 2 ((count value) - 1))
		}
	}
	id = (variableIndex server varName)
	if (notNil id) { setVar (smallRuntime) (id - 1) value } // VM uses zero-based index
}
