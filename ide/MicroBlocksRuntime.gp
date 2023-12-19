// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksRuntime.gp - Runtime support for MicroBlocks
// John Maloney, April, 2017

to smallRuntime aScripter {
	if (isNil (global 'smallRuntime')) {
		setGlobal 'smallRuntime' (initialize (new 'SmallRuntime') aScripter)
	}
	return (global 'smallRuntime')
}

defineClass SmallRuntime ideVersion latestVmVersion scripter chunkIDs chunkRunning chunkStopping msgDict portName port connectionStartTime lastScanMSecs pingSentMSecs lastPingRecvMSecs recvBuf oldVarNames vmVersion boardType lastBoardDrives loggedData loggedDataNext loggedDataCount vmInstallMSecs disconnected crcDict lastCRC lastRcvMSecs readFromBoard decompiler decompilerStatus blockForResultImage fileTransferMsgs fileTransferProgress fileTransfer firmwareInstallTimer recompileAll

method scripter SmallRuntime { return scripter }
method serialPortOpen SmallRuntime { return (notNil port) }
method recompileNeeded SmallRuntime { recompileAll = true }

method initialize SmallRuntime aScripter {
	scripter = aScripter
	chunkIDs = (dictionary)
	readFromBoard = false
	clearLoggedData this
	return this
}

method evalOnBoard SmallRuntime aBlock showBytes {
	step scripter // save script changes if needed

	if (isNil showBytes) { showBytes = false }
	if showBytes {
		bytes = (chunkBytesFor this aBlock)
		print (join 'Bytes for chunk ' id ':') bytes
		print '----------'
		return
	}
	if ('not connected' == (updateConnection this)) {
		showError (morph aBlock) (localized 'Board not connected')
		return
	}
    if (or (isNil vmVersion) (vmVersion < 300)) {
        return (vmIncomptabibleWithIDE this)
    }
	if (isNil (ownerThatIsA (morph aBlock) 'ScriptEditor')) {
		// running a block from the palette, not included in saveAllChunks
		saveChunk this aBlock
	}
	runChunk this (lookupChunkID this aBlock)
}

method stopRunningBlock SmallRuntime aBlock {
	if (isRunning this aBlock) {
		stopRunningChunk this (lookupChunkID this aBlock)
	}
}

method chunkTypeFor SmallRuntime aBlockOrFunction {
	if (isClass aBlockOrFunction 'Function') { return 3 }
	if (and
		(isClass aBlockOrFunction 'Block')
		(isPrototypeHat aBlockOrFunction)) {
			return 3
	}

	expr = (expression aBlockOrFunction)
	op = (primName expr)
	if ('whenStarted' == op) { return 4 }
	if ('whenCondition' == op) { return 5 }
	if ('whenBroadcastReceived' == op) { return 6 }
	if ('whenButtonPressed' == op) {
		button = (first (argList expr))
		if ('A' == button) { return 7 }
		if ('B' == button) { return 8 }
		return 9 // A+B
	}
	if (isClass expr 'Command') { return 1 }
	if (isClass expr 'Reporter') { return 2 }

	error 'Unexpected argument to chunkTypeFor'
}

method chunkBytesFor SmallRuntime aBlockOrFunction {
	if (isClass aBlockOrFunction 'String') { // look up function by name
		aBlockOrFunction = (functionNamed (project scripter) aBlockOrFunction)
		if (isNil aBlockOrFunction) { return (list) } // unknown function
	}
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
	// Display the instructions for the given stack.

	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler (topBlock aBlock))
	result = (list)
	firstString = true
	for item code {
		if (not (isClass item 'Array')) {
			if firstString {
				add result '--------'
				firstString = false
			}
			add result (toString item) // string literal
		} ('metadata' == (first item)) {
			if ((count (last code)) > 0) {
				add result '--------'
			}
		} ('pushLiteral' == (first item)) {
			instr = (join '[' (opcodeForInstr compiler (first item)) '] ' (first item) ' ')
			instr = (join instr (at item 2) ' ("' (at item 3) '")')
			addWithLineNum this result instr
		} ('pushImmediate' == (first item)) {
			arg = (at item 2)
			if (1 == (arg & 1)) {
				arg = (arg >> 1) // decode integer
				if (arg >= 4194304) { arg = (arg - 8388608) }
				if (and (arg < 128) (arg > 63)) { arg = (arg - 128) } // 8-bit integer
			} (0 == arg) {
				arg = false
			} (4 == arg) {
				arg = true
			}
			instr = (join '[' (opcodeForInstr compiler (first item)) '] ' (first item) ' ')
			addWithLineNum this result (join instr arg)
		} (isOneOf (first item) 'pushLargeInteger' 'pushHugeInteger') {
			arg = (at item 2)
			instr = (join '[' (opcodeForInstr compiler (first item)) '] ' (first item) ' ' arg)
			addWithLineNum this result instr
		} ('callFunction' == (first item)) {
			arg = (at item 2)
			calledChunkID = ((arg >> 8) & 255)
			argCount = (arg & 255)
			instr = (join '[' (opcodeForInstr compiler (first item)) '] ' (first item) ' ')
			addWithLineNum this result (join instr calledChunkID ' ' argCount)
		} (not (isLetter (at (first item) 1))) { // operator; don't show arg count
			addWithLineNum this result (toString (first item))
		} ('placeholder' == (first item)) {
			addWithLineNum this result '<data>'
		} else {
	        if (isOneOf (first item) 'commandPrimitive' 'reporterPrimitive') {
	            // re-order item to display argCount last
	            item = (copy item)
	            argCount = (at item 4)
	            atPut item 4 (at item 5)
	            atPut item 5 argCount
	        }
			// instruction (an array of form <cmd> <args...>)
			instr = (join '[' (opcodeForInstr compiler (at item 1)) '] ')
			for s item { instr = (join instr s ' ') }
			addWithLineNum this result instr item
		}
	}
	ws = (openWorkspace (global 'page') (joinStrings result (newline)))
	setTitle ws 'Instructions'
	setFont ws 'Arial' (16 * (global 'scale'))
	setExtent (morph ws) (400 * (global 'scale')) (400 * (global 'scale'))
	fixLayout ws
}

method addWithLineNum SmallRuntime aList instruction items {
	currentLine = ((count aList) + 1)
	targetLine = ''
	if (and
		(notNil items)
		(isOneOf (first items)
			'pushLiteral' 'jmp' 'longJmp' 'jmpTrue' 'jmpFalse' 'jmpAnd' 'jmpOr' 'decrementAndJmp')) {
		offset = (toInteger (last items))
		if ('pushLiteral' != (first items)) {
		    if (or (0 == offset) (offset < -128) (offset > 127) ('longJmp' == (first items))) {
		        offset += 1
		    }
		}
		targetLine = (join ' (line ' (+ currentLine 1 offset) ')')
	}
	add aList (join '' currentLine ' ' instruction targetLine)
}

method showCompiledBytes SmallRuntime aBlock {
	// Display the instruction bytes for the given stack.

	bytes = (chunkBytesFor this (topBlock aBlock))
	result = (list)
	add result (join '[' (count bytes) ' bytes]' (newline))
	for i (count bytes) {
		add result (toString (at bytes i))
		if (0 == (i % 2)) {
			add result (newline)
		} else {
			add result ' '
		}
	}
	if (and ((count result) > 0) ((newline) == (last result))) { removeLast result }
	ws = (openWorkspace (global 'page') (joinStrings result))
	setTitle ws 'Instruction Bytes'
	setFont ws 'Arial' (16 * (global 'scale'))
	setExtent (morph ws) (220 * (global 'scale')) (400 * (global 'scale'))
	fixLayout ws
}

method showCallTree SmallRuntime aBlock {
	proto = (editedPrototype aBlock)
	if (notNil proto) {
		if (isNil (function proto)) { return }
		funcName = (functionName (function proto))
	} else {
		funcName = (primName (expression aBlock))
	}

    globalVars = (allVariableNames (project scripter))
	allFunctions = (dictionary)
	for f (allFunctions (project scripter)) { atPut allFunctions (functionName f) f }

	result = (list)
	appendCallsForFunction this funcName result '' globalVars allFunctions (array funcName)

	ws = (openWorkspace (global 'page') (joinStrings result (newline)))
	setTitle ws 'Call Tree'
	setFont ws 'Arial' (16 * (global 'scale'))
	setExtent (morph ws) (400 * (global 'scale')) (400 * (global 'scale'))
	fixLayout ws
}

method appendCallsForFunction SmallRuntime funcName result indent globalVars allFunctions callers {
	func = (at allFunctions funcName)
	updateCmdList func (cmdList func)
	localNames = (toList (localNames func))
	removeAll localNames globalVars

	argCount = (count (argNames func))
	localCount = (count localNames)
	stackWords = (+ 3 argCount localCount)
	info = ''
	if (or (argCount > 0) (localCount > 0)) {
		info = (join info ' (')
		if (argCount > 0) {
			info = (join info argCount ' arg')
			if (argCount > 1) { info = (join info 's') }
			if (localCount > 0) { info = (join info ', ') }
		}
		if (localCount > 0) {
			info = (join info localCount ' local')
			if (localCount > 1) { info = (join info 's') }
		}
		info = (join info ')')
	}
	add result (join indent funcName info ' ' stackWords)
	indent = (join '   ' indent)

	if (isNil (cmdList func)) { return }

	processed = (dictionary)
	for cmd (allBlocks (cmdList func)) {
		op = (primName cmd)
		if (and (contains allFunctions op) (not (contains processed op))) {
			if (contains callers op) {
				add result (join indent '   ' funcName ' [recursive]')
			} else {
				appendCallsForFunction this op result indent globalVars allFunctions (copyWith callers op)
			}
			add processed op
		}
	}
}

// Decompiler tests

method testDecompiler SmallRuntime aBlock {
    if (isClass aBlock 'BlockDefinition') {
        funcName = (functionNamed (project scripter) (op aBlock))
        gpCode = (decompileBytecodes -1 (chunkTypeFor this funcName) (chunkBytesFor this funcName))
    } else {
        topBlock = (topBlock aBlock)
        gpCode = (decompileBytecodes -1 (chunkTypeFor this topBlock) (chunkBytesFor this topBlock))
    }
     showCodeInHand this gpCode
}

method showCodeInHand SmallRuntime gpCode {
	if (isClass gpCode 'Function') {
		block = (scriptForFunction gpCode)
	} (or (isClass gpCode 'Command') (isClass gpCode 'Reporter')) {
		block = (toBlock gpCode)
	} else {
		// decompiler didn't return something that can be represented as blocks
		return
	}
	grab (hand (global 'page')) block
	fixBlockColor block
}

method compileAndDecompile SmallRuntime aBlockOrFunction {
    if (isClass aBlockOrFunction 'Function') {
        chunkID = (first (at chunkIDs (functionName aBlockOrFunction)))
    }
	chunkType = (chunkTypeFor this aBlockOrFunction)
	bytecodes1 = (chunkBytesFor this aBlockOrFunction)
	gpCode = (decompileBytecodes chunkID chunkType bytecodes1)
	bytecodes2 = (chunkBytesFor this gpCode)
	if (bytecodes1 == bytecodes2) {
		if ((count bytecodes1) > 900) {
			print 'large chunkType:' chunkType 'bytes:' (count bytecodes1)
		}
	} else {
		print 'FAILED! chunkType:' chunkType 'bytes in:' (count bytecodes1) 'bytes out' (count bytecodes2)
	}
}

method decompileAll SmallRuntime {
	// Called by dev menu 'decompile all' for testing.

	decompileAllExamples this
}

method decompileAllExamples SmallRuntime {
    // decompileAllExamples (smallRuntime)

	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Examples') {
			print fn
			openProjectFromFile (findMicroBlocksEditor) (join '//' fn)
			decompileAllInProject this
		}
	}
}

method decompileAllLibraries SmallRuntime {
    // decompileAllLibraries (smallRuntime)

	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Libraries') {
			print fn
			clearProject (findMicroBlocksEditor)
			importLibraryFromFile (scripter (findMicroBlocksEditor)) (join '//' fn)
			decompileAllInProject this
		}
	}
}

method decompileAllInProject SmallRuntime {
    // decompileAllInProject (smallRuntime)

	assignFunctionIDs this
	for aFunction (allFunctions (project scripter)) {
		compileAndDecompile this aFunction
	}
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (not (isPrototypeHat aBlock)) { // functions are handled above
			compileAndDecompile this aBlock
		}
	}
}

method analyzeAllExamples SmallRuntime {
    grandTotal = 0
    projectCount = 0
	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Examples') {
			print fn
			openProjectFromFile (findMicroBlocksEditor) (join '//' fn)
			grandTotal += (analyzeProject this)
		    projectCount += 1
		}
	}
	print 'Grand total:' grandTotal 'for' projectCount 'projects'
}

method analyzeProject SmallRuntime {
	totalBytes = 0
	assignFunctionIDs this
	for aFunction (allFunctions (project scripter)) {
		byteCount = (count (chunkBytesFor this aFunction))
		if (byteCount > 700) { print ' ' (functionName aFunction) byteCount }
		totalBytes += byteCount
	}
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (not (isPrototypeHat aBlock)) { // functions are handled above
			byteCount = (count (chunkBytesFor this aBlock))
			if (byteCount > 700) { print '     script' byteCount }
			totalBytes += byteCount
		}
	}
	print '  Total:' totalBytes
	print '-----------'
	return totalBytes
}

method metadataBytesInAllLibraries SmallRuntime {
   // metadataBytesInAllProjects (smallRuntime)

	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Examples') {
			openProjectFromFile (findMicroBlocksEditor) (join '//' fn)
			print (metadataBytesInProject this) fn
		}
	}
}

method metadataBytesInAllProjects SmallRuntime {
   // metadataBytesInAllProjects (smallRuntime)

	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Examples') {
			openProjectFromFile (findMicroBlocksEditor) (join '//' fn)
			print (metadataBytesInProject this) fn
		}
	}
}

method metadataBytesInAllLibraries SmallRuntime {
   // metadataBytesInAllLibraries (smallRuntime)

	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Libraries') {
			clearProject (findMicroBlocksEditor)
			importLibraryFromFile (scripter (findMicroBlocksEditor)) (join '//' fn)
			print (metadataBytesInProject this) fn
		}
	}
}

method metadataBytesInProject SmallRuntime {
    // metadataBytesInProject (smallRuntime)

    byteCount = 0
	assignFunctionIDs this
	for aFunction (allFunctions (project scripter)) {
		byteCount += (metadataBytesFor this aFunction)
	}
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (not (isPrototypeHat aBlock)) { // functions are handled above
		    byteCount += (metadataBytesFor this aBlock)
		}
	}
	return byteCount
}

method metadataBytesFor SmallRuntime aBlockOrFunction {
	if (isClass aBlockOrFunction 'String') { // look up function by name
		aBlockOrFunction = (functionNamed (project scripter) aBlockOrFunction)
		if (isNil aBlockOrFunction) { return (list) } // unknown function
	}
	opcodes = (list)
	appendDecompilerMetadata (initialize (new 'SmallCompiler')) aBlockOrFunction opcodes
	metadata = (joinStrings (copyFromTo (last opcodes) 2) (string 9))
    return (byteCount metadata)
}

// Decompiling

method readCodeFromNextBoardConnected SmallRuntime {
	readFromBoard = true
	disconnected = false
	if ('Browser' == (platform)) {
		// in browser, cannot add the spinner before user has clicked connect icon
		inform 'Plug in the board and click the USB icon to connect.'
		return
	}
	decompilerStatus = (localized 'Plug in the board.')
	spinner = (newSpinner (action 'decompilerStatus' (smallRuntime)) (action 'decompilerDone' (smallRuntime)))
	addPart (global 'page') spinner
}

method readCodeFromBoard SmallRuntime {
	decompiler = (newDecompiler)
	waitForPing this
	decompilerStatus = (localized 'Reading project from board...')

	if ('Browser' == (platform)) {
		prompter = (findMorph 'Prompter')
		if (notNil prompter) { destroy prompter } // remove the prompt to connect board

		if (not (canReplaceCurrentProject (findMicroBlocksEditor))) {
			return // uncommon: user started writing code before connecting the board
		}

		// in browser, spinner was not added earlier
		spinner = (newSpinner (action 'decompilerStatus' (smallRuntime)) (action 'decompilerDone' (smallRuntime)))
		addPart (global 'page') spinner
	}

	sendMsg this 'getVarNamesMsg'
	lastRcvMSecs = (msecsSinceStart)
	while (((msecsSinceStart) - lastRcvMSecs) < 100) {
		processMessages this
		waitMSecs 10
	}

	sendMsg this 'getAllCodeMsg' 1
	lastRcvMSecs = (msecsSinceStart)
	while (((msecsSinceStart) - lastRcvMSecs) < 2000) {
		processMessages this
		doOneCycle (global 'page')
		waitMSecs 10
	}
	if (isNil decompiler) { return } // decompilation was aborted

print 'Read' (count (getField decompiler 'vars')) 'vars' (count (getField decompiler 'chunks')) 'chunks'
	proj = (decompileProject decompiler)
	decompilerStatus = (localized 'Loading project...')
	doOneCycle (global 'page')
	installDecompiledProject this proj
	readFromBoard = false
	decompiler = nil
}

method decompilerDone SmallRuntime { return (and (isNil decompiler) (not readFromBoard)) }
method decompilerStatus SmallRuntime { return decompilerStatus }

method stopDecompilation SmallRuntime {
	readFromBoard = false
	spinnerM = (findMorph 'MicroBlocksSpinner')
	if (notNil spinnerM) { removeFromOwner spinnerM }

	if (notNil decompiler) {
		decompiler = nil
		clearBoardIfConnected this true
		stopAndSyncScripts this
	}
}

method waitForPing SmallRuntime {
	// Try to get a ping back from the board. Used to ensure that the board is responding.

	endMSecs = ((msecsSinceStart) + 1000)
	lastPingRecvMSecs = 0
	iter = 0
	while (0 == lastPingRecvMSecs) {
	    now = (msecsSinceStart)
		if (now > endMSecs) { return } // no response within the timeout
		if ((iter % 20) == 0) {
		    // send a ping every 100 msecs
		    sendMsg this 'pingMsg'
		    pingSentMSecs = now
		}
		processMessages this
		iter += 1
		waitMSecs 5
	}
}

method installDecompiledProject SmallRuntime proj {
	clearBoardIfConnected this true
	setProject scripter proj
	updateLibraryList scripter
	checkForNewerLibraryVersions (project scripter) true
	restoreScripts scripter // fix block colors
	cleanUp (scriptEditor scripter)
	saveAllChunksAfterLoad this
}

method receivedChunk SmallRuntime chunkID chunkType bytecodes {
	lastRcvMSecs = (msecsSinceStart)
	if (isEmpty bytecodes) {
		print 'truncated chunk!' chunkID chunkType (count bytecodes) // shouldn't happen
		return
	}
	if (notNil decompiler) {
		addChunk decompiler chunkID chunkType bytecodes
	}
}

method receivedVarName SmallRuntime varID varName byteCount {
	lastRcvMSecs = (msecsSinceStart)
	if (notNil decompiler) {
		addVar decompiler varID varName
	}
}

// HTTP server support

method readVarsFromBoard SmallRuntime client {
	if (notNil decompiler) { return }

	// pretend to be a decompiler to collect variable names
	decompiler = client
	waitForPing this
	sendMsg this 'getVarNamesMsg'
	lastRcvMSecs = (msecsSinceStart)
	while (((msecsSinceStart) - lastRcvMSecs) < 50) {
		processMessages this
		waitMSecs 10
	}
	// clear decompiler
	decompiler = nil
}


// chunk management

method syncScripts SmallRuntime {
	// Called by scripter when anything changes.

	if (isNil port) { return }
	if (notNil decompiler) { return }

	// force re-save of any functions in the scripting area
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (isPrototypeHat aBlock) {
			fName = (functionName (function (editedPrototype aBlock)))
			entry = (at chunkIDs fName nil)
			if (notNil entry) {
				// record that function is in scripting area so must be checked for changes
				atPut entry 5 true
			}
		}
	}

	saveAllChunks this false
}

method lookupChunkID SmallRuntime key {
	// If the given block or function name has been assigned a chunkID, return it.
	// Otherwise, return nil.

	entry = (at chunkIDs key nil)
	if (isNil entry) { return nil }
	return (first entry)
}

method removeObsoleteChunks SmallRuntime {
	// Remove obsolete chunks. Chunks become obsolete when they are deleted or inserted into
	// a script so they are no longer a stand-alone chunk. Functions become obsolete when
	// they are deleted or the library containing them is deleted.

	for k (keys chunkIDs) {
		isObsolete = false
		if (isClass k 'Block') {
			owner = (owner (morph k))
			isObsolete = (or
				(isNil owner)
				(isNil (handler owner))
				(not (isAnyClass (handler owner) 'Hand' 'ScriptEditor' 'BlocksPalette')))
		} (isClass k 'String') {
			isObsolete = (isNil (functionNamed (project scripter) k))
		}
		if isObsolete {
			deleteChunkFor this k
		}
	}
}

method unusedChunkID SmallRuntime {
	// Return an unused chunkID.

	inUse = (dictionary)
	for entry (values chunkIDs) {
		add inUse (first entry) // the chunk ID is first element of entry
	}
	for i 256 {
		id = (i - 1)
		if (not (contains inUse id)) { return id }
	}
	error 'Too many code chunks (functions and scripts). Max is 256).'
}

method ensureChunkIdFor SmallRuntime aBlock {
	// Return the chunkID for the given block. Functions are handled by assignFunctionIDs.
	// If necessary, register the block in the chunkIDs dictionary.

	entry = (at chunkIDs aBlock nil)
	if (isNil entry) {
		id = (unusedChunkID this)
		entry = (array id nil (chunkTypeFor this aBlock) '' false)
		atPut chunkIDs aBlock entry // block -> (<id>, <crc>, <chunkType>, <lastSrc>, <functionMayHaveChanged>)
	}
	return (first entry)
}

method chunkEntryForBlock SmallRuntime aBlock {
	return (at chunkIDs aBlock nil)
}

method assignFunctionIDs SmallRuntime {
	// Ensure that there is a chunk ID for every user-defined function.
	// This must be done before generating any code to allow for recursive calls.

	for func (allFunctions (project scripter)) {
		fName = (functionName func)
		if (not (contains chunkIDs fName)) {
			id = (unusedChunkID this)
			entry = (array id nil (chunkTypeFor this func) '' true)
			atPut chunkIDs fName entry // fName -> (<id>, <crc>, <chunkType>, <lastSrc>, <functionMayHaveChanged>)
		}
	}
}

method functionNameForID SmallRuntime chunkID {
	assignFunctionIDs this
	for pair (sortedPairs chunkIDs) {
		id = (first (first pair))
		if (id == chunkID) { return (last pair) } // return function name
	}
	return (join 'f' chunkID)
}

method deleteChunkFor SmallRuntime key {
	if (and (isClass key 'Block') (isPrototypeHat key)) {
		key = (functionName (function (editedPrototype key)))
	}
	entry = (at chunkIDs key nil)
	if (and (notNil entry) (notNil port)) {
		chunkID = (first entry)
		sendMsgSync this 'deleteChunkMsg' chunkID
		remove chunkIDs key
	}
}

method stopAndSyncScripts SmallRuntime alreadyStopped {
	// Stop everything. Sync and verify scripts with the board using chunk CRC's.

	step scripter // save recently edited scripts

	removeHint (global 'page')
	if (and (notNil port) (true != alreadyStopped)) {
		sendStopAll this
		softReset this
	}
	clearRunningHighlights this
	doOneCycle (global 'page')

	if (shiftKeyDown (keyboard (global 'page'))) {
		recompileAll = true
	}
	suspendCodeFileUpdates this
	saveAllChunks this true
	resumeCodeFileUpdates this
    showDownloadProgress (findMicroBlocksEditor) 3 1
}

method softReset SmallRuntime {
	// Stop everyting, clear memory, and reset the I/O pins.

	sendMsg this 'systemResetMsg' // send the reset message
}

method isWebSerial SmallRuntime {
	return (and ('Browser' == (platform)) (browserHasWebSerial))
}

method webSerialConnect SmallRuntime action {
	if ('disconnect' == action) {
		if ('boardie' != portName) {
			stopAndSyncScripts this
			sendStartAll this
		} else {
			browserCloseBoardie
		}
		closeSerialPort 1
		portName = nil
		port = nil
	} ('open Boardie' == action) {
		browserOpenBoardie
		disconnected = false
		connectionStartTime = (msecsSinceStart)
		portName = 'boardie'
		port = 1
	} else {
		if (and ('Browser' == (platform)) (not (or (browserIsChromeOS) (browserHasWebSerial)))) { // running in a browser w/o WebSerial (or it is not enabled)
			inform (localized 'Only recent Chrome and Edge browsers support WebSerial.')
			return
		}
		if (beginsWith action 'connect (BLE)') {
		    openSerialPort 'webBLE' 115200
		} else {
		    openSerialPort 'webserial' 115200
		}
		disconnected = false
		connectionStartTime = (msecsSinceStart)
		portName = 'webserial'
		port = 1
	    lastPingRecvMSecs = 0
	    sendMsg this 'pingMsg'
	}
}

method selectPort SmallRuntime {
	if (isNil disconnected) { disconnected = false }

	if ('Browser' == (platform)) {
		menu = (menu 'Connect' (action 'webSerialConnect' this) true)
		if (and (isNil port) ('boardie' != portName)) {
			if (browserHasWebSerial) {
				addItem menu 'connect'
				allowBLEConnect = true
				if allowBLEConnect {
				    addItem menu 'connect (BLE) (Experimental!)'
				    addLine menu
				}
			}
			addItem menu 'open Boardie'
		} else {
			addItem menu 'disconnect'
		}
		popUpAtHand menu (global 'page')
		return
	}

	portList = (portList this)
	menu = (menu 'Connect' (action 'setPort' this) true)
	if (or disconnected (devMode)) {
		for s portList {
			if (or (isNil port) (portName != s)) { addItem menu s }
		}
		if (isEmpty portList) {
			addItem menu 'Connect board and try again'
		}
	}
	if (and (devMode) ('Browser' != (platform))) {
		addItem menu 'other...'
	}
	if (notNil port) {
		addLine menu
		if (notNil portName) {
			addItem menu (join 'disconnect (' portName ')')
		} else {
			addItem menu 'disconnect'
		}
	}
	popUpAtHand menu (global 'page')
}

method portList SmallRuntime {
	portList = (list)
	if ('Win' == (platform)) {
		portList = (list)
		for pname (listSerialPorts) {
			blackListed = (or
				((containsSubString pname 'Bluetooth') > 0)
				((containsSubString pname '(COM1)') > 0)
				((containsSubString pname 'Intel(R) Active Management') > 0))
			if (not blackListed) {
				add portList pname
			}
		}
	} ('Browser' == (platform)) {
		listSerialPorts // first call triggers callback
		waitMSecs 5
		portList = (list)
		for portName (listSerialPorts) {
			if (not (beginsWith portName '/dev/tty.')) {
				add portList portName
			}
		}
	} else {
		for fn (listFiles '/dev') {
			if (or	(notNil (nextMatchIn 'usb' (toLowerCase fn) )) // MacOS
					(notNil (nextMatchIn 'acm' (toLowerCase fn) ))) { // Linux
			    if (isNil (nextMatchIn 'usbmon' (toLowerCase fn))) { // ignore 'usbmonX' devices
				    add portList (join '/dev/' fn)
				}
			}
		}
		if ('Linux' == (platform)) {
			// add pseudoterminal
			ptyName = (readFile '/tmp/ublocksptyname')
			if (notNil ptyName) {
				add portList ptyName
			}
		}
		// Mac OS lists a port as both cu.<name> and tty.<name>
		for s (copy portList) {
			if (beginsWith s '/dev/tty.') {
				if (contains portList (join '/dev/cu.' (substring s 10))) {
					remove portList s
				}
			}
		}
	}
	return portList
}

method setPort SmallRuntime newPortName {
	if (beginsWith newPortName 'Connect board and try again') { return }
	if (beginsWith newPortName 'disconnect') {
		if (notNil port) {
			stopAndSyncScripts this
			sendStartAll this
		}
		disconnected = true
		closePort this
		updateIndicator (findMicroBlocksEditor)
		return
	}
	if ('other...' == newPortName) {
		newPortName = (freshPrompt (global 'page') 'Port name?' (localized 'none'))
		if ('' == newPortName) { return }
	}
	closePort this
	disconnected = false

	// the prompt answer 'none' is entered by the user in the current language
	if (or (isNil newPortName) (newPortName == (localized 'none'))) {
		portName = nil
	} else {
		portName = newPortName
		openPortAndSendPing this
	}
	updateIndicator (findMicroBlocksEditor)
}

method closePort SmallRuntime {
	// Close the serial port and clear info about the currently connected board.

	if (notNil port) { closeSerialPort port }
	port = nil
	vmVersion = nil
	boardType = nil

	// remove running highlights and result bubbles when disconnected
	clearRunningHighlights this
}

method enableAutoConnect SmallRuntime success {
	closeAllDialogs (findMicroBlocksEditor)
	if ('Browser' == (platform)) {
		// In the browser, the serial port must be closed and re-opened after installing
		// firmware on an ESP board. Not sure why. Adding a delay did not help.
		closePort this
		closeSerialPort 1 // make sure port is really disconnected
		disconnected = true
		if success { otherReconnectMessage this }
		return
	}
	disconnected = false
	stopAndSyncScripts this
}

method tryToInstallVM SmallRuntime {
	// Invite the user to install VM if we see a new board drive and are not able to connect to
	// it within a few seconds. Remember the last set of boardDrives so we don't keep asking.
	// Details: On Mac OS (at least), 3-4 seconds elapse between when the board drive appears
	// and when the USB-serial port appears. Thus, the IDE waits a bit to see if it can connect
	// to the board before prompting the user to install the VM to avoid spurious prompts.

	if (and (notNil vmInstallMSecs) ((msecsSinceStart) > vmInstallMSecs)) {
		vmInstallMSecs = nil
		if (and (notNil port) (isOpenSerialPort port)) { return }
		ok = (confirm (global 'page') nil (join
			(localized 'The board is not responding.') (newline)
			(localized 'Try to Install MicroBlocks on the board?')))
		if ok { installVM this }
		return
	}

	boardDrives = (collectBoardDrives this)
	if (lastBoardDrives == boardDrives) { return }
	lastBoardDrives = boardDrives
	if (isEmpty boardDrives) {
		vmInstallMSecs = nil
	} else {
		vmInstallMSecs = ((msecsSinceStart) + 5000) // prompt to install VM in a few seconds
	}
}

method connectedToBoard SmallRuntime {
	pingTimeout = 8000
	if (or (isNil port) (not (isOpenSerialPort port))) { return false }
	if (or (isNil lastPingRecvMSecs) (lastPingRecvMSecs == 0)) { return false }
	return (((msecsSinceStart) - lastPingRecvMSecs) < pingTimeout)
}

method updateConnection SmallRuntime {
	pingSendInterval = 2000 // msecs between pings
	pingTimeout = 8000
	if (isNil pingSentMSecs) { pingSentMSecs = 0 }
	if (isNil lastPingRecvMSecs) { lastPingRecvMSecs = 0 }
	if (isNil disconnected) { disconnected = false }

	if (notNil decompiler) { return 'connected' }
	if disconnected { return 'not connected' }

	// handle connection attempt in progress
	if (notNil connectionStartTime) { return (tryToConnect this) }

	// if port is not open, try to reconnect or find a different board
	if (or (isNil port) (not (isOpenSerialPort port))) {
		clearRunningHighlights this
		closePort this
		if ('Browser' == (platform)) {
			portName = nil // clear 'boardie' when boardie is closed with power button
			return 'not connected' // user must initiate connection attempt
		}
		return (tryToConnect this)
	}

	// if the port is open and it is time, send a ping
	now = (msecsSinceStart)
	if ((now - pingSentMSecs) > pingSendInterval) {
		if ((now - pingSentMSecs) > 5000) {
			// it's been a long time since we sent a ping; laptop may have been asleep
			// set lastPingRecvMSecs to N seconds into future to suppress warnings
			lastPingRecvMSecs = now
		}
		sendMsg this 'pingMsg'
		pingSentMSecs = now
		return 'connected'
	}

	msecsSinceLastPing = (now - lastPingRecvMSecs)
	if (msecsSinceLastPing < pingTimeout) {
		// got a ping recently: we're connected
		return 'connected'
	} else {
		// ping timeout: close port to force reconnection
		print 'Lost communication to the board'
		clearRunningHighlights this
        closePort this
		return 'not connected'
	}
}

method justConnected SmallRuntime {
	// Called when a board has just connected (browser or stand-alone).

	print 'Connected to' portName
	connectionStartTime = nil
	vmVersion = nil
	sendMsgSync this 'getVersionMsg'
	sendStopAll this
	clearRunningHighlights this
	setDefaultSerialDelay this
	abortFileTransfer this
	processMessages this // process incoming version message
	if readFromBoard {
		readFromBoard = false
		readCodeFromBoard this
	} else {
		codeReuseDisabled = false // set this to false to attempt to reuse code on board
		if (or codeReuseDisabled (isEmpty chunkIDs) (not (boardHasSameProject this))) {
			if (not codeReuseDisabled) { print 'Full download' }
			clearBoardIfConnected this
		} else {
			print 'Incremental download' vmVersion boardType
		}
        showDownloadProgress (findMicroBlocksEditor) 2 0
        stopAndSyncScripts this true
        softReset this
	}
}

method tryToConnect SmallRuntime {
	// Called when connectionStartTime is not nil, indicating that we are trying
	// to establish a connection to a board the current serial port.
	if (and
		(not (hasUserCode (project (findProjectEditor))))
		(autoDecompileEnabled (findMicroBlocksEditor))
	) {
		readFromBoard = true
	}

	if (and (isWebSerial this) ('boardie' != portName)) {
		if (isOpenSerialPort 1) {
			portName = 'webserial'
			port = 1
            if (lastPingRecvMSecs != 0) { // got a ping; we're connected!
                justConnected this
                return 'connected'
            }
            sendMsg this 'pingMsg' // send another ping
			return 'not connected' // don't make circle green until successful ping
		} else {
			portName = nil
			port = nil
			return 'not connected'
		}
	}

	connectionAttemptTimeout = 5000 // milliseconds

	// check connection status only N times/sec
	now = (msecsSinceStart)
	if (isNil lastScanMSecs) { lastScanMSecs = 0 }
	msecsSinceLastScan = (now - lastScanMSecs)
	if (and (msecsSinceLastScan > 0) (msecsSinceLastScan < 20)) { return 'not connected' }
	lastScanMSecs = now

	if (notNil connectionStartTime) {
		if (lastPingRecvMSecs != 0) { // got a ping; we're connected!
			justConnected this
			return 'connected'
		}
        sendMsg this 'pingMsg' // send another ping
		if (now < connectionStartTime) { connectionStartTime = now } // clock wrap
		if ((now - connectionStartTime) < connectionAttemptTimeout) { return 'not connected' } // keep trying
	}

	closePort this
	connectionStartTime = nil

	if ('Browser' == (platform)) {  // disable autoconnect on ChromeOS
		disconnected = true
		return 'not connected'
	}

	portNames = (portList this)
	if (isEmpty portNames) { return 'not connected' } // no ports available

	// try the port following portName in portNames
	// xxx to do: after trying all the ports, call tryToInstallVM (but only if portNames isn't empty)
	i = 1
	if (notNil portName) {
		i = (indexOf portNames portName)
		if (isNil i) { i = 0 }
		i = ((i % (count portNames)) + 1)
	}
	portName = (at portNames i)
	openPortAndSendPing this
}

method openPortAndSendPing SmallRuntime {
	// Open port and send ping request
	closePort this // ensure port is closed
	connectionStartTime = (msecsSinceStart)
	ensurePortOpen this // attempt to reopen the port
	if (notNil port) {
		// discard any random bytes in buffer
		readSerialPort port true
	}
	lastPingRecvMSecs = 0
	sendMsg this 'pingMsg'
}

method ideVersion SmallRuntime { return ideVersion }
method latestVmVersion SmallRuntime { return latestVmVersion }

method ideVersionNumber SmallRuntime {
	// Return the version number portion of the version string (i.e. just digits and periods).

	for i (count ideVersion) {
		ch = (at ideVersion i)
		if (not (or (isDigit ch) ('.' == ch))) {
			return (substring ideVersion 1 (i - 1))
		}
	}
	return ideVersion
}

method readVersionFile SmallRuntime {
	// defaults in case version file is missing (which shouldn't happen)
	ideVersion = '0.0.0'
	latestVmVersion = 0

	data = (readEmbeddedFile 'versions')
	if (isNil data) { data = (readFile 'runtime/versions') }
	if (notNil data) {
		for s (lines data) {
			if (beginsWith s 'IDE ') { ideVersion = (substring s 5) }
			if (beginsWith s 'VM ') { latestVmVersion = (toNumber (substring s 4)) }
		}
	}
}

method showAboutBox SmallRuntime {
	vmVersionReport = (newline)
	if (notNil vmVersion) {
		vmVersionReport = (join ' (Firmware v' vmVersion ')' (newline))
	}
	(inform (global 'page') (join
		'MicroBlocks v' (ideVersion this) vmVersionReport (newline)
		(localized 'by') ' John Maloney, Bernat Romagosa, & Jens Mönig.' (newline)
		(localized 'Created with GP') ' (gpblocks.org)' (newline) (newline)
		(localized 'More info at http://microblocks.fun')) 'About MicroBlocks')
}

method checkBoardType SmallRuntime {
	if (and (isNil boardType) (notNil port)) {
		vmVersion = nil
		getVersion this
	}
	return boardType
}

method getVersion SmallRuntime {
	sendMsg this 'getVersionMsg'
}

method extractVersionNumber SmallRuntime versionString {
	// Return the version number from the versionString.
	// Version string format: vNNN, where NNN is one or more decimal digits,
	// followed by non-digits characters that are ignored. Ex: 'v052a micro:bit'

	words = (words (substring versionString 2))
	if (isEmpty words) { return -1 }
	result = 0
	for ch (letters (first words)) {
		if (not (isDigit ch)) { return result }
		digit = ((byteAt ch 1) - (byteAt '0' 1))
		result = ((10 * result) + digit)
	}
	return result
}

method extractBoardType SmallRuntime versionString {
	// Return the board type from the versionString.
	// Version string format: vNNN [boardType]

	words = (words (substring versionString 2))
	if (isEmpty words) { return -1 }
	return (joinStrings (copyWithout words (at words 1)) ' ')
}

method versionReceived SmallRuntime versionString {
	if (isNil versionString) { return } // bad version message
	if (isNil vmVersion) { // first time: record and check the version number
		vmVersion = (extractVersionNumber this versionString)
		boardType = (extractBoardType this versionString)
		checkVmVersion this
		installBoardSpecificBlocks this
	} else { // not first time: show the version number
		inform (global 'page') (join 'MicroBlocks Virtual Machine ' versionString) 'Firmware version'
	}
	updateConnectionName (findProjectEditor) boardType
}

method checkVmVersion SmallRuntime {
	// prevent version check from running while the decompiler is working
	if readFromBoard { return }
	if ((latestVmVersion this) > vmVersion) {
	    offerToUpdate = (not (isOneOf boardType
	        'CircuitPlayground' 'CircuitPlayground Bluefruit' 'Clue' 'MakerPort'
	        'RP2040' 'Pico W' 'Pico:ed' 'Wukong2040'))
	    if (not offerToUpdate) {
	        // Inform the user but don't offer to update these boards since updating
	        // then requires the user to put the board into boot mode.
		    inform (global 'page') (join
			    (localized 'The MicroBlocks in your board is not current')
			    ' (v' vmVersion ' vs. v' (latestVmVersion this) ').') 'Firmware version'
			return
	    }
		ok = (confirm (global 'page') nil (join
			(localized 'The MicroBlocks in your board is not current')
			' (v' vmVersion ' vs. v' (latestVmVersion this) ').' (newline)
			(localized 'Try to update MicroBlocks on the board?')))
		if ok { installVM this }
	}
}

method vmIncomptabibleWithIDE SmallRuntime {
    msg = (localized 'The firmware on the board is not compatible with this version of MicroBlocks.')
     inform (global 'page') msg
}

method installBoardSpecificBlocks SmallRuntime {
	// installs default blocks libraries for each type of board.

	if (or readFromBoard (notNil decompiler)) { return } // don't load libraries while decompiling
	if (hasUserCode (project scripter)) { return } // don't load libraries if project has user code
	if (boardLibAutoLoadDisabled (findMicroBlocksEditor)) { return } // board lib autoload has been disabled by user
    if (isNil boardType) { return } // can happen if VM was updated by versionReceived

	if ('Boardie' == boardType) {
		importEmbeddedLibrary scripter 'LED Display'
		importEmbeddedLibrary scripter 'Tone'
    } ('Citilab ED1' == boardType) {
		importEmbeddedLibrary scripter 'ED1 Buttons'
		importEmbeddedLibrary scripter 'Tone'
		importEmbeddedLibrary scripter 'Basic Sensors'
		importEmbeddedLibrary scripter 'LED Display'
	} (isOneOf boardType 'micro:bit' 'micro:bit v2' 'Calliope' 'Calliope v3' 'Mbits') {
		importEmbeddedLibrary scripter 'Basic Sensors'
		importEmbeddedLibrary scripter 'LED Display'
	} ('CircuitPlayground' == boardType) {
		importEmbeddedLibrary scripter 'Circuit Playground'
		importEmbeddedLibrary scripter 'Basic Sensors'
		importEmbeddedLibrary scripter 'NeoPixel'
		importEmbeddedLibrary scripter 'Tone'
	} ('CircuitPlayground Bluefruit' == boardType) {
		importEmbeddedLibrary scripter 'Basic Sensors'
		importEmbeddedLibrary scripter 'NeoPixel'
		importEmbeddedLibrary scripter 'Tone'
	} ('M5Stack-Core' == boardType) {
		importEmbeddedLibrary scripter 'LED Display'
		importEmbeddedLibrary scripter 'Tone'
		importEmbeddedLibrary scripter 'TFT'
		importEmbeddedLibrary scripter 'HTTP client'
	} ('ESP8266' == boardType) {
		importEmbeddedLibrary scripter 'HTTP client'
	} ('IOT-BUS' == boardType) {
		importEmbeddedLibrary scripter 'LED Display'
		importEmbeddedLibrary scripter 'TFT'
		importEmbeddedLibrary scripter 'touchScreenPrims'
	} ('ESP32' == boardType) {
		importEmbeddedLibrary scripter 'HTTP client'
	} ('cocorobo' == boardType) {
		importEmbeddedLibrary scripter '未来科技盒主控'
		importEmbeddedLibrary scripter '未来科技盒电机扩展'
	} ('TTGO RP2040' == boardType) {
		importEmbeddedLibrary scripter 'LED Display'
	} ('Pico:ed' == boardType) {
		importEmbeddedLibrary scripter 'LED Display'
	} ('Wukong2040' == boardType) {
		importEmbeddedLibrary scripter 'WuKong2040'
	} ('Databot' == boardType) {
		importEmbeddedLibrary scripter 'databot'
	} ('RP2040 Gizmo' == boardType) {
		importEmbeddedLibrary scripter 'Gizmo'
	} (beginsWith boardType 'MakerPort') {
		importEmbeddedLibrary scripter 'MakerPort'
	}
}

// BLE Control

method boardIsBLECapable SmallRuntime {
    status = (updateConnection this)
    if ('connected' != status) { return false }
	if (isNil boardType) { getVersion this }
    if (isOneOf boardType
        'Citilab ED1' 'Databot' 'M5Stack-Core' 'ESP32' 'Mbits' 'M5StickC+' 'M5StickC' 'M5Atom-Matrix') {
        return true
    }
    return false
}

method setBLEFlag SmallRuntime {
    enableBLE = (confirm (global 'page') nil 'Allow the attached board to be connected via BLE?')
    if enableBLE {
        sendMsg this 'enableBLEMsg' 1
    } else {
        sendMsg this 'enableBLEMsg' 0
    }
}

method clearBoardIfConnected SmallRuntime doReset {
	if (notNil port) {
		sendStopAll this
		if doReset { softReset this }
		sendMsgSync this 'deleteAllCodeMsg' 1 // delete all code from board
	}
	clearVariableNames this
	clearRunningHighlights this
	chunkIDs = (dictionary)
}

method sendStopAll SmallRuntime {
	sendMsg this 'stopAllMsg'
	clearRunningHighlights this
}

method startAll SmallRuntime {
    if (and (notNil vmVersion) (vmVersion < 300)) {
        return (vmIncomptabibleWithIDE this)
    }
    sendStartAll this
}

method sendStartAll SmallRuntime {
	step scripter // save script changes if needed
	sendMsg this 'startAllMsg' 1
}

// Saving and verifying

method reachableFunctions SmallRuntime {
	// Not currently used. This function finds all the functions in a project that
	// are called explicitly. This might be used to prune unused library functions
	// when downloading a project. However, it does not find dynamic calls that us
	// the "call" primitive, so it is a bit risky.

	proj = (project scripter)
	todo = (list)
	result = (dictionary)

	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (isPrototypeHat aBlock) {
			// todo: add function name to todo list
		} else {
			add todo aBlock
		}
	}
	while (notEmpty todo) {
		blockOrFuncName = (removeFirst todo)
		expr = nil
		if (isClass blockOrFuncName 'Block') {
			expr = (expression blockOrFuncName)
		} (isClass blockOrFuncName 'String') {
			func = (functionNamed proj blockOrFuncName)
			if (notNil func) { expr = (cmdList func) }
		}
		if (notNil expr) {
			for b (allBlocks expr) {
				op = (primName b)
				if (and (not (contains result op)) (notNil (functionNamed proj op))) {
					add result op
					add todo op
				}
			}
		}
	}
	print (count result) 'reachable functions:'
	for fName (keys result) { print '  ' fName }
}

method suspendCodeFileUpdates SmallRuntime { sendMsgSync this 'extendedMsg' 2 (list) }
method resumeCodeFileUpdates SmallRuntime { sendMsg this 'extendedMsg' 3 (list) }

method saveAllChunksAfterLoad SmallRuntime {
	if (not (connectedToBoard this)) { return }
	suspendCodeFileUpdates this
	saveAllChunks this true
	resumeCodeFileUpdates this
    showDownloadProgress (findMicroBlocksEditor) 3 1
}

method saveAllChunks SmallRuntime checkCRCs {
	// Save the code for all scripts and user-defined functions.

	if (isNil checkCRCs) { checkCRCs = true }
	if (not (connectedToBoard this)) { return }
    if (or (isNil vmVersion) (vmVersion < 300)) { return } // incompatible VM

	setCursor 'wait'

	t = (newTimer)
	editor = (findMicroBlocksEditor)
	totalScripts = (
		(count (allFunctions (project scripter))) +
		(count (sortedScripts (scriptEditor scripter))))
	progressInterval = (max 1 (floor (totalScripts / 20)))
	processedScripts = 0
	skipHiddenFunctions = true
	if (saveVariableNames this) { recompileAll = true }
	if recompileAll {
		// Clear the source code field of all chunk entries to force script recompilation
		// and possible re-download since variable offsets have changed.
		suspendCodeFileUpdates this
		for entry (values chunkIDs) {
			atPut entry 4 ''
			atPut entry 5 true
		}
		skipHiddenFunctions = false
	}
	assignFunctionIDs this
	removeObsoleteChunks this

	functionsSaved = 0
	for aFunction (allFunctions (project scripter)) {
		if (saveChunk this aFunction skipHiddenFunctions) {
			functionsSaved += 1
			if (0 == (functionsSaved % progressInterval)) {
				showDownloadProgress editor 3 (processedScripts / totalScripts)
			}
		}
		if (not (connectedToBoard this)) { // connection closed
		    print 'Lost communication to the board in saveAllChunks'
		    setCursor 'default'
		    return
		}
		processedScripts += 1
	}
	if (functionsSaved > 0) { print 'Downloaded' functionsSaved 'functions to board' (join '(' (msecSplit t) ' msecs)') }

	scriptsSaved = 0
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (not (isPrototypeHat aBlock)) { // skip function def hat; functions get saved above
			if (saveChunk this aBlock skipHiddenFunctions) {
				scriptsSaved += 1
				if (0 == (scriptsSaved % progressInterval)) {
					showDownloadProgress editor 3 (processedScripts / totalScripts)
				}
			}
            if (not (connectedToBoard this)) { // connection closed
                print 'Lost communication to the board in saveAllChunks'
                setCursor 'default'
                return
            }
		}
		processedScripts += 1
	}
	if (scriptsSaved > 0) { print 'Downloaded' scriptsSaved 'scripts to board' (join '(' (msecSplit t) ' msecs)') }

	recompileAll = false
	if checkCRCs { verifyCRCs this }
	resumeCodeFileUpdates this
	showDownloadProgress editor 3 1

	setCursor 'default'
}

method forceSaveChunk SmallRuntime aBlockOrFunction {
	// Save the chunk for the given block or function even if it was previously saved.

	if (contains chunkIDs aBlockOrFunction) {
		// clear the old CRC and source to force re-save
		atPut (at chunkIDs aBlockOrFunction) 2 nil // clear the old CRC
		atPut (at chunkIDs aBlockOrFunction) 4 '' // clear the old source
	}
	saveChunk this aBlockOrFunction false
}

method sourceForChunk SmallRuntime aBlockOrFunction {
	pp = (new 'PrettyPrinter')
	source = ''
	if (isClass aBlockOrFunction 'Function') {
		source = (prettyPrintFunction pp aBlockOrFunction)
	} else {
		expr = (expression aBlockOrFunction)
		if (isClass expr 'Reporter') {
			source = (prettyPrint pp expr)
		} else {
			source = (prettyPrintList pp expr)
		}
	}
	return source
}

method saveChunk SmallRuntime aBlockOrFunction skipHiddenFunctions {
	// Save the given script or function as an executable code "chunk".
	// Also save the source code (in GP format) and the script position.

	if (isNil skipHiddenFunctions) { skipHiddenFunctions = true } // optimize by default

	pp = (new 'PrettyPrinter')
	if (isClass aBlockOrFunction 'String') {
		aBlockOrFunction = (functionNamed (project scripter) aBlockOrFunction)
		if (isNil aBlockOrFunction) { return false } // unknown function
	}
	if (isClass aBlockOrFunction 'Function') {
		functionName = (functionName aBlockOrFunction)
		chunkID = (lookupChunkID this functionName)
		entry = (at chunkIDs functionName)
		if (and skipHiddenFunctions (not (at entry 5))) { return false } // function is not in scripting area so has not changed
		atPut entry 5 false
		currentSrc = (prettyPrintFunction pp aBlockOrFunction)
	} else {
		expr = (expression aBlockOrFunction)
		if (isClass expr 'Reporter') {
			currentSrc = (prettyPrint pp expr)
		} else {
			currentSrc = (prettyPrintList pp expr)
		}
		chunkID = (ensureChunkIdFor this aBlockOrFunction)
		entry = (at chunkIDs aBlockOrFunction)
		if ((at entry 3) != (chunkTypeFor this aBlockOrFunction)) {
			// user changed A/B/A+B button hat type with menu
			atPut entry 3 (chunkTypeFor this aBlockOrFunction)
			atPut entry 4 '' // clear lastSrc to force save
		}
	}

	if (currentSrc == (at entry 4)) { return false } // source hasn't changed; save not needed
	atPut entry 4 currentSrc // remember the source of the code we're about to save

	// save the binary code for the chunk
	chunkType = (chunkTypeFor this aBlockOrFunction)
	chunkBytes = (chunkBytesFor this aBlockOrFunction)

    while (((count chunkBytes) % 4) != 0) {
        // pad with zeros to make chunk byte count be an even multiple of four
        // this ensures 32-bit word chunk alignment in the code store
        add chunkBytes 0
    }

	data = (list chunkType)
	addAll data chunkBytes
	if ((count data) > 1000) {
		if (isClass aBlockOrFunction 'Function') {
            print (join (functionName aBlockOrFunction) (localized 'Script is too large to send to board.'))
            // The following causes a recursive error because "inform" runs the step function
            // which tries to save the script again. Workaround is to only print the error
            // in the console.
// 			inform (global 'page') (join
// 				(localized 'Function "') (functionName aBlockOrFunction)
// 				(localized '" is too large to send to board.'))
		} else {
			showError (morph aBlockOrFunction) (localized 'Script is too large to send to board.')
		}
		return false
	}

	// don't save the chunk if its CRC has not changed unless is a button or broadcast
	// hat because the CRC does not reflect changes to the button or broadcast name
	crcOptimization = true
	if (isClass aBlockOrFunction 'Block') {
		op = (primName (expression aBlockOrFunction))
		crcOptimization = (not (isOneOf op 'whenButtonPressed' 'whenBroadcastReceived'))
	}
	if (and crcOptimization ((at entry 2) == (computeCRC this chunkBytes))) {
		return false
	}

	// record if chunk is running
	restartChunk = (and (isClass aBlockOrFunction 'Block') (isRunning this aBlockOrFunction))

// Old code to store chunk on board; does not check crc:
// 	// Note: micro:bit v1 misses chunks if time window is over 10 or 15 msecs
// 	if (((msecsSinceStart) - lastPingRecvMSecs) < 10) {
// 		sendMsg this 'chunkCode16Msg' chunkID data
// 		sendMsg this 'pingMsg'
// 	} else {
// 		ok = (sendMsgSync this 'chunkCode16Msg' chunkID data)
// 	}
// 	processMessages this
// 	atPut entry 2 (computeCRC this chunkBytes) // remember the CRC of the code we just saved

	chunkCRC = (computeCRC this chunkBytes)
	if (storeChunkOnBoard this chunkID data chunkCRC) {
		atPut entry 2 chunkCRC // remember the CRC of the code we just saved
	} else {
        print 'Failed to save chunk:' chunkID
		atPut entry 2 nil // save failed; clear CRC
	}

	// restart the chunk if it was running
	if restartChunk {
		stopRunningChunk this chunkID
		waitForResponse this
		runChunk this chunkID
		waitForResponse this
	}
	return true
}

method storeChunkOnBoard SmallRuntime chunkID data chunkCRC {
	// Send the given chunk to the board and wait for the board to return the CRC.
	// That ensures that the chunk has been saved to Flash memory.
	// This can take several seconds if the board does a Flash compaction.

	lastCRC = nil
	sendMsg this 'chunkCode16Msg' chunkID data
	sendMsg this 'getChunkCRCMsg' chunkID

	// wait for CRC to be reported
	timeout = 3000 // must be less than ping timeout
	startT = (msecsSinceStart)
	while (and (lastCRC != chunkCRC) (((msecsSinceStart) - startT) < timeout)) {
		processMessages this
		waitMSecs 1
	}
	return (lastCRC == chunkCRC)
}

method computeCRC SmallRuntime chunkData {
	// Return the CRC for the given compiled code.

	crc = (crc (toBinaryData (toArray chunkData)))

	// convert crc to a 4-byte array
	result = (newArray 4)
	for i 4 { atPut result i (digitAt crc i) }
	return result
}

method verifyCRCs SmallRuntime {
	// Check that the CRCs of the chunks on the board match the ones in the IDE.
	// Resend the code of any chunks whose CRC's do not match.

	if (not (connectedToBoard this)) { return }

	// For testing: control type of CRC collection (default: forceIndividual = false)
	// collectCRCsIndividually is slower and less reliable than collectCRCsBulk but since
	// it works incrementally on the board it interferes less with real-time music performance.
	forceIndividual = false

	// collect CRCs from the board
	crcDict = (dictionary)
	if (and (notNil vmVersion) (vmVersion >= 159) (not forceIndividual)) {
		collectCRCsBulk this
	} else {
		collectCRCsIndividually this
	}

	// build dictionaries:
	//  ideChunks: maps chunkID -> block or functionName
	//  crcForChunkID: maps chunkID -> CRC
	ideChunks = (dictionary)
	crcForChunkID = (dictionary)
	for pair (sortedPairs chunkIDs) {
		id = (first (first pair))
		key = (last pair)
		if (and (isClass key 'String') (isNil (functionNamed (project scripter) key))) {
			remove chunkIDs key // remove reference to deleted function (rarely needed)
		} else {
			atPut ideChunks id (last pair)
			atPut crcForChunkID id (at (first pair) 2)
		}
	}

	editor = (findMicroBlocksEditor)
	totalCount = ((count crcDict) + (count ideChunks))
	processedCount = 0

	// process CRCs
	for chunkID (keys crcDict) {
		sourceItem = (at ideChunks chunkID)
		if (and (notNil sourceItem) ((at crcDict chunkID) != (at crcForChunkID chunkID))) {
			print 'CRC mismatch; resaving chunk:' chunkID
			forceSaveChunk this sourceItem
			showDownloadProgress editor 3 (processedCount / totalCount)
		}
		processedCount += 1
	}

	// check for missing chunks
	for chunkID (keys ideChunks) {
		if (not (contains crcDict chunkID)) {
			print 'Resaving missing chunk:' chunkID
			sourceItem = (at ideChunks chunkID)
			forceSaveChunk this sourceItem
			showDownloadProgress editor 3 (processedCount / totalCount)
		}
		processedCount += 1
	}
	showDownloadProgress editor 3 1
}

method boardHasSameProject SmallRuntime {
	// Return true if the board appears to have the same project as the IDE.

	if (not (connectedToBoard this)) { return false }

	// update chunkIDs dictionary for script/function additions or removals while disconnected
	assignFunctionIDs this
	for aBlock (sortedScripts (scriptEditor scripter)) {
		if (not (isPrototypeHat aBlock)) { // skip function def hat; functions get IDs above
			ensureChunkIdFor this aBlock
		}
	}

	// collect CRCs from the board
	crcDict = (dictionary)
	collectCRCsBulk this

	// build dictionaries:
	//  ideChunks: chunkID -> block or functionName
	//  crcForChunkID: chunkID -> CRC
	ideChunks = (dictionary)
	crcForChunkID = (dictionary)
	for pair (sortedPairs chunkIDs) {
		key = (last pair)
		chunkID = (at (first pair) 1)
		crc = (at (first pair) 2)
		atPut ideChunks chunkID key
		atPut crcForChunkID chunkID crc
	}

	// count matching chunks
	matchCount = 0
	for chunkID (keys crcDict) {
		entry = (at ideChunks chunkID)
		if (and (notNil entry) ((at crcDict chunkID) == (at crcForChunkID chunkID))) {
			matchCount += 1
		}
	}

	// count chunks that have changed or are entirely missing from the board
	changedOrMissingCount = 0
	for chunkID (keys ideChunks) {
		if (or
		    (not (contains crcDict chunkID))
		    ((at crcDict chunkID) != (at crcForChunkID chunkID))) {
			     changedOrMissingCount += 1
		}
	}

	return (and (matchCount > 3) (matchCount > changedOrMissingCount))
}

method collectCRCsIndividually SmallRuntime {
	// Collect the CRC's from all chunks on the board by requesting them individually

	crcDict = (dictionary)

	// request a CRC for every chunk
	for entry (values chunkIDs) {
		sendMsg this 'getChunkCRCMsg' (first entry)
		processMessages this
	}

	// if there are any chunks, wait for first CRC to arrive
	if ((count chunkIDs) > 0) {
		timeoutFirstCRC = 4000 // max time to wait for first CRC
		waitStartT = (msecsSinceStart)
		while (and
			(isEmpty crcDict)
			(((msecsSinceStart) - waitStartT) < timeoutFirstCRC)) {
				// wait for the first CRC to arrive
				processMessages this
				waitMSecs 10
		}
	}

	timeout = 120
	lastRcvMSecs = (msecsSinceStart)
	while (((msecsSinceStart) - lastRcvMSecs) < timeout) {
		processMessages this
		waitMSecs 10
	}
}

method crcReceived SmallRuntime chunkID chunkCRC {
	// Received an individual CRC message from board.
	// Record the CRC for the given chunkID.

	lastRcvMSecs = (msecsSinceStart)
	lastCRC = chunkCRC
	if (notNil crcDict) {
		atPut crcDict chunkID chunkCRC
	}
}

method collectCRCsBulk SmallRuntime {
	// Collect the CRC's from all chunks on the board via a bulk CRC request.

	crcDict = nil

	// request CRCs for all chunks on board
	sendMsgSync this 'getAllCRCsMsg' 1

	// wait until crcDict is filled in or timeout
	startT = (msecsSinceStart)
	while (and (isNil crcDict) (((msecsSinceStart) - startT) < 2000)) {
		processMessages this
		waitMSecs 5
	}

	if (isNil crcDict) { crcDict = (dictionary) } // timeout
}

method allCRCsReceived SmallRuntime data {
	// Received a message from baord with the CRCs of all chunks.
	// Create crcDict and record the (possibly empty) list of CRCs.
	// Each CRC record is 5 bytes: <chunkID (one byte)> <CRC (four bytes)>

	crcDict = (dictionary)
	byteCount = (count data)
	i = 1
	while (i <= (byteCount - 4)) {
		chunkID = (at data i)
		chunkCRC = (copyFromTo data (i + 1) (i + 4))
		atPut crcDict chunkID chunkCRC
		i += 5
	}
}

method saveVariableNames SmallRuntime {
	// If the variables list has changed, save the new variable names.
	// Return true if varibles have changed, false otherwise.

	newVarNames = (allVariableNames (project scripter))
	if (oldVarNames == newVarNames) { return false }

	editor = (findMicroBlocksEditor)
	varCount = (count newVarNames)
	progressInterval = (max 1 (floor (varCount / 20)))

	clearVariableNames this
	varID = 0
	for varName newVarNames {
		if (notNil port) {
			if (0 == (varID % 50)) {
				// send a sync message every N variables
				sendMsgSync this 'varNameMsg' varID (toArray (toBinaryData varName))
			} else {
				sendMsg this 'varNameMsg' varID (toArray (toBinaryData varName))
			}
		}
		varID += 1
		if (0 == (varID % progressInterval)) {
			showDownloadProgress editor 2 (varID / varCount)
		}
	}
	oldVarNames = (copy newVarNames)
	return true
}

method runChunk SmallRuntime chunkID {
    if (or (isNil vmVersion) (vmVersion < 300)) { return } // incompatible VM
	sendMsg this 'startChunkMsg' chunkID
}

method stopRunningChunk SmallRuntime chunkID {
	sendMsg this 'stopChunkMsg' chunkID
}

method sendBroadcastToBoard SmallRuntime msg {
	sendMsg this 'broadcastMsg' 0 (toArray (toBinaryData msg))
}

method getVar SmallRuntime varID {
	if (isNil varID) { varID = 0 }
	sendMsg this 'getVarMsg' varID
}

method getVarNamed SmallRuntime varName {
	sendMsg this 'getVarMsg' 255 (toArray (toBinaryData varName))
}

method setVar SmallRuntime varID val {
	body = nil
	if (isClass val 'Integer') {
		body = (newArray 5)
		atPut body 1 1 // type 1 - Integer
		atPut body 2 (val & 255)
		atPut body 3 ((val >> 8) & 255)
		atPut body 4 ((val >> 16) & 255)
		atPut body 5 ((val >> 24) & 255)
	} (isClass val 'String') {
		body = (toArray (toBinaryData (join (string 2) val)))
	} (isClass val 'Boolean') {
		body = (newArray 2)
		atPut body 1 3 // type 3 - Boolean
		if val {
			atPut body 2 1 // true
		} else {
			atPut body 2 0 // false
		}
	}
	if (notNil body) { sendMsg this 'setVarMsg' varID body }
}

method variablesChanged SmallRuntime {
	// Called by scripter when variables are added or removed.

	sendStopAll this
	clearVariableNames this
	scriptChanged scripter
}

method clearVariableNames SmallRuntime {
	if (notNil port) { sendMsgSync this 'clearVarsMsg' 1 }
	oldVarNames = nil
}

// Serial Delay

method serialDelayMenu SmallRuntime {
	menu = (menu (join 'Serial delay' (newline) '(smaller is faster, but may fail if computer cannot keep up)') (action 'setSerialDelay' this) true)
	for i (range 1 5) { addItem menu i }
	for i (range 6 20 2) { addItem menu i }
	addLine menu
	addItem menu 'reset to default (10)'
	popUpAtHand menu (global 'page')
}

method setDefaultSerialDelay SmallRuntime {
	setSerialDelay this 'reset to default'
}

method setSerialDelay SmallRuntime newDelay {
	if ('reset to default' == newDelay) {
		newDelay = 5
	}
	sendMsg this 'extendedMsg' 1 (list newDelay)
}

// Message handling

method msgNameToID SmallRuntime msgName {
	if (isClass msgName 'Integer') { return msgName }
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
		atPut msgDict 'getChunkCRCMsg' 11
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
		atPut msgDict 'chunkCRCMsg' 23
		atPut msgDict 'pingMsg' 26
		atPut msgDict 'broadcastMsg' 27
		atPut msgDict 'chunkAttributeMsg' 28
		atPut msgDict 'varNameMsg' 29
		atPut msgDict 'extendedMsg' 30
		atPut msgDict 'enableBLEMsg' 31
		atPut msgDict 'chunkCode16Msg' 32
		atPut msgDict 'getAllCRCsMsg' 38
		atPut msgDict 'allCRCsMsg' 39
		atPut msgDict 'deleteFile' 200
		atPut msgDict 'listFiles' 201
		atPut msgDict 'fileInfo' 202
		atPut msgDict 'startReadingFile' 203
		atPut msgDict 'startWritingFile' 204
		atPut msgDict 'fileChunk' 205
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
#define needsListError			11	// Needs a list
#define needsBooleanError		12	// Needs a boolean
#define needsIntegerError		13	// Needs an integer
#define needsStringError		14	// Needs a string
#define nonComparableError		15	// Those objects cannot be compared for equality
#define arraySizeError			16	// List size must be a non-negative integer
#define needsIntegerIndexError	17	// List or string index must be an integer
#define indexOutOfRangeError	18	// List or string index out of range
#define byteArrayStoreError		19	// A ByteArray can only store integer values between 0 and 255
#define hexRangeError			20	// Hexadecimal input must between between -1FFFFFFF and 1FFFFFFF
#define i2cDeviceIDOutOfRange	21	// I2C device ID must be between 0 and 127
#define i2cRegisterIDOutOfRange	22	// I2C register must be between 0 and 255
#define i2cValueOutOfRange		23	// I2C value must be between 0 and 255
#define notInFunction			24	// Attempt to access an argument outside of a function
#define badForLoopArg			25	// for-loop argument must be a positive integer or list
#define stackOverflow			26	// Insufficient stack space
#define primitiveNotImplemented	27	// Primitive not implemented in this virtual machine
#define notEnoughArguments		28	// Not enough arguments passed to primitive
#define waitTooLong				29	// The maximum wait time is 3600000 milliseconds (one hour)
#define noWiFi					30	// This board does not support WiFi
#define zeroDivide				31	// Division (or modulo) by zero is not defined
#define argIndexOutOfRange		32	// Argument index out of range
#define needsIndexable			33	// Needs an indexable type such as a string or list
#define joinArgsNotSameType		34	// All arguments to join must be the same type (e.g. lists)
#define i2cTransferFailed		35	// I2C transfer failed
#define needsByteArray			36	// Needs a byte array
#define serialPortNotOpen		37	// Serial port not open
#define serialWriteTooBig		38	// Serial port write is limited to 128 bytes
#define needsListOfIntegers		39	// Needs a list of integers
#define byteOutOfRange			40	// Needs a value between 0 and 255
#define needsPositiveIncrement	41	// Range increment must be a positive integer
#define needsIntOrListOfInts	42	// Needs an integer or a list of integers
#define wifiNotConnected		43	// Not connected to a WiFi network
#define cannotConvertToInteger	44	// Cannot convert that to an integer
#define cannotConvertToBoolean	45	// Cannot convert that to a boolean
#define cannotConvertToList		46	// Cannot convert that to a list
#define cannotConvertToByteArray 47	// Cannot convert that to a byte array
#define unknownDatatype			48	// Unknown datatype
#define invalidUnicodeValue		49	// Unicode values must be between 0 and 1114111 (0x10FFFF)
#define cannotUseWithBLE		50	// Cannot use this feature when board is connected to IDE via Bluetooth
#define bad8BitBitmap			51	// Needs an 8-bit bitmap: a list containing the bitmap width and contents (a byte array)
#define badColorPalette			52	// Needs a color palette: a list of positive 24-bit integers representing RGB values
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
	ensurePortOpen this
	if (isNil port) { return }

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
	dataToSend = (toBinaryData (toArray msg))

	if ('boardie' == portName) { // send all data at once to boardie
		(writeSerialPort port dataToSend)
		return
	}

	while ((byteCount dataToSend) > 0) {
		// Note: Adafruit USB-serial drivers on Mac OS locks up if >= 1024 bytes
		// written in one call to writeSerialPort, so send smaller chunks
		// Note: Maximum serial write in Chrome browser is only 64 bytes!
        // Note: Receive buffer on micro:bit is only 63 bytes.
		byteCount = (min 63 (byteCount dataToSend))
		chunk = (copyFromTo dataToSend 1 byteCount)
		bytesSent = (writeSerialPort port chunk)
		if (not (isOpenSerialPort port)) {
			closePort this
			return
		}
		waitMSecs 3 // limit throughput to avoid overunning buffer when board is busy
		if (bytesSent < byteCount) { waitMSecs 25 } // output queue full; wait a bit
		dataToSend = (copyFromTo dataToSend (bytesSent + 1))
	}
}

method sendMsgSync SmallRuntime msgName chunkID byteList {
	// Send a message followed by a 'pingMsg', then a wait for a ping response from VM.

	readAvailableSerialData this
	sendMsg this msgName chunkID byteList
	if ('boardie' == portName) { return true } // don't wait for a response

	if (not (connectedToBoard this)) { return false }

	ok = (waitForResponse this)
	if (not ok) {
		print 'Lost communication to the board in sendMsgSync'
		closePort this
		return false
	}
	return true
}

method readAvailableSerialData SmallRuntime {
	// Read any available data into recvBuf so that waitForResponse will await fresh data.

	if (isNil port) { return }
	waitMSecs 20 // leave some time for queued data to arrive
	if (isNil recvBuf) { recvBuf = (newBinaryData 0) }
	s = (readSerialPort port true)
	if (notNil s) { recvBuf = (join recvBuf s) }
}

method waitForResponse SmallRuntime {
	// Wait for some data to arrive from the board. This is taken to mean that the
	// previous operation has completed. Return true if a response was received.

	sendMsg this 'pingMsg'
	timeout = 3000 // must be less than ping timeout
	iter = 1
	start = (msecsSinceStart)
	while (((msecsSinceStart) - start) < timeout) {
		if (isNil port) { return false }
		s = (readSerialPort port true)
		if (notNil s) {
			recvBuf = (join recvBuf s)
			return true
		}
		if ((iter % 50) == 0) { sendMsg this 'pingMsg' }
		iter += 1
		waitMSecs 5
	}
	return false
}

method ensurePortOpen SmallRuntime {
	if (true == disconnected) { return }
	if (isWebSerial this) { return }
	if (or (isNil port) (not (isOpenSerialPort port))) {
		if (and (notNil portName)
				(or (contains (portList this) portName)
				(notNil (findSubstring 'pts' portName)))) { // support for GnuBlocks
			port = (safelyRun (action 'openSerialPort' portName 115200))
			if (not (isClass port 'Integer')) { port = nil } // failed
			if (isNil port) { return }
			// connected!
			disconnected = false
			if ('Browser' == (platform)) { waitMSecs 100 } // let browser callback complete
		}
	}
}

method processMessages SmallRuntime {
	if (isNil recvBuf) { recvBuf = (newBinaryData 0) }
	repeat 100 { // process up to N messages
		if (not (processNextMessage this)) { return } // done!
	}
}

method processNextMessage SmallRuntime {
	// Process the next message, if any. Return false when there are no more messages.

	if (or (isNil port) (not (isOpenSerialPort port))) { return false }

	// Read any available bytes and append to recvBuf
	s = (readSerialPort port true)
	if (notNil s) { recvBuf = (join recvBuf s) }
	if ((byteCount recvBuf) < 3) { return false } // not enough bytes for even a short message

	// Parse and dispatch messages
	firstByte = (byteAt recvBuf 1)
	byteTwo = (byteAt recvBuf 2)
	if (or (byteTwo < 1) (and (40 <= byteTwo) (byteTwo < 200)) (byteTwo > 205)) {
		print 'Serial error, opcode:' (byteAt recvBuf 2)
		discardMessage this
		return true
	}
	if (250 == firstByte) { // short message
		msg = (copyFromTo recvBuf 1 3)
		recvBuf = (copyFromTo recvBuf 4) // remove message
		handleMessage this msg
	} (251 == firstByte) { // long message
		if ((byteCount recvBuf) < 5) { return false } // incomplete length field
		bodyBytes = (((byteAt recvBuf 5) << 8) | (byteAt recvBuf 4))
		if (bodyBytes >= 1024) {
			print 'Serial error, length:' bodyBytes
			discardMessage this
			return true
		}
		if ((byteCount recvBuf) < (5 + bodyBytes)) { return false } // incomplete body
		msg = (copyFromTo recvBuf 1 (bodyBytes + 5))
		recvBuf = (copyFromTo recvBuf (bodyBytes + 6)) // remove message
		handleMessage this msg
	} else {
		print 'Serial error, start byte:' firstByte
		print (toString recvBuf) // show the string (could be an ESP error message)
		discardMessage this
	}
	return true
}

method discardMessage SmallRuntime { skipMessage this true }

method skipMessage SmallRuntime discard {
	// Discard bytes in recvBuf until the start of the next message, if any.

	end = (byteCount recvBuf)
	i = 2
	while (i < end) {
		byte = (byteAt recvBuf i)
		if (or (250 == byte) (251 == byte)) {
		if (true == discard) { print '    ' (toString (copyFromTo recvBuf 1 (i - 1))) }
			recvBuf = (copyFromTo recvBuf i)
			return
		}
		i += 1
	}
	if (true == discard) { print '    ' (toString recvBuf) }
	recvBuf = (newBinaryData 0) // no message start found; discard entire buffer
}

// Message handling

method handleMessage SmallRuntime msg {
	lastPingRecvMSecs = (msecsSinceStart) // reset ping timer when any valid message is recevied
	op = (byteAt msg 2)
	if (op == (msgNameToID this 'taskStartedMsg')) {
		updateRunning this (byteAt msg 3) true
	} (op == (msgNameToID this 'taskDoneMsg')) {
		updateRunning this (byteAt msg 3) false
	} (op == (msgNameToID this 'taskReturnedValueMsg')) {
		chunkID = (byteAt msg 3)
		showResult this chunkID (returnedValue this msg) false true
		updateRunning this chunkID false
	} (op == (msgNameToID this 'taskErrorMsg')) {
		chunkID = (byteAt msg 3)
		showError this chunkID (errorString this (byteAt msg 6))
		updateRunning this chunkID false
	} (op == (msgNameToID this 'outputValueMsg')) {
		chunkID = (byteAt msg 3)
		if (chunkID == 255) {
			print (returnedValue this msg)
		} (chunkID == 254) {
			addLoggedData this (toString (returnedValue this msg))
		} else {
			showResult this chunkID (returnedValue this msg) false true
		}
	} (op == (msgNameToID this 'varValueMsg')) {
		varValueReceived (httpServer scripter) (byteAt msg 3) (returnedValue this msg)
	} (op == (msgNameToID this 'versionMsg')) {
		versionReceived this (returnedValue this msg)
	} (op == (msgNameToID this 'chunkCRCMsg')) {
		crcReceived this (byteAt msg 3) (copyFromTo (toArray msg) 6)
	} (op == (msgNameToID this 'allCRCsMsg')) {
		allCRCsReceived this (copyFromTo (toArray msg) 6)
	} (op == (msgNameToID this 'pingMsg')) {
		lastPingRecvMSecs = (msecsSinceStart)
	} (op == (msgNameToID this 'broadcastMsg')) {
		broadcastReceived (httpServer scripter) (toString (copyFromTo msg 6))
	} (op == (msgNameToID this 'chunkCode16Msg')) {
		receivedChunk this (byteAt msg 3) (byteAt msg 6) (toArray (copyFromTo msg 7))
	} (op == (msgNameToID this 'varNameMsg')) {
		receivedVarName this (byteAt msg 3) (toString (copyFromTo msg 6)) ((byteCount msg) - 5)
	} (op == (msgNameToID this 'fileInfo')) {
		recordFileTransferMsg this (copyFromTo msg 6)
	} (op == (msgNameToID this 'fileChunk')) {
		recordFileTransferMsg this (copyFromTo msg 6)
	} else {
		print 'msg:' (toArray msg)
	}
}

method updateRunning SmallRuntime chunkID runFlag {
	if (isNil chunkRunning) {
		chunkRunning = (newArray 256 false)
	}
	if (isNil chunkStopping) {
		chunkStopping = (dictionary)
	}
	if runFlag {
		atPut chunkRunning (chunkID + 1) runFlag
		remove chunkStopping chunkID
		updateHighlights this
	} else {
		// add chunkID to chunkStopping dictionary to be unhighlighted after a short pause
		stepCount = 2 // two scripter steps, about half a second
		atPut chunkStopping chunkID stepCount
	}
}

method updateStopping SmallRuntime {
	// Decrement the counts for chunks that are stopping.
	// Turn off highlights for chunks whose counts reach zero.

	if (and (isNil chunkStopping) (isEmpty chunkStopping))  { return }
	highlightChanged = false
	for chunkID (keys chunkStopping) {
		count = ((at chunkStopping chunkID) - 1) // decrement count
		if (count > 0) {
			atPut chunkStopping chunkID count // continue to wait
		} else {
			atPut chunkRunning (chunkID + 1) false
			remove chunkStopping chunkID
			highlightChanged = true
		}
	}
	if highlightChanged { updateHighlights this }
}

method isRunning SmallRuntime aBlock {
	chunkID = (lookupChunkID this aBlock)
	if (or (isNil chunkRunning) (isNil chunkID)) { return false }
	return (at chunkRunning (chunkID + 1))
}

// File Transfer Support

method boardHasFileSystem SmallRuntime {
	if (true == disconnected) { return false }
	if (and (isWebSerial this) (not (isOpenSerialPort 1))) { return false }
	if (not (connectedToBoard this)) { return false }
	if (isNil boardType) { getVersion this }
	return (isOneOf boardType 'Citilab ED1' 'M5Stack-Core' 'M5StickC+' 'M5StickC' 'M5Atom-Matrix' '未来科技盒' 'ESP32' 'ESP8266' 'Mbits' 'RP2040' 'Pico W' 'Pico:ed' 'Wukong2040' 'TTGO RP2040' 'Boardie' 'Databot' 'Mbits')
}

method deleteFileOnBoard SmallRuntime fileName {
	msg = (toArray (toBinaryData fileName))
	sendMsg this 'deleteFile' 0 msg
}

method getFileListFromBoard SmallRuntime {
	if ('boardie' == portName) {
		return (boardieFileList)
	}

	sendMsg this 'listFiles'
	collectFileTransferResponses this

	result = (list)
	for msg fileTransferMsgs {
		fileNum = (readInt32 this msg 1)
		fileSize = (readInt32 this msg 5)
		fileName = (toString (copyFromTo msg 9))
		add result fileName
	}
	return result
}

method getFileFromBoard SmallRuntime {
	setCursor 'wait'
	fileNames = (sorted (toArray (getFileListFromBoard this)))
	fileNames = (copyWithout fileNames 'ublockscode')
	setCursor 'default'
	if (isEmpty fileNames) {
		inform 'No files on board.'
		return
	}
	menu = (menu 'File to read from board:' (action 'getAndSaveFile' this) true)
	for fn fileNames {
		addItem menu fn
	}
	popUpAtHand menu (global 'page')
}

method getAndSaveFile SmallRuntime remoteFileName {
	data = (readFileFromBoard this remoteFileName)
	if ('Browser' == (platform)) {
        (confirm (global 'page') nil 'Save file?')
		browserWriteFile data remoteFileName 'fileFromBoard'
	} else {
		fName = (fileToWrite remoteFileName)
		if ('' != fName) { writeFile fName data }
	}
}

method readFileFromBoard SmallRuntime remoteFileName {
	if ('boardie' == portName) {
		return (boardieGetFile remoteFileName)
	}

	fileTransferProgress = 0
	spinner = (newSpinner (action 'fileTransferProgress' this 'downloaded') (action 'fileTransferCompleted' this))
	setStopAction spinner (action 'abortFileTransfer' this)
	addPart (global 'page') spinner

	msg = (list)
	id = (rand ((1 << 24) - 1))
	appendInt32 this msg id
	addAll msg (toArray (toBinaryData remoteFileName))
	sendMsg this 'startReadingFile' 0 msg
	collectFileTransferResponses this

	totalBytes = 0
	for msg fileTransferMsgs {
		// format: <transfer ID (4 byte int)><byte offset (4 byte int)><data...>
		transferID = (readInt32 this msg 1)
		offset = (readInt32 this msg 5)
		byteCount = ((byteCount msg) - 8)
		totalBytes += byteCount
		if (totalBytes > 0) {
			fileTransferProgress = (100 - (round (100 * (byteCount / totalBytes))))
			doOneCycle (global 'page')
		}
	}

	result = (newBinaryData totalBytes)
	startIndex = 1
	for msg fileTransferMsgs {
		byteCount = ((byteCount msg) - 8)
		endIndex = ((startIndex + byteCount) - 1)
		if (byteCount > 0) { replaceByteRange result startIndex endIndex msg 9 }
		startIndex += byteCount
	}

	fileTransferProgress = nil
	setCursor 'default'
	return result
}

method putFileOnBoard SmallRuntime {
	if ('Browser' == (platform)) {
		putNextDroppedFileOnBoard (findMicroBlocksEditor)
		browserReadFile ''
	} else {
		pickFileToOpen (action 'writeFileToBoard' this)
	}
}

method writeFileToBoard SmallRuntime srcFileName {
	if (notNil (findMorph 'MicroBlocksFilePicker')) {
		destroy (findMorph 'MicroBlocksFilePicker')
	}

	fileData = (readFile srcFileName true)
	if (isNil fileData) { return }

	targetFileName = (filePart srcFileName)
	if ((count targetFileName) > 30) {
		targetFileName = (substring targetFileName 1 30)
	}

	fileTransferProgress = 0
	spinner = (newSpinner (action 'fileTransferProgress' this 'uploaded') (action 'fileTransferCompleted' this))
	setStopAction spinner (action 'abortFileTransfer' this)
	addPart (global 'page') spinner

	sendFileData this targetFileName fileData
}

// busy tells the MicroBlocksEditor to suspend board communciations during file transfers
method busy SmallRuntime { return (notNil fileTransferProgress) }

method fileTransferProgress SmallRuntime actionLabel { return (join '' fileTransferProgress '% ' (localized actionLabel)) }

method abortFileTransfer SmallRuntime {
	if (not (fileTransferCompleted this)) { fileTransferProgress = nil }
}

method fileTransferCompleted SmallRuntime {
	// return true if the file transfer is complete or aborted
	return (or (isNil fileTransferProgress) (fileTransferProgress == 100))
}

method sendFileData SmallRuntime fileName fileData {
	if ('boardie' == portName) {
		boardiePutFile fileName fileData (byteCount fileData)
		return
	}

	// send data as a sequence of chunks
	setCursor 'wait'
	fileTransferProgress = 0

	totalBytes = (byteCount fileData)
	id = (rand ((1 << 24) - 1))
	bytesSent = 0

	msg = (list)
	appendInt32 this msg id
	addAll msg (toArray (toBinaryData fileName))
	sendMsgSync this 'startWritingFile' 0 msg

	while (bytesSent < totalBytes) {
		if (isNil fileTransferProgress) {
			print 'File transfer aborted.'
			return
		}
		msg = (list)
		appendInt32 this msg id
		appendInt32 this msg bytesSent
		chunkByteCount = (min 960 (totalBytes - bytesSent))
		repeat chunkByteCount {
			bytesSent += 1
			add msg (byteAt fileData bytesSent)
		}
		sendMsgSync this 'fileChunk' 0 msg
		if (totalBytes > 0) {
			fileTransferProgress = (round (100 * (bytesSent / totalBytes)))
			doOneCycle (global 'page')
		}
		processMessages this
	}
	// final (empty) chunk
	msg = (list)
	appendInt32 this msg id
	appendInt32 this msg bytesSent
	sendMsgSync this 'fileChunk' 0 msg

	fileTransferProgress = nil
}

method appendInt32 SmallRuntime msg n {
	add msg (n & 255)
	add msg ((n >> 8) & 255)
	add msg ((n >> 16) & 255)
	add msg ((n >> 24) & 255)
}

method readInt32 SmallRuntime msg i {
	result = (byteAt msg i)
	result += ((byteAt msg (i + 1)) << 8)
	result += ((byteAt msg (i + 2)) << 16)
	result += ((byteAt msg (i + 3)) << 24)
	return result
}

method collectFileTransferResponses SmallRuntime {
	fileTransferMsgs = (list)
	timeout = 1000
	lastRcvMSecs = (msecsSinceStart)
	while (((msecsSinceStart) - lastRcvMSecs) < timeout) {
		if (notEmpty fileTransferMsgs) { timeout = 500 } // decrease timeout after first response
		processMessages this
		doOneCycle (global 'page')
		waitMSecs 10
	}
}

method recordFileTransferMsg SmallRuntime msg {
	// Record a file transfer message sent by board.

	if (notNil fileTransferMsgs) { add fileTransferMsgs msg }
	lastRcvMSecs = (msecsSinceStart)
}

// Script Highlighting

method clearRunningHighlights SmallRuntime {
	chunkRunning = (newArray 256 false) // clear all running flags
	updateHighlights this
}

method updateHighlights SmallRuntime {
	scale = (global 'scale')
	for m (parts (morph (scriptEditor scripter))) {
		if (isClass (handler m) 'Block') {
			if (isRunning this (handler m)) {
				addHighlight m
			} else {
				removeHighlight m
			}
		}
	}
}

method removeResultBubbles SmallRuntime {
	for m (allMorphs (morph (global 'page'))) {
		h = (handler m)
		if (and (isClass h 'SpeechBubble') (isClass (handler (clientMorph h)) 'Block')) {
			removeFromOwner m
		}
	}
}

method showError SmallRuntime chunkID msg {
	showResult this chunkID msg true
}

method showResult SmallRuntime chunkID value isError isResult {
	for m (join
			(parts (morph (scriptEditor scripter)))
			(parts (morph (blockPalette scripter)))) {
		h = (handler m)
		if (and (isClass h 'Block') (chunkID == (lookupChunkID this h))) {
			if (true == isError) {
				showError m value
			} else {
				showHint m value nil false
			}
			if (or (isNil value) ('' == value)) {
				removeHintForMorph (global 'page') m
			} else {
				if (shiftKeyDown (keyboard (global 'page'))) {
					setClipboard (toString value)
				}
			}
			if (and (true == isResult) (h == blockForResultImage)) {
				blockForResultImage = nil
				doOneCycle (global 'page')
				waitMSecs 500 // show result bubble briefly before showing menu
				exportAsImageScaled h value
			}
			if (and (true == isError) (h == blockForResultImage)) {
				blockForResultImage = nil
				doOneCycle (global 'page')
				waitMSecs 500 // show error bubble briefly before showing menu
				exportAsImageScaled h value true
			}
		}
	}
}

method exportScriptImageWithResult SmallRuntime aBlock {
	topBlock = (topBlock aBlock)
	if (isPrototypeHat topBlock) { return }
	blockForResultImage = topBlock
	if (not (isRunning this topBlock)) {
		evalOnBoard this topBlock
	}
}

// Return values

method returnedValue SmallRuntime msg {
	byteCount = (byteCount msg)
	if (byteCount < 7) { return nil } // incomplete msg

	type = (byteAt msg 6)
	if (1 == type) {
		if (byteCount < 10) { return nil } // incomplete msg
		return (+ ((byteAt msg 10) << 24) ((byteAt msg 9) << 16) ((byteAt msg 8) << 8) (byteAt msg 7))
	} (2 == type) {
		return (stringFromByteRange msg 7 (byteCount msg))
	} (3 == type) {
		return (0 != (byteAt msg 7))
	} (4 == type) {
		if (byteCount < 8) { return nil } // incomplete msg
		total = (((byteAt msg 8) << 8) | (byteAt msg 7))
		if (total == 0) { return '[empty list]' }
		sentItems = (readItems this msg)
		out = (list '[')
		for item sentItems {
			add out (toString item)
			add out ', '
		}
		if ((count out) > 1) { removeLast out }
		if (total > (count sentItems)) {
			add out (join ' ... and ' (total - (count sentItems)) ' more')
		}
		add out ']'
		return (joinStrings out)
	} (5 == type) {
		if (byteCount < 9) { return nil } // incomplete msg
		total = (((byteAt msg 8) << 8) | (byteAt msg 7))
		if (total == 0) { return '(empty byte array)' }
		sentCount = (byteAt msg 9)
		sentCount = (min sentCount (byteCount - 9))
		out = (list '(')
		for i sentCount {
			add out (toString (byteAt msg (9 + i)))
			add out ', '
		}
		if ((count out) > 1) { removeLast out }
		if (total > sentCount) {
			add out (join ' ... and ' (total - sentCount) ' more bytes')
		}
		add out ')'
		return (joinStrings out)
	} else {
		print 'Serial error, type: ' type
		return nil
	}
}

method readItems SmallRuntime msg {
	// Read a sequence of list items from the given value message.

	result = (list)
	byteCount = (byteCount msg)
	if (byteCount < 10) { return result } // corrupted msg
	count = (byteAt msg 9)
	i = 10
	repeat count {
		if (byteCount < (i + 1)) { return result } // corrupted msg
		itemType = (byteAt msg i)
		if (1 == itemType) { // integer
			if (byteCount < (i + 4)) { return result } // corrupted msg
			n = (+ ((byteAt msg (i + 4)) << 24) ((byteAt msg (i + 3)) << 16)
					((byteAt msg (i + 2)) << 8) (byteAt msg (i + 1)))
			add result n
			i += 5
		} (2 == itemType) { // string
			len = (byteAt msg (i + 1))
			if (byteCount < (+ i len 1)) { return result } // corrupted msg
			add result (toString (copyFromTo msg (i + 2) (+ i len 1)))
			i += (len + 2)
		} (3 == itemType) { // boolean
			isTrue = ((byteAt msg (i + 1)) != 0)
			add result isTrue
			i += 2
		} (4 == itemType) { // sublist
			if (byteCount < (i + 3)) { return result } // corrupted msg
			n = (+ ((byteAt msg (i + 2)) << 8) (byteAt msg (i + 1)))
			if (0 != (byteAt msg (i + 3))) {
				print 'skipping sublist with non-zero sent items'
				return result
			}
			add result (join '[' n ' item list]')
			i += 4
		} (5 == itemType) { // bytearray
			if (byteCount < (i + 3)) { return result } // corrupted msg
			n = (+ ((byteAt msg (i + 2)) << 8) (byteAt msg (i + 1)))
			if (0 != (byteAt msg (i + 3))) {
				print 'skipping bytearray with non-zero sent items inside a list'
				return result
			}
			add result (join '(' n ' bytes)')
			i += 4
		} else {
			print 'unknown item type in value message:' itemType
			return result
		}
	}
	return result
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

method installVM SmallRuntime eraseFlashFlag downloadLatestFlag {
    closeAllDialogs (findMicroBlocksEditor)
	if ('Browser' == (platform)) {
		installVMInBrowser this eraseFlashFlag downloadLatestFlag
		return
	}
	boards = (collectBoardDrives this)
	if ((count boards) == 1) {
		b = (first boards)
		copyVMToBoard this (first b) (last b)
	} ((count boards) > 1) {
		menu = (menu 'Select board:' this)
		for b boards {
			addItem menu (niceBoardName this b) (action 'copyVMToBoard' this (first b) (last b))
		}
		popUpAtHand menu (global 'page')
	} (notNil boardType) {
		if (and (contains (array 'ESP8266' 'ESP32' 'Citilab ED1' 'M5Stack-Core' 'M5StickC+' 'M5StickC' 'M5Atom-Matrix' '未来科技盒' 'Databot') boardType)
				(confirm (global 'page') nil (join (localized 'Use board type ') boardType '?'))) {
			flashVM this boardType eraseFlashFlag downloadLatestFlag
		} (isOneOf boardType 'CircuitPlayground' 'CircuitPlayground Bluefruit' 'Clue' 'MakerPort') {
			adaFruitResetMessage this
		} (isOneOf boardType 'RP2040' 'Pico W' 'Pico:ed' 'Wukong2040') {
			rp2040ResetMessage this
		}
	} else {
		disconnected = true
		closePort this
		menu = (menu 'Select board type:' this)
		if (not eraseFlashFlag) {
			for boardName (array 'microbit' 'Calliope mini') {
				addItem menu boardName (action 'noBoardFoundMessage' this)
			}
			addLine menu
		}
		for boardName (array 'Citilab ED1' 'M5Stack-Core' 'M5StickC+' 'M5StickC' 'M5Atom-Matrix' '未来科技盒' 'ESP32' 'ESP8266' 'Databot') {
			addItem menu boardName (action 'flashVM' this boardName eraseFlashFlag downloadLatestFlag)
		}
		if (not eraseFlashFlag) {
			addLine menu
			addItem menu 'ELECFREAKS Pico:ed' (action 'rp2040ResetMessage' this)
			addItem menu 'ELECFREAKS Wukong2040' (action 'rp2040ResetMessage' this)
			addItem menu 'RP2040 (Pico or Pico-W)' (action 'rp2040ResetMessage' this)
			addItem menu 'Adafruit Board' (action 'adaFruitResetMessage' this)
			addItem menu 'MakerPort' (action 'adaFruitResetMessage' this)
		}
		popUpAtHand menu (global 'page')
	}
}

method niceBoardName SmallRuntime board {
	name = (first board)
	if (beginsWith name 'MICROBIT') {
		return 'micro:bit'
	} (beginsWith name 'MINI') {
		return 'Calliope mini'
	} (beginsWith name 'CPLAYBOOT') {
		return 'Circuit Playground Express'
	} (beginsWith name 'CPLAYBTBOOT') {
		return 'Circuit Playground Bluefruit'
	} (beginsWith name 'CLUE') {
		return 'Clue'
	} (beginsWith name 'RPI-RP2') {
		return 'Raspberry Pi Pico'
	}
	return name
}

method collectBoardDrives SmallRuntime {
	result = (list)
	if ('Mac' == (platform)) {
		for v (listDirectories '/Volumes') {
			path = (join '/Volumes/' v '/')
			driveName = (getBoardDriveName this path)
			if (notNil driveName) { add result (list driveName path) }
		}
	} ('Linux' == (platform)) {
		// Try both Debian ('/media') and Fedora ('/run/media') variants
		for media (list '/media' '/run/media') {
			for userName (listDirectories media) {
				prefix = (join media '/' userName)
				for v (listDirectories prefix) {
					path = (join prefix '/' v '/')
					driveName = (getBoardDriveName this path)
					if (notNil driveName) { add result (list driveName path) }
				}
			}
		}
	} ('Win' == (platform)) {
		for letter (range 65 90) {
			drive = (join (string letter) ':')
			driveName = (getBoardDriveName this drive)
			if (notNil driveName) { add result (list driveName drive) }
		}
	}
	return result
}

method getBoardDriveName SmallRuntime path {
	for fn (listFiles path) {
		if ('MICROBIT.HTM' == fn) {
			contents = (readFile (join path fn))
			return 'MICROBIT' }
		if (isOneOf fn 'MINI.HTM' 'CALLIOPE.HTM' 'Calliope.html') { return 'MINI' }
		if ('INFO_UF2.TXT' == fn) {
			contents = (readFile (join path fn))
			if (notNil (nextMatchIn 'CPlay Express' contents)) { return 'CPLAYBOOT' }
			if (notNil (nextMatchIn 'Circuit Playground nRF52840' contents)) { return 'CPLAYBTBOOT' }
			if (notNil (nextMatchIn 'Adafruit Clue' contents)) { return 'CLUEBOOT' }
			if (notNil (nextMatchIn 'Adafruit CLUE nRF52840' contents)) { return 'CLUEBOOT' } // bootloader 0.7
			if (notNil (nextMatchIn 'MakerPort' contents)) { return 'MAKERBOOT' }
			if (notNil (nextMatchIn 'RPI-RP2' contents)) { return 'RPI-RP2' }
		}
	}
	return nil
}

method picoVMFileName SmallRuntime {
	tmp = (array nil)
	menu = (menu 'Pico board type?' (action 'atPut' tmp 1) true)
	addItem menu 'ELECFREAKS Pico:ed'
	addItem menu 'ELECFREAKS Wukong2040'
	addItem menu 'RP2040 (Pico or Pico W)'
	waitForSelection menu
	result = (first tmp)
	if ('ELECFREAKS Pico:ed' == result) {
		return 'vm_pico_ed.uf2'
	} ('ELECFREAKS Wukong2040' == result) {
		return 'vm_wukong2040.uf2'
	} ('RP2040 (Pico or Pico W)' == result) {
		return 'vm_pico_w.uf2'
	}
	return 'none'
}

method copyVMToBoard SmallRuntime driveName boardPath {
	// disable auto-connect and close the serial port
	disconnected = true
	closePort this

	if ('MICROBIT' == driveName) {
		vmFileName = 'vm_microbit-universal.hex'
	} ('MINI' == driveName) {
		vmFileName = 'vm_calliope-universal.hex'
	} ('CPLAYBOOT' == driveName) {
		vmFileName = 'vm_circuitplay.uf2'
	} ('CPLAYBTBOOT' == driveName) {
		vmFileName = 'vm_cplay52.uf2'
	} ('CLUEBOOT' == driveName) {
		vmFileName = 'vm_clue.uf2'
	} ('MAKERBOOT' == driveName) {
		vmFileName = 'vm_makerport.uf2'
	} ('RPI-RP2' == driveName) {
		vmFileName = (picoVMFileName this)
	} else {
		print 'unknown drive name in "copyVMToBoard"' // shouldn't happen
		return
	}
	vmData = (readEmbeddedFile (join 'precompiled/' vmFileName) true)
	if (isNil vmData) {
		error (join (localized 'Could not read: ') (join 'precompiled/' vmFileName))
	}
	writeFile (join boardPath vmFileName) vmData
	vmVersion = nil
	print 'Installed' (join boardPath vmFileName) (join '(' (byteCount vmData) ' bytes)')
	waitMSecs 2000
	if (isOneOf driveName 'MICROBIT' 'MINI') { waitMSecs 8000 }
	disconnected = false
}

// Browser Virtual Machine Intaller

method installVMInBrowser SmallRuntime eraseFlashFlag downloadLatestFlag {
	if ('micro:bit' == boardType) {
		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'micro:bit'
	} ('micro:bit v2' == boardType) {
		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'micro:bit v2'
	} (isOneOf boardType 'Calliope' 'Calliope v3') {
		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'Calliope mini'
	} ('CircuitPlayground' == boardType) {
		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'Circuit Playground Express'
	} ('CircuitPlayground Bluefruit' == boardType) {
		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'Circuit Playground Bluefruit'
	} ('Clue' == boardType) {
		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'Clue'
// disable until MakerPort v3 is out
// 	} ('MakerPort' == boardType) {
// 		copyVMToBoardInBrowser this eraseFlashFlag downloadLatestFlag 'MakerPort'
	} (isOneOf boardType 'RP2040' 'Pico W' 'Pico:ed' 'Wukong2040') {
		rp2040ResetMessage this
	} (and
		(isOneOf boardType 'Citilab ED1' 'M5Stack-Core' 'M5StickC+' 'M5StickC' 'M5Atom-Matrix' '未来科技盒' 'ESP32' 'ESP8266' 'Databot')
		(confirm (global 'page') nil (join (localized 'Use board type ') boardType '?'))) {
			flashVM this boardType eraseFlashFlag downloadLatestFlag
	} else {
		menu = (menu 'Select board type:' (action 'copyVMToBoardInBrowser' this eraseFlashFlag downloadLatestFlag) true)
		if eraseFlashFlag {
			// addItem menu 'Citilab ED1'
			addItem menu 'M5Stack-Core'
			addItem menu 'M5StickC+'
			addItem menu 'M5StickC'
			addItem menu 'M5Atom-Matrix'
			addItem menu 'ESP32'
			addItem menu 'ESP8266'
			// addItem menu 'mPython'
			addItem menu '未来科技盒'
			// addItem menu 'Mbits'
		} else {
			addItem menu 'micro:bit'
			// addItem menu 'Calliope mini'
			addLine menu
			addItem menu 'ELECFREAKS Pico:ed'
			addItem menu 'ELECFREAKS Wukong2040'
			addItem menu 'RP2040 (Pico or Pico W)'
			addLine menu
			//addItem menu 'Circuit Playground Express'
			//addItem menu 'Circuit Playground Bluefruit'
			//addItem menu 'Clue'
			//addItem menu 'Metro M0'
			//addLine menu
			addItem menu 'M5Stack-Core'
			addItem menu 'M5StickC+'
			addItem menu 'M5StickC'
			addItem menu 'M5Atom-Matrix'
			addItem menu 'ESP32'
			addItem menu 'ESP8266'
			// addItem menu 'Mbits'
			// addItem menu 'mPython'
			addItem menu '未来科技盒'
		}
		popUpAtHand menu (global 'page')
	}
}

method flashVMInBrowser SmallRuntime boardName eraseFlashFlag downloadLatestFlag {
	if (isNil port) {
		// prompt user to open the serial port
		selectPort this
		timeout = 10000 // ten seconds
		start = (msecsSinceStart)
		while (and (not (isOpenSerialPort 1)) (((msecsSinceStart) - start) < timeout)) {
			// do UI cycles until serial port is opened or timeout
			doOneCycle (global 'page')
			waitMSecs 10 // refresh screen
		}
	}
	if (isOpenSerialPort 1) {
		port = 1
		flashVM this boardName eraseFlashFlag downloadLatestFlag
	}
}

method copyVMToBoardInBrowser SmallRuntime eraseFlashFlag downloadLatestFlag boardName {
	if (isOneOf boardName 'Citilab ED1' 'M5Stack-Core' 'M5StickC+' 'M5StickC' 'M5Atom-Matrix' '未来科技盒' 'ESP32' 'ESP8266' 'Databot') {
		flashVMInBrowser this boardName eraseFlashFlag downloadLatestFlag
		return
	}

	if ('micro:bit' == boardName) {
		vmFileName = 'vm_microbit-universal.hex'
		driveName = 'MICROBIT'
	} ('micro:bit v2' == boardName) {
		vmFileName = 'vm_microbit-universal.hex'
		driveName = 'MICROBIT'
	} ('Calliope mini' == boardName) {
		vmFileName = 'vm_calliope-universal.hex'
		driveName = 'MINI'
	} ('Calliope v3' == boardName) {
		vmFileName = 'vm_calliope-universal.hex'
		driveName = 'MINI'
	} ('Circuit Playground Express' == boardName) {
		vmFileName = 'vm_circuitplay.uf2'
		driveName = 'CPLAYBOOT'
	} ('Circuit Playground Bluefruit' == boardName) {
		vmFileName = 'vm_cplay52.uf2'
		driveName = 'CPLAYBTBOOT'
	} ('Clue' == boardName) {
		vmFileName = 'vm_clue.uf2'
		driveName = 'CLUEBOOT'
	} ('MakerPort' == boardName) {
		vmFileName = 'vm_makerport.uf2'
		driveName = 'MAKERBOOT'
	} ('RP2040 (Pico or Pico W)' == boardName) {
		vmFileName = 'vm_pico_w.uf2'
		driveName = 'RPI-RP2'
	} ('ELECFREAKS Pico:ed' == boardName) {
		vmFileName = 'vm_pico_ed.uf2'
		driveName = 'RPI-RP2'
	} ('ELECFREAKS Wukong2040' == boardName) {
		vmFileName = 'vm_wukong2040.uf2'
		driveName = 'RPI-RP2'
	} else {
		return // bad board name
	}

	prefix = ''
	if (endsWith vmFileName '.uf2') {
		if ('RPI-RP2' == driveName) {
			// Extra instruction for RP2040 Pico
			prefix = (join
				prefix
				(localized 'Connect USB cable while holding down the white BOOTSEL button before proceeding.')
				(newline) (newline))
		} ('MAKERBOOT' == driveName) {
			// Extra instruction for MakerPort
			prefix = (join
				prefix
				(localized 'Press the reset button on the board twice before proceeding.')
				(newline) (newline))
		} else {
			// Extra instruction for Adafruit boards
			prefix = (join
				prefix
				(localized 'Press the reset button on the board twice before proceeding. The NeoPixels should turn green.')
				(newline) (newline))
		}
	}
	msg = (join prefix (localized 'Save the firmware file when prompted.'))
	response = (inform msg (localized 'Firmware Install'))
	if (isNil response) { return }

	vmData = (readFile (join 'precompiled/' vmFileName) true)
	if (isNil vmData) { return } // could not read file

	// disconnect before updating VM; avoids micro:bit autoconnect issue on Chromebooks
	disconnected = true
	closePort this
	updateIndicator (findMicroBlocksEditor)

	if (endsWith vmFileName '.hex') {
		// for micro:bit & calliope, filename must be less than 9 letter before the extension
		filePart = (filePart vmFileName)
		vmFileName = (join (substring filePart 1 (min 9 (count filePart))) '.hex')
	}

	browserWriteFile vmData vmFileName 'vmInstall'
    waitMSecs 5000 // leave time for file to download before showing next prompt

    inform (join (localized 'Drag the firmware file you just saved to the') ' ' driveName ' ' (localized 'drive') '.')
    waitMSecs 1000 // leave time for file dialog box to appear before showing next prompt

	if (endsWith vmFileName '.uf2') {
		if (or ('MAKERBOOT' == driveName) ('RPI-RP2' == driveName)) {
			otherReconnectMessage this
		} else {
			adaFruitReconnectMessage this
		}
	} else {
	    otherReconnectMessage this
	}
}

method noBoardFoundMessage SmallRuntime {
	inform (localized 'No boards found; is your board plugged in?') 'No boards found'
}

method adaFruitResetMessage SmallRuntime {
	inform (localized 'For Adafruit boards and MakerPort, double-click reset button and try again.')
}

method adaFruitReconnectMessage SmallRuntime {
	msg = (join
		(localized 'When the NeoPixels turn off') ', '
		(localized 'reconnect to the board by clicking the "Connect" button (USB icon).'))
	inform msg
}

method rp2040ResetMessage SmallRuntime {
	inform (localized 'Connect USB cable while holding down the white BOOTSEL button and try again.')
}

method otherReconnectMessage SmallRuntime {
	title = (localized 'Firmware Installed')
	msg = (localized 'Reconnect to the board by clicking the "Connect" button (USB icon).')
	inform (global 'page') msg title nil true
}

// Countdown for firmware install on nRF5x boards; not currently used

method waitForFirmwareInstall SmallRuntime {
	firmwareInstallTimer = nil
	spinner = (newSpinner (action 'firmwareInstallStatus' this) (action 'firmwareInstallDone' this))
	addPart (global 'page') spinner
}

method startFirmwareCountdown SmallRuntime fileName {
	// Called by editor after firmware file is saved.

	if ('_no_file_selected_' == fileName) {
		spinner = (findMorph 'MicroBlocksSpinner')
		if (notNil spinner) { destroy (handler spinner) }
	} else {
		firmwareInstallTimer = (newTimer)
	}
}

method firmwareInstallSecsRemaining SmallRuntime {
	if (isNil firmwareInstallTimer) { return 0 }
	installWaitMSecs = 6000
	if (and ('Browser' == (platform)) (browserIsChromeOS)) {
		installWaitMSecs = 16000
	}
	return (ceiling ((installWaitMSecs - (msecs firmwareInstallTimer)) / 1000))
}

method firmwareInstallStatus SmallRuntime {
	if (isNil firmwareInstallTimer) { return 'Installing firmware...' }
	return (join '' (firmwareInstallSecsRemaining this) ' ' (localized 'seconds remaining') '.')
}

method firmwareInstallDone SmallRuntime {
	if (isNil firmwareInstallTimer) { return false }

	if ((firmwareInstallSecsRemaining this) <= 0) {
		firmwareInstallTimer = nil
		otherReconnectMessage this
		return true
	}
	return false
}

// espressif board flashing

method flasher SmallRuntime { return flasher }

method confirmRemoveFlasher SmallRuntime { // xxx needed?
	ok = (confirm
		(global 'page')
		nil
		(localized 'Are you sure you want to cancel the upload process?'))
	if ok { removeFlasher this }
}

method removeFlasher SmallRuntime {
	destroy flasher
	flasher = nil
}

method flashVM SmallRuntime boardName eraseFlashFlag downloadLatestFlag {
	if ('Browser' == (platform)) {
		disconnected = true
		flasherPort = port
		port = nil
		// workaround for ESP32 install issue introduced in 1.2.89:
		flasherPort = nil
		portName = 'webserial'
	} else {
		setPort this 'disconnect'
		flasherPort = nil
	}
	flasher = (newFlasher boardName portName eraseFlashFlag downloadLatestFlag)
	addPart (global 'page') (spinner flasher)
	startFlasher flasher flasherPort
}

// data logging

method lastDataIndex SmallRuntime { return loggedDataNext }

method clearLoggedData SmallRuntime {
	loggedData = (newArray 10000)
	loggedDataNext = 1
	loggedDataCount = 0
}

method addLoggedData SmallRuntime s {
	atPut loggedData loggedDataNext s
	loggedDataNext = ((loggedDataNext % (count loggedData)) + 1)
	if (loggedDataCount < (count loggedData)) { loggedDataCount += 1 }
}

method loggedData SmallRuntime howMany {
	if (or (isNil howMany) (howMany > loggedDataCount)) {
		howMany = loggedDataCount
	}
	result = (newArray howMany)
	start = (loggedDataNext - howMany)
	if (start > 0) {
		replaceArrayRange result 1 howMany loggedData start
	} else {
		tailCount = (- start)
		tailStart = (((count loggedData) - tailCount) + 1)
		replaceArrayRange result 1 tailCount loggedData tailStart
		replaceArrayRange result (tailCount + 1) howMany loggedData 1
	}
	return result
}

// Install ESP firmware from URL

method installESPFirmwareFromURL SmallRuntime {
	defaultURL = ''
	if ('Databot' == boardType) {
		defaultURL = 'http://microblocks.fun/downloads/databot/databot2.0_V2.18.bin'
	}
	url = (trim (freshPrompt (global 'page') 'ESP32 firmware URL?' defaultURL))
	if ('' == url) { return }

	if ('Browser' == (platform)) {
		disconnected = true
		flasherPort = port
		port = nil
	} else {
		setPort this 'disconnect'
		flasherPort = nil
	}
	flasher = (newFlasher boardName portName false false)
	installFromURL flasher flasherPort url
}

// Install ESP firmware from file

method installESPFirmwareFromFile SmallRuntime fileName data {
	if ('Browser' == (platform)) {
		disconnected = true
		flasherPort = port
		port = nil
	} else {
		setPort this 'disconnect'
		flasherPort = nil
	}
	flasher = (newFlasher fileName portName false false)
	installFromData flasher flasherPort fileName data
}
