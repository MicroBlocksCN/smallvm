defineClass CloudDataServer userNames server

// start (new 'CloudDataServer')

to cloudDataHost {
  if (notNil (global 'cloudDataHost')) { return (global 'cloudDataHost') }
//  return '208.82.117.98'
//  return '127.0.0.1'
  return '104.236.119.50' // digial ocean
}

to cloudDataPort { return 2002 }

to putData user key data compressFlag {
  if (isNil data) { return }
  blob = (write (new 'Serializer') data)
  if compressFlag { blob = (deflate blob) }
  msg = (newRemoteMessage 'put' user key)
  add (blobs msg) blob
  callServer msg (cloudDataHost) (cloudDataPort)
}

to getData user key decompressFlag {
  msg = (newRemoteMessage 'get' user key)
  reply = (callServer msg (cloudDataHost) (cloudDataPort))
  if (and (notNil reply) ((count (blobs reply)) > 0)) {
	blob = (first (blobs reply))
	if decompressFlag { blob = (inflate blob) }
	return (read (new 'Serializer') blob)
  }
  return nil
}

to getDataServerStats {
  msg = (newRemoteMessage 'stats')
  reply = (callServer msg (cloudDataHost) (cloudDataPort))
  if (isNil reply) { return nil }
  return (args reply)
}

method start CloudDataServer port {
  if (isNil port) { port = 2002 }
  collectUserNames this
  server = (newMessageServer (action 'handleMessage' this) port)
  startServer server
}

method collectUserNames CloudDataServer {
  userNames = (list)
  for n (listDirectories 'cloudServer') {
	if (not (beginsWith n '.')) { add userNames n }
  }
  print 'Registered users:' userNames
}

method handleMessage CloudDataServer msg connection {
  cmd = (command msg)
//  print (dateString) cmd (remoteAddress (socket connection))
  if ('get' == cmd) {
    response = (handleGet this msg)
  } ('put' == cmd) {
    response = (handlePut this msg)
  } ('stats' == cmd) {
    response = (handleStats this msg)
  } else {
	response = (newRemoteMessage 'unknownCommand' cmd)
  }
  sendFinalMessage connection response
}

method handleGet CloudDataServer msg {
  if ((count (args msg)) < 2) {
	return (newRemoteMessage 'notEnoughArguments' (command msg))
  }
  user = (at (args msg) 1)
  key = (at (args msg) 2)
  if (not (and (isClass user 'String') (isClass key 'String'))) {
	return (newRemoteMessage 'arguments must be strings')
  }
  user = (canonicalizedWord user)
  if (not (contains userNames user)) {
	return (newRemoteMessage 'unknownUser' user)
  }
  data = (readFile (join './cloudServer/' (safeFileName this user) '/' (safeFileName this key)) true)
  if (isNil data) {
	return (newRemoteMessage 'fileNotFound' key)
  }
  response = (newRemoteMessage 'ok')
  add (blobs response) data
  return response
}

method handlePut CloudDataServer msg {
  if (or ((count (args msg)) < 2) ((count (blobs msg)) < 1)) {
	return (newRemoteMessage 'notEnoughArguments' (command msg))
  }
  user = (at (args msg) 1)
  key = (at (args msg) 2)
  if (not (and (isClass user 'String') (isClass key 'String'))) {
	return (newRemoteMessage 'arguments must be strings')
  }
  user = (canonicalizedWord user)
  if (not (contains userNames user)) {
	return (newRemoteMessage 'unknownUser' user)
  }
  data = (at (blobs msg) 1)
  writeFile (join './cloudServer/' (safeFileName this user) '/' (safeFileName this key)) data
  return (newRemoteMessage 'ok')
}

method handleStats CloudDataServer msg {
  return (newRemoteMessage 'ok'
	'uptime' (timeSince (startSecs server))
	'connections' (connectionCount server)
	'requestCount' (requestCount server)
	'gcCount' (last (memStats)))
}

method safeFileName CloudDataServer s {
  result = (letters s)
  for i (count result) {
	ch = (at result i)
	if (or ('/' == ch) ('\' == ch)) { atPut result i '-' }
	if ('.' == ch) { atPut result i ',' }
  }
  return (joinStrings result)
}
