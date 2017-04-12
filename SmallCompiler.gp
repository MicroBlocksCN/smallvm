// SmallCompiler.gp - A blocks compiler for SmallVM
// John Maloney, April, 2017

to evalOnArduino cmdList {
  compiler = (initialize (new 'SmallCompiler'))
  bytes = (list)
  instructions = (smallVMInstructionsFor cmdList)
  for item instructions {
	if (isClass item 'Array') {
	  addAll bytes (bytesForInstruction compiler item)
	} (isClass item 'String') {
	  addAll bytes (bytesForStringLiteral compiler item)
	} else {
	  error 'Instruction must be an Array or String:' item
	}
  }
  sendMsg bytes
}

to sendMsg byteList {
  msg = (list 17 42 0 (count byteList))
  addAll msg byteList
  port = (openSerialPort '/dev/tty.usbmodem1422' 9600)
  writeSerialPort port (toBinaryData (toArray msg))
  monitorSerial port
  closeSerialPort port
}

to monitorSerial port {
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

to compileSmallVM cmdList {
  code = (smallVMInstructionsFor cmdList)
  for item code { print item }
}

to smallVMInstructionsFor cmdList {
  compiler = (initialize (new 'SmallCompiler'))
  if (isClass cmdList 'Command') {
	result = (instructionsForCmdList compiler cmdList)
  } else {
	result = (instructionsForCmdList compiler (newReporter 'return' cmdList))
  }

  if (or
  	(isEmpty result)
	(not (isOneOf (first (last result)) 'halt' 'stopTask' 'return'))) {
	  // make sure execution stops at end of script
	  add result (array 'halt' 0)
  }
  return (appendLiterals compiler result)
}

defineClass SmallCompiler opcodes primitives globals trueObj falseObj

method initialize SmallCompiler {
  initOpcodes this
  initPrimitives this
  globals = (dictionary)
  trueObj = 2
  falseObj = 4
  return this
}

method initOpcodes SmallCompiler {
  opcodes = (dictionary)
  atPut opcodes 'halt' 0
  atPut opcodes 'noop' 1
  atPut opcodes 'pushImmediate' 2
  atPut opcodes 'pushLiteral' 3
  atPut opcodes 'pushVar' 4
  atPut opcodes 'popVar' 5
  atPut opcodes 'incrementVar' 6
  atPut opcodes 'pop' 7
  atPut opcodes 'jmp' 8
  atPut opcodes 'jmpTrue' 9
  atPut opcodes 'jmpFalse' 10
  atPut opcodes 'decrementAndJmp' 11
  atPut opcodes 'callFunction' 12
  atPut opcodes 'returnResult' 13
  atPut opcodes 'add' 14
  atPut opcodes 'subtract' 15
  atPut opcodes 'multiply' 16
  atPut opcodes 'divide' 17
  atPut opcodes 'lessThan' 18
  atPut opcodes 'printIt' 19
  atPut opcodes 'at' 20
  atPut opcodes 'atPut' 21
  atPut opcodes 'newArray' 22
  atPut opcodes 'fillArray' 23
}

method initPrimitives SmallCompiler {
  primitives = (dictionary)
  atPut primitives 'halt' 'halt'
  atPut primitives 'stopTask' 'halt' // map stop block to halt, too
  atPut primitives 'noop' 'noop'
  atPut primitives '+' 'add'
  atPut primitives '-' 'subtract'
  atPut primitives '*' 'multiply'
  atPut primitives '/' 'divide'
  atPut primitives '<' 'lessThan'
  atPut primitives 'print' 'printIt'
  atPut primitives 'at' 'at'
  atPut primitives 'atPut' 'atPut'
  atPut primitives 'newArray' 'newArray'
  atPut primitives 'fillArray' 'fillArray'
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
	add result (array 'returnResult')
  } ('if' == op) {
	return (instructionsForIf this args)
  } ('animate' == op) { // forever loop
	return (instructionsForForever this args)
  } ('repeat' == op) {
	return (instructionsForRepeat this args)
  } else { // primitive
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
  	// to do: > 24 bits
	return (list (array 'pushImmediate' ((expr << 1) | 1)))
  } (isClass expr 'String') {
	return (list (array 'pushLiteral' expr))
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
  primOp = (at primitives op nil)
  if (notNil primOp) {
	for arg args {
	  addAll result (instructionsForExpression this arg)
	}
	add result  (array primOp (count args))
	if isCommand {
	  add result  (array 'pop' 1)
	}
  } else {
	print 'Skipping unknown op:' op
  }
  return result
}

method globalVarIndex SmallCompiler varName {
  id = (at globals varName nil)
  if (isNil id) {
	id = ((count globals) + 1)
	atPut globals varName id
  }
  return id
}

method appendLiterals SmallCompiler instructions {
  // For now, all literals are strings. May add literal arrays later.

  literals = (list)
  literalOffsets = (dictionary)
  nextOffset = (count instructions)
  for ip (count instructions) {
	instr = (at instructions ip)
	if ('pushLiteral' == (first instr)) {
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
  return (join instructions literals)
}

method wordsForLiteral SmallCompiler literal {
  headerWords = 1
  if (isClass literal 'String') {
	return (headerWords + (floor (((byteCount literal) + 4) / 4)))
  }
  error 'Illegal literal type:' literal
}


method bytesForInstruction SmallCompiler instr {
  opcode = (at opcodes (first instr))
  result = (array opcode 0 0 0) // little endian
  if ((count instr) > 1) {
	arg = (at instr 2)
	atPut result 2 (arg & 255)
	atPut result 3 ((arg >> 8) & 255)
	atPut result 4 ((arg >> 16) & 255)
  }
  return result
}

method bytesForStringLiteral SmallCompiler s {
  byteCount = (byteCount s)
  wordCount = (floor ((byteCount + 4) / 4))
  headerWord = ((wordCount << 4) | 5);
  result = (list)
  repeat 4 { // little endian
	add result (headerWord & 255)
	headerWord = (headerWord >> 8)
  }
  for i byteCount {
	add result (byteAt s i)
  }
  repeat (4 - (byteCount % 4)) { // pad with zeros to word boundary
	add result 0
  }
  return result
}
