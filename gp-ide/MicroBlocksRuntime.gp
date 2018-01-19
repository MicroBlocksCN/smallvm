// SmallCompiler.gp - A blocks compiler for SmallVM
// John Maloney, April, 2017

to smallRuntime aScripter {
	if (isNil (global 'smallRuntime')) {
		setGlobal 'smallRuntime' (new 'SmallRuntime' aScripter)
	}
	return (global 'smallRuntime')
}

defineClass SmallRuntime scripter chunkIDs chunkRunning msgDict portName port recvBuf

method scripter SmallRuntime { return scripter }

method microBlocksSpecs SmallRuntime {
	return (array
	'I/O'
		(array ' ' 'setLEDOp'			'set user LED _' 'bool' true)
		(array 'r' 'analogReadOp'		'read analog pin _' 'num' 1)
		(array ' ' 'analogWriteOp'		'write analog pin _ value _' 'num num' 1 1023)
		(array 'r' 'digitalReadOp'		'read digital pin _' 'num' 1)
		(array ' ' 'digitalWriteOp'		'set digital pin _ to _' 'num bool' 1 true)
		(array 'r' 'analogPinsOp'		'analog pins')
		(array 'r' 'digitalPinsOp'		'digital pins')
		(array 'r' 'microsOp'			'micros')
		(array 'r' 'millisOp'			'millis')
		(array 'r' 'i2cGet'				'i2c get device _ register _' 'num num')
		(array ' ' 'i2cSet'				'i2c set device _ register _ to _' 'num num num')
		(array ' ' 'printIt'			'print _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 'Hello, Arduino!')
		(array ' ' 'sayIt'				'say _' 'auto' 123)
	'MicroBit'
		(array ' ' 'mbDisplay'			'display _ _ _ _ _  _ _ _ _ _  _ _ _ _ _  _ _ _ _ _  _ _ _ _ _' 'bool bool bool bool bool  bool bool bool bool bool  bool bool bool bool bool  bool bool bool bool bool  bool bool bool bool bool')
		(array ' ' 'mbDisplayOff'		'clear display')
		(array ' ' 'mbPlot'				'plot x _ y _' 'num num' 3 3)
		(array ' ' 'mbUnplot'			'unplot x _ y _' 'num num' 3 3)
		(array 'r' 'mbTiltX'			'tilt x')
		(array 'r' 'mbTiltY'			'tilt y')
		(array 'r' 'mbTiltZ'			'tilt z')
		(array 'r' 'mbMagX'				'magnetic x')
		(array 'r' 'mbMagY'				'magnetic y')
		(array 'r' 'mbMagZ'				'magnetic z')
		(array 'r' 'mbMagTemp'			'temperature Celcius')
	'Control'
		(array ' ' 'if'					'if _ _ : else if _ _ : ...' 'bool cmd bool cmd')
		(array ' ' 'repeat'				'repeat _ _' 'num cmd' 10)
		(array ' ' 'while'				'while _ _' 'bool cmd')
		(array ' ' 'waitUntil'			'wait until _' 'bool')
		(array ' ' 'stopTask'			'stop this task')
		(array ' ' 'stopAll'			'stop all')
		(array ' ' 'return'				'return _' 'auto')
		(array ' ' 'waitMicrosOp'		'wait _ microsecs' 'num' 10000)
		(array ' ' 'waitMillisOp'		'wait _ millisecs' 'num' 500)
		(array 'h' 'whenStarted'		'when started')
		(array 'h' 'whenCondition'		'when _' 'bool')
		(array ' ' 'noop'				'no op')
	'Math'
		(array 'r' 'add'				'_ + _ : + _ : ...' 'num num num' 10 2 10)
		(array 'r' 'subtract'			'_ − _' 'num num' 10 2)
		(array 'r' 'multiply'			'_ × _ : × _ : ...' 'num num num' 10 2 10)
		(array 'r' 'divide'				'_ / _' 'num num' 10 2)
		(array 'r' 'modulo'				'_ % _' 'num num' 10 2)
		(array 'r' 'lessThan'			'_ < _' 'num num' 3 4)
		(array 'r' 'lessOrEq'			'_ <= _' 'num num' 3 4)
		(array 'r' 'equal'				'_ == _' 'num num' 3 4)
		(array 'r' 'greaterOrEq'		'_ >= _' 'num num' 3 4)
		(array 'r' 'greaterThan'		'_ > _' 'num num' 3 4)
		(array 'r' 'booleanConstant'	'_' 'bool' true)
		(array 'r' 'notOp'				'not _' 'bool' true)
		(array 'r' 'and'				'_ and _ : and _ : ...' 'bool bool bool' true false)
		(array 'r' 'or'					'_ or _ : or _ : ...' 'bool bool bool' true false)
	'Arrays'
		(array 'r' 'newArray'			'new array _' 'num' 10)
		(array 'r' 'newByteArray'		'new byte array _' 'num' 10)
		(array ' ' 'fillArray'			'fill array _ with _' 'num auto' nil 0)
		(array 'r' 'at'					'array _ at _' 'auto num' nil 1)
		(array ' ' 'atPut'				'set array _ at _ to _' 'num num' nil 1 10)
		(array 'r' 'peekOp'				'memory at _ _' 'num num' 0 0)
		(array ' ' 'pokeOp'				'set memory at _ _ to _' 'num num num' 0 0 0)
		(array 'r' 'hexToInt'			'hex _' 'str' '3F')
	'Variables'
		(array 'r' 'v'					'_' 'menu.sharedVarMenu' 'n')
		(array ' ' '='					'set _ to _' 'menu.sharedVarMenu auto' 'n' 0)
		(array ' ' '+='					'increase _ by _' 'menu.sharedVarMenu num' 'n' 1)
	)
}

method initMicroBlocksSpecs SmallRuntime {
	authoringSpecs = (authoringSpecs)
	if (isEmpty (specsFor authoringSpecs 'Arduino')) {
		clear authoringSpecs
		addSpecs authoringSpecs (microBlocksSpecs this)
	}
}

method evalOnArduino SmallRuntime aBlock showBytes {
	if (isNil showBytes) { showBytes = false }
	bytes = (chunkBytesForBlock this aBlock)
	if showBytes {
		print (join 'Bytes for chunk ' id ':') bytes
		print '----------'
		return
	}
	id = (chunkIdFor this aBlock)
	chunkType = (chunkTypeForBlock this aBlock)
	saveChunk this id chunkType bytes
	runChunk this id
}

method chunkTypeForBlock SmallRuntime aBlock {
	expr = (expression aBlock)
	op = (primName expr)
	if ('whenStarted' == op) { chunkType = 4
	} ('whenCondition' == op) { chunkType = 5
	} (isClass expr 'Command') { chunkType = 1
	} (isClass expr 'Reporter') { chunkType = 2
	} ('nop' == op) { chunkType = 3 // xxx need a better test for function def hats
	}
	return chunkType
}

method chunkBytesForBlock SmallRuntime aBlock {
	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler (expression aBlock))
	bytes = (list)
	for item code {
		if (isClass item 'Array') {
			addBytesForInstructionTo compiler item bytes
		} (isClass item 'Integer') {
			addBytesForIntegerLiteralTo compiler item bytes
		} (isClass item 'String') {
			addBytesForStringLiteral compiler item bytes
		} else {
			error 'Instruction must be an Array or String:' item
		}
	}
	return bytes
}

method showInstructions SmallRuntime aBlockOrFunction {
	// Print the instructions for the given stack.

	compiler = (initialize (new 'SmallCompiler'))
	if (isClass aBlockOrFunction 'Block') {
		expr = (expression aBlockOrFunction)
	} else {
		expr = (cmdList aBlockOrFunction)
	}
	code = (instructionsFor compiler expr)
	for item code {
		if (and (isClass item 'Array') ('pushImmediate' == (first item))) {
			arg = (at item 2)
			if (1 == (arg & 1)) {
				arg = (arg >> 1) // decode integer
			} (4 == arg) {
				arg = true
			} (8 == arg) {
				arg = false
			}
			print (array 'pushImmediate' arg)
		} else {
			print item
		}
	}
	print '----------'
}

method chunkIdFor SmallRuntime aBlock {
	if (isNil chunkIDs) { chunkIDs = (dictionary) }
	entry = (at chunkIDs aBlock nil)
	if (isNil entry) {
		id = (count chunkIDs)
		entry = (array id aBlock) // block -> <id> <last expression>
		atPut chunkIDs aBlock entry
	}
	return (first entry)
}

method resetArduino SmallRuntime {
	// Reset the Arduino.

	// First try closing the serial port, opening it at 1200 baud,
	// then closing and reopening the port at the normal speed.
	// This works only for certain models of the Arduino. It does not work for non-Arduinos.
	closeSerialPort port
	port = (openSerialPort portName 1200)
	closeSerialPort port
	port = nil
	ensurePortOpen this // reopen the port
	recvBuf = nil

	sendMsg this 'systemResetMsg' // send the reset message
}

method selectPort SmallRuntime {
	menu = (menu 'Serial port:' (action 'setPort' this) true)
	for fn (listFiles '/dev') {
		if ((find (letters fn) (letters 'usb')) > 0) {
			addItem menu fn
		}
	}
	popUpAtHand menu (global 'page')
}

method setPort SmallRuntime newPortName {
	if (notNil port) {
		closeSerialPort port
		port = nil
	}
	portName = (join '/dev/' newPortName)
	ensurePortOpen this
}

method clearBoardIfConnected SmallRuntime {
	if (notNil port) { sendDeleteAll this }
}

method sendDeleteAll SmallRuntime { sendMsg this 'deleteAllCodeMsg' }

method sendStopAll SmallRuntime {
	sendMsg this 'stopAllMsg'
	allStopped this
}

method sendStartAll SmallRuntime {
	saveAllChunks this
	sendMsg this 'startAllMsg'
}

method saveAllChunks SmallRuntime {
	for aBlock (sortedScripts (scriptEditor scripter)) {
		op = (primName (expression aBlock))
		if ('nop' != op) {
			id = (chunkIdFor this aBlock)
			chunkType = (chunkTypeForBlock this aBlock)
			bytes = (chunkBytesForBlock this aBlock)
			saveChunk this id chunkType bytes
		}
	}
}

method saveChunk SmallRuntime chunkID chunkType bytes {
	body = (list chunkType)
	addAll body bytes
	add body 254 // terminator byte (helps board detect dropped bytes)
	sendMsg this 'storeChunkMsg' chunkID body
}

method runChunk SmallRuntime chunkID {
	sendMsg this 'startChunkMsg' chunkID
}

method stopRunningChunk SmallRuntime chunkID {
	sendMsg this 'stopChunkMsg' chunkID
}

// Testing

method getVar SmallRuntime varID {
	if (isNil varID) { varID = 0 }
	sendMsg this 'getVarMsg' varID
}

method getVersion SmallRuntime {
	sendMsg this 'getVersionMsg'
}

method msgNameToID SmallRuntime msgName {
	if (isNil msgDict) {
		msgDict = (dictionary)
		atPut msgDict 'storeChunkMsg' 1
		atPut msgDict 'deleteChunkMsg' 2
		atPut msgDict 'startChunkMsg' 3
		atPut msgDict 'stopChunkMsg' 4
		atPut msgDict 'startAllMsg' 5
		atPut msgDict 'stopAllMsg' 6
		atPut msgDict 'getVarMsg' 7
		atPut msgDict 'deleteVarMsg' 10
		atPut msgDict 'deleteCommentMsg' 11
		atPut msgDict 'getVersionMsg' 12
		atPut msgDict 'getAllCodeMsg' 13
		atPut msgDict 'deleteAllCodeMsg' 14
		atPut msgDict 'systemResetMsg' 15
		atPut msgDict 'taskStartedMsg' 16
		atPut msgDict 'taskDoneMsg' 17
		atPut msgDict 'taskReturnedValueMsg' 18
		atPut msgDict 'taskErrorMsg' 19
		atPut msgDict 'outputValueMsg' 20
		atPut msgDict 'argValueMsg' 21
		atPut msgDict 'versionMsg' 22
		atPut msgDict 'chunkCodeMsg' 23
		atPut msgDict 'chunkPositionMsg' 27
		atPut msgDict 'chunkAttributeMsg' 28
		atPut msgDict 'varNameMsg' 29
		atPut msgDict 'commentMsg' 30
		atPut msgDict 'commentPositionMsg' 31
	}
	msgType = (at msgDict msgName)
	if (isNil msgType) { error 'Unknown message:' msgName }
	return msgType
}

method sendMsg SmallRuntime msgName chunkID byteList {
	if (isNil chunkID) { chunkID = 0 }
	msgID = (msgNameToID this msgName)
	if (isNil byteList) { // short message
		msg = (list 250 msgID chunkID)
	} else { // long message
		byteCount = (count byteList)
		msg = (list 251 msgID chunkID (byteCount & 255) ((byteCount >> 8) & 255))
		addAll msg byteList
	}
	ensurePortOpen this
	writeSerialPort port (toBinaryData (toArray msg))
}

method ensurePortOpen SmallRuntime {
	if (isNil port) {
		if (isNil portName) {
			portName = '/dev/tty.usbmodem1422'
		}
		port = (openSerialPort portName 115200)
	}
}

method processMessages SmallRuntime {
	if (or (isNil port) (not (isOpenSerialPort port))) { return }
	if (isNil recvBuf) { recvBuf = (newBinaryData 0) }
	repeat 20 { processMessages2 this }
}

method processMessages2 SmallRuntime {
// showOutputStrings this
// return // xxx

// s = (readSerialPort port)
// if (notNil s) { print s } // print raw debug strings from VM
// return // xxx

// s = (readSerialPort port true)
// if (notNil s) { print (toArray s) } // print message bytes
// return // xxx

	// Read any available bytes and append to recvBuf
	s = (readSerialPort port true)
	if (notNil s) { recvBuf = (join recvBuf s) }
	if ((byteCount recvBuf) < 3) { return } // incomplete message

	// Parse and dispatch messages
	firstByte = (byteAt recvBuf 1)
	if (250 == firstByte) { // short message
		handleMessage this (copyFromTo recvBuf 1 3)
		recvBuf = (copyFromTo recvBuf 4) // remove message
	} (251 == firstByte) { // long message
		if ((byteCount recvBuf) < 5) { return } // incomplete length field
		bodyBytes = (((byteAt recvBuf 5) << 8) | (byteAt recvBuf 4))
		if ((byteCount recvBuf) < (5 + bodyBytes)) { return } // incomplete body
		handleMessage this (copyFromTo recvBuf 1 (bodyBytes + 5))
		recvBuf = (copyFromTo recvBuf (bodyBytes + 6)) // remove message
	} else {
		print 'Bad message header byte; should be 250 or 251 but is:' firstByte
		recvBuf = (newBinaryData 0) // discard
	}
}

method handleMessage SmallRuntime msg {
	op = (byteAt msg 2)
	if (op == (msgNameToID this 'taskStartedMsg')) {
		updateRunning this (byteAt msg 3) true
	} (op == (msgNameToID this 'taskDoneMsg')) {
		updateRunning this (byteAt msg 3) false
	} (op == (msgNameToID this 'taskReturnedValueMsg')) {
		showResult this (byteAt msg 3) (returnedValue this msg)
	} (op == (msgNameToID this 'taskErrorMsg')) {
		print 'error:' (byteAt msg 6) // error code
	} (op == (msgNameToID this 'outputValueMsg')) {
		print (returnedValue this msg)
	} (op == (msgNameToID this 'argValueMsg')) {
		print (returnedValue this msg)
	} (op == (msgNameToID this 'versionMsg')) {
		print (returnedValue this msg)
	} else {
		print 'msg:' (toArray msg)
	}
}

method updateRunning SmallRuntime chunkID runFlag {
	if (isNil chunkRunning) {
		chunkRunning = (newArray 256 false)
	}
	atPut chunkRunning (chunkID + 1) runFlag
	updateHighlights this
}

method isRunning SmallRuntime aBlock {
	if (isNil chunkRunning) { return false }
	return (at chunkRunning ((chunkIdFor this aBlock) + 1))
}

method allStopped SmallRuntime {
	chunkRunning = (newArray 256 false) // clear all running flags
	updateHighlights this
}

method updateHighlights SmallRuntime {
	scale = (global 'scale')
	for m (parts (morph (scriptEditor scripter))) {
		if (isClass (handler m) 'Block') {
			if (isRunning this (handler m)) {
				addHighlight m (4 * scale)
			} else {
				removeHighlight m
			}
		}
	}
}

method showResult SmallRuntime chunkID value {
	for m (parts (morph (scriptEditor scripter))) {
		h = (handler m)
		if (and (isClass h 'Block') (chunkID == (chunkIdFor this h))) {
			showHint m value
		}
	}
	updateRunning this chunkID false
}

method returnedValue SmallRuntime msg {
	type = (byteAt msg 6)
	if (1 == type) {
		return (+ ((byteAt msg 10) << 24) ((byteAt msg 9) << 16) ((byteAt msg 8) << 8) (byteAt msg 7))
	} (2 == type) {
		return (toString (copyFromTo msg 7))
	} (3 == type) {
		return (0 != (byteAt msg 7))
	} true {
		return (join 'unknown type: ' type)
	}
}

method showOutputStrings SmallRuntime {
	// For debuggong. Just display incoming characters.
	if (isNil port) { return }
	s = (readSerialPort port)
	if (notNil s) {
		if (isNil recvBuf) { recvBuf = '' }
		recvBuf = (toString recvBuf)
		recvBuf = (join recvBuf s)
		while (notNil (findFirst recvBuf (newline))) {
			i = (findFirst recvBuf (newline))
			out = (substring recvBuf 1 (i - 2))
			recvBuf = (substring recvBuf (i + 1))
			print out
		}
	}
}
