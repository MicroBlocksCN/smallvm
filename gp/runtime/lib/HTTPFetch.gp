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
socket = (openClientSocket host port)
if (isNil socket) { return '' }
nl = (string 13 10)
request = (join
'GET ' (urlEncode path) ' HTTP/1.1' nl
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
