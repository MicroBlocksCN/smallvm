to basicHTTPGet host path port {
	// Return the body of the HTTP response as a string. Return empty string if request fails.

	return (toString (basicHTTPGetBinary host path port))
}

to basicHTTPGetBinary host path port {
	// Return the body of the HTTP response as binary data or empty BinaryData if request fails.

	response = (basicHTTPGetResponse host path port)
	i = (basicHTTPHeaderStart response)
	if (i > 0) { return (copyFromTo response (i + 4)) } // copy without headers
	return response // no header break found, so assume headers already removed
}

to basicHTTPGetHeaders host path port {
	// Return the headers of the HTTP response as a string or empty string if not found.

	response = (basicHTTPGetResponse host path port)
	i = (basicHTTPHeaderStart response)
	if (i < 1) { return '' }
	return (toString (copyFromTo response 1 i))
}

to basicHTTPHeaderStart data {
	for i (byteCount data) {
		// find the end of the header (byte sequence: 13 10 13 10)
		if (and
			(13 == (byteAt data i))
			(10 == (byteAt data (i + 1)))
			(13 == (byteAt data (i + 2)))
			(10 == (byteAt data (i + 3)))
		) {
			return i
		}
	}
	return -1
}

to basicHTTPGetResponse host path port {
	// Return the entire HTTP response, including headers, as binary data.

	if (isNil path) { path = '/' }
	if (isNil port) { port = 80 }
	if ('Browser' == (platform)) {
		url = (join 'http://' host path)
		if (80 != port) { url = (join url ':' port) }
		return (httpGetInBrowser url)
	}
	socket = (openClientSocket host port)
	if (isNil socket) { return (newBinaryData) }
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
	return response
}

to httpGetInBrowser url timeout {
	if (isNil timeout) { timeout = 1000 }
	if (and (beginsWith (browserURL) 'https:') (beginsWith url 'http:')) { // switch to 'https'
		url = (join 'https://' (substring url 8))
	}
	requestID = (startFetch url)
print 'httpGetInBrowser started' requestID
	start = (msecsSinceStart)
	while (((msecsSinceStart) - start) < timeout) {
		result = (fetchResult requestID)
		if (false == result) { print 'timeout'; return '' } // request failed
		if (notNil result) { print 'result:' result; return result } // request completed
		waitMSecs 20
	}
}
