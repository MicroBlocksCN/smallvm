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
	if ('Browser' == (platform)) { return '' }
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
		if (count > 0) { add response chunk }
	}
	closeSocket socket
	return (joinStrings response)
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
