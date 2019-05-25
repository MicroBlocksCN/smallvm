// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksCompiler.gp - A blocks compiler for microBlocks
// John Maloney, April, 2017

defineClass SmallCompiler opcodes argNames localVars trueObj falseObj zeroObj oneObj stringClassID

method initialize SmallCompiler {
	initOpcodes this
	argNames = (dictionary)
	localVars = (dictionary)
	falseObj = 0
	trueObj = 4
	zeroObj = ((0 << 1) | 1)
	oneObj = ((1 << 1) | 1)
	stringClassID = 4
	return this
}

method dumpTranslationTemplate SmallCompiler {
  result = (list)
  for item (microBlocksSpecs this) {
	if (isClass item 'Array') {
	  add result (at item 3)
	  add result (at item 3)
	  add result ''
	}
  }
  writeFile 'microBlocksTranlationTemplate.txt' (joinStrings result (newline))
}

method microBlocksSpecs SmallCompiler {
	return (array
	'Output'
		(array ' ' 'setUserLED'			'set user LED _' 'bool' true)
		(array ' ' 'sayIt'				'say _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 123 '' '')
		(array ' ' 'printIt'			'log data _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 'Hello!')
		(array ' ' 'mbDisplay'			'display _' 'microbitDisplay')
		(array ' ' 'mbDisplayOff'		'clear display')
		(array ' ' 'mbPlot'				'plot x _ y _' 'num num' 3 3)
		(array ' ' 'mbUnplot'			'unplot x _ y _' 'num num' 3 3)
	'Input'
		(array 'r' 'buttonA'			'button A')
		(array 'r' 'buttonB'			'button B')
		(array 'r' 'millisOp'			'milliseconds')
		(array 'r' 'microsOp'			'microseconds')
		(array 'r' 'mbTiltX'			'tilt x')
		(array 'r' 'mbTiltY'			'tilt y')
		(array 'r' 'mbTiltZ'			'tilt z')
		(array 'r' 'mbTemp'				'temperature (°C)')
		(array 'r' '[display:lightLevel]' 'light level')
		(array 'r' '[sensors:touchRead]'	'capacitive sensor _' 'num' 1)
	'Pins'
		(array 'r' 'digitalReadOp'		'read digital pin _ : pullup _' 'num bool' 1 false)
		(array 'r' 'analogReadOp'		'read analog pin _' 'num' 1)
		(array ' ' 'digitalWriteOp'		'set digital pin _ to _' 'num bool' 1 true)
		(array ' ' 'analogWriteOp'		'set pin _ to _' 'num num' 1 1023)
		(array 'r' 'analogPins'			'analog pins')
		(array 'r' 'digitalPins'		'digital pins')
	'Control'
		(array 'h' 'whenStarted'		'when started')
		(array 'h' 'whenButtonPressed'	'when button _ pressed' 'menu.buttonMenu' 'A')
		(array ' ' 'forever'			'forever _' 'cmd')
		(array ' ' 'repeat'				'repeat _ _' 'num cmd' 10)
		(array ' ' 'waitMillis'			'wait _ millisecs' 'num' 500)
		(array ' ' 'waitMicros'			'wait _ microsecs' 'num' 10000)
		(array ' ' 'if'					'if _ _ : else if _ _ : ...' 'bool cmd bool cmd')
		(array 'h' 'whenCondition'		'when _' 'bool')
		(array ' ' 'waitUntil'			'wait until _' 'bool')
		(array 'h' 'whenBroadcastReceived'	'when _ received' 'str' 'go!')
		(array ' ' 'sendBroadcastSimple'	'broadcast _' 'str' 'go!' '')
 		(array ' ' 'return'				'return _' 'auto' 0)
 		(array ' ' 'comment'			'comment _' 'str' 'Comment your code :-)')
		(array ' ' 'for'				'for _ in _ _' 'var num cmd' 'i' 10)
		(array ' ' 'repeatUntil'		'repeat until _ _' 'bool cmd' false)
		(array ' ' 'stopTask'			'stop this task')
		(array ' ' 'stopAll'			'stop all')
	'Math'
		(array 'r' '+'					'_ + _' 'num num' 10 2)
		(array 'r' '-'					'_ − _' 'num num' 10 2)
		(array 'r' '*'					'_ × _' 'num num' 10 2)
		(array 'r' '/'					'_ / _' 'num num' 10 2)
		(array 'r' '%'					'_ mod _' 'num num' 10 2)
		(array 'r' 'absoluteValue'		'abs _ ' 'num' -10)
		(array 'r' 'minimum'			'min _ : _ : ...' 'num num' 1 2)
		(array 'r' 'maximum'			'max _ : _ : ...' 'num num' 1 2)

		(array 'r' 'random'				'random _ to _' 'num num' 1 10)
		(array 'r' '<'					'_ < _' 'num num' 3 4)
		(array 'r' '<='					'_ <= _' 'num num' 3 4)
		(array 'r' '=='					'_ = _' 'auto auto' 3 4)
		(array 'r' '!='					'_ ≠ _' 'auto auto' 3 4)
		(array 'r' '>='					'_ >= _' 'num num' 3 4)
		(array 'r' '>'					'_ > _' 'num num' 3 4)
		(array 'r' 'booleanConstant'	'_' 'bool' true)
		(array 'r' 'not'				'not _' 'bool' true)
		(array 'r' 'and'				'_ and _' 'bool bool' true false)
		(array 'r' 'or'					'_ or _ ' 'bool bool' true false)
	'Variables'
		(array 'r' 'v'					'_' 'menu.allVarsMenu' 'n')
		(array ' ' '='					'set _ to _' 'menu.allVarsMenu auto' 'n' 0)
		(array ' ' '+='					'change _ by _' 'menu.allVarsMenu num' 'n' 1)
		(array ' ' 'local'				'local _ _' 'var auto' 'var' 0)
	'Lists'
		(array 'r' 'newArray'			'new list length _' 'num' 10)
//		(array 'r' 'newByteArray'		'new byte list _' 'num' 10)
		(array ' ' 'fillArray'			'fill list _ with _' 'str auto' nil 0)
		(array ' ' 'atPut'				'replace item _ of _ with _' 'num str auto' 1 nil 10)
		(array 'r' 'at'					'item _ of _' 'num str' 1 nil)
		(array 'r' 'size'				'length of _' 'str' nil)
	'Advanced'
		(array 'r' '&'					'_ & _' 'num num' 1 3)
		(array 'r' '|'					'_ | _' 'num num' 1 2)
		(array 'r' '^'					'_ ^ _' 'num num' 1 3)
		(array 'r' '~'					'~ _' 'num' 1 3)
		(array 'r' '<<'					'_ << _' 'num num' 3 2)
		(array 'r' '>>'					'_ >> _' 'num num' -100 2)
		(array 'r' 'longMult'			'( _ * _ ) >> _' 'num num num' 1024 2048 10)
		(array 'r' '[misc:sin]'			'fixed sine _' 'num' 9000)

		(array 'r' 'boardType'			'board type')

		(array ' ' 'sendBroadcast'		'broadcast _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 'go!' '')

		(array ' ' 'mbDrawShape'		'draw shape _ at x _ y _' 'num num num' 31 1 1)
		(array 'r' 'mbShapeForLetter'	'shape for letter _' 'str' 'A')

		(array ' ' 'neoPixelSetPin'		'set NeoPixel pin _ is RGBW _' 'auto bool' '' false)
		(array ' ' 'neoPixelSend'		'send NeoPixel rgb _' 'num' 5)

		(array 'r' 'i2cGet'				'i2c get device _ register _' 'num num')
		(array ' ' 'i2cSet'				'i2c set device _ register _ to _' 'num num num')
		(array ' ' '[sensors:i2cRead]'	'i2c device _ read _' 'num auto')
		(array ' ' '[sensors:i2cWrite]'	'i2c device _ write _' 'num auto')

		(array ' ' 'spiSend'			'spi send _' 'num' 0)
		(array 'r' 'spiRecv'			'spi receive')

		(array 'r' 'hexToInt'			'hex _' 'str' '3F')

		(array ' ' 'noop'				'no op')
		(array ' ' 'ignoreArgs'			'ignore : _ : ...' 'auto' 0)

		(array 'r' '[io:hasTone]'		'has tone support')
		(array ' ' '[io:playTone]'		'play tone pin _ frequency _' 'num num' 0 440)

		(array 'r' '[io:hasServo]'		'has servo support')
		(array ' ' '[io:setServo]'		'set servo pin _ to _ usecs' 'num num' 0 1500)

		(array 'r' '[net:hasWiFi]'		'has WiFi support')
		(array ' ' '[net:startWiFi]'	'start WiFi _ password _ : be hotspot _' 'str str bool' 'SSID' 'MyPassword' true)
		(array ' ' '[net:stopWiFi]'		'stop WiFi')
		(array 'r' '[net:wifiStatus]'	'WiFi status')
		(array 'r' '[net:myIPAddress]'	'my IP address')

		(array 'r' '[net:thingDescription]'			'thing description')
		(array ' ' '[net:clearThingDescription]'	'clear thing description')
		(array ' ' '[net:appendToThingDescription]'	'append to thing description _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' '')
		(array ' ' '[net:appendToThingProperty]'	'append to thing property _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' '')

		(array ' ' '[tft:enableDisplay]'	'enable TFT _' 'bool' true)
		(array ' ' '[tft:setPixel]'			'set TFT pixel x _ y _ to _' 'num num num' 50 32 16711680)
		(array ' ' '[tft:line]'			'draw line on TFT from x _ y _ to x _ y _ color _' 'num num num num num' 12 8 25 15 255)
		(array ' ' '[tft:rect]'			'draw rectangle on TFT at x _ y _ width _ height _ color _ : filled _' 'num num num num num bool' 10 10 40 30 65280 false)
		(array ' ' '[tft:roundedRect]'			'draw rounded rectangle on TFT at x _ y _ width _ height _ radius _ color _ : filled _' 'num num num num num num bool' 10 10 40 30 8 12255317 false)
		(array ' ' '[tft:circle]'			'draw circle on TFT at x _ y _ radius _ color _ : filled _' 'num num num num bool' 60 100 30 65535 false)
		(array ' ' '[tft:triangle]'			'draw triangle on TFT at x _ y _ , x _ y _ , x _ y _ color _ : filled _' 'num num num num num num num bool' 20 20 30 80 60 5 5592354 false)
		(array ' ' '[tft:text]'			'write _ on TFT at x _ y _ color _ : scale _ wrap _' 'str num num num num bool' 'Hello World!' 0 80 16777215 1 false)

		(array 'r' '[tft:tftTouched]'			'TFT touched')
		(array 'r' '[tft:tftTouchX]'			'TFT touch X position')
		(array 'r' '[tft:tftTouchY]'			'TFT touch Y position')
		(array 'r' '[tft:tftTouchPressure]'	        'TFT touch pressure')

		(array ' ' '[radio:sendInteger]'			'radio send number _' 'num' 123)
		(array ' ' '[radio:sendString]'				'radio send string _' 'str' 'Hello!')
		(array ' ' '[radio:sendPair]'				'radio send pair _ = _' 'str num' 'light' 10)
		(array 'r' '[radio:messageReceived]'		'radio message received?')
		(array 'r' '[radio:receivedInteger]'		'radio last number')
		(array 'r' '[radio:receivedString]'			'radio last string')
		(array 'r' '[radio:receivedMessageType]'	'radio last message type')
		(array ' ' '[radio:setGroup]'				'radio set group _' 'num' 0)
		(array ' ' '[radio:setChannel]'				'radio set channel (0-83)  _' 'num' 7)
		(array ' ' '[radio:setPower]'				'radio set power (0-7) _' 'num' 4)
		(array 'r' '[radio:signalStrength]'			'radio last signal strength')
		(array 'r' '[radio:packetReceive]'			'radio receive packet _' 'str')
		(array ' ' '[radio:packetSend]'				'radio send packet _' 'str')
		(array ' ' '[radio:disableRadio]'			'disable radio')

	'Disabled (does not work)'
 		(array ' ' 'ifElse'				'if _ _ else _' 'bool cmd cmd')
	)
}

method initMicroBlocksSpecs SmallCompiler {
	authoringSpecs = (authoringSpecs)
	if (isEmpty (specsFor authoringSpecs 'Output')) {
		clear authoringSpecs
		addSpecs authoringSpecs (microBlocksSpecs this)
	}
}

method initOpcodes SmallCompiler {
	// Initialize the opcode dictionary by parsing definitions copied and pasted from interp.h

	defsFromHeaderFile = '
		halt 0
		noop 1
		pushImmediate 2		// true, false, and ints that fit in 24 bits
		pushBigImmediate 3	// ints that do not fit in 24 bits (and later, floats)
		pushLiteral 4		// string or array constant from literals frame
		pushVar 5
		storeVar 6
		incrementVar 7
		pushArgCount 8
		pushArg 9
		storeArg 10
		incrementArg 11
		pushLocal 12
		storeLocal 13
		incrementLocal 14
		pop 15
		jmp 16
		jmpTrue 17
		jmpFalse 18
		decrementAndJmp 19
		callFunction 20
		returnResult 21
		waitMicros 22
		waitMillis 23
		sendBroadcast 24
		recvBroadcast 25
		stopAll 26
		forLoop 27
		initLocals 28
	RESERVED 29
	RESERVED 30
	RESERVED 31
	RESERVED 32
		minimum 33
		maximum 34
		< 35
		<= 36
		== 37
		!= 38
		>= 39
		> 40
		not 41
		+ 42
		- 43
		* 44
		/ 45
		% 46
		absoluteValue 47
		random 48
		hexToInt 49
		& 50
		| 51
		^ 52
		~ 53
		<< 54
		>> 55
		longMult 56
	RESERVED 57
	RESERVED 58
	RESERVED 59
		newArray 60
		newByteArray 61
		fillArray 62
		at 63
		atPut 64
		size 65
	RESERVED 66
	RESERVED 67
	RESERVED 68
	RESERVED 69
		millisOp 70
		microsOp 71
	RESERVED 72
	RESERVED 73
		sayIt 74
		printIt 75
		boardType 76
	RESERVED 77
	RESERVED 78
	RESERVED 79
		analogPins 80
		digitalPins 81
		analogReadOp 82
		analogWriteOp 83
		digitalReadOp 84
		digitalWriteOp 85
		digitalSet 86
		digitalClear 87
		buttonA 88
		buttonB 89
		setUserLED 90
		i2cSet 91
		i2cGet 92
		spiSend 93
		spiRecv 94
	RESERVED 95
	RESERVED 96
	RESERVED 97
	RESERVED 98
	RESERVED 99
		mbDisplay 100 		// temporary micro:bit primitives for demos
		mbDisplayOff 101
		mbPlot 102
		mbUnplot 103
		mbTiltX 104
		mbTiltY 105
		mbTiltZ 106
		mbTemp 107
		neoPixelSend 108
		mbDrawShape 109
		mbShapeForLetter 110
		neoPixelSetPin 111
	RESERVED 112
	RESERVED 113
	RESERVED 114
	RESERVED 115
	RESERVED 116
	RESERVED 117
	RESERVED 118
	RESERVED 119
	RESERVED 120
	RESERVED 121
	RESERVED 122
	RESERVED 123
	RESERVED 124
	RESERVED 125
		callCommandPrimitive 126
		callReporterPrimitive 127'
	opcodes = (dictionary)
	for line (lines defsFromHeaderFile) {
		words = (words line)
		if (and ((count words) > 1) ('RESERVED' != (first words))) {
			atPut opcodes (at words 1) (toInteger (at words 2))
		}
	}
}

// instruction generation: entry point

method instructionsFor SmallCompiler aBlockOrFunction {
	// Return a list of instructions for the given block, script, or function.
	// Add a 'halt' if needed and append any literals (e.g. strings) used.

	if (and (isClass aBlockOrFunction 'Block') (isPrototypeHat aBlockOrFunction)) {
		// function definition hat: get its function
		aBlockOrFunction = (function (editedPrototype aBlockOrFunction))
	}

	argNames = (dictionary)
	if (isClass aBlockOrFunction 'Function') {
		func = aBlockOrFunction
		for a (argNames func) {
			atPut argNames a (count argNames)
		}
		cmdOrReporter = (cmdList func)
		if (isNil cmdOrReporter) { // a function hat without any blocks
			cmdOrReporter = (newCommand 'noop')
		}
	} else {
		cmdOrReporter = (expression aBlockOrFunction)
	}

	assignFunctionIDs (smallRuntime)
	collectVars this cmdOrReporter

	result = (list (array 'initLocals' (count localVars)))
	if (isClass cmdOrReporter 'Command') {
		op = (primName cmdOrReporter)
		if ('whenCondition' == op) {
			addAll result (instructionsForWhenCondition this cmdOrReporter)
		} ('whenButtonPressed' == op) {
			addAll result (instructionsForButtonPressed this cmdOrReporter)
		} ('whenStarted' == op) {
			addAll result (instructionsForCmdList this (nextBlock cmdOrReporter))
			add result (array 'halt' 0)
		} ('whenBroadcastReceived' == op) {
			addAll result (instructionsForExpression this (first (argList cmdOrReporter)))
			add result (array 'recvBroadcast' 1)
			addAll result (instructionsForCmdList this (nextBlock cmdOrReporter))
			add result (array 'halt' 0)
		} (isClass aBlockOrFunction 'Function') {
			if (or ('noop' != (primName cmdOrReporter)) (notNil (nextBlock cmdOrReporter))) {
				if (isEmpty (argNames func)) {
					add result (array 'pushLiteral' (functionName func))
					add result (array 'recvBroadcast' 1)
				}
				addAll result (instructionsForCmdList this cmdOrReporter)
			}
			add result (array 'pushImmediate' falseObj)
			add result (array 'returnResult' 0)
		} else {
			addAll result (instructionsForCmdList this cmdOrReporter)
			add result (array 'halt' 0)
		}
	} else {
		addAll result (instructionsForCmdList this (newReporter 'return' cmdOrReporter))
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

// instruction generation: when button pressed hat block

method instructionsForButtonPressed SmallCompiler cmdOrReporter {
	result = (list)
	addAll result (instructionsForCmdList this cmdOrReporter)
	button = (first (argList cmdOrReporter))
	if ('A' == button) {
		condition = (list (newReporter 'not' (newReporter 'buttonA')))
	} ('B' == button) {
		condition = (list (newReporter 'not' (newReporter 'buttonB')))
	}
	if (notNil condition) { // add wait until bubtton up
		addAll result (instructionsForWaitUntil this condition)
	}
	add result (array 'halt' 0)
	return result
}

// instruction generation: when hat block

method instructionsForWhenCondition SmallCompiler cmdOrReporter {
	condition = (instructionsForExpression this (first (argList cmdOrReporter)))
	body = (instructionsForCmdList this (nextBlock cmdOrReporter))
	result = (list)

	// wait until condition becomes true
	addAll result (instructionsForExpression this 10)
	add result (array 'waitMillis' 1)
	addAll result condition
	add result (array 'jmpFalse' (0 - ((count condition) + 3)))

	addAll result body

	// loop back to condition test
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
		add result (setVar this (first args))
	} ('+=' == op) {
		addAll result (instructionsForExpression this (at args 2))
		add result (incrementVar this (first args))
	} ('return' == op) {
		if (0 == (count args)) {
			add result (array 'pushImmediate' zeroObj)
		} else {
			addAll result (instructionsForExpression this (at args 1))
		}
		add result (array 'returnResult' 0)
	} ('stopTask' == op) {
		add result (array 'halt' 0)
	} ('forever' == op) {
		return (instructionsForForever this args)
	} ('if' == op) {
		return (instructionsForIf this args)
	} ('ifElse' == op) {
		return (instructionsForIfElse this (toList args))
	} ('repeat' == op) {
		return (instructionsForRepeat this args)
	} ('repeatUntil' == op) {
		return (instructionsForRepeatUntil this args)
	} ('waitUntil' == op) {
		return (instructionsForWaitUntil this args)
	} ('for' == op) {
		return (instructionsForForLoop this args)
	} (and ('digitalWriteOp' == op) (isClass (first args) 'Integer') (isClass (last args) 'Boolean')) {
		pinNum = ((first args) & 255)
		if (true == (last args)) {
			add result (array 'digitalSet' pinNum)
		} else {
			add result (array 'digitalClear' pinNum)
		}
		return result
	} ('sendBroadcastSimple' == op) {
		return (primitive this 'sendBroadcast' args true)
	} ('comment' == op) {
		// comments do not generate any code
	} ('ignoreArgs' == op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array 'pop' (count args))
		return result
	} (isFunctionCall this op) {
		return (instructionsForFunctonCall this op args true)
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

method instructionsForIfElse SmallCompiler args {
	if ((count args) != 3) { error 'compiler error: expected three arguments to ifElse' }
	addAt args 3 true // insert true before 'else' case
	return (instructionsForIf this args)
}

method instructionsForForever SmallCompiler args {
	result = (instructionsForCmdList this (at args 1))
	add result (array 'jmp' (0 - ((count result) + 1)))
	return result
}

method instructionsForRepeat SmallCompiler args {
	result = (instructionsForExpression this (at args 1)) // loop count
	body = (instructionsForCmdList this (at args 2))
	add result (array 'pushImmediate' oneObj)
	add result (array '+' 2)
	add result (array 'jmp' (count body))
	addAll result body
	add result (array 'decrementAndJmp' (0 - ((count body) + 1)))
	return result
}

method instructionsForRepeatUntil SmallCompiler args {
	result = (list)
	conditionTest = (instructionsForExpression this (at args 1))
	body = (instructionsForCmdList this (at args 2))
	add result (array 'jmp' (count body))
	addAll result body
	addAll result conditionTest
	add result (array 'jmpFalse' (0 - (+ (count body) (count conditionTest) 1)))
	return result
}

method instructionsForWaitUntil SmallCompiler args {
	result = (list)
	conditionTest = (instructionsForExpression this (at args 1))
	addAll result conditionTest
	add result (array 'jmpFalse' (0 - (+ (count conditionTest) 1)))
	return result
}

method instructionsForForLoop SmallCompiler args {
	result = (instructionsForExpression this (at args 2))
	loopVarIndex = (at localVars (first args))
	body = (instructionsForCmdList this (at args 3))
	addAll result (array
		(array 'pushImmediate' falseObj) // this will be N, the total loop count
		(array 'pushImmediate' falseObj) // this will be a decrementing loop counter
		(array 'jmp' (count body)))
	addAll result body
	addAll result (array
		(array 'forLoop' loopVarIndex)
		(array 'jmp' (0 - ((count body) + 2)))
		(array 'pop' 3))
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
		return (list (array 'pushImmediate' zeroObj))
	} (isClass expr 'Integer') {
		if (and (-4194304 <= expr) (expr <= 4194303)) { // 23-bit encoded as 24 bit int object
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
	} (isClass expr 'Color') {
		return (instructionsForExpression this (scaledRGB this expr))
	}

	// expressions
	op = (primName expr)
	args = (argList expr)
	if ('v' == op) { // variable
		return (list (getVar this (first args)))
	} ('booleanConstant' == op) {
		if (first args) {
			return (list (array 'pushImmediate' trueObj))
		} else {
			return (list (array 'pushImmediate' falseObj))
		}
	} ('colorSwatch' == op) {
		c = (color (at args 1) (at args 2) (at args 3))
		return (instructionsForExpression this (scaledRGB this c))
	} ('and' == op) {
		return (instructionsForAnd this args)
	} ('or' == op) {
		return (instructionsForOr this args)
	} (isFunctionCall this op) {
		return (instructionsForFunctonCall this op args false)
	} else {
		return (primitive this op args false)
	}
}

method scaledRGB SmallCompiler aColor {
	brightness = (((raise 2 (5 * (brightness aColor))) - 1) / 31) // range: 0-1
	saturation = (2 * (saturation aColor)) // increase saturation
	color = (colorHSV (hue aColor) saturation (0.125 * brightness)) // RGB components all 0-31
	return (pixelRGB color)
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
	if ('mbDisplay' == op) {
	  if (25 == (count args)) {
		shift = 0
		displayWord = 0
		for bit args {
		  if (true == bit) { displayWord = (displayWord | (1 << shift)) }
			shift += 1
		}
	  } (1 == (count args)) {
		displayWord = (first args)
	  } else {
		print 'Bad mbDisplay arguments'
		return result
	  }
	  addAll result (instructionsForExpression this displayWord)
	  add result (array 'mbDisplay' 1)
	} ('comment' == op) {
		// ignore comments
	} (contains opcodes op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array op (count args))
	} (and (beginsWith op '[') (endsWith op ']')) {
		// named primitives of the form '[primSetName:primName]'
		i = (findFirst op ':')
		if (notNil i) {
			primSetName = (substring op 2 (i - 1))
			primName = (substring op (i + 1) ((count op) - 1))
			add result (array 'pushLiteral' primSetName)
			add result (array 'pushLiteral' primName)
			for arg args {
				addAll result (instructionsForExpression this arg)
			}
			if isCommand {
				add result (array 'callCommandPrimitive' ((count args) + 2))
			} else {
				add result (array 'callReporterPrimitive' ((count args) + 2))
			}
		}
	} else {
		print 'Skipping unknown op:' op
	}
	return result
}

// Variables

method collectVars SmallCompiler cmdOrReporter {
	sharedVars = (variableNames (targetModule (scripter (smallRuntime))))
	sharedVars = (copyWithout sharedVars 'extensions')

	localVars = (dictionary)
	todo = (list cmdOrReporter)
	while ((count todo) > 0) {
		cmd = (removeFirst todo)
		if (isOneOf (primName cmd) 'local' 'for') {
			// explicit local variables and 'for' loop indexes are always local
			varName = (first (argList cmd))
			if (not (or
				(contains argNames varName)
				(contains localVars varName))) {
					atPut localVars varName (count localVars)
			}
		} (isOneOf (primName cmd) 'v' '=' '+=') {
			// undeclared variables that are not global (shared) are treated as local
			varName = (first (argList cmd))
			if (not (or
				(contains sharedVars varName)
				(contains argNames varName)
				(contains localVars varName))) {
					atPut localVars varName (count localVars)
			}
		}
		for arg (argList cmd) {
			if (isAnyClass arg 'Command' 'Reporter') {
				add todo arg
			}
		}
		if (notNil (nextBlock cmd)) { add todo (nextBlock cmd) }
	}
}

method getVar SmallCompiler varName {
	if (notNil (at localVars varName)) {
		return (array 'pushLocal' (at localVars varName))
	} (notNil (at argNames varName)) {
		return (array 'pushArg' (at argNames varName))
	}
	globalID = (globalVarIndex this varName)
	if (notNil globalID) { return (array 'pushVar' globalID) }
}

method setVar SmallCompiler varName {
	if (notNil (at localVars varName)) {
		return (array 'storeLocal' (at localVars varName))
	} (notNil (at argNames varName)) {
		return (array 'storeArg' (at argNames varName))
	}
	globalID = (globalVarIndex this varName)
	if (notNil globalID) { return (array 'storeVar' globalID) }
}

method incrementVar SmallCompiler varName {
	if (notNil (at localVars varName)) {
		return (array 'incrementLocal' (at localVars varName))
	} (notNil (at argNames varName)) {
		return (array 'incrementArg' (at argNames varName))
	}
	globalID = (globalVarIndex this varName)
	if (notNil globalID) { return (array 'incrementVar' globalID) }
}

method globalVarIndex SmallCompiler varName {
	varNames = (copyWithout (variableNames (targetModule (scripter (smallRuntime)))) 'extensions')
	id = (indexOf varNames varName)
	if (isNil id) {
		error 'Unknown variable' varName
	}
	if (id >= 25) { error 'Id' id 'for variable' varName 'is out of range' }
	return (id - 1) // VM uses zero-based index
}

// function calls

method isFunctionCall SmallCompiler op {
	return (notNil (lookupChunkID (smallRuntime) op))
}

method instructionsForFunctonCall SmallCompiler op args isCmd {
	result = (list)
	callee = (lookupChunkID (smallRuntime) op)
	for arg args {
		addAll result (instructionsForExpression this arg)
	}
	add result (array 'callFunction' (((callee & 255) << 8) | ((count args) & 255)))
	if isCmd { add result (array 'pop' 1) } // discard the return value
	return result
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
	headerWord = ((wordCount << 4) | stringClassID);
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
