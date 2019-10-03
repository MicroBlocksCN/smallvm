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

to httpGet host path port protocol {
        if (isNil protocol) { protocol = 'http' }
	if (isNil path) { path = '/' }
	if (isNil port) { port = 80 }
	if ('Browser' == (platform)) {
		url = (join protocol '://' host path)
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
		if (count > 0) { add response chunk }
	}
	closeSocket socket
	return (joinStrings response)
}

to httpGetInBrowser url timeout {
	if (isNil timeout) { timeout = 1000 }
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

to httpHeaders response {
	headers = (list)
	for line (lines response) {
		if ('' == line) { return (joinStrings headers (newline)) }
		add headers line
	}
	return response // no body
}
