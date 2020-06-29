// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to blocks
// John Maloney, March, 2020

// To do:
// [ ] handle function calls
// [x] make testDecompiler generate blocks
// [ ] make test method that clears current scripts then fetched and decompiles code from board
// [ ] make compiler store local names
// [ ] use local names
// [ ] store function spec and parameter names

to decompileBytecodes bytecodes chunkType {
	return (decompile (new 'MicroBlocksDecompiler') bytecodes chunkType)
}

defineClass MicroBlocksDecompiler reporters opcodes controlStructures code stack

method decompile MicroBlocksDecompiler bytecodes chunkType {
	// Approach:
	//	0. Convert bytecodes into sequence of opcode tuples
	//	1. find and replace loops
	//	2. find and replace if's (recursively)
	//	3. walk the entire tree and generate code

	opcodes = (list)
	for i (range 1 (count bytecodes) 4) {
		op = (at bytecodes i)
		arg = (+
			((at bytecodes (i + 3)) << 16)
			((at bytecodes (i + 2)) << 8)
			 (at bytecodes (i + 1)))
		arg = ((arg << 7) >> 7) // shift to sign-extend arg
		addr = (floor ((i + 3) / 4))
		add opcodes (array addr op arg)
	}
	lastInstruction = (findLastInstruction this)
	getOpNames this lastInstruction
	decodeImmediates this lastInstruction
	opcodes = (copyFromTo opcodes 1 lastInstruction)
	controlStructures = (newArray (count opcodes))
	findLoops this
	findIfs this

	print '----'
	printSequence2 this
	print '----'
	printSequence3 this 1 (count opcodes) 0
	print '----'

	if (cmdIs this (last opcodes) 'halt' 0) { removeLast opcodes }
	gpCode = (addHatBlock this chunkType (codeForSequence this 1 (count opcodes)))
	print (prettyPrint this gpCode)
	showCodeInHand this gpCode
}

method showCodeInHand MicroBlocksDecompiler gpCode {
	block = (toBlock gpCode)
	grab (hand (global 'page')) block
	fixBlockColor block
}

// Command tuple operations

method cmdOp MicroBlocksDecompiler cmd { return (at cmd 2) }
method cmdArg MicroBlocksDecompiler cmd { return (at cmd 3) }

method jumpTarget MicroBlocksDecompiler jmpCmd {
	// Return the target index of the given jump command.

	return (+ (at jmpCmd 1) (cmdArg this jmpCmd) 1)
}

method cmdIs MicroBlocksDecompiler cmd op arg {
	// Return true of the given command has the given op and argument.

	return (and (notNil cmd) (op == (at cmd 2)) (arg == (at cmd 3)))
}

// Debugging

method printSequence2 MicroBlocksDecompiler {
	for i (count controlStructures) {
		cmd = (at opcodes i)
		line = (join '' i ': ' (cmdOp this cmd) ' ' (cmdArg this cmd))
		cntr = (at controlStructures i)
		if (notNil cntr) { line = (join line ' ' cntr) }
		print line
	}
}

method printSequence3 MicroBlocksDecompiler start end indent {
	spaces = (joinStrings (newArray indent ' '))
	i = start
	while (i <= end) {
		ctrl = (at controlStructures i)
		atPut controlStructures i nil // avoid infinite recursion on 'forever'
		if (notNil ctrl) {
			op = (first ctrl)
			if ('if' == op) {
				print (join spaces op)
				printSequence3 this (at ctrl 3) (at ctrl 4) (indent + 4)
			} ('if-else' == op) {
				print (join spaces op)
				printSequence3 this (at ctrl 3) (at ctrl 4) (indent + 4)
				print (join spaces 'else')
				printSequence3 this (at ctrl 5) (at ctrl 6) (indent + 4)
			} (isOneOf op 'for' 'forever' 'repeat') {
				print (join spaces op)
				printSequence3 this (at ctrl 3) (at ctrl 4) (indent + 4)
			} ('repeatUntil' == op) {
				print (join spaces 'until')
				printSequence3 this (at ctrl 3) (at ctrl 4) (indent + 4)
				print (join spaces 'do')
				printSequence3 this (at ctrl 5) (at ctrl 6) (indent + 4)
			} ('whenCondition' == op) {
				print 'when:'
				printSequence3 this (at ctrl 3) (at ctrl 4) (indent + 4)
				print 'then:'
				printSequence3 this (at ctrl 5) (at ctrl 6) (indent + 4)
 			} else {
 				print (join spaces op)
			}
			atPut controlStructures i ctrl // restore ctrl to controlStructure
			i = ((at ctrl 2) + 1)
		} else {
			cmd = (at opcodes i)
			print (join spaces (cmdOp this cmd) ' ' (cmdArg this cmd))
			i += 1
		}
	}
}

method printSequence MicroBlocksDecompiler seq indent {
	// Used during debugging to print a partially decoded opcode sequence with indentation.

	if (isNil indent) { indent = 0 }
	spaces = (joinStrings (newArray indent ' '))
	for cmd seq {
		op = (cmdOp this cmd)
		if ('if' == op) {
			print (join spaces op)
			printSequence this (at cmd 3) (indent + 4)
			elsePart = (at cmd 4)
			if (notNil elsePart) {
				print (join spaces 'else')
				printSequence this elsePart (indent + 4)
			}
		} (isOneOf op 'forever' 'repeat' 'for' 'repeatUntil') {
			print (join spaces op)
			printSequence this (cmdArg this cmd) (indent + 4)
		} (isOneOf op 'whenStarted' 'whenButtonPressed' 'whenBroadcastReceived') {
			print (join spaces op)
			printSequence this (cmdArg this cmd) (indent + 4)
		} ('whenCondition' == op) {
			print 'when:'
			printSequence this (at cmd 3) (indent + 4)
			print 'then:'
			printSequence this (at cmd 4) (indent + 4)
		} else {
			print (join spaces op ' ' (cmdArg this cmd))
		}
	}
}

method prettyPrint MicroBlocksDecompiler expression {
	// Used during debugging to print the GP code output of the decompiler.

	pp = (new 'PrettyPrinter')
	if (isClass expression 'Reporter') {
		if (isOneOf (primName expression) 'v') {
			return (join '(v ' (first (argList expression)) ')')
		} else {
			return (join '(' (prettyPrint pp expression) ')')
		}
	} else {
		return (prettyPrintList pp expression)
	}
	return '???' // should not get here
}

// Helper methods

method findLastInstruction MicroBlocksDecompiler {
	// Find the index of the last instruction in opcodes. The last instruction
	// may be followed by literal values such as strings. Replace the offsets
	// in 'pushLiteral' instructions with the referenced literal string.

	pushLiteralOpcode = 4
	result = (count opcodes)
	for i (count opcodes) {
		if (i > result) { return result }
		instr = (at opcodes i)
		if (pushLiteralOpcode == (cmdOp this instr)) {
			literalIndex = (+ i (cmdArg this instr) 1)
			if (literalIndex <= result) {
				result = (literalIndex - 1)
			}
			atPut instr 3 (readLiteral this literalIndex) // insert the literal into instruction
		}
	}
	return result
}

method readLiteral MicroBlocksDecompiler literalIndex {
	// Return the literal string starting at the given index in the opcode list.

	header = (at opcodes literalIndex)
	lowByte = (at header 2)
	if (4 != (lowByte & 15)) {
		print 'bad string literal (should not happen)'
		return ''
	}
	highBytes = (at header 3)
	wordCount = ((highBytes << 4) | (lowByte >> 4))
	bytes = (list)
	for i (range (literalIndex + 1) (literalIndex + wordCount)) {
		instr = (at opcodes i)
		add bytes (at instr 2)
		highBytes = (at instr 3)
		add bytes (highBytes & 255)
		add bytes ((highBytes >> 8) & 255)
		add bytes ((highBytes >> 16) & 255)
	}
	while (and (notEmpty bytes) (0 == (last bytes))) {
		removeLast bytes // remove trailing zero bytes
	}
	return (callWith 'string' (toArray bytes))
}

method getOpNames MicroBlocksDecompiler lastInstruction {
	// Replace the numerical opcode of each opcode entry with its name except
	// for entries immediately following a pushBigImmediate instruction, which
	// are inline integer constants.

	opcodeDefs = (opcodes (initialize (new 'SmallCompiler')))
	opcodeToName = (range 0 255)
	for p (sortedPairs opcodeDefs false) {
		atPut opcodeToName ((first p) + 1) (last p)
	}
	for i lastInstruction {
		op = nil
		if ('pushBigImmediate' != lastOp) {
			instr = (at opcodes i)
			op = (at opcodeToName ((at instr 2) + 1))
			atPut instr 2 op
		}
		lastOp = op
	}
}

method decodeImmediates MicroBlocksDecompiler lastInstruction {
	// Decode values encoded in pushImmediate instructions (true, false, or small integer.)

	for i lastInstruction {
		instr = (at opcodes i)
		if ('pushImmediate' == (cmdOp this instr)) {
			val = (last instr)
			decoded = val
			if (1 == (val & 1)) {
				decoded = (floor (val / 2)) // small integer
			} (0 == val) {
				decoded = false
			} (4 == val) {
				decoded = true
			} else {
				print 'cannot decode immediate value:' val
			}
			atPut instr 3 decoded
		}
	}
}

method addHatBlock MicroBlocksDecompiler chunkType gpCode {
	// Prefix given code with a hat block based on chunkType and return the result.

	result = gpCode
	if (4 == chunkType) {
		result = (newCommand 'whenStarted')
		setField result 'nextBlock' gpCode
	} (6 == chunkType) {
		if ('recvBroadcast' == (primName gpCode)) {
			result = (newCommand 'whenBroadcastReceived' (first (argList gpCode)))
			setField result 'nextBlock' (nextBlock gpCode)
		}
	} (7 == chunkType) {
		result = (newCommand 'whenButtonPressed' 'A')
		setField result 'nextBlock' gpCode
	} (8 == chunkType) {
		result = (newCommand 'whenButtonPressed' 'B')
		setField result 'nextBlock' gpCode
	} (9 == chunkType) {
		result = (newCommand 'whenButtonPressed' 'A+B')
		setField result 'nextBlock' gpCode
	}
	return result
}

// Loops

method findLoops MicroBlocksDecompiler {
	// Create entries for all loop constructs in the opcode sequence.

	i = 1
	while (i <= (count opcodes)) {
		cmd = (at opcodes i)
		if (and (isOneOf (cmdOp this cmd) 'jmp' 'jmpFalse' 'decrementAndJmp') ((cmdArg this cmd) < 0)) {
			// a jump instruction with a negative offset marks the end of a loop
			loopType = (loopTypeAt this i opcodes)
			if ('whenCondition' == loopType) {
				loopStart = 2
				loopEnd = (count opcodes)
				conditionStart = 4
				conditionEnd = (i - 1)
				bodyStart = (i + 1)
				bodyEnd = ((count opcodes) - 1)
				loopRec = (array 'whenCondition' loopEnd conditionStart conditionEnd bodyStart bodyEnd)
			} ('repeatUntil' == loopType) {
				bodyStart = (jumpTarget this cmd)
				loopStart = (bodyStart - 1)
				conditionStart = (jumpTarget this (at opcodes loopStart))
				conditionEnd = (i - 1)
				bodyEnd = (conditionStart - 1)
				loopEnd = i
				loopRec = (array 'repeatUntil' loopEnd conditionStart conditionEnd bodyStart bodyEnd)
			} else {
				bodyStart = (jumpTarget this cmd)
				bodyEnd = (i - 1)
				loopStart = bodyStart
				loopEnd = i
				if ('for' == loopType) {
					loopStart = (bodyStart - 3)
					bodyEnd = (i - 2)
					loopEnd = (i + 1)
				} ('repeat' == loopType) {
					loopStart = (bodyStart - 1)
				}
				loopRec = (array loopType loopEnd bodyStart bodyEnd)
				if ('for' == loopType) {
					forIndexVar = (cmdArg this (at opcodes (i - 1)))
					loopRec = (copyWith loopRec forIndexVar)
				}
			}
			atPut controlStructures loopStart loopRec
			i = (loopEnd + 1)
		} else {
			i += 1
		}
	}
}

method loopTypeAt MicroBlocksDecompiler i seq {
	// Return the loop type based on the pattern of jumps starting at i in the given sequence.

	cmd = (at seq i)
	op = (cmdOp this cmd)
	if ('decrementAndJmp' == op) { return 'repeat' }
	if ('jmp' == op) {
		if ('forLoop' == (cmdOp this (at seq (i - 1)))) {
			return 'for'
		} else {
			return 'forever'
		}
	}
	if ('jmpFalse' == op) {
		loopStart = (i + (cmdArg this cmd))
		if (and (1 == loopStart)
				('jmp' == (cmdOp this (last seq)))
				(2 == (jumpTarget this (last seq)))) {
					return 'whenCondition'
		}
		if ('jmp' == (cmdOp this (at seq loopStart))) {
			return 'repeatUntil'
		} else {
			return 'waitUntil'
		}
	}
	return 'unknown loop type'
}

// Conditionals

method findIfs MicroBlocksDecompiler {
	// Create entries for all "if" and "if-else" constructs in the opcode sequence.

	for i (count opcodes) {
		cmd = (at opcodes i)
		if (and ('jmpFalse' == (cmdOp this cmd)) ((cmdArg this cmd) >= 0) (not (isAnd this opcodes cmd))) {
			trueStart = (i + 1)
			trueEnd = ((jumpTarget this cmd) - 1)
			lastCmdOfTrue = (at opcodes trueEnd)
			if ('jmp' == (cmdOp this lastCmdOfTrue)) {
				falseStart = (trueEnd + 1)
				falseEnd = ((jumpTarget this lastCmdOfTrue) - 1)
				conditionalRec = (array 'if-else' falseEnd trueStart (trueEnd - 1) falseStart falseEnd)
			} else {
				conditionalRec = (array 'if' trueEnd trueStart trueEnd)
			}
			atPut controlStructures i conditionalRec
		}
	}
}

method isAnd MicroBlocksDecompiler seq cmd {
	// Return true if the subsequence starting with cmd is was generated by an "and" expression.

	if ('jmpFalse' != (cmdOp this cmd)) { return false }
	i = (jumpTarget this cmd)
	cmdBeforeEnd = (at seq (i - 1))
	endCmd = (at seq i)
	return (and
		(cmdIs this cmdBeforeEnd 'jmp' 1)
		(cmdIs this endCmd 'pushImmediate' false))
}

// Decoding

method codeForSequence MicroBlocksDecompiler start end {
	// Decode the given sequence of opecodes and return a GP Reporter (if it is an expression)
	// or a GP Command (if it is a command or sequence of commands). The opcode sequence must
	// be complete and well-formed (e.g. if it encodes a command sequence it should leave the
	// stack empty) and does not contain any control structures (loops or if statements).

	if (isNil reporters) { buildReporterDictionary this }

	// save state so it can be restored after a recursive call
	oldCode = code
	oldStack = stack

	code = (list)
	stack = (list)
	i = start
	while (i <= end) {
		cmd = (at opcodes i)
		op = (cmdOp this cmd)
		next = (i + 1)
		if (notNil (at controlStructures i)) {
			ctrl = (at controlStructures i)
			op = (first ctrl)
			next = ((at ctrl 2) + 1)
		}
		if (isOneOf op 'jmpFalse' 'jmpTrue') { // old style "and" or "or" reporter
			i = (decodeOldANDorORreporter this op i)
		} (isOneOf op 'jmpAnd' 'jmpOr') { // new style "and" or "or" reporter
			i = (decodeNewANDorORreporter this op i)
		} ('pushBigImmediate' == op) {
			nextCmd = (at opcodes (i + 1))
			add stack ((((at nextCmd 3) << 8) | (at nextCmd 2)) >> 1) // convert obj to int
			i += 2
		} ('callFunction' == op) {
			cmdArg = (cmdArg this cmd)
			argCount = (cmdArg & 255)
			chunkID = ((cmdArg >> 8) & 255)
			fName = (functionNameForID (smallRuntime) chunkID)
			isReporter = (not (cmdIs this (at opcodes (i + 1)) 'pop' 1))
			if isReporter {
				add stack (makeCommand this fName argCount true)
				i += 1
			} else {
				add code (makeCommand this fName argCount)
				i += 2
			}
		} else {
			decodeCmd this i
			i = next
		}
	}

	result = nil
	if (and (isEmpty code) ((count stack) == 1)) {
		result = (first stack) // result is a reporter
	} else {
		// result is a command or squence of commands; stack should be empty
		if (not (isEmpty stack)) { error 'incomplete sequence?' }
		if (notEmpty code) {
			lastCmd = nil
			for cmd code {  // chain all commands together
				if (notNil lastCmd) {
					setField lastCmd 'nextBlock' cmd
				}
				lastCmd = cmd
			}
			result = (first code)
		}
	}

	// restore state and return the result
	code = oldCode
	stack = oldStack
	return result
}

method decodeOldANDorORreporter MicroBlocksDecompiler op i {
	// Decode an old-style AND or OR reporter (before jmpAnd/jmpOr).

	if ('jmpFalse' == op) { gpOp = 'and' } else { gpOp = 'or' }
	target = (jumpTarget this (at opcodes i))
	i += 1
	start = i
	while (not (and
		(op == (cmdOp this (at opcodes i)))
		(target == (jumpTarget this (at opcodes i))) )) {
			// find the jump at the end of the first argument
			i += 1
	}
	end = (i - 1)
	arg1 = (removeLast stack)
	arg2 = (codeForSequence this start end)
	add stack (newReporter gpOp arg1 arg2)
	return (i + 4)
}

method decodeNewANDorORreporter MicroBlocksDecompiler op seq i {
	// Decode an new AND or OR reporter (using jmpAnd/jmpOr).

	if ('jmpAnd' == op) { gpOp = 'and' } else { gpOp = 'or' }
	start = (i + 1)
	end = (i + (cmdArg this (at opcodes i)))
	arg1 = (removeLast stack)
	arg2 = (codeForSequence this start end)
	add stack (newReporter gpOp arg1 arg2)
	return (end + 1)
}

method decodeCmd MicroBlocksDecompiler i {
	cmd = (at opcodes i)
	cmdArg = (cmdArg this cmd)
	op = (cmdOp this cmd)
	if (notNil (at controlStructures i)) {
		ctrl = (at controlStructures i)
		cmd = ctrl
		op = (first cmd)
		atPut controlStructures i nil // avoid infinite recursion on 'forever' and 'waitUntil'
	}

	if ('halt' == op) {
		add code (newCommand 'stopTask')
	} (isOneOf op 'pushImmediate' 'pushLiteral') {
		add stack cmdArg

	// Variables
	} ('pushVar' == op) {
		add stack (newReporter 'v' (join 'V' cmdArg))
	} ('storeVar' == op) {
		add code (newCommand '=' (join 'V' cmdArg) (removeLast stack))
	} ('incrementVar' == op) {
		add code (newCommand '+=' (join 'V' cmdArg) (removeLast stack))
	} ('pushArgCount' == op) {
		add stack (newCommand 'pushArgCount')
	} ('pushArg' == op) {
		add stack (newReporter 'v' (join 'A' cmdArg))
	} ('storeArg' == op) {
		add code (newCommand '=' (join 'A' cmdArg) (removeLast stack))
	} ('incrementArg' == op) {
		add code (newCommand '+=' (join 'A' cmdArg) (removeLast stack))
	} ('pushLocal' == op) {
		add stack (newReporter 'v' (join 'L' cmdArg))
	} ('storeLocal' == op) {
		add code (newCommand '=' (join 'L' cmdArg) (removeLast stack))
	} ('incrementLocal' == op) {
		add code (newCommand '+=' (join 'L' cmdArg) (removeLast stack))

	} ('initLocals' == op) {
		// skip
	} ('returnResult' == op) {
		add code (makeCommand this 'return' 1)

	} ('if' == op) {
		add code (newCommand 'if'
			(removeLast stack)
			(codeForSequence this (at cmd 3) (at cmd 4)))
	} ('if-else' == op) {
		add code (newCommand 'if'
			(removeLast stack)
			(codeForSequence this (at cmd 3) (at cmd 4))
			true
			(codeForSequence this (at cmd 5) (at cmd 6)))
	} ('for' == op) {
		body = (codeForSequence this (at cmd 3) (at cmd 4))
		indexVarName = (join 'L' (at cmd 5)) // xxx look up actual local name
		add code (newCommand 'for' indexVarName (removeLast stack) body)
	} ('forever' == op) {
		body = (codeForSequence this (at cmd 3) (at cmd 4))
		add code (newCommand 'forever' body)
	} ('repeat' == op) {
		body = (codeForSequence this (at cmd 3) (at cmd 4))
		add code (newCommand 'repeat' (removeLast stack) body)
	} ('repeatUntil' == op) {
		condition = (codeForSequence this (at cmd 3) (at cmd 4))
		body = (codeForSequence this (at cmd 5) (at cmd 6))
		add code (newCommand 'repeatUntil' condition body)
	} ('waitUntil' == op) {
		condition = (codeForSequence this (at cmd 3) (at cmd 4))
		add code (newCommand 'waitUntil' condition)
	} ('whenCondition' == op) {
		condition = (codeForSequence this (at cmd 3) (at cmd 4))
		body = (codeForSequence this (at cmd 5) (at cmd 6))
		whenHat = (newCommand 'whenCondition' condition)
		if (notNil body) {
			setField whenHat 'nextBlock' body
		}
		add code whenHat

// old code for if (including handling of multiple cases)
// 	} ('if' == op) {
// 		if (notNil (at cmd 4)) { // if-else
// 			elsePart = (codeForSequence (at cmd 4))
// 			if ('if' == (primName elsePart)) {
// 				// combine nested if's
// 				argList = (list 'if' (removeLast stack) (codeForSequence (at cmd 3)))
// 				addAll argList (argList elsePart)
// 				add code (callWith 'newCommand' (toArray argList))
// 			} else {
// 				add code (newCommand 'if'
// 					(removeLast stack)
// 					(codeForSequence (at cmd 3))
// 					true
// 					(codeForSequence (at cmd 4)))
// 			}
// 		} else { // if without else
// 			add code (newCommand 'if'
// 				(removeLast stack)
// 				(codeForSequence (at cmd 3)))
// 		}

	// everything else
	} (contains reporters op) {
		add stack (makeCommand this op cmdArg)
	} else {
		add code (makeCommand this op cmdArg)
	}
	if (notNil ctrl) { atPut controlStructures i ctrl }
}

method makeCommand MicroBlocksDecompiler op argCount isReporter {
	// Return a GP Command or Reporter for the given op taking argCount items from the stack.
	// If optional isReporter arg is not supplied, look up the op in the reporters dictionary.

	if (isNil isReporter) {
		isReporter = (contains reporters op)
	}
	if (or ('callCommandPrimitive' == op) ('callReporterPrimitive' == op)) {
		argsStart = ((count stack) - (argCount - 1))
		primName = (at stack argsStart)
		primSet = (at stack (argsStart + 1))
		op = (join '[' primName ':' primSet ']')
		removeAt stack argsStart
		removeAt stack argsStart
		argCount += -2
	}

	if isReporter {
		result = (newIndexable 'Reporter' argCount)
	} else {
		result = (newIndexable 'Command' argCount)
	}
	setField result 'primName' op
	setField result 'lineno' 1
	setField result 'fileName' ''

	j = (count result) // index of last arg
	repeat argCount {
		setField result j (removeLast stack)
		j += -1
	}
	return result
}

// Helper Methods

method buildReporterDictionary MicroBlocksDecompiler {
	// Build a dictionary of the MicroBlocks built-in reporters. This is used to
	// decide whether a given opcode is a reporter or a command.

	reporters = (dictionary)
	add reporters 'pushArgCount'
	add reporters 'getArg'
	add reporters 'callReporterPrimitive'
	for spec (microBlocksSpecs (new 'SmallCompiler')) {
		if (and (isClass spec 'Array') ('r' == (first spec))) {
			op = (at spec 2)
			if (not (beginsWith op '[')) { add reporters (at spec 2) }
		}
	}
}
