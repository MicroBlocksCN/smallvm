// webBrowserRuntime.gp -- runtime support when GP is running in a web browser
// John Maloney, December 2016

// *** Project Fetching at Startup ***

to fetchProject {
  // Called from browser startup.gp to fetch a project encoded in the URL, if any.
  // Project URL for testing: http://gpblocks.org/projects/1-Intro/Effects.gpp

  setGlobal 'initialProject' nil
  projURL = (extractProjectArg (browserURL))
  if (isNil projURL) { return }
  print 'fetching' projURL
  request = (startFetch projURL)
  if (isNil request) { return }
  while true {
	result = (fetchResult request)
	if (isNil result) {
	  waitMSecs 20
	} else {
	  if (isClass result 'BinaryData') {
		print 'got project' projURL (byteCount result) 'bytes'
		setGlobal 'initialProject' (list result projURL)
	  } else { print 'failed' }
	  return
	}
  }
}

to extractProjectArg url {
  i = (indexOf (letters url) '#')
  if (isNil i) { i = (indexOf (letters url) '?') }
  if (isNil i) { return nil }
  result = (substring url (i + 1))
  if (not (or (beginsWith result 'http://') (beginsWith result 'http://'))) {
	if (beginsWith url 'https:') {
	  prefix = 'https:'
	} else {
	  prefix = 'http:'
	}
	result = (join prefix '//' result)
  }
  return result
}

to extractCommand url {
  end = (indexOf (letters url) '#')
  if (isNil end) { end = ((count url) + 1) }
  start = (lastIndexOf (letters url) '/' end)
  if (isNil start) { start = 1 }
  return (substring url (start + 1) (end - 1))
}

// fetch primitive tests

to clearRequests {
  setGlobal 'requests' (list)
}

to fetch1 {
  if (isNil (global 'requests')) { setGlobal 'requests' (list) }
  requests = (global 'requests')
  projects = (list 'AnimatedTree.gpp' 'Engine.gpp' 'FerrisWheel.gpp' 'Jabberwocky.gpp' 'SpiroGraph.gpp' )
  for p projects {
    r = (startFetch (join 'http://gpblocks.org/projects/2-Animation/' p))
    if (isNil r) {
	  print 'could not start request for:' p
	} else {
	  add requests r
	}
  }
}

to fetch2 {
  for r (global 'requests') {
    result = (fetchResult r)
    if (isClass result 'BinaryData') {
		print r 'got' (byteCount result) 'bytes'
	} (false == result) {
		print r 'failed'
	} (isNil result) {
		print r 'still in progress'
	} else {
		print r 'unexpected' result
	}
  }
}
