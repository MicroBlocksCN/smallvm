// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

//Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// SmallCompiler.gp - A blocks compiler for SmallVM
// John Maloney, April, 2017

to smallRuntime aScripter {
	if (isNil (global 'smallRuntime')) {
		setGlobal 'smallRuntime' (setScripter (new 'SmallRuntime') aScripter)
	}
	return (global 'smallRuntime')
}

defineClass SmallRuntime scripter chunkIDs chunkRunning msgDict portName port pingSentMSecs lastPingRecvMSecs recvBuf oldVarNames

method scripter SmallRuntime { return scripter }

method setScripter SmallRuntime aScripter {
	scripter = aScripter
	chunkIDs = (dictionary)
	return this
}

method evalOnBoard SmallRuntime aBlock showBytes {
	if (isNil showBytes) { showBytes = false }
	if showBytes {
		bytes = (chunkBytesFor this aBlock)
		print (join 'Bytes for chunk ' id ':') bytes
		print '----------'
		return
	}

	// save all chunks, including functions and broadcast receivers
	// (it would be more efficient to save only chunks that have changed)
	saveAllChunks this
	if (isNil (ownerThatIsA (morph aBlock) 'ScriptEditor')) {
		// running a block from the palette, not included in saveAllChunks
		saveChunk this aBlock
	}
	runChunk this (lookupChunkID this aBlock)
}

method chunkTypeFor SmallRuntime aBlockOrFunction {
	if (isClass aBlockOrFunction 'Function') { return 3 }

	expr = (expression aBlockOrFunction)
	op = (primName expr)
	if ('whenStarted' == op) { return 4 }
	if ('whenCondition' == op) { return 5 }
	if ('whenBroadcastReceived' == op) { return 6 }
	if (isClass expr 'Command') { return 1 }
	if (isClass expr 'Reporter') { return 2 }

	error 'Unexpected argument to chunkTypeFor'
}

method chunkBytesFor SmallRuntime aBlockOrFunction {
	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler aBlockOrFunction)
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

method showInstructions SmallRuntime aBlock {
	// Print the instructions for the given stack.

	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler (topBlock aBlock))
	for item code {
		if (not (isClass item 'Array')) {
			print item
		} ('pushImmediate' == (first item)) {
			arg = (at item 2)
			if (1 == (arg & 1)) {
				arg = (arg >> 1) // decode integer
			} (0 == arg) {
				arg = false
			} (4 == arg) {
				arg = true
			}
			print 'pushImmediate' arg
		} ('pushBigImmediate' == (first item)) {
			print 'pushBigImmediate' // don't show arg count; could be confusing
		} ('callFunction' == (first item)) {
			arg = (at item 2)
			calledChunkID = ((arg >> 8) & 255)
			argCount = (arg & 255)
			print 'callFunction' calledChunkID argCount
		} (not (isLetter (at (first item) 1))) { // operators
			print (first item)
		} else {
			callWith 'print' item // print the array elements
		}
	}
	print '----------'
}

// chunk management

method syncScripts SmallRuntime {
	if (notNil port) { saveAllChunks this }
}

method lookupChunkID SmallRuntime key {
	// If the given block or function name has been assigned a chunkID, return it.
	// Otherwise, return nil.

	entry = (at chunkIDs key nil)
	if (isNil entry) { return nil }
	return (first entry)
}

method ensureChunkIdFor SmallRuntime aBlock {
	// Return the chunkID for the given block. Functions are handled by assignFunctionIDs.
	// If necessary, register the block in the chunkIDs dictionary.

	entry = (at chunkIDs aBlock nil)
	if (isNil entry) {
		id = (count chunkIDs)
		entry = (array id aBlock) // block -> <id> <last expression>
		atPut chunkIDs aBlock entry
	}
	return (first entry)
}

method assignFunctionIDs SmallRuntime {
	// Ensure that there is a chunk ID for every user-defined function.
	// This must be done before generating any code to allow for recursive calls.

	for func (functions (targetModule scripter)) {
		fName = (functionName func)
		if (not (contains chunkIDs fName)) {
			atPut chunkIDs fName (array (count chunkIDs) 'New Function!') // forces function save
		}
	}
}

method deleteChunkForBlock SmallRuntime aBlock {
	key = aBlock
	if (isPrototypeHat aBlock) {
		key = (functionName (function (editedPrototype aBlock)))
	}
	entry = (at chunkIDs key nil)
	if (and (notNil entry) (notNil port)) {
		chunkID = (first entry)
		sendMsg this 'deleteChunkMsg' chunkID
		remove chunkIDs key
	}
}

method stopAndSyncScripts SmallRuntime {
	// Stop everyting and sync scripts with the board.

	clearBoardIfConnected this
	saveAllChunks this
}

method softReset SmallRuntime {
	// Stop everyting, clear memory, and reset the I/O pins.

	sendMsg this 'systemResetMsg' // send the reset message
}

method selectPort SmallRuntime {
	portList = (list)
	if ('Win' == (platform)) {
		portList = (listSerialPorts)
		if (isEmpty portList) {
			portList = (list)
			for n 32 { add portList (join 'COM' n) }
		}
	} ('Browser' == (platform)) {
		listSerialPorts // first call triggers callback
		waitMSecs 50
		portList = (listSerialPorts)
	} else {
		for fn (listFiles '/dev') {
			if (or (notNil (nextMatchIn 'usb' (toLowerCase fn) )) // MacOS
				   (notNil (nextMatchIn 'acm' (toLowerCase fn) ))) { // Linux
				add portList fn
			}
		}
		// Mac OS (and perhaps Linuxes) list a port as both cu.<name> and tty.<name>
		for s (copy portList) {
			if (beginsWith s 'tty.') {
				if (contains portList (join 'cu.' (substring s 5))) {
					remove portList s
				}
			}
		}
		names = (dictionary)
		addAll names portList

	}
	menu = (menu 'Serial port:' (action 'setPort' this) true)
	for s portList { addItem menu s }
	addItem menu 'other...'
	if (notNil port) {
		addLine menu
		addItem menu 'disconnect'
	}
	popUpAtHand menu (global 'page')
}

method setPort SmallRuntime newPortName {
	if ('other...' == newPortName) {
		newPortName = (prompt (global 'page') 'Port name?' 'none')
		if ('' == newPortName) { return }
	}
	if (and ('disconnect' == newPortName) (notNil port)) {
		stopAndSyncScripts this
		sendStartAll this
	}
	if (notNil port) {
		closeSerialPort port
		port = nil
	}
	if (or (isNil newPortName) (isOneOf newPortName 'disconnect' 'none')) { // just close port
		portName = nil
	} else {
		portName = (join '/dev/' newPortName)
		if (isOneOf (platform) 'Browser' 'Win') { portName = newPortName }
		ensurePortOpen this
	}
	// update the connection indicator more quickly than it would otherwise
	lastPingRecvMSecs = 0 // force ping timeout
	updateIndicator (findMicroBlocksEditor)
	waitMSecs 20
	processMessages this
	updateIndicator (findMicroBlocksEditor)
	clearBoardIfConnected this
}

method closePort SmallRuntime {
	if (notNil port) {
		stopAndSyncScripts this
		closeSerialPort port
		port = nil
	}
}

method connectionStatus SmallRuntime {
	pingSendInterval = 2000 // msecs between pings
	if (isNil pingSentMSecs) { pingSentMSecs = 0 }
	if (isNil lastPingRecvMSecs) { lastPingRecvMSecs = 0 }

	if (or (isNil port) (not (isOpenSerialPort port))) {
		port = nil
		return 'not connected'
	}
	if (((msecsSinceStart) - pingSentMSecs) > pingSendInterval) {
		sendMsg this 'pingMsg'
		pingSentMSecs = (msecsSinceStart)
	}
	msecsSinceLastPing = ((msecsSinceStart) - lastPingRecvMSecs)
	if (msecsSinceLastPing < (pingSendInterval + 200)) {
		return 'connected'
	}
	return 'board not responding'
}

method ideVersion SmallRuntime { return '0.1.15' }

method showAboutBox SmallRuntime {
	inform (global 'page') (join
		'MicroBlocks v' (ideVersion this) (newline)
		'by' (newline)
		'John Maloney, Bernat Romagosa, and Jens Mönig' (newline)
		'Created with GP (gpblocks.org)' (newline)
		'More info at http://microblocks.fun')
}

method getVersion SmallRuntime {
	sendMsg this 'getVersionMsg'
}

method showVersion SmallRuntime versionString {
	inform (global 'page') (join 'MicroBlocks Virtual Machine' (newline) versionString)
}

method clearBoardIfConnected SmallRuntime {
	if (notNil port) {
		sendStopAll this
		clearVariableNames this
		sendMsg this 'deleteAllCodeMsg' // delete all code from board
		waitMSecs 50 // leave time to write to flash or next message will be missed
	}
	allStopped this
	chunkIDs = (dictionary)
}

method sendStopAll SmallRuntime {
	sendMsg this 'stopAllMsg'
	allStopped this
}

method sendStartAll SmallRuntime {
	saveAllChunks this
	sendMsg this 'startAllMsg'
}

method saveAllChunks SmallRuntime {
	// Save the code for all scripts and user-defined functions.

	saveVariableNames this
	assignFunctionIDs this
	for aFunction (functions (targetModule scripter)) {
		saveChunk this aFunction
	}
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (not (isPrototypeHat aBlock)) { // skip function def hat; functions get saved above
			saveChunk this aBlock
		}
	}
}

method saveChunk SmallRuntime aBlockOrFunction {
	// Save the script starting with the given block or function as an executable code "chunk".
	// Also save the source code (in GP format) and the script position.

	if (isClass aBlockOrFunction 'Function') {
		chunkID = (lookupChunkID this (functionName aBlockOrFunction))
		entry = (at chunkIDs (functionName aBlockOrFunction))
		newCode = (cmdList aBlockOrFunction)
	} else {
		chunkID = (ensureChunkIdFor this aBlockOrFunction)
		entry = (at chunkIDs aBlockOrFunction)
		newCode = (expression aBlockOrFunction)
	}

	if (newCode == (at entry 2)) { return } // code hasn't changed
	if (notNil newCode) { newCode = (copy newCode) }
	atPut entry 2 newCode // remember the code we're about to save

	// save the binary code for the chunk
	chunkType = (chunkTypeFor this aBlockOrFunction)
	data = (list chunkType)
	addAll data (chunkBytesFor this aBlockOrFunction)
	sendMsg this 'chunkCodeMsg' chunkID data
	waitMSecs ((count data) / 10) // wait approximate transmission time

	// restart the chunk if it is a Block and is running
	if (and (isClass aBlockOrFunction 'Block') (isRunning this aBlockOrFunction)) {
		stopRunningChunk this chunkID
		runChunk this chunkID
	}
}

method saveVariableNames SmallRuntime {
	newVarNames = (variableNames (targetModule scripter))
	if (oldVarNames == newVarNames) { return }

	varID = 0
	for varName newVarNames {
		sendMsg this 'varNameMsg' varID (toArray (toBinaryData varName))
		varID += 1
	}
	oldVarNames = (copy newVarNames)
}

method runChunk SmallRuntime chunkID {
	sendMsg this 'startChunkMsg' chunkID
}

method stopRunningChunk SmallRuntime chunkID {
	sendMsg this 'stopChunkMsg' chunkID
}

method getVar SmallRuntime varID {
	if (isNil varID) { varID = 0 }
	sendMsg this 'getVarMsg' varID
}

method clearVariableNames SmallRuntime {
	oldVarNames = nil
	sendMsg this 'clearVarsMsg'
}

method getAllVarNames SmallRuntime {
	sendMsg this 'getVarNamesMsg'
}

// Message handling

method msgNameToID SmallRuntime msgName {
	if (isNil msgDict) {
		msgDict = (dictionary)
		atPut msgDict 'chunkCodeMsg' 1
		atPut msgDict 'deleteChunkMsg' 2
		atPut msgDict 'startChunkMsg' 3
		atPut msgDict 'stopChunkMsg' 4
		atPut msgDict 'startAllMsg' 5
		atPut msgDict 'stopAllMsg' 6
		atPut msgDict 'getVarMsg' 7
		atPut msgDict 'setVarMsg' 8
		atPut msgDict 'getVarNamesMsg' 9
		atPut msgDict 'clearVarsMsg' 10
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
		atPut msgDict 'varValueMsg' 21
		atPut msgDict 'versionMsg' 22
		atPut msgDict 'pingMsg' 26
		atPut msgDict 'broadcastMsg' 27
		atPut msgDict 'chunkAttributeMsg' 28
		atPut msgDict 'varNameMsg' 29
		atPut msgDict 'commentMsg' 30
		atPut msgDict 'commentPositionMsg' 31
	}
	msgType = (at msgDict msgName)
	if (isNil msgType) { error 'Unknown message:' msgName }
	return msgType
}

method errorString SmallRuntime errID {
	// Return an error string for the given errID from error definitions copied and pasted from interp.h

	defsFromHeaderFile = '
#define noError					0	// No error
#define unspecifiedError		1	// Unknown error
#define badChunkIndexError		2	// Unknown chunk index

#define insufficientMemoryError	10	// Insufficient memory to allocate object
#define needsArrayError			11	// Needs an Array or ByteArray
#define needsBooleanError		12	// Needs a boolean
#define needsIntegerError		13	// Needs an integer
#define needsStringError		14	// Needs a string
#define nonComparableError		15	// Those objects cannot be compared for equality
#define arraySizeError			16	// Array size must be a non-negative integer
#define needsIntegerIndexError	17	// Array index must be an integer
#define indexOutOfRangeError	18	// Array index out of range
#define byteArrayStoreError		19 	// A ByteArray can only store integer values between 0 and 255
#define hexRangeError			20	// Hexadecimal input must between between -1FFFFFFF and 1FFFFFFF
#define i2cDeviceIDOutOfRange	21	// I2C device ID must be between 0 and 127
#define i2cRegisterIDOutOfRange	22	// I2C register must be between 0 and 255
#define i2cValueOutOfRange		23	// I2C value must be between 0 and 255
#define notInFunction			24	// Attempt to access an argument outside of a function
#define badForLoopArg			25	// for-loop argument must be a positive integer, array, or bytearray
#define stackOverflow			26	// Insufficient stack space
'
	for line (lines defsFromHeaderFile) {
		words = (words line)
		if (and ((count words) > 2) ('#define' == (first words))) {
			if (errID == (toInteger (at words 3))) {
				msg = (joinStrings (copyFromTo words 5) ' ')
				return (join 'Error: ' msg)
			}
		}
	}
	return (join 'Unknown error: ' errID)
}

method sendMsg SmallRuntime msgName chunkID byteList {
	if (isNil chunkID) { chunkID = 0 }
	msgID = (msgNameToID this msgName)
	if (isNil byteList) { // short message
		msg = (list 250 msgID chunkID)
	} else { // long message
		byteCount = ((count byteList) + 1)
		msg = (list 251 msgID chunkID (byteCount & 255) ((byteCount >> 8) & 255))
		addAll msg byteList
		add msg 254 // terminator byte (helps board detect dropped bytes)
	}
	ensurePortOpen this
	if (isNil port) {
		inform 'Use "Connect" button to connect to a MicroBlocks device.'
		return
	}
	writeSerialPort port (toBinaryData (toArray msg))
}

method ensurePortOpen SmallRuntime {
	if (or (isNil port) (not (isOpenSerialPort port))) {
		if (notNil portName) {
			port = (openSerialPort portName 115200)
		}
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
		byteTwo = (byteAt recvBuf 2)
		if (or (byteTwo < 1) (byteTwo > 32)) {
			print 'Bad message type; should be 1-31 but is:' (byteAt recvBuf 2)
			skipMessage this // discard
			return
		}
		bodyBytes = (((byteAt recvBuf 5) << 8) | (byteAt recvBuf 4))
		if ((byteCount recvBuf) < (5 + bodyBytes)) { return } // incomplete body
		handleMessage this (copyFromTo recvBuf 1 (bodyBytes + 5))
		recvBuf = (copyFromTo recvBuf (bodyBytes + 6)) // remove message
	} else {
		print 'Bad message start byte; should be 250 or 251 but is:' firstByte
		skipMessage this // discard
	}
}

method skipMessage SmallRuntime {
	// Discard bytes in recvBuf until the start of the next message, if any.

	end = (byteCount recvBuf)
	i = 2
	while (i < end) {
		byte = (byteAt recvBuf i)
		if (or (250 == byte) (251 == byte)) {
			recvBuf = (copyFromTo recvBuf i)
			return
		}
		i += 1
	}
	recvBuf = (newBinaryData 0) // no message start found; discard entire buffer
}

method handleMessage SmallRuntime msg {
	op = (byteAt msg 2)
	if (op == (msgNameToID this 'taskStartedMsg')) {
		updateRunning this (byteAt msg 3) true
	} (op == (msgNameToID this 'taskDoneMsg')) {
		updateRunning this (byteAt msg 3) false
	} (op == (msgNameToID this 'taskReturnedValueMsg')) {
		chunkID = (byteAt msg 3)
		showResult this chunkID (returnedValue this msg)
		updateRunning this chunkID false
	} (op == (msgNameToID this 'taskErrorMsg')) {
		chunkID = (byteAt msg 3)
		showResult this chunkID (errorString this (byteAt msg 6))
		updateRunning this chunkID false
	} (op == (msgNameToID this 'outputValueMsg')) {
		chunkID = (byteAt msg 3)
		if (chunkID == 255) {
			print (returnedValue this msg)
		} else {
			showResult this chunkID (returnedValue this msg)
		}
	} (op == (msgNameToID this 'varValueMsg')) {
		print 'variable value:' (returnedValue this msg)
	} (op == (msgNameToID this 'versionMsg')) {
		showVersion this (returnedValue this msg)
	} (op == (msgNameToID this 'pingMsg')) {
		lastPingRecvMSecs = (msecsSinceStart)
	} (op == (msgNameToID this 'broadcastMsg')) {
//		print 'received broadcast:' (toString (copyFromTo msg 6))
	} (op == (msgNameToID this 'chunkCodeMsg')) {
		print 'chunkCodeMsg:' (byteCount msg) 'bytes'
	} (op == (msgNameToID this 'chunkAttributeMsg')) {
		print 'chunkAttributeMsg:' (byteCount msg) 'bytes'
	} (op == (msgNameToID this 'varNameMsg')) {
		print 'varNameMsg:' (byteAt msg 3) (toString (copyFromTo msg 6)) ((byteCount msg) - 5) 'bytes'
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
	chunkID = (lookupChunkID this aBlock)
	if (or (isNil chunkRunning) (isNil chunkID)) { return false }
	return (at chunkRunning (chunkID + 1))
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
	for m (join
			(parts (morph (scriptEditor scripter)))
			(parts (morph (blockPalette scripter)))) {
		h = (handler m)
		if (and (isClass h 'Block') (chunkID == (lookupChunkID this h))) {
			showHint m value
		}
	}
}

method returnedValue SmallRuntime msg {
	type = (byteAt msg 6)
	if (1 == type) {
		return (+ ((byteAt msg 10) << 24) ((byteAt msg 9) << 16) ((byteAt msg 8) << 8) (byteAt msg 7))
	} (2 == type) {
		return (toString (copyFromTo msg 7))
	} (3 == type) {
		return (0 != (byteAt msg 7))
	} (4 == type) {
		return (toArray (copyFromTo msg 7))
	} (5 == type) {
		// xxx Arrays are not yet handled
		intArraySize = (truncate (((byteCount msg) - 6) / 5))
		return (join 'a list of ' intArraySize ' items')
	} else {
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

// Virtual Machine Installer

method installVM SmallRuntime {
  boards = (collectBoardDrives this)
  if ((count boards) > 0) {
	menu = (menu 'Select board:' this)
	for b boards {
		addItem menu (niceBoardName this b) (action 'copyVMToBoard' this (first b) (last b))
	}
	popUpAtHand menu (global 'page')
  } else {
	inform 'No boards found; is your board plugged in?'
  }
}

method niceBoardName SmallRuntime board {
  name = (first board)
  if (beginsWith name 'MICROBIT') {
	return 'BBC micro:bit'
  } (beginsWith name 'MINI') {
	return 'Calliope mini'
  } (beginsWith name 'CPLAYBOOT') {
	return 'Circuit Playground Express'
  }
  return name
}

method collectBoardDrives SmallRuntime {
  result = (list)
  if ('Mac' == (platform)) {
	for v (listDirectories '/Volumes') {
	  path = (join '/Volumes/' v '/')
	  if (beginsWith v 'MICROBIT') { add result (list v path) }
	  if (beginsWith v 'MINI') { add result (list v path) }
	  if (beginsWith v 'CPLAYBOOT') { add result (list v path) }
	}
  } ('Linux' == (platform)) {
	for dir (listDirectories '/media') {
	  prefix = (join '/media/' dir)
	  for v (listDirectories prefix) {
		path = (join prefix '/' v '/')
		if (beginsWith v 'MICROBIT') { add result (list v path) }
		if (beginsWith v 'MINI') { add result (list v path) }
		if (beginsWith v 'CPLAYBOOT') { add result (list v path) }
	  }
	}
  } ('Win' == (platform)) {
	for letter (range 65 90) {
	  drive = (join (string letter) ':')
	  boardName = (getBoardName this drive)
	  if (notNil boardName) { add result (list boardName drive) }
	}
  }
  return result
}

method getBoardName SmallRuntime path {
  for fn (listFiles path) {
	if ('MICROBIT.HTM' == fn) { return 'MICROBIT' }
	if ('MINI.HTM' == fn) { return 'MINI' }
	if ('INFO_UF2.TXT' == fn) {
	  contents = (readFile (join path fn))
	  if (notNil (nextMatchIn 'CPlay Express' contents)) {
		return 'CPLAYBOOT'
	  }
	}
  }
  return nil
}

method copyVMToBoard SmallRuntime boardName boardPath {
  if (beginsWith boardName 'MICROBIT') {
	vmFileName = 'vm.ino.BBCmicrobit.hex'
  } (beginsWith boardName 'MINI') {
	vmFileName = 'vm.ino.Calliope.hex'
  } (beginsWith boardName 'CPLAYBOOT') {
	vmFileName = 'vm.circuitplay.uf2'
  }
  if (notNil vmFileName) {
	vmData = (readEmbeddedFile (join 'precompiled/' vmFileName) true)
  }
  if (isNil vmData) {
	error (join 'Could not read: ' (join 'precompiled/' vmFileName))
  }
  closePort (smallRuntime) // disconnect
  writeFile (join boardPath vmFileName) vmData
  print 'Installed' (join boardPath vmFileName) (join '(' (byteCount vmData) ' bytes)')
  waitMSecs 8000
  ensurePortOpen (smallRuntime)
}

// testing

method broadcastTest SmallRuntime {
	msg = 'go!'
	sendMsg this 'broadcastMsg' 0 (toArray (toBinaryData msg))
}

method setVarTest SmallRuntime {
	val = 'foobar'
	varID = 0
	body = nil
	if (isClass val 'Integer') {
		body = (newBinaryData 5)
		byteAtPut body 1 1 // type 1 - Integer
		byteAtPut body 2 (val & 255)
		byteAtPut body 3 ((val >> 8) & 255)
		byteAtPut body 4 ((val >> 16) & 255)
		byteAtPut body 5 ((val >> 24) & 255)
	} (isClass val 'String') {
		body = (toBinaryData (join (string 2) val))
	} (isClass val 'Boolean') {
		body = (newBinaryData 2)
		byteAtPut body 1 3 // type 3 - Boolean
		if val {
			byteAtPut body 2 1 // true
		} else {
			byteAtPut body 2 0 // false
		}
	}
	if (notNil body) { sendMsg this 'setVarMsg' 0 (toArray body) }
}

method getCodeTest SmallRuntime {
	sendMsg this 'getAllCodeMsg'
}
