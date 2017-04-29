// SmallCompiler.gp - A blocks compiler for SmallVM
// John Maloney, April, 2017

to compileSmallVM cmdOrReporter {
	// Print the instructions.

	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler cmdOrReporter)
	for item code {
		if (and (isClass item 'Array') ('pushImmediate' == (first item))) {
			arg = (at item 2)
			if (1 == (arg & 1)) { arg = (arg >> 1) } // decode integer
			print (array 'pushImmediate' arg)
		} else {
			print item
		}
	}
	print '----------'
}

to evalOnArduino cmdOrReporter {
	evalOnArduino (new 'SmallRuntime') cmdOrReporter
}

defineClass SmallRuntime port codeChunks

method evalOnArduino SmallRuntime cmdOrReporter {
	compiler = (initialize (new 'SmallCompiler'))
	code = (instructionsFor compiler cmdOrReporter)
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
print bytes
sendMsg this bytes
return
	saveChunkForBlock this cmdOrReporter
//	sendMsg bytes
}

method saveChunkForBlock SmallRuntime cmdOrReporter {
	if (isNil codeChunks) { codeChunks = (dictionary) }
	entry = (at codeChunks cmdOrReporter nil)
	if (isNil entry) {
		id = (count codeChunks)
		entry = (array id cmdOrReporter)
		atPut codeChunks entry
	}
}

method sendMsg SmallRuntime byteList {
	msg = (list 17 42 0 (count byteList))
	addAll msg byteList
	port = (openSerialPort '/dev/tty.usbmodem1422' 9600)
	writeSerialPort port (toBinaryData (toArray msg))
	monitorSerial this
	closeSerialPort port
}

method monitorSerial SmallRuntime {
	buf = ''
	while true {
		s = (readSerialPort port)
		if (notNil s) {
			buf = (join buf s)
			while (notNil (findFirst buf (newline))) {
				i = (findFirst buf (newline))
				out = (substring buf 1 (i - 2))
				buf = (substring buf (i + 1))
				if ((count (words out)) > 0) { print out }
				if (beginsWith out 'uBlocks>') { return }
			}
		}
		waitMSecs 10
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
		(array 'r' 'analogRead'			'read analog pin _' 'num' 1)
		(array ' ' 'analogWrite'		'set analog pin _ to _' 'num num' 1 1023)
		(array 'r' 'digitalRead'		'read digital pin _' 'num' 1)
		(array ' ' 'digitalWrite'		'set digital pin _ to _' 'num bool' 1 true)
		(array 'r' 'micros'				'micros')
		(array 'r' 'millis'				'millis')
		(array ' ' 'noop'				'no op')
		(array 'r' 'peek'				'memory at _' 'num' 0)
		(array ' ' 'poke'				'set memory at _ to _' 'num num' 0 0)
	'Control_' // Arduinio control blocks
		(array ' ' 'animate'			'forever _' 'cmd')
		(array ' ' 'if'					'if _ _ : else if _ _ : ...' 'bool cmd bool cmd')
		(array ' ' 'repeat'				'repeat _ _' 'num cmd' 10)
		(array ' ' 'halt'				'stop this task')
		(array ' ' 'self_stopAll'		'stop all')
		(array ' ' 'return'				'return _' 'auto')
		(array 'h' 'whenStarted'		'when started')
		(array 'h' 'whenCondition'		'when _' 'bool')
	'Math' // Arduinio math blocks
		(array 'r' 'add'				'_ + _ : + _ : ...' 'num num num' 10 2 10)
		(array 'r' 'subtract'			'_ − _' 'num num' 10 2)
		(array 'r' 'multiply'			'_ × _ : × _ : ...' 'num num num' 10 2 10)
		(array 'r' 'divide'				'_ / _' 'num num' 10 2)
		(array 'r' 'lessThan'			'_ < _' 'num num' 3 4)
	)
}

defineClass SmallCompiler opcodes globals trueObj falseObj

method initialize SmallCompiler {
	initOpcodes this
	globals = (dictionary)
	trueObj = 2
	falseObj = 4
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
#define add 23
#define subtract 24
#define multiply 25
#define divide 26
#define lessThan 27
#define at 28
#define atPut 29
#define newArray 30
#define fillArray 31
#define analogReadOp 32
#define analogWriteOp 33
#define digitalReadOp 34
#define digitalWriteOp 35
#define microsOp 36
#define millisOp 37
#define peekOp 38
#define pokeOp 39
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
	if (or
		(isEmpty result)
		(not (isOneOf (first (last result)) 'halt' 'stopTask' 'return'))) {
			// add halt to stop execution at end of script
			add result (array 'halt' 0)
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
		addAll result (instructionsForExpression this (at args 1))
		add result (array 'returnResult' 0)
	} ('if' == op) {
		return (instructionsForIf this args)
	} ('animate' == op) { // forever loop
		return (instructionsForForever this args)
	} ('repeat' == op) {
		return (instructionsForRepeat this args)
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

method instructionsForExpression SmallCompiler expr {
	// immediate values
	if (true == expr) {
		return (list (array 'pushImmediate' trueObj))
	} (false == expr) {
		return (list (array 'pushImmediate' falseObj))
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
		if isCommand {
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


// Patches to Scripter

method devModeCategories Scripter {
	return (userModeCategories this)
}

method userModeCategories Scripter {
	addArduinoBlocks (new 'SmallRuntime')
	return (array 'Control_' 'Arduino' 'Math' 'Variables' 'My Blocks')
}

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
