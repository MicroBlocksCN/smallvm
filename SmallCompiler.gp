// SmallCompiler.gp - A blocks compiler for SmallVM
// John Maloney, April, 2017

to smallRuntime {
	if (isNil (global 'smallRuntime')) {
		setGlobal 'smallRuntime' (new 'SmallRuntime')
	}
	return (global 'smallRuntime')
}

defineClass SmallRuntime port chunkIDs recvBuf msgDict

method evalOnArduino SmallRuntime aBlock showBytes {
	if (isNil showBytes) { showBytes = false }
	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler (expression aBlock))
	bytes = (list)
	for item code {
		if (isClass item 'Array') {
			addBytesForInstructionTo compiler item bytes
		} (isClass item 'Integer') {
			addBytesForIntegerTo compiler item bytes
		} (isClass item 'String') {
			addBytesForStringLiteral compiler item bytes
		} else {
			error 'Instruction must be an Array or String:' item
		}
	}
	id = (chunkIdFor this aBlock)
	if showBytes {
		print (join 'Bytes for chunk ' id ':') bytes
		print '----------'
		return
	}
	saveChunk this id 1 bytes
	runChunk this id
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
			if (1 == (arg & 1)) { arg = (arg >> 1) } // decode integer
			if (2 == arg) { arg = true }
			if (4 == arg) { arg = false }
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

method sendPing SmallRuntime {
	ensurePortOpen this
	sendMsg this 'showChunksMsg'
	sendMsg this 'showTasksMsg'
	showResult this // show results when called from command line
}

method sendStopAll SmallRuntime {
	ensurePortOpen this
	sendMsg this 'stopAllMsg'
}

method resetArduino SmallRuntime {
	// Reset the Arduino by closing the serial port, opening it
	// at 1200 baud, then closing and reopening the port.

	if (notNil port) { closeSerialPort port }
	port = (openSerialPort '/dev/tty.usbmodem1422' 1200)
	closeSerialPort port
	port = nil
	ensurePortOpen this
}

method saveChunk SmallRuntime chunkID chunkType bytes {
	ensurePortOpen this
	byteCount = ((count bytes) + 1)
	// msg body is: <chunkType (1 byte)> <instruction data>
	msg = (list 2 chunkID (byteCount & 255) ((byteCount >> 8) & 255) chunkType)
	addAll msg bytes
	writeSerialPort port (toBinaryData (toArray msg))
}

method runChunk SmallRuntime chunkID {
	sendMsg this 'startChunkMsg' chunkID
}

method msgNameToID SmallRuntime msgName {
	if (isNil msgDict) {
		msgDict = (dictionary)
		atPut msgDict 'storeChunkMsg' 2
		atPut msgDict 'deleteChunkMsg' 3
		atPut msgDict 'startAllMsg' 4
		atPut msgDict 'stopAllMsg' 5
		atPut msgDict 'startChunkMsg' 6
		atPut msgDict 'stopChunkMsg' 7
		atPut msgDict 'getTaskStatusMsg' 8
		atPut msgDict 'getOutputMsg' 10
		atPut msgDict 'getReturnValueMsg' 12
		atPut msgDict 'getErrorIPMsg' 14
		atPut msgDict 'showChunksMsg' 16
		atPut msgDict 'showTasksMsg' 17
	}
	msgID = (at msgDict msgName)
	if (isNil msgID) { error 'Unknown message:' msgName }
	return msgID
}

method sendMsg SmallRuntime msgName chunkID byteList {
	if (isNil chunkID) { chunkID = 0 }
	if (isNil byteList) { byteList = (list) }
	msgID = (msgNameToID this msgName)
	byteCount = (count byteList)
	msg = (list msgID chunkID (byteCount & 255) ((byteCount >> 8) & 255))
	addAll msg byteList
	ensurePortOpen this
	writeSerialPort port (toBinaryData (toArray msg))
}

method ensurePortOpen SmallRuntime {
	if (isNil port) {
		port = (openSerialPort '/dev/tty.usbmodem1422' 9600)
	}
}

method showResult SmallRuntime {
	lastReadTime = (msecsSinceStart)
	while (((msecsSinceStart) - lastReadTime) < 1000) {
		showOutput this
		waitMSecs 50
	}
}

method showOutput SmallRuntime {
	if (isNil port) { return }
//	sendMsg this 'getOutputMsg'  // xxx using direct terminal output for now
	s = (readSerialPort port)
	if (notNil s) {
		if (isNil recvBuf) { recvBuf = '' }
		recvBuf = (join recvBuf s)
		while (notNil (findFirst recvBuf (newline))) {
			i = (findFirst recvBuf (newline))
			out = (substring recvBuf 1 (i - 2))
			recvBuf = (substring recvBuf (i + 1))
			print out
		}
	}
}

method addArduinoBlocks SmallRuntime {
	authoringSpecs = (authoringSpecs)
	if (isEmpty (specsFor authoringSpecs 'Arduino')) {
		addSpecs authoringSpecs (arduinoSpecs this)
	}
}

method arduinoSpecs SmallRuntime {
	return (array
	'Arduino'
		(array ' ' 'printIt'			'print _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 'Hello, Arduino!')
		(array 'r' 'analogReadOp'		'read analog pin _' 'num' 1)
		(array ' ' 'analogWriteOp'		'set analog pin _ to _' 'num num' 1 1023)
		(array 'r' 'digitalReadOp'		'read digital pin _' 'num' 1)
		(array ' ' 'digitalWriteOp'		'set digital pin _ to _' 'num bool' 1 true)
		(array ' ' 'setLEDOp'			'set user LED _' 'bool' true)
		(array 'r' 'microsOp'			'micros')
		(array 'r' 'millisOp'			'millis')
		(array ' ' 'noop'				'no op')
		(array 'r' 'peekOp'				'memory at _' 'num' 0)
		(array ' ' 'pokeOp'				'set memory at _ to _' 'num num' 0 0)
	'Control_' // Arduinio control blocks
		(array ' ' 'animate'			'forever _' 'cmd')
		(array ' ' 'if'					'if _ _ : else if _ _ : ...' 'bool cmd bool cmd')
		(array ' ' 'repeat'				'repeat _ _' 'num cmd' 10)
		(array ' ' 'halt'				'stop this task')
		(array ' ' 'stopAll'			'stop all')
		(array ' ' 'return'				'return _' 'auto')
		(array ' ' 'waitMicrosOp'		'wait _ microsecs' 'num' 10000)
		(array ' ' 'waitMillisOp'		'wait _ millisecs' 'num' 500)
		(array 'h' 'whenStarted'		'when started')
		(array 'h' 'whenCondition'		'when _' 'bool')
	'Math' // Arduinio math blocks
		(array 'r' 'add'				'_ + _ : + _ : ...' 'num num num' 10 2 10)
		(array 'r' 'subtract'			'_ − _' 'num num' 10 2)
		(array 'r' 'multiply'			'_ × _ : × _ : ...' 'num num num' 10 2 10)
		(array 'r' 'divide'				'_ / _' 'num num' 10 2)
		(array 'r' 'lessThan'			'_ < _' 'num num' 3 4)
	'Arrays'
		(array 'r' 'newArray'			'new array _' 'num' 10)
		(array 'r' 'newByteArray'		'new byte array _' 'num' 10)
		(array ' ' 'fillArray'			'fill array _ with _' 'num auto' nil 0)
		(array 'r' 'at'					'array _ at _' 'auto num' nil 1)
		(array ' ' 'atPut'				'set array _ at _ to _' 'num num' nil 1 10)
	)
}

defineClass SmallCompiler opcodes globals trueObj falseObj

method initialize SmallCompiler {
	initOpcodes this
	globals = (dictionary)
	trueObj = 4
	falseObj = 8
	return this
}

method initOpcodes SmallCompiler {
	// Initialize the opcode dictionary by parsing definitions copied and pasted from interp.h

	defsFromHeaderFile = '
#define halt 0
#define noop 1
#define pushImmediate 2 // true, false, and ints that fit in 24 bits
#define pushBigImmediate 3 // ints that do not fit in 24 bits (and later, floats)
#define pushLiteral 4 // string or array constant from literals frame
#define pushVar 5
#define popVar 6
#define incrementVar 7
#define pushArgCount 8
#define pushArg 9
#define pushLocal 10
#define popLocal 11
#define incrementLocal 12
#define pop 13
#define jmp 14
#define jmpTrue 15
#define jmpFalse 16
#define decrementAndJmp 17
#define callFunction 18
#define returnResult 19
#define waitMicrosOp 20
#define waitMillisOp 21
#define printIt 22
#define stopAll 23
#define add 24
#define subtract 25
#define multiply 26
#define divide 27
#define lessThan 28
#define newArray 29
#define newByteArray 30
#define fillArray 31
#define at 32
#define atPut 33
#define analogReadOp 34
#define analogWriteOp 35
#define digitalReadOp 36
#define digitalWriteOp 37
#define setLEDOp 38
#define microsOp 39
#define millisOp 40
#define peekOp 41
#define pokeOp 42
'
	opcodes = (dictionary)
	for line (lines defsFromHeaderFile) {
		words = (words line)
		if (and ((count words) > 2) ('#define' == (first words))) {
			atPut opcodes (at words 2) (toInteger (at words 3))
		}
	}
}

method instructionsFor SmallCompiler cmdOrReporter {
	// Return a list of instructions for stack of blocks or a reporter.
	// Add a 'halt' if needed and append any literals (e.g. strings) used.

	if (isClass cmdOrReporter 'Command') {
		result = (instructionsForCmdList this cmdOrReporter)
	} else {
		result = (instructionsForCmdList this (newReporter 'return' cmdOrReporter))
	}
	add result (array 'halt' 0)
	if (and
		((count result) == 2)
		(isOneOf (first (first result)) 'halt' 'stopAll')) {
			// In general, just looking at the final instructon isn't enough because
			// it could just be the end of a conditional body that is jumped
			// over; in that case, we need the final halt as the jump target.
			removeLast result // remove the final halt
	}
	appendLiterals this result
	return result
}

method instructionsForCmdList SmallCompiler cmdList {
	result = (list)
	cmd = cmdList
	while (notNil cmd) {
		addAll result (instructionsForCmd this cmd)
		cmd = (nextBlock cmd)
	}
	return result
}

method instructionsForCmd SmallCompiler cmd {
	result = (list)
	op = (primName cmd)
	args = (argList cmd)
	if (isOneOf op '=' 'local') {
		addAll result (instructionsForExpression this (at args 2))
		add result (array 'popVar' (globalVarIndex this (first args)))
	} ('+=' == op) {
		addAll result (instructionsForExpression this (at args 2))
		add result (array 'incrementVar' (globalVarIndex this (first args)))
	} ('return' == op) {
		if (0 == (count args)) {
			add result (array 'pushImmediate' 1)
		} else {
			addAll result (instructionsForExpression this (at args 1))
		}
		add result (array 'returnResult' 0)
	} ('if' == op) {
		return (instructionsForIf this args)
	} ('animate' == op) { // forever loop
		return (instructionsForForever this args)
	} ('repeat' == op) {
		return (instructionsForRepeat this args)
	} ('whenCondition' == op) {
		return (instructionsForWhenCondition this args)
	} ('whenStarted' == op) {
		return (list)
	} else {
		return (primitive this op args true)
	}
	return result
}

method instructionsForIf SmallCompiler args {
	result = (list)
	jumpsToFix = (list)
	i = 1
	while (i < (count args)) {
		finalCase = ((i + 2) >= (count args)) // true if this is the final case in the if statement
		test = (at args i)
		body = (instructionsForCmdList this (at args (i + 1)))
		if (true != test) {
			addAll result (instructionsForExpression this test)
			offset = (count body)
			if (not finalCase) { offset += 1 }
			add result (array 'jmpFalse' offset)
		}
		addAll result body
		if (not finalCase) {
			jumpToEnd = (array 'jmp' (count result)) // jump offset to be fixed later
			add jumpsToFix jumpToEnd
			add result jumpToEnd
		}
		i += 2
	}
	instructionCount = (count result)
	for jumpInstruction jumpsToFix {
		atPut jumpInstruction 2 (instructionCount - ((at jumpInstruction 2) + 1)) // fix jump offset
	}
	return result
}

method instructionsForForever SmallCompiler args {
	result = (instructionsForCmdList this (at args 1))
	add result (array 'jmp' (0 - ((count result) + 1)))
	return result
}

method instructionsForRepeat SmallCompiler args {
	result = (instructionsForExpression this (at args 1)) // loop count
	body = (instructionsForCmdList this (at args 2))
	addAll result body
	add result (array 'decrementAndJmp' (0 - ((count body) + 1)))
	return result
}

method instructionsForWhenCondition SmallCompiler args {
	result = (instructionsForExpression this (at args 1)) // evaluate condition
	add result (array 'jumpFalse' (0 - ((count result) + 1)))
	return result
}

method instructionsForExpression SmallCompiler expr {
	// immediate values
	if (true == expr) {
		return (list (array 'pushImmediate' trueObj))
	} (false == expr) {
		return (list (array 'pushImmediate' falseObj))
	} (isNil expr) {
		return (list (array 'pushImmediate' 1)) // the integer zero
	} (isClass expr 'Integer') {
		if (and (-8388608 <= expr) (expr < 8388607)) {
			return (list (array 'pushImmediate' (((expr << 1) | 1) & (hex 'FFFFFF')) ))
		} else {
			return (list
				(array 'pushBigImmediate' 0)
				((expr << 1) | 1)) // 32-bit integer objects follows pushBigImmediate instruction
		}
	} (isClass expr 'String') {
		return (list (array 'pushLiteral' expr))
	} (isClass expr 'Float') {
		error 'Floats are not yet supported'
	}

	// expressions
	op = (primName expr)
	args = (argList expr)
	if ('v' == op) {
		return (list (array 'pushVar' (globalVarIndex this (first args))))
	} else {
		return (primitive this op args false)
	}
}

method primitive SmallCompiler op args isCommand {
	result = (list)
	if ('print' == op) { op = 'printIt' }
	if (contains opcodes op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array op (count args))
		if (and isCommand (not (isOneOf op 'halt' 'stopAll')))  {
			add result (array 'pop' 1)
		}
	} else {
		print 'Skipping unknown op:' op
	}
	return result
}

method globalVarIndex SmallCompiler varName {
	id = (at globals varName nil)
	if (isNil id) {
		id = (count globals) // zero-based index
		atPut globals varName id
	}
	return id
}

method appendLiterals SmallCompiler instructions {
	// For now, strings are the only literals. May add literal arrays later.

	literals = (list)
	literalOffsets = (dictionary)
	nextOffset = (count instructions)
	for ip (count instructions) {
		instr = (at instructions ip)
		if (and (isClass instr 'Array') ('pushLiteral' == (first instr))) {
			literal = (at instr 2)
			litOffset = (at literalOffsets literal)
			if (isNil litOffset) {
				litOffset = nextOffset
				add literals literal
				atPut literalOffsets literal litOffset
				nextOffset += (wordsForLiteral this literal)
			}
			atPut instr 2 (litOffset - ip)
		}
	}
	addAll instructions literals
}

method wordsForLiteral SmallCompiler literal {
	headerWords = 1
	if (isClass literal 'String') {
		return (headerWords + (floor (((byteCount literal) + 4) / 4)))
	}
	error 'Illegal literal type:' literal
}

method addBytesForInstructionTo SmallCompiler instr bytes {
	// Append the bytes for the given instruction to bytes (little endian).

	add bytes (at opcodes (first instr))
	arg = (at instr 2)
	if (not (and (-16777216 <= arg) (arg <= 16777215))) {
		error 'Argument does not fit in 24 bits'
	}
	add bytes (arg & 255)
	add bytes ((arg >> 8) & 255)
	add bytes ((arg >> 16) & 255)
}

method addBytesForIntegerTo SmallCompiler n bytes {
	// Append the bytes for the given integer to bytes (little endian).

	add bytes (n & 255)
	add bytes ((n >> 8) & 255)
	add bytes ((n >> 16) & 255)
	add bytes ((n >> 24) & 255)
}

method addBytesForStringLiteral SmallCompiler s bytes {
	// Append the bytes for the given string to bytes.

	byteCount = (byteCount s)
	wordCount = (floor ((byteCount + 4) / 4))
	headerWord = ((wordCount << 4) | 5);
	repeat 4 { // add header bytes, little endian
		add bytes (headerWord & 255)
		headerWord = (headerWord >> 8)
	}
	for i byteCount {
		add bytes (byteAt s i)
	}
	repeat (4 - (byteCount % 4)) { // pad with zeros to next word boundary
		add bytes 0
	}
}

// Patches to Block and Scripter

method blockColorForCategory AuthoringSpecs cat {
  defaultColor = (color 4 148 220)
  if (isOneOf cat 'Control' 'Functions' 'Control_') {
	if (notNil (global 'controlColor')) { return (global 'controlColor') }
	return (color 230 168 34)
  } ('Variables' == cat) {
	if (notNil (global 'variableColor')) { return (global 'variableColor') }
	return (color 243 118 29)
  } (isOneOf cat 'Operators' 'Math') {
	if (notNil (global 'operatorsColor')) { return (global 'operatorsColor') }
	return (color 98 194 19)
  }
  if (notNil (global 'defaultColor')) { return (global 'defaultColor') }
  return defaultColor
}

method contextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
  isInPalette = ('template' == (grabRule morph))
// xxx
addItem menu 'show instructions' 'showInstructions'
addItem menu 'show compiled bytes' 'showCompiledBytes'
addLine menu

  if (isVariadic this) {
    if (canExpand this) {addItem menu 'expand' 'expand'}
    if (canCollapse this) {addItem menu 'collapse' 'collapse'}
    addLine menu
  }
  if (and isInPalette (isRenamableVar this)) {
    addItem menu 'rename...' 'userRenameVariable'
    addLine menu
  }
  addItem menu 'duplicate' 'grabDuplicate' 'just this one block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu '...all' 'grabDuplicateAll' 'duplicate including all attached blocks'
  }
  addItem menu 'copy to clipboard' 'copyToClipboard'

  if (not isInPalette) {
    addLine menu
    addItem menu 'delete' 'delete'
  }
  return menu
}

method showInstructions Block { showInstructions (smallRuntime) this }
method showCompiledBytes Block { evalOnArduino (smallRuntime) this true }

method contextMenu BlockDefinition {
  menu = (menu nil this)
 // xxx
addItem menu 'show instructions' 'showInstructions'
addItem menu 'show compiled bytes' 'showCompiledBytes'
addLine menu
 if isShort {
    addItem menu 'show details' 'showDetails'
  } else {
    addItem menu 'hide details' 'hideDetails'
  }
  addLine menu
  for tp (array 'command' 'reporter') {
    addItem menu '' (action 'setType' this tp) tp (fullCostume (morph (block tp (color 4 148 220) '                    ')))
  }
  addLine menu
  addItem menu 'delete' 'deleteDefinition'
  if (devMode) {
   addItem menu 'set method name' 'setMethodNameUI'
  }
  popUp menu (global 'page') (left morph) (bottom morph)
}

method showInstructions BlockDefinition { showInstructions (smallRuntime) (functionNamed op) }
method showCompiledBytes BlockDefinition { evalOnArduino (smallRuntime) this true }

method clicked Block hand {
  evalOnArduino (smallRuntime) (topBlock this)
}

method devModeCategories Scripter {
	return (userModeCategories this)
}

method userModeCategories Scripter {
	addArduinoBlocks (new 'SmallRuntime')
	return (array 'Control_' 'Arduino' 'Math' 'Arrays' 'Variables' 'My Blocks')
}

method addVariableBlocks Scripter {
  scale = (global 'scale')
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (-3 * scale))

  addSectionLabel this 'Shared Variables'
  addButton this 'Add a shared variable' (action 'createSharedVariable' this) 'A shared variable is visible to all scripts in all classes. Any script can view or change shared variables, making them useful for things like game scores.'
  sharedVars = (sharedVars this)
  if (notEmpty sharedVars) {
	addButton this 'Delete a shared variable' (action 'deleteSharedVariable' this)
	nextY += (8 * scale)
	for varName sharedVars {
	  lastY = nextY
	  b = (toBlock (newReporter 'shared' varName))
	  addBlock this b nil true
	  readout = (makeMonitor b)
	  setGrabRule (morph readout) 'ignore'
	  setStyle readout 'varPane'
	  setPosition (morph readout) nextX lastY
	  addPart (morph (contents blocksFrame)) (morph readout)
	  step readout
	  refIcon = (initialize (new 'MorphRefIcon') varName nil (targetModule this))
	  setPosition (morph refIcon) (nextX + (114 * scale)) (lastY + (5 * scale))
	  addPart (morph (contents blocksFrame)) (morph refIcon)
	}
	nextY += (5 * scale)
	addBlock this (toBlock (newCommand 'setShared' (first sharedVars) 0)) nil false
	addBlock this (toBlock (newCommand 'increaseShared' (first sharedVars) 1)) nil false
  }

  addSectionLabel this 'Script Variables'
  nextY += (2 * scale)
  addBlock this (toBlock (newCommand 'local' 'var' 0)) nil false
  addBlock this (toBlock (newCommand '=' 'var' 0)) nil false
  addBlock this (toBlock (newCommand '+=' 'var' 1)) nil false
}

method addMyBlocks Scripter {
  scale = (global 'scale')
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (16 * scale))

  addButton this 'Make a block' (action 'createSharedBlock' this)
  nextY += (8 * scale)

  for f (functions (targetModule this)) {
	spec = (specForOp (authoringSpecs) (functionName f))
	if (isNil spec) { spec = (blockSpecFor f) }
	addBlock this (blockForSpec spec) spec
  }
}

method step ProjectEditor {
  if ('Browser' == (platform)) { processImportedFiles this }
  processDroppedFiles this
  if (isNil fpsReadout) { return }
  frameCount += 1
  msecs = ((msecsSinceStart) - lastFrameTime)
  if (and (frameCount > 2) (msecs > 200)) {
	fps = ((1000 * frameCount) / msecs)
	setText fpsReadout (join '' (round fps 0.1) ' fps')
	lastFrameTime = (msecsSinceStart)
	frameCount = 0
  }
  showOutput (smallRuntime)
}

method contextMenu ScriptEditor {
  menu = (menu nil this)
  // Arudino additions to background menu
  addItem menu 'Arduino stop all' (action 'sendStopAll' (smallRuntime))
  addItem menu 'Arduino status' (action 'sendPing' (smallRuntime))
  addLine menu
  addItem menu 'Arduino reset and clear' (action 'resetArduino' (smallRuntime))
  addLine menu
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  if (and (notNil lastDrop) (isRestorable lastDrop)) {
    addItem menu 'undrop' 'undrop' 'undo last drop'
  }
  addLine menu
  addItem menu 'copy all scripts to clipboard' 'copyScriptsToClipboard'
  clip = (getClipboard)
  if (beginsWith clip 'GP Scripts') {
	addItem menu 'paste scripts' 'pasteScripts'
  } (beginsWith clip 'GP Script') {
	addItem menu 'paste script' 'pasteScripts'
  }
  cb = (ownerThatIsA morph 'ClassBrowser')
  if (notNil cb) {
    if (wasEdited (handler cb)) {
      addLine menu
      addItem menu 'save changes' (action 'saveEditedFunction' (handler cb))
    }
  }
  return menu
}
