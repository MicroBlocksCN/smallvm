// SmallCompiler.gp - A blocks compiler for SmallVM
// John Maloney, April, 2017

to smallRuntime aScripter {
	if (isNil (global 'smallRuntime')) {
		setGlobal 'smallRuntime' (new 'SmallRuntime' aScripter)
	}
	return (global 'smallRuntime')
}

defineClass SmallRuntime scripter chunkIDs msgDict portName port recvBuf

method scripter SmallRuntime { return scripter }

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
	// Reset the Arduino by closing the serial port, opening it
	// at 1200 baud, then closing and reopening the port.

	ensurePortOpen this // make sure portName is initialized
	closeSerialPort port
	port = (openSerialPort portName 1200)
	closeSerialPort port
	port = nil
	ensurePortOpen this // reopen the port
	recvBuf = nil
}

method sendStopAll SmallRuntime { sendMsg this 'stopAllMsg' }

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

method msgNameToID SmallRuntime msgName {
	if (isNil msgDict) {
		msgDict = (dictionary)
		atPut msgDict 'storeChunkMsg' 1
		atPut msgDict 'deleteChunkMsg' 2
		atPut msgDict 'startChunkMsg' 3
		atPut msgDict 'stopChunkMsg' 4
		atPut msgDict 'startAllMsg' 5
		atPut msgDict 'stopAllMsg' 6
		atPut msgDict 'deleteAllChunksMsg' 14
		atPut msgDict 'systemResetMsg' 15
		atPut msgDict 'taskStartedMsg' 16
		atPut msgDict 'taskDoneMsg' 17
		atPut msgDict 'taskReturnedValueMsg' 18
		atPut msgDict 'taskErrorMsg' 19
		atPut msgDict 'outputStringMsg' 20
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
//			portName = '/dev/tty.usbmodem105'
			portName = '/dev/tty.usbmodem1422'
		}
		port = (openSerialPort portName 115200)
	}
}

method processMessages SmallRuntime {
	if (isNil port) { return }
	if (isNil recvBuf) { recvBuf = (newBinaryData 0) }

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
		error 'Bad message header byte; should be 250 or 251 but is:' firstByte
	}
}

method handleMessage SmallRuntime msg {
	op = (byteAt msg 2)
	if (op == (msgNameToID this 'taskStartedMsg')) {
//		print 'started' (byteAt msg 3)
	} (op == (msgNameToID this 'taskDoneMsg')) {
//		print 'stopped' (byteAt msg 3)
	} (op == (msgNameToID this 'taskReturnedValueMsg')) {
		print (returnedValue this msg)
	} (op == (msgNameToID this 'taskErrorMsg')) {
		print 'error:' (byteAt msg 6) // error code
	} (op == (msgNameToID this 'outputStringMsg')) {
		print (returnedValue this msg)
	} else {
		print 'msg:' (toArray msg)
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

method addArduinoBlocks SmallRuntime {
	authoringSpecs = (authoringSpecs)
	if (isEmpty (specsFor authoringSpecs 'Arduino')) {
		clear authoringSpecs
		addSpecs authoringSpecs (arduinoSpecs this)
	}
}

method arduinoSpecs SmallRuntime {
	return (array
	'Arduino'
		(array ' ' 'printIt'			'print _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 'Hello, Arduino!')
		(array ' ' 'sayIt'				'say _' 'auto' 123)
		(array 'r' 'analogReadOp'		'read analog pin _' 'num' 1)
		(array ' ' 'analogWriteOp'		'set analog pin _ to _' 'num num' 1 1023)
		(array 'r' 'digitalReadOp'		'read digital pin _' 'num' 1)
		(array ' ' 'digitalWriteOp'		'set digital pin _ to _' 'num bool' 1 true)
		(array ' ' 'setLEDOp'			'set user LED _' 'bool' true)
		(array 'r' 'analogPinsOp'		'analog pins')
		(array 'r' 'digitalPinsOp'		'digital pins')
		(array 'r' 'microsOp'			'micros')
		(array 'r' 'millisOp'			'millis')
		(array 'r' 'i2cGet'				'i2c get device _ register _' 'num num')
		(array ' ' 'i2cSet'				'i2c set device _ register _ to _' 'num num num')
		(array ' ' 'noop'				'no op')
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

defineClass SmallCompiler opcodes trueObj falseObj

method initialize SmallCompiler {
	initOpcodes this
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
#define modulo 43
#define lessOrEq 44
#define equal 45
#define greaterOrEq 46
#define greaterThan 47
#define notOp 48
#define sayIt 49
#define analogPinsOp 50
#define digitalPinsOp 51
#define hexToInt 52
#define i2cGet 53
#define i2cSet 54
'
	opcodes = (dictionary)
	for line (lines defsFromHeaderFile) {
		words = (words line)
		if (and ((count words) > 2) ('#define' == (first words))) {
			atPut opcodes (at words 2) (toInteger (at words 3))
		}
	}
}

// instruction generation: entry point

method instructionsFor SmallCompiler cmdOrReporter {
	// Return a list of instructions for stack of blocks or a reporter.
	// Add a 'halt' if needed and append any literals (e.g. strings) used.

	if (isClass cmdOrReporter 'Command') {
		op = (primName cmdOrReporter)
		if ('whenCondition' == op) {
			result = (instructionsForWhenCondition this cmdOrReporter)
		} ('whenStarted' == op) {
			result = (instructionsForWhenStarted this cmdOrReporter)
			add result (array 'halt' 0)
		} else {
			result = (instructionsForCmdList this cmdOrReporter)
			add result (array 'halt' 0)
		}
	} else {
		result = (instructionsForCmdList this (newReporter 'return' cmdOrReporter))
	}
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

// instruction generation: hat blocks

method instructionsForWhenStarted SmallCompiler cmdOrReporter {
	body = (instructionsForCmdList this (nextBlock cmdOrReporter))
	return body
}

method instructionsForWhenCondition SmallCompiler cmdOrReporter {
	condition = (instructionsForExpression this (first (argList cmdOrReporter)))
	body = (instructionsForCmdList this (nextBlock cmdOrReporter))
	result = (list)

	// poll until condition becomes true
	addAll result condition
	add result (array 'jmpFalse' (0 - ((count condition) + 1)))

	addAll result body

	// loop until condition not true
 	addAll result condition
 	add result (array 'jmpTrue' (0 - ((count condition) + 1)))

	add result (array 'jmp' (0 - ((count result) + 1)))
	return result
}

// instruction generation: command lists and control structures

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
	} ('stopTask' == op) {
		add result (array 'halt' 0)
	} ('if' == op) {
		return (instructionsForIf this args)
	} ('repeat' == op) {
		return (instructionsForRepeat this args)
	} ('waitUntil' == op) {
		return (instructionsForWaitUntil this args)
	} ('while' == op) {
		return (instructionsForWhile this args)
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

method instructionsForWaitUntil SmallCompiler args {
	conditionTest = (instructionsForExpression this (at args 1))
	result = (list)
	addAll result conditionTest
	add result (array 'jmpFalse' (0 - (+ (count conditionTest) 1)))
	return result
}

method instructionsForWhile SmallCompiler args {
	result = (list)
	body = (instructionsForCmdList this (at args 2))
	if (true == (at args 1)) { // special case: the condition is constant 'true'
		addAll result body
		add result (array 'jmp' (0 - (+ (count body) 1)))
		return result
	}
	conditionTest = (instructionsForExpression this (at args 1))
	add result (array 'jmp' (count body))
	addAll result body
	addAll result conditionTest
	add result (array 'jmpTrue' (0 - (+ (count body) (count conditionTest) 1)))
	return result
}

// instruction generation: expressions

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
	if ('v' == op) { // variable
		return (list (array 'pushVar' (globalVarIndex this (first args))))
	} ('booleanConstant' == op) {
		if (first args) {
			return (list (array 'pushImmediate' trueObj))
		} else {
			return (list (array 'pushImmediate' falseObj))
		}
	} ('and' == op) {
		return (instructionsForAnd this args)
	} ('or' == op) {
		return (instructionsForOr this args)
	} else {
		return (primitive this op args false)
	}
}

method instructionsForAnd SmallCompiler args {
	tests = (list)
	totalInstrCount = 3 // final three instructions
	for expr args {
		instrList = (instructionsForExpression this expr)
		add tests instrList
		totalInstrCount += ((count instrList) + 1)
	}
	instrCount = 0
	result = (list)
	for t tests {
		addAll result t
		add result (array 'jmpFalse' (totalInstrCount - ((count result) + 2)))
	}
	add result (array 'pushImmediate' trueObj) // all conditions were true: push result
	add result (array 'jmp' 1) // skip over false case
	add result (array 'pushImmediate' falseObj) // some condition was false: push result
	return result
}

method instructionsForOr SmallCompiler args {
	tests = (list)
	totalInstrCount = 3 // final three instructions
	for expr args {
		instrList = (instructionsForExpression this expr)
		add tests instrList
		totalInstrCount += ((count instrList) + 1)
	}
	instrCount = 0
	result = (list)
	for t tests {
		addAll result t
		add result (array 'jmpTrue' (totalInstrCount - ((count result) + 2)))
	}
	add result (array 'pushImmediate' falseObj) // all conditions were false: push result
	add result (array 'jmp' 1) // skip over true case
	add result (array 'pushImmediate' trueObj) // some condition was true: push result
	return result
}

// instruction generation utility methods

method primitive SmallCompiler op args isCommand {
	result = (list)
	if ('print' == op) { op = 'printIt' }
	if (contains opcodes op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array op (count args))
		if (and isCommand (not (isOneOf op 'noop' 'stopTask' 'stopAll')))  {
			add result (array 'pop' 1)
		}
	} else {
		print 'Skipping unknown op:' op
	}
	return result
}

method globalVarIndex SmallCompiler varName {
	varNames = (copyWithout (variableNames (targetModule (scripter (smallRuntime)))) 'extensions')
	id = (indexOf varNames varName)
	if (isNil id) {
		error 'Unknown variable' varName
	}
	return (id - 1) // VM uses zero-based index
}

// literal values (strings and large integers )

method appendLiterals SmallCompiler instructions {
	// For now, strings and integers too large for pushImmediate are the only literals.
	// Perhaps add support for constant literal arrays later.

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

// binary code generation

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

method addBytesForIntegerLiteralTo SmallCompiler n bytes {
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

// *****************************
// Code below this point patches the GP IDE to turn it into an interim uBlocks IDE
// *****************************

method blockColorForCategory AuthoringSpecs cat {
  defaultColor = (color 4 148 220)
  if (isOneOf cat 'Control' 'Functions' 'Control') {
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

method clear AuthoringSpecs {
  specsList = (list)
  specsByOp = (dictionary)
  opCategory = (dictionary)
  return this
}

method clicked Block hand {
  evalOnArduino (smallRuntime) (topBlock this)
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
  processMessages (smallRuntime)
}

method devModeCategories Scripter {
	return (userModeCategories this)
}

method userModeCategories Scripter {
	addArduinoBlocks (smallRuntime this)
	return (array 'Control' 'Arduino' 'Math' 'Arrays' 'Variables' 'My Blocks')
}

method addVariableBlocks Scripter {
  scale = (global 'scale')
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (-3 * scale))

  addSectionLabel this 'Variables'
  addButton this 'Add a variable' (action 'createSharedVariable' this) 'Variables are visible to all scripts.'
  sharedVars = (sharedVars this)
  if (notEmpty sharedVars) {
	addButton this 'Delete a variable' (action 'deleteSharedVariable' this)
	nextX += (-135 * scale) // suppress indentation of variable blocks by addBlock
	nextY += (8 * scale)
	for varName sharedVars {
	  lastY = nextY
	  b = (toBlock (newReporter 'v' varName))
	  addBlock this b nil true
	}
	nextX += (135 * scale)
	nextY += (5 * scale)
	addBlock this (toBlock (newCommand '=' (first sharedVars) 0)) nil false
	addBlock this (toBlock (newCommand '+=' (first sharedVars) 1)) nil false
  }
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

method scriptEditor Scripter {
  return (contents scriptsFrame)
}

method contextMenu ScriptEditor {
  menu = (menu nil this)
  // Arudino additions to background menu
  addItem menu 'Arduino start all' (action 'sendStartAll' (smallRuntime))
  addItem menu 'Arduino stop all' (action 'sendStopAll' (smallRuntime))
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
