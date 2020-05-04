defineClass HTTPFetcher socket received headers body

method oldFetch HTTPFetcher host path port {
  // Old code
if (isNil path) { path = '/' }
if (isNil port) { port = 80 }
socket = (openClientSocket host port)
if (isNil socket) { return '' }
nl = (string 13 10)
request = (join
'GET ' path ' HTTP/1.1' nl
'Host: ' host nl nl)
writeSocket socket request
waitMSecs 1000 // wait a bit
response = (list)
count = 1 // start loop
while (count > 0) {
chunk = (readSocket socket)
count = (byteCount chunk)
//	print count
if (count > 0) { add response chunk }
}
closeSocket socket
return (joinStrings response)
}

to httpGet host path port {
	if (isNil path) { path = '/' }
	if (isNil port) { port = 80 }
	if ('Browser' == (platform)) {
		url = (join 'http://' host path)
		if (80 != port) { url = (join url ':' port) }
		return (toString (httpGetInBrowser url))
	}
	socket = (openClientSocket host port)
	if (isNil socket) { return '' }
	nl = (string 13 10)
	request = (join
		'GET ' path ' HTTP/1.1' nl
		'Host: ' host nl nl)
	writeSocket socket request
	waitMSecs 1000 // wait a bit
	response = (list)
	count = 1 // start loop
	while (count > 0) {
		chunk = (readSocket socket)
		count = (byteCount chunk)
		if (count > 0) {
			add response chunk
			waitMSecs 50
		}
	}
	closeSocket socket
	return (joinStrings response)
}

to httpGetInBrowser url timeout {
	if (isNil timeout) { timeout = 1000 }
	if (and (beginsWith (browserURL) 'https:') (beginsWith url 'http:')) { // switch to 'https'
		url = (join 'https://' (substring url 8))
	}
	requestID = (startFetch url)
	start = (msecsSinceStart)
	while (((msecsSinceStart) - start) < timeout) {
		result = (fetchResult requestID)
		if (false == result) { return '' } // request failed
		if (notNil result) { return result } // request completed
		waitMSecs 20
	}
}

to httpBody response {
	headers = (list)
	lines = (lines response)
	i = (indexOf lines '')
	if (isNil i) { return '' } // no body
	return (joinStrings (copyFromTo lines (i + 1)) (newline))
}

to httpGetBinary host path port {
	if (isNil path) { path = '/' }
	if (isNil port) { port = 80 }
	if ('Browser' == (platform)) {
		url = (join 'http://' host path)
		if (80 != port) { url = (join url ':' port) }
		return (toString (httpGetInBrowser url))
	}
	socket = (openClientSocket host port)
	if (isNil socket) { return '' }
	nl = (string 13 10)
	request = (join
		'GET ' path ' HTTP/1.1' nl
		'Host: ' host nl
		'Accept:' 'application/octet-stream' nl nl)
	writeSocket socket request
	waitMSecs 1000 // wait a bit
	response = (newBinaryData)
	count = 1 // start loop
	while (count > 0) {
		chunk = (readSocket socket true)
		count = (byteCount chunk)
		if (count == 0) {
			waitMSecs 600
			chunk = (readSocket socket true)
			count = (byteCount chunk)
		}
		if (count > 0) {
			response = (join response chunk)
			waitMSecs 50
		}
	}
	closeSocket socket
	return (httpBinaryBody response)
}

to httpBinaryBody data {
	for i (byteCount data) {
		// find the end of the header (byte sequence 13 10 13 10)
		if (and
			(13 == (byteAt data i))
			(10 == (byteAt data (i + 1)))
			(13 == (byteAt data (i + 2)))
			(10 == (byteAt data (i + 3)))
		) {
			// return the body of the response as binary data
			return (copyFromTo data (i + 4))
		}
	}
	return nil
}

to httpHeaders response {
	headers = (list)
	for line (lines response) {
		if ('' == line) { return (joinStrings headers (newline)) }
		add headers line
	}
	return response // no body
}

to httpPut data host path port contentType {
	if (isNil path) { path = '/' }
	if (isNil port) { port = 80 }
	if (isNil contentType) { contentType = 'application/octet-stream' }
	socket = (openClientSocket host port)
	if (isNil socket) { return '' }
	nl = (string 13 10)
	request = (join
		'PUT ' path ' HTTP/1.1' nl
		'Host: ' host nl
		'Content-type: ' contentType nl
		'Content-length: ' (toString (count data)) nl nl)
	request = (join (toBinaryData request) (toBinaryData data))

	// send the request, including body data, if any
	while ((byteCount request) > 0) {
		written = (writeSocket socket request)
		if (0 == written) {
			waitMSecs 10 // wait a bit
		} (written < 0) {
			request = (toBinaryData '') // socket closed
		} else {
			request = (copyFromTo request (written + 1))
		}
	}

	response = (list)
	count = 1 // start loop
	while (count > 0) {
		chunk = (readSocket socket)
		count = 0
		if (notNil chunk) { count = (byteCount chunk) }
		if (count > 0) {
			add response chunk
			waitMSecs 50
		}
	}
	closeSocket socket
	return (joinStrings response)
}
