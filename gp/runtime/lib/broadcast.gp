to whenBroadcastReceived msg data {
  // Defines a broadcast responder for msg (a String). A class
  // can have zero, one, or many responders for any given message.
  // The body of the responder can use the argument 'data' to
  // access the message data, if any was provided.
}

// The following stub allows old projects containing monitors to
// be opened so that obsolete monitors can be replaced.
to callImplicitSelfReporter { return 'replace this monitor!' }

to send msgName dstMorphs msgData {
  // The send block is the new way to broadcast to specific receiver(s).
  // The receiver or receiver list is the second argument with msgData (if any) last.
  broadcast msgName msgData dstMorphs
}

to broadcast msgName msgData dstMorphs {
  // Broadcast a message to the given morphs and return the resulting list of tasks.

  page = (global 'page')
  if (isNil page) { return }
  tasks = (list)
  uninterruptedly {
	for m (broadcastDestinations dstMorphs) {
	  for pair (respondersForBroadcast (handler m) msgName) {
		rcvr = (first pair)
		func = (last pair)
		task = (launch page (newReporter 'call' func (handler m) msgData) rcvr)
		setTopBlock task (cmdList func)
		add tasks task
	  }
	}
  }
  return tasks
}

to broadcastAndWait msgName msgData dstMorphs {
  // obsolete
  gather msgName dstMorphs msgData
}

to gather msgName dstMorphs msgData {
  tasks = (broadcast msgName msgData dstMorphs)
  if (isEmpty tasks) { return tasks }
  while (someTaskInProgress tasks) {
	waitForNextFrame
  }
  result = (list)
  for t tasks {
	if (notNil (result t)) { add result (result t) }
  }
  return (toArray result)
}

to someTaskInProgress taskList {
  // Return true if any task in the given list is still running.
  for t taskList {
	if (not (isTerminated t)) { return true }
  }
  return false
}

to broadcastDestinationsNEW dstList { // not currently used!
  // Return a list of morphs for the given destination list,
  // including both the destination morph and its parts.
  // If dstList is nil, use the owner of the implicit receiver.

  if (isNil dstList) { // no dstList; use implicit receiver's owner
	rcvr = (implicitReceiver)
	if (and (hasField rcvr 'morph') (notNil (owner (getField rcvr 'morph')))) {
	  dstList = (array (owner (getField rcvr 'morph')))
	} else {
	  dstList = (array (self_stageMorph))
	}
  } (not (isAnyClass dstList 'List' 'Array')) { // convert singleton to array
	dstList = (array dstList)
  }
  result = (list)
  for m dstList {
	if (hasField m 'morph') {
	  m = (getField m 'morph')
	}
	if (isClass m 'Morph') {
	  add result m
	  addAll result (parts m)
	}
  }
  return (toArray result)
}

to broadcastDestinations dstList {
  if (isNil dstList) { // broadcast to all morphs
	dstList = (allMorphs (self_stageMorph) true)
  } (not (isAnyClass dstList 'List' 'Array')) { // convert singleton to array
	dstList = (array dstList)
  }
  result = (list)
  for dst dstList { // replace handlers in result, if any, with their morphs
	if (and (not (isClass dst 'Morph')) (hasField dst 'morph')) {
	  add result (getField dst 'morph')
	}
	if (implements dst 'handler') { // destinations must implement 'handler' (as morphs do)
	  add result dst
	}
  }
  return result
}

to respondersForBroadcast handler msgName {
  scripts = (scripts (classOf handler))
  if (isNil scripts) { return (array) }

  result = (list)
  for entry scripts { // a script is an array: (x, y, cmd)
	cmd = (at entry 3)
	if (and (isAnyClass cmd 'Command' 'Reporter') ('whenBroadcastReceived' == (primName cmd))) {
	  args = (argList cmd)
	  if ((first args) == msgName) {
		// Create a function to run in the context of the handler
		// with the message data as the second argument.
		paramName = 'data'
		if ((count args) > 1) { paramName = (at args 2) }
		func = (functionFor handler paramName cmd)
		setField func 'functionName' (join 'broadcast: ' msgName)
		add result (array handler func)
	  }
	}
  }
  return result
}

// event hat block stubs

to whenClicked {}
to whenDropped {}
to whenKeyPressed {}
to whenPageResized {}
to whenScrolled scrollX scrollY {}
to whenTracking {}

// event dispatching

to dispatchEvent targetObj evtName evtArg1 evtArg2 {
  // Dispatch an event to the given handler. Return true if
  // at least one event hat was found, false otherwise.
  // The arguments evtArg1 evtArg2 are optional.

  page = (global 'page')
  evtHandled = false
  uninterruptedly {
	for pair (respondersForEvent targetObj evtName evtArg1) {
	  evtHandled = true
	  rcvr = (first pair)
	  func = (last pair)
	  task = (launch page (newCommand 'call' func rcvr evtArg1 evtArg2) rcvr)
	  setTopBlock task (cmdList func)
	}
  }
  return evtHandled
}

to dispatchKeyPressedEvent targetObj keyName {
  // Dispatch a whenKeyPressed event to all morphs. Return true
  // if at least one event hat was found, false otherwise.
  // The arguments evtArg1 evtArg2 are optional.

  page = (global 'page')
  uninterruptedly {
    for m (allMorphs (morph targetObj) true) {
      for pair (respondersForEvent (handler m) 'whenKeyPressed' keyName) {
		rcvr = (first pair)
		func = (last pair)
		task = (launch page (newCommand 'call' func rcvr keyName) rcvr)
		setTopBlock task (cmdList func)
	  }
	}
  }
}

to respondersForEvent targetObj evtName keyName {
  result = (list)
  scripts = (scripts (classOf targetObj))
  if (isNil scripts) { return result }

  for entry scripts { // a script is an array: (x, y, cmd)
	cmd = (at entry 3)
	if (and (isAnyClass cmd 'Command' 'Reporter') ((primName cmd) == evtName)) {
	  func = nil
	  args = (argList cmd)
	  if (isOneOf evtName 'whenScrolled' 'whenTracking') {
		func = (functionFor targetObj (at args 1) (at args 2) cmd)
	  } ('whenKeyPressed' == evtName) {
		hatKey = (first (argList cmd))
		paramName = 'key'
		if ((count args) > 1) { paramName = (at args 2) }
		if (or ('any' == hatKey) (keyName == hatKey)) {
		  func = (functionFor targetObj paramName cmd)
		}
	  } else {
		func = (functionFor targetObj cmd)
	  }
	  if (notNil func) {
		setField func 'functionName' (join 'event: ' evtName)
		add result (array targetObj func)
	  }
	}
  }
  return result
}
