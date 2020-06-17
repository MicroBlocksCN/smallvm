// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to blocks
// John Maloney, March, 2020

to decompileBytecodes bytecodes {
	return (decompile (new 'MicroBlocksDecompiler') bytecodes)
}

defineClass MicroBlocksDecompiler reporters opcodes sequence stack code

method decompile MicroBlocksDecompiler bytecodes {
	collectReporters this

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

// debug: show original opcodes
// 	for i (count opcodes) {
// 		print (at opcodes i)
// 	}
// debug: print sequence
//	printSequence this sequence

 	findLoops this
	print '----'
	printSequence this sequence
	print '----'
	printCode this
}

method collectReporters MicroBlocksDecompiler {
	reporters = (dictionary)
	add reporters 'callReporterPrimitive'
	for spec (microBlocksSpecs (new 'SmallCompiler')) {
		if (and (isClass spec 'Array') ('r' == (first spec))) {
			op = (at spec 2)
			if (not (beginsWith op '[')) { add reporters (at spec 2) }
		}
	}
	print 'got' (count reporters) 'reporters'
}

method printSequence MicroBlocksDecompiler seq indent {
	if (isNil indent) { indent = 0 }
	spaces = (joinStrings (newArray indent ' '))
	for cmd seq {
		if (cmdIsControl this cmd) {
			print (join spaces (cmdOp this cmd))
			printSequence this (cmdSubsequence this cmd) (indent + 4)
		} else {
			print (join spaces (cmdOp this cmd) ' ' (cmdArg this cmd))
		}
	}
}

// Accessors for command tuples

method cmdIndex MicroBlocksDecompiler cmd { return (at cmd 1) }
method cmdOp MicroBlocksDecompiler cmd { return (at cmd 2) }
method cmdArg MicroBlocksDecompiler cmd { return (at cmd 3) }
method cmdSubsequence MicroBlocksDecompiler cmd { return (at cmd 3) }
method cmdIsControl MicroBlocksDecompiler cmd {
	return (isOneOf (at cmd 2)
		'_sequence_' 'forever' 'repeat' 'if' 'for' 'repeatUntil'
		'whenStarted' 'whenButtonPressed' 'whenCondition')
}

method findLastInstruction MicroBlocksDecompiler {
	// Find the index of the last instruction in opcodes. The last instruction
	// may be followed by literal values such as strings.

	pushLiteral = 4
	result = (count opcodes)
	for i (count opcodes) {
		if (i > result) { return result }
		instr = (at opcodes i)
		if (pushLiteral == (cmdOp this instr)) {
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
	opcodeDefs = (opcodes (initialize (new 'SmallCompiler')))
	opcodeToName = (range 0 255)
	for p (sortedPairs opcodeDefs false) {
		atPut opcodeToName ((first p) + 1) (last p)
	}
	for i lastInstruction {
		instr = (at opcodes i)
		op = (at opcodeToName ((at instr 2) + 1))
		atPut instr 2 op
	}
}

method decodeImmediates MicroBlocksDecompiler lastInstruction {
	for i lastInstruction {
		instr = (at opcodes i)
		if ('pushImmediate' == (cmdOp this instr)) {
			val = (last instr)
			decoded = val
			if (1 == (val % 2)) {
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

method findLoops MicroBlocksDecompiler {
	i = 1
	while (i <= (count sequence)) {
		cmd = (at sequence i)
		if (and
			(isOneOf (cmdOp this cmd) 'jmp' 'jmpFalse' 'decrementAndJmp')
			((cmdArg this cmd) < 0)) {
				loopType = (loopTypeAt this i)
				bodyStart = (+ (cmdIndex this cmd) (cmdArg this cmd) 1)
				bodyEnd = (i - 1)
				loopStart = bodyStart
				loopEnd = i
				if ('for' == loopType) {
					loopStart = (bodyStart - 3)
					bodyEnd = (i - 2)
					loopEnd = (i + 1)
				} (isOneOf loopType 'repeat' 'repeatUntil') {
					loopStart = (bodyStart - 1)
				}
				loopStart = (indexOfCmd this loopStart)
				newCmd = (array loopStart loopType (copyFromTo sequence bodyStart bodyEnd))
				sequence = (join
					(copyFromTo sequence 1 (loopStart - 1))
					(array newCmd)
					(copyFromTo sequence (loopEnd + 1) (count sequence)))
				i = loopStart
		} else {
			i += 1
		}
	}
}

method indexOfCmd MicroBlocksDecompiler originalIndex {
	// Return the current index of the command with the given original index in sequence.

	for i (count sequence) {
		cmd = (at sequence i)
		if (originalIndex == (cmdIndex this cmd)) { return i }
	}
	error 'command index not found'
}

method loopTypeAt MicroBlocksDecompiler i {
	jmpCmd = (cmdOp this (at sequence i))
	if ('jmp' == jmpCmd) {
		if ('forLoop' == (cmdOp this (at sequence (i - 1)))) {
			return 'for'
		} else {
			return 'forever'
		}
	}
	if ('jmpFalse' == jmpCmd) { return 'repeatUntil' }
	if ('decrementAndJmp' == jmpCmd) { return 'repeat' }
	return 'unknown loop type'
}

method printCode MicroBlocksDecompiler {
	code = (list)
	stack = (list)
	for cmd sequence {
		processCmd this cmd
	}
	for cmd code {
		print (prettyPrint this cmd)
	}
}

method processCmd MicroBlocksDecompiler cmd {
	op = (cmdOp this cmd)
	cmdArg = (cmdArg this cmd)
	if (isOneOf op 'pushImmediate' 'pushBigImmediate' 'pushLiteral') {
		add stack cmdArg
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
		// do nothing
	} ('returnResult' == op) {
		add code (makeCommand this op 1)
	} ('forever' == op) {
		// xxx do nothing for now
	} (contains reporters op) {
		add stack (makeReporter this op cmdArg)
	} else {
		add code (makeCommand this op cmdArg)
	}
}

method makeCommand MicroBlocksDecompiler op argCount {
	if ('callCommandPrimitive' == op) {
		primName = (removeLast stack)
		primSet = (removeLast stack)
		op = (join '[' primSet ':' primName ']')
		argCount += -2
	}

	result = (newIndexable 'Command' argCount)
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

method makeReporter MicroBlocksDecompiler op argCount {
	if ('callReporterPrimitive' == op) {
		primName = (removeLast stack)
		primSet = (removeLast stack)
		op = (join '[' primSet ':' primName ']')
		argCount += -2
	}

	result = (newIndexable 'Reporter' argCount)
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

method prettyPrint MicroBlocksDecompiler expression {
	pp = (new 'PrettyPrinter')
	if (isClass expression 'Reporter') {
		if (isOneOf (primName expression) 'v') {
			return (join '(v ' (first (argList expression)) ')')
		} else {
			return (join '(' (prettyPrint pp expression) ')')
		}
	} else {
		return (prettyPrint pp expression)
	}
	return '???' // should not get here
}
