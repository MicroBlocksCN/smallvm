// messageServer.gp - A message-based server framework.

// A MessageServer listens for connections on a given port, manages connections,
// and invokes the client-supplied msgAction on each message it receives;

defineClass MessageServer msgAction port startSecs requestCount serverSocket connections

method msgAction MessageServer { return msgAction }
method port MessageServer { return port }
method startSecs MessageServer { return startSecs }
method connectionCount MessageServer { return (count connections) }
method requestCount MessageServer { return requestCount }

to newMessageServer msgAction port {
  result = (initialize (new 'MessageServer'))
  if (notNil msgAction) { setField result 'msgAction' msgAction }
  if (notNil port) { setField result 'port' port }
  return result
}

method initialize MessageServer {
  msgAction = 'print'
  port = 1234
  startSecs = 0
  requestCount = 0
  serverSocket = nil
  connections = (list)
  return this
}

method startServer MessageServer {
  stopServer this
  gc
  startSecs = (first (time))
  serverLoop this
}

method stopServer MessageServer {
  // Close the serverSocket and all connections.

  if (notNil serverSocket) { closeSocket serverSocket }
  serverSocket = nil
  for c connections { closeConnection c }
  connections = (list)
  gc
}

method serverLoop MessageServer {
  serverSocket = (openServerSocket port)
  print (dateString) 'Message server listening on port' port
  while true {
	clientSock = (acceptConnection serverSocket)
	if (notNil clientSock) {
//	  print (dateString) 'Connection from' (remoteAddress clientSock)
	  add connections (newMessageConnection clientSock)
	}
	connectionWasClosed = false
	for c connections {
	  msg = (nextMessage c)
	  if (notNil msg) {
		requestCount += 1
		call msgAction msg c this
	  }
	  if (not (isOpen c)) { connectionWasClosed = true }
	}
	if connectionWasClosed {
	  connections = (filter 'isOpen' connections)
	  gcIfNeeded
	}
	if ((count connections) > 0) {
	  gcIfNeeded
	  waitMSecs 5
	} else {
	  waitMSecs 50
	}
  }
}

// A MessageConnection transmits and receives RemoteMessages over a
// TCP/IP socket. The connectTo method creates a connection to a server.
// Messages are sent with sendMessage and received with nextMessage.
// The actual data transfer is done by processConnection, which is called
// by sendMessage and nextMessage. One of these three methods periodically
// to ensure that data gets transfered. (In most cases, the client will
// call nextMessage to poll for new messages, which will ensure that data
// gets transfered).

defineClass MessageConnection sock inBuf outBuf done

method socket MessageConnection { return sock }

to newMessageConnection sock {
  result = (initialize (new 'MessageConnection'))
  setField result 'sock' sock
  return result
}

method initialize MessageConnection {
  inBuf = (newBinaryData 0)
  outBuf = (newBinaryData 0)
  done = false
  return this
}

method connectTo MessageConnection host port {
  // Connect to a message server on the given host and port.

  if (notNil sock) { closeSocket sock }
  sock = (openClientSocket host port)
  initialize this
  return this
}

method closeConnection MessageConnection {
  if (notNil sock) { closeSocket sock }
  sock = nil
}

method isOpen MessageConnection {
  return (notNil sock)
}

method nextMessage MessageConnection {
  // Return the next incoming message, or nil if there isn't one.

  processConnection this
  if ((byteCount inBuf) == 0) { return nil }
  newline = 10
  strm = (dataStream inBuf)
  parts = (words (nextStringUpTo strm newline))
  if (and ((count parts) == 2) ('MSG' == (first parts))) {
	byteCount = (toInteger (at parts 2))
	if (((position strm) + byteCount) <= (byteCount inBuf)) {
		msg = (fromData (new 'RemoteMessage') (nextData strm byteCount))
		inBuf = (copyFromTo inBuf ((position strm) + 1))
		return msg
	}
  }
  return nil
}

method sendFinalMessage MessageConnection msg {
  // Queue the given RemoteMessage for sending.
  // Close the connection after all messages have been sent.

  done = true
  sendMessage this msg
}

method sendMessage MessageConnection msg {
  // Queue the given RemoteMessage for sending.

  body = (toBinaryData msg)
  header = (join 'MSG ' (toString (byteCount body)) (newline))

  buf = (newBinaryData (+ (byteCount outBuf) (byteCount header) (byteCount body)))
  strm = (dataStream buf)
  nextPutAll strm outBuf
  nextPutAll strm header
  nextPutAll strm body
  outBuf = (contents strm)
  processConnection this
}

method processConnection MessageConnection {
  // This is where data is actually received and transmited.

  if (isNil sock) { return }

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
  } (isNil (socketStatus sock)) {
	closeConnection this // connection closed by other end
  } else {
	if done { closeConnection this } // final message has been sent
  }
  gcIfNeeded
}

// A RemoteMessage is a serializable message used for network communications.
// It consists of a command, zero or more arguments, and zero or more 'blobs'.
// Arguments can be numbers, strings, booleans, or nil. Blobs can contain string
// or binary data. The format of a message is:
//
//		command [arguments] <newline>
//		[blobs]
//
// The ASCII newline character is the single byte 10.
// Each blob is:
//
//		bytecount <newline>
//		<bytecount bytes of data> <newline>
//		<terminator> <newline>
//
// The bytecount is a human-readable string representing decimal number.
// The terminator is the 10-byte string: '----------' (i.e. 10 hyphens).
//
// This format allows messages to be viewed in a text editor for debugging
// (one can easily read bytecounts or search for terminators), yet it supports
// efficient inclusion of arbitrary binary data (no need to encode as Base64).

defineClass RemoteMessage command args blobs

method command RemoteMessage { return command }
method args RemoteMessage { return args }
method blobs RemoteMessage { return blobs }

to newRemoteMessage cmd args... {
  result = (initialize (new 'RemoteMessage'))
  setField result 'command' cmd
  for i (argCount) {
	if (i > 1) {
	  add (args result) (arg i)
	}
  }
  return result
}

method initialize RemoteMessage {
  command = ''
  args = (list)
  blobs = (list)
  return this
}

method callServer RemoteMessage host port {
  // Send this message to the given server and wait for a reply.

  connection = (connectTo (newMessageConnection) host port)
  sendMessage connection this
  gc
  while (isOpen connection) {
	reply = (nextMessage connection)
	if (notNil reply) {
	  if ('ok' == (command reply)) {
		closeConnection connection
		return reply
	  } else {
		print (dateString) 'server error:' (command reply)
		closeConnection connection
		return nil
	  }
	} else {
	  waitMSecs 2
	}
  }
  closeConnection connection
  return nil
}

method fromData RemoteMessage data {
  newline = 10
  strm = (dataStream data)

  cmd = (first (parse (nextStringUpTo strm newline)))
  command = (primName cmd)
  args = (argList cmd)

  blobs = (list)
  while (not (atEnd strm)) {
	blobLength = (toInteger (nextStringUpTo strm newline))
	add blobs (nextData strm blobLength)
	nextUInt8 strm // skip newline
	separator = (nextStringUpTo strm newline)
	if (separator != '----------') {
	  error 'Bad separator'
	}
  }
  return this
}

method toBinaryData RemoteMessage {
  newline = 10
  parts = (list command)
  for a args { add parts (printString a) }
  strm = (dataStream (newBinaryData 10000))
  nextPutAll strm (joinStrings parts ' ')
  putUInt8 strm newline
  for b blobs {
	nextPutAll strm (toString (byteCount b))
	putUInt8 strm newline
	nextPutAll strm b
	putUInt8 strm newline
	nextPutAll strm '----------'
	putUInt8 strm newline
  }
  return (contents strm)
}
