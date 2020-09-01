// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksThingServer.gp - An HTTP server implementing the Web of THings REST
// protocol. This server allows a Snap! and other tools running in the browser to communicate
// with a board tethered via a USB cable to the MicroBlocks IDE.
//
// John Maloney and Bernat Romagosa, May, 2019

defineClass MicroBlocksThingServer serverSocket vars workers

to newMicroBlocksThingServer {
	result = (initialize (new 'MicroBlocksThingServer'))
	return result
}

method initialize MicroBlocksThingServer {
	serverSocket = nil
	vars = (dictionary)
	workers = (list)
	return this
}

method start MicroBlocksThingServer {
	stop this
	serverSocket = (openServerSocket 6473)
	print 'MicroBlocks Thing Server listening on port 6473'
	return (isRunning this)
}

method stop MicroBlocksThingServer {
	if (notNil serverSocket) { closeSocket serverSocket }
	serverSocket = nil
	for c workers { closeConnection c }
	workers = (list)
}

method isRunning MicroBlocksThingServer {
	return (notNil serverSocket)
}

method step MicroBlocksThingServer {
	if (isNil serverSocket) { return }

	// accept a new connection if there is one
	clientSock = (acceptConnection serverSocket)
	if (notNil clientSock) {
		add workers (newMicroBlocksThingWorker this clientSock)
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

method run MicroBlocksThingServer {
	start this
	while true {
		step this
		waitMSecs 1 // chill for a bit to avoid burning CPU time
	}
}

// Broadcasts

method broadcastReceived MicroBlocksThingServer msg {
	// Called by the the runtime system when a broadcast is received from the board.
	// Add the broadcast to the queue for each worker.

	for w workers { broadcastReceived w msg }
}

// Variables

method clearVars MicroBlocksThingServer {
	vars = (dictionary)
}

method variableIndex MicroBlocksThingServer varName {
	// Return the id of the given variable or nil if the variable is not defined.

	varNames = (allVariableNames (project (scripter (smallRuntime))))
	return (indexOf varNames varName)
}

method requestVarFromBoard MicroBlocksThingServer varName {
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

method varValueReceived MicroBlocksThingServer varID value {
	varNames = (allVariableNames (project (scripter (smallRuntime))))
	if (varID < (count varNames)) {
		varName = (at varNames (varID + 1))
		atPut vars varName value
	}
}

defineClass MicroBlocksThingWorker server sock inBuf outBuf broadcastsFromBoard

to newMicroBlocksThingWorker aMicroBlocksThingServer aSocket {
	return (initialize (new 'MicroBlocksThingWorker') aMicroBlocksThingServer aSocket)
}

method initialize MicroBlocksThingWorker aMicroBlocksThingServer aSocket {
	server = aMicroBlocksThingServer
	sock = aSocket
	inBuf = (newBinaryData 0)
	outBuf = (newBinaryData 0)
	broadcastsFromBoard = (list)
	return this
}

method closeConnection MicroBlocksThingWorker {
	if (notNil sock) { closeSocket sock }
	sock = nil
}

method isOpen MicroBlocksThingWorker {
	return (notNil sock)
}

method stepWorker MicroBlocksThingWorker {
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

method processNext MicroBlocksThingWorker {
	// Process the next request in inBuf. Do nothing if the request is not complete.

	headers = (extractHeaders this)
	if (isNil headers) { return } // incomplete headers
	contentLength = (contentLength this headers)
	requestEnd = (+ (count headers) 4 contentLength)
	if ((byteCount inBuf) < requestEnd) { return } // incomplete body

	body = (copyFromTo inBuf ((count headers) + 5) requestEnd)
	inBuf = (copyFromTo inBuf (requestEnd + 1))
	handleRequest this headers body
}

method extractHeaders MicroBlocksThingWorker {
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

method contentLength MicroBlocksThingWorker headers {
	// Return the value of the Content-Length: header or zero if there isn't one.

	s = (getHeader this headers 'Content-Length:')
	if (and (notNil s) (representsAnInteger s)) { return (toNumber s) }
	return 0
}

method getHeader MicroBlocksThingWorker headers headerName {
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

method handleRequest MicroBlocksThingWorker header body {
	method = (at (words (first (lines header))) 1)
	path = (at (words (first (lines header))) 2)
	if ('/' == path) {
		if ('GET' == method) {
			responseBody = (getWebThingDefinition this)
		} else {
			responseBody = (errorResponse this 'Unhandled method')
		}
	} (beginsWith path '/getBroadcasts') {
		if ('GET' == method) {
			responseBody = (getBroadcasts this path)
		} else {
			responseBody = (errorResponse this 'Unhandled method')
		}
	} (beginsWith path '/broadcast') {
		if ('GET' == method) {
			responseBody = (sendBroadcast this path)
		} else {
			responseBody = (errorResponse this 'Unhandled method')
		}
	} (beginsWith path '/properties') {
		if ('GET' == method) {
			responseBody = (getProperties this path)
		} ('PUT' == method) {
			(setProperty this path body)
			responseBody = (getProperties this path)
		} else {
			responseBody = (errorResponse this 'Unhandled method')
		}
	} (beginsWith path '/mb') {
		responseBody = (handleMBRequest this (substring path 4))
	} else {
		responseBody = (errorResponse this)
	}
	responseHeaders = (list)
	add responseHeaders 'HTTP/1.1 200 OK'
	add responseHeaders 'Access-Control-Allow-Origin: *'
	add responseHeaders 'Access-Control-Allow-Methods: PUT, GET, OPTIONS, POST'
	if (not (beginsWith path '/mb')) {
		add responseHeaders 'Content-Type: application/json'
	}
	add responseHeaders (join 'Content-Length: ' (count responseBody))
	add responseHeaders ''
	add responseHeaders (toString responseBody)
	outBuf = (join outBuf (joinStrings responseHeaders (string 13 10)))
}

method errorResponse MicroBlocksThingWorker errorString {
	if (isNil errorString) {
		errorString = 'Unrecognized command'
	}
	return (join '{"error":' errorString '}')
}

// WebThing definition

method getWebThingDefinition MicroBlocksThingWorker {
	result = (list)
	add result '{ "name": "MicroBlocks IDE",'
	add result '"@context": "https://iot.mozilla.org/schemas/",'
	add result '"@type": "MicroBlocksIDE",'
	add result '"properties":'
	add result (getProperties this)
	add result '}'
	return (joinStrings result (newline))
}

// Properties (uBlocks variables)

method getProperties MicroBlocksThingWorker path {
	if ((count path) > 11) {
		varName = (urlDecode (substring path 13))
		if (endsWith varName '/') { varName = (substring varName 1 ((count varName) - 1)) }
		value = (requestVarFromBoard server varName)
		return (join '{"' varName '":' (jsonStringify value) '}')
	} else {
		result = (list)
		varNames = (filter
		(function each { return (not (beginsWith each '_')) })
		(allVariableNames (project (scripter (smallRuntime)))))
		add result '{'
	if ((count varNames) > 0) {
		for v varNames {
			add result (join '"' v '":{')
			add result (join '"href":"/properties/' v '",')
			add result (join '"type":"string"')
			add result '},'
		}
		// remove last comma
		atPut result (count result) (substring (last result) 1 ((count (last result)) - 1))
	}
		add result '}'
		return (joinStrings result (newline))
	}
}

method setProperty MicroBlocksThingWorker path body {
	// Handle PUT request with URL of form: /properties/<URL_encoded var name>
	//	with body: {"varName":value}
	//	where value is:
	//		true, false, <integer value>, <url-encoded string>
	// Set the given variable to the given value.
	// A string can be enclosed in optional double-quotes to pass strings that
	// would otherwise be interpreted as booleans or integers.

	dict = (jsonParse (toString body))
	varName = (first (keys dict))
	value = (at dict varName)
	id = (variableIndex server varName)
	if (notNil id) { setVar (smallRuntime) (id - 1) value } // VM uses zero-based index
}

method handleMBRequest MicroBlocksThingWorker path {
	if ('/' == path) {
		return (helpString this)
	} (beginsWith path '/getBroadcasts') {
		return (getBroadcasts this path)
	} (beginsWith path '/broadcast') {
		return (sendBroadcast this path)
	} (beginsWith path '/getVar') {
		return (getVar this path)
	} (beginsWith path '/setVar') {
		return (setVar this path)
	} else {
		return 'Unrecognized /mb command'
	}
}

method helpString MicroBlocksThingWorker {
	result = (list)
	add result 'MicroBlocks HTTP Server'
	add result ''
	add result '/mb/ - this help text'
	add result '/mb/getBroadcasts - get broadcasts from board, (URL-encoded strings, one per line)'
	add result '/mb/broadcast/URL_encoded_message - broadcast message to board'
	add result '/mb/getVar/URL_encoded_var_name - get variable value'
	add result '/mb/setVar/URL_encoded_var_name/value - set variable value'
	add result '  (value is: true, false, an integer, or a url_encoded_string)'
	add result '  (use double-quotes for string values that would otherwise be treated as a boolean or integer such as "true", "false", or "12345")'
	return (joinStrings result (newline))
}

// Broadcasts

method broadcastReceived MicroBlocksThingWorker msg {
	// Add the given message to the list of received broadcasts.

	add broadcastsFromBoard msg
}

method getBroadcasts MicroBlocksThingWorker path {
	// Handle URL of form: /getBroadcasts
	// Return a list of URL-encoded broacast strings received from the board, one per line.

	result = (joinStrings broadcastsFromBoard (newline))
	broadcastsFromBoard = (list) // clear list
	return result
}

method sendBroadcast MicroBlocksThingWorker path {
	// Handle URL of form: /broadcast/<URL_encoded broadcast string>
	// Send the given broadcast to the board.

	msg = (urlDecode (substring path 12))
	sendBroadcastToBoard (smallRuntime) msg
}

// Variables

method getVar MicroBlocksThingWorker path {
	// Handle URL of form: /getVar/<URL_encoded var name>
	// Return the value of the given variable.

	varName = (urlDecode (substring path 9))
	if (endsWith varName '/') { varName = (substring varName 1 ((count varName) - 1)) }
	if ('' == varName) { return 'error: missing var name' }
	value = (requestVarFromBoard server varName)
	return (jsonStringify value)
}

method setVar MicroBlocksThingWorker path {
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
		value = (urlDecode valueString)
		if (and ((count value) >= 2) (beginsWith value '"') (endsWith value '"')) {
			// string enclosed in double quotes: remove quotes
			value = (substring value 2 ((count value) - 1))
		}
	}
	id = (variableIndex server varName)
	if (notNil id) { setVar (smallRuntime) (id - 1) value } // VM uses zero-based index
}
