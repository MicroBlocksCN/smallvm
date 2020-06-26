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

defineClass MicroBlocksDecompiler decoder opcodes

method decompile MicroBlocksDecompiler bytecodes chunkType {
	// Approach:
	//	0. Convert bytecodes into sequence of opcode tuples
	//	1. find and replace loops
	//	2. find and replace if's (recursively)
	//	3. walk the entire tree and generate code

	decoder = (new 'MicroBlocksSequenceDecoder')
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
	sequence = (copyFromTo opcodes 1 lastInstruction)
printSequence this sequence
print '----'
return

	sequence = (replaceLoops this sequence)
	sequence = (replaceIfs this sequence)

	print '----'
	printSequence this sequence
	print '----'

	if (cmdIs this (last sequence) 'halt' 0) { removeLast sequence }
	code = (addHatBlock this chunkType (codeForSequence sequence))
	print (prettyPrint this code)
	showCodeInHand this code
}

method showCodeInHand MicroBlocksDecompiler code {
	block = (toBlock code)
	grab (hand (global 'page')) block
	fixBlockColor block
}

// Command tuple operations

method cmdIndex MicroBlocksDecompiler cmd { return (at cmd 1) }
method cmdOp MicroBlocksDecompiler cmd { return (at cmd 2) }
method cmdArg MicroBlocksDecompiler cmd { return (at cmd 3) }

method jumpTarget MicroBlocksDecompiler jmpCmd {
	// Return the target index of the given jump command.

	return (+ (cmdIndex this jmpCmd) (cmdArg this jmpCmd) 1)
}

method cmdAt MicroBlocksDecompiler seq origIndex {
	// Return the command with the given original index in the given sequence.
	// Since the sequence may have been modified, this requires scanning the opcodes
	// to find the one tagged with origIndex.

	for cmd seq {
		if (origIndex == (cmdIndex this cmd)) { return cmd }
	}
	return nil
}

method cmdIs MicroBlocksDecompiler cmd op arg {
	// Return true of the given command has the given op and argument.

	return (and (notNil cmd) (op == (at cmd 2)) (arg == (at cmd 3)))
}

// Debugging

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

method addHatBlock MicroBlocksDecompiler chunkType code {
	// Prefix given code with a hat block based on chunkType and return the result.

	result = code
	if (4 == chunkType) {
		result = (newCommand 'whenStarted')
		setField result 'nextBlock' code
	} (6 == chunkType) {
		if ('recvBroadcast' == (primName code)) {
			result = (newCommand 'whenBroadcastReceived' (first (argList code)))
			setField result 'nextBlock' (nextBlock code)
		}
	} (7 == chunkType) {
		result = (newCommand 'whenButtonPressed' 'A')
		setField result 'nextBlock' code
	} (8 == chunkType) {
		result = (newCommand 'whenButtonPressed' 'B')
		setField result 'nextBlock' code
	} (9 == chunkType) {
		result = (newCommand 'whenButtonPressed' 'A+B')
		setField result 'nextBlock' code
	}
	return result
}

// Loops

method replaceLoops MicroBlocksDecompiler seq {
	// Replace loops in the given sequence and return the result.

	i = 1
	while (i <= (count seq)) {
		cmd = (at seq i)
		if (and
			(isOneOf (cmdOp this cmd) 'jmp' 'jmpFalse' 'decrementAndJmp')
			((cmdArg this cmd) < 0)) {
				loopType = (loopTypeAt this i seq)
				if ('whenCondition' == loopType) {
					condition = (copyFromTo seq 4 (i - 1))
					bodyStart = (i + 1)
					bodyEnd = ((count seq) - 1)
					body = (replaceIfs this (copyFromTo seq bodyStart bodyEnd))
					whenHat = (array 1 'whenCondition' condition body)
					seq = (array whenHat)
					i = ((count seq) + 1)
				} ('repeatUntil' == loopType) {
					bodyStart = (jumpTarget this cmd)
					loopStart = (bodyStart - 1)
					conditionStart = (jumpTarget this (cmdAt this seq loopStart))
					conditionEnd = (i - 1)
					bodyEnd = (conditionStart - 1)
					loopEnd = i

					bodyStart = (indexOf seq (cmdAt this seq bodyStart))
					bodyEnd = (indexOf seq (cmdAt this seq bodyEnd))
					body = (replaceIfs this (copyFromTo seq bodyStart bodyEnd))

					conditionStart = (indexOf seq (cmdAt this seq conditionStart))
					conditionEnd = (indexOf seq (cmdAt this seq conditionEnd))
					condition = (replaceIfs this (copyFromTo seq conditionStart conditionEnd))

					loopCmd = (array 0 'repeatUntil' condition body)

					seq = (join
						(copyFromTo seq 1 (loopStart - 1))
						(array loopCmd)
						(copyFromTo seq (loopEnd + 1) (count seq)))
					i = loopStart
				} else {
					bodyStart = (jumpTarget this cmd)
					bodyEnd = (i - 1)
					loopStart = bodyStart
					loopEnd = i
					if ('for' == loopType) {
						forIndexVar = (cmdArg this (at seq (i - 1)))
						loopStart = (bodyStart - 3)
						bodyEnd = (i - 2)
						loopEnd = (i + 1)
					} ('repeat' == loopType) {
						loopStart = (bodyStart - 1)
					}
					loopStart = (indexOf seq (cmdAt this seq loopStart))
					loopEnd = (indexOf seq (cmdAt this seq loopEnd))
					body = (replaceIfs this (copyFromTo seq bodyStart bodyEnd))
					loopCmd = (array 0 loopType body)
					if ('for' == loopType) {
						loopCmd = (copyWith loopCmd forIndexVar)
					}
					seq = (join
						(copyFromTo seq 1 (loopStart - 1))
						(array loopCmd)
						(copyFromTo seq (loopEnd + 1) (count seq)))
					i = loopStart
				}
		} else {
			i += 1
		}
	}
	return seq
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

method replaceIfs MicroBlocksDecompiler seq {
	// Replace "if" and "if-else" statements in the given sequence and return the result.

	i = 1
	while (i <= (count seq)) {
		cmd = (at seq i)
		if (and ('jmpFalse' == (cmdOp this cmd)) ((cmdArg this cmd) >= 0) (not (isOr this seq cmd))) {
			trueStart = ((cmdIndex this cmd) + 1)
			trueEnd = ((jumpTarget this cmd) - 1)
			lastCmdOfTrue = (cmdAt this seq trueEnd)
			if ('jmp' == (cmdOp this lastCmdOfTrue)) {
				falseEnd = ((jumpTarget this lastCmdOfTrue) - 1)
				trueCase = (copySeqFromTo this seq trueStart (trueEnd - 1))
				falseCase = (copySeqFromTo this seq (trueEnd + 1) falseEnd)
				trueCase = (replaceIfs this trueCase)
				falseCase = (replaceIfs this falseCase)
				ifEnd = (indexOf seq (cmdAt this seq falseEnd))
			} else {
				trueCase = (copySeqFromTo this seq trueStart trueEnd)
				trueCase = (replaceIfs this trueCase)
				falseCase = nil
				ifEnd = (indexOf seq (cmdAt this seq trueEnd))
			}
			conditionalCmd = (array 0 'if' trueCase falseCase)
			seq = (join
				(copyFromTo seq 1 (i - 1))
				(array conditionalCmd)
				(copyFromTo seq (ifEnd + 1) (count seq)))
			i = (ifEnd + 1)
		} else {
			i += 1
		}
	}
	return seq
}

method copySeqFromTo MicroBlocksDecompiler seq from to {
	// Copy the subsequence with the given range of indices in the original sequence.

	startIndex = (indexOf seq (cmdAt this seq from))
	endIndex = (indexOf seq (cmdAt this seq to))
	return (copyFromTo seq startIndex endIndex)
}

method isOr MicroBlocksDecompiler seq cmd {
	// Return true if the subsequence starting with cmd is was generated by an "or" expression.

	if ('jmpFalse' != (cmdOp this cmd)) { return false }
	i = (jumpTarget this cmd)
	cmdBeforeEnd = (cmdAt this seq (i - 1))
	endCmd = (cmdAt this seq i)
	return (and
		(cmdIs this cmdBeforeEnd 'jmp' 1)
		(cmdIs this endCmd 'pushImmediate' false))
}

// A MicroBlocksSequenceDecoder translates an opcode sequence into GP code representing blocks.

defineClass MicroBlocksSequenceDecoder reporters code stack

to codeForSequence seq {
	// Return a GP Reporter or list GP Commands for the given expression.

	if (isEmpty seq) { return nil }
	return (decode (new 'MicroBlocksSequenceDecoder') seq)
}

method decode MicroBlocksSequenceDecoder seq {
	// Decode the given sequence of opecodes and return a GP Reporter (if it is an expression)
	// Commands (if it is a command or sequence of commands). The opcode sequence must be
	// complete and well-formed (e.g. if it encodes a command sequence it should leave the
	// stack empty) and does not contain any control structures (loops or if statements).

	if (isNil reporters) { buildReporterDictionary this }
	code = (list)
	stack = (list)
	i = 1
	while (i <= (count seq)) {
		op = (cmdOp this (at seq i))
		if (isOneOf op 'jmpFalse' 'jmpTrue') { // old style "and" or "or" reporter
			i = (decodeOldANDorORreporter this op seq i)
		} (isOneOf op 'jmpAnd' 'jmpOr') { // new style "and" or "or" reporter
			i = (decodeNewANDorORreporter this op seq i)
		} ('pushBigImmediate' == op) {
			next = (at seq (i + 1))
			add stack (((at next 3) << 8) | (at next 2))
			i += 2
		} ('callFunction' == op) {
			// xxx need to get actual function name
			// xxx need to distinguish between commands and reporters
			cmdArg = (cmdArg this (at seq i))
			argCount = (cmdArg & 255)
			fName = (join 'f' ((cmdArg >> 8) & 255))
			add code (makeCommand this fName argCount)
			i += 2
		} else {
			decodeCmd this (at seq i)
			i += 1
		}
	}
	if (and (isEmpty code) ((count stack) == 1)) {
		return (first stack) // result is a single reporter
	}
	if (not (isEmpty stack)) { error 'incomplete sequence?' }
	for cmd code {
		if (notNil lastCmd) {
			setField lastCmd 'nextBlock' cmd
		}
		lastCmd = cmd
	}
	return (first code)
}

method decodeOldANDorORreporter MicroBlocksSequenceDecoder op seq i {
	// Decode an old-style AND or OR reporter (before jmpAnd/jmpOr).

	if ('jmpFalse' == op) { gpOp = 'and' } else { gpOp = 'or' }
	i += 1
	start = i
	while (op != (cmdOp this (at seq i))) { i += 1 }
	arg1 = (removeLast stack)
	arg2 = (codeForSequence (copyFromTo seq start (i - 1)))
	add stack (newReporter gpOp arg1 arg2)
	return (i + 4)
}

method decodeNewANDorORreporter MicroBlocksSequenceDecoder op seq i {
	// Decode an new AND or OR reporter (using jmpAnd/jmpOr).

	if ('jmpAnd' == op) { gpOp = 'and' } else { gpOp = 'or' }
	start = (i + 1)
	end = (i + (cmdArg this (at seq i)))
	arg1 = (removeLast stack)
	arg2 = (codeForSequence (copyFromTo seq start end))
	add stack (newReporter gpOp arg1 arg2)
	return (end + 1)
}

method decodeCmd MicroBlocksSequenceDecoder cmd {
	op = (cmdOp this cmd)
	cmdArg = (cmdArg this cmd)
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
		if (notNil (at cmd 4)) { // if-else
			elsePart = (codeForSequence (at cmd 4))
			if ('if' == (primName elsePart)) {
				// combine nested if's
				argList = (list 'if' (removeLast stack) (codeForSequence (at cmd 3)))
				addAll argList (argList elsePart)
				add code (callWith 'newCommand' (toArray argList))
			} else {
				add code (newCommand 'if'
					(removeLast stack)
					(codeForSequence (at cmd 3))
					true
					(codeForSequence (at cmd 4)))
			}
		} else { // if without else
			add code (newCommand 'if'
				(removeLast stack)
				(codeForSequence (at cmd 3)))
		}
	} ('whenCondition' == op) {
		whenHat = (newCommand 'whenCondition' (codeForSequence (at cmd 3)))
		if (not (isEmpty (at cmd 4))) {
			setField whenHat 'nextBlock' (codeForSequence (at cmd 4))
		}
		add code whenHat

	// loops
	} ('forever' == op) {
		add code (newCommand 'forever' (codeForSequence cmdArg))
	} ('repeat' == op) {
		add code (newCommand 'repeat' (removeLast stack) (codeForSequence cmdArg))
	} ('for' == op) {
		indexVarName = (join 'L' (at cmd 4)) // xxx look up actual local name
		add code (newCommand 'for' indexVarName (removeLast stack) (codeForSequence cmdArg))
	} ('repeatUntil' == op) {
		add code (newCommand 'repeatUntil' (codeForSequence cmdArg) (codeForSequence (at cmd 4)))
	} ('waitUntil' == op) {
		add code (newCommand 'waitUntil' (codeForSequence cmdArg))

	// everything else
	} (contains reporters op) {
		add stack (makeCommand this op cmdArg)
	} else {
		add code (makeCommand this op cmdArg)
	}
}

method makeCommand MicroBlocksSequenceDecoder op argCount {
	// Return a GP Command or Reporter for the given op taking argCount items from the stack.

	isReporter = (contains reporters op)
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

method cmdOp MicroBlocksSequenceDecoder cmd { return (at cmd 2) }
method cmdArg MicroBlocksSequenceDecoder cmd { return (at cmd 3) }

method buildReporterDictionary MicroBlocksSequenceDecoder {
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
