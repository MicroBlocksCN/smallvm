// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to blocks
// John Maloney, March, 2020

// To do:
// [ ] decode "or" and "and"
// [ ] decode "if"
// [ ] decode "when" hats
// [ ] handle function calls
// [ ] store local names
// [ ] store function spec and parameter names

to decompileBytecodes bytecodes {
	return (decompile (new 'MicroBlocksDecompiler') bytecodes)
}

defineClass MicroBlocksDecompiler reporters opcodes stack code

method decompile MicroBlocksDecompiler bytecodes {
	buildReporterDictionary this

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

// replaceIfs this sequence
// return

// debug: show original opcodes
// 	for i (count opcodes) {
// 		print (at opcodes i)
// 	}
// debug: print sequence
//	printSequence this sequence

 	sequence = (replaceLoops this sequence)
	print '----'
	printSequence this sequence
	print '----'
	printCode this (codeForSequence this sequence)
}

method buildReporterDictionary MicroBlocksDecompiler {
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

// Command tuple operations

method cmdIndex MicroBlocksDecompiler cmd { return (at cmd 1) }
method cmdOp MicroBlocksDecompiler cmd { return (at cmd 2) }
method cmdArg MicroBlocksDecompiler cmd { return (at cmd 3) }

method cmdIsControl MicroBlocksDecompiler cmd {
	return (isOneOf (at cmd 2)
		'forever' 'repeat' 'if' 'for' 'repeatUntil'
		'whenStarted' 'whenButtonPressed' 'whenCondition')
}

method cmdIs MicroBlocksDecompiler cmd op arg {
	// Return true of the given command has the given op and argument.

	return (and (op == (at cmd 2)) (arg == (at cmd 3)))
}

// Debugging

method printSequence MicroBlocksDecompiler seq indent {
	if (isNil indent) { indent = 0 }
	spaces = (joinStrings (newArray indent ' '))
	for cmd seq {
		if (cmdIsControl this cmd) {
			print (join spaces (cmdOp this cmd))
			printSequence this (cmdArg this cmd) (indent + 4)
		} else {
			print (join spaces (cmdOp this cmd) ' ' (cmdArg this cmd))
		}
	}
}

method printCode MicroBlocksDecompiler cmdListOrReporter {
	if (isClass cmdListOrReporter 'Reporter') {
		print (prettyPrint this cmdListOrReporter)
	} else {
		for cmd cmdListOrReporter {
			print (prettyPrint this cmd)
		}
	}
}

// Helper methods

method findLastInstruction MicroBlocksDecompiler {
	// Find the index of the last instruction in opcodes. The last instruction
	// may be followed by literal values such as strings.
	// Replace string literal offsets with the referenced string.

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

method replaceLoops MicroBlocksDecompiler seq {
	// Replace loops in the given sequence and return the result.

	i = 1
	while (i <= (count seq)) {
		cmd = (at seq i)
		if (and
			(isOneOf (cmdOp this cmd) 'jmp' 'jmpFalse' 'decrementAndJmp')
			((cmdArg this cmd) < 0)) {
				loopType = (loopTypeAt this i seq)
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
				loopStart = (indexOfCmd this loopStart seq)
				loopEnd = (indexOfCmd this loopEnd seq)
				newCmd = (array 0 loopType (copyFromTo seq bodyStart bodyEnd))
				if ('repeatUntil' == loopType) {
					conditionStart = (+ loopStart (cmdArg this (at seq loopStart)) 1)
					newCmd = (copyWith newCmd conditionStart)
				}
				seq = (join
					(copyFromTo seq 1 (loopStart - 1))
					(array newCmd)
					(copyFromTo seq (loopEnd + 1) (count seq)))
				i = loopStart
		} else {
			i += 1
		}
	}
	return seq
}

// Overall:
//	 1. find and replace loops
//   2. find and replace if's
//	 3. walk tree and generate code

// Find the end of the if (from jump at end of first action)
// Push top of stack as first condition test
// Repeatedly:
//	Find the end of current action and record its subsequence
//	Find the end of the next test and record the code for it
//	(it will be an expression so it can't contain if's or loops)
// Replace if's in the action subsequences
// Replace the entire if sequence with new if structure

method replaceIfs MicroBlocksDecompiler seq {
	// Replace "if" statements in the given sequence and return the result.

	i = 1
	while (i <= (count seq)) {
		cmd = (at seq i)
		if (and ('jmpFalse' == (cmdOp this cmd)) ((cmdArg this cmd) >= 0) (not (isOr this seq cmd))) {
			ifStart = i
			ifEnd = (targetIndex this cmd)
			lastCmdOfCase = (cmdAt this seq (ifEnd - 1))
			if ('jmp' == (cmdOp this lastCmdOfCase)) {
				ifEnd = ((targetIndex this lastCmdOfCase) - 1)
			}
print 'found if from' ifStart 'to' ifEnd
			// construct if structure with tests and actions
			// replace it in the sequence

			i = (ifEnd + 1)
		} else {
			i += 1
		}
	}
	return seq
}

method findIFs MicroBlocksDecompiler seq { // xxx
	// Replace loops in the given sequence and return the result.

	i = 1
	while (i <= (count seq)) {
		cmd = (at seq i)
		if (and
			('jmpFalse' == (cmdOp this cmd))
			((cmdArg this cmd) >= 0)
			(not (isOr this seq cmd))) {
				actionCount = 0

print 'found if' i (countIfCases this seq cmd)
		}
		i += 1
	}
}

method countIfCases MicroBlocksDecompiler seq cmd { // xxx
	result = 1
	if ('jmpFalse' != (cmdOp this cmd)) { return result }
	i = 0
	endOfSequence = (count seq)
	while (i <= endOfSequence) {
		result += 1
		i = (+ (cmdIndex this cmd) (cmdArg this cmd) 1)
		lastCmdOfCase = (cmdAt this seq (i - 1))
print '  lastCmdOfCase' lastCmdOfCase

		if ('jmp' != (cmdOp this lastCmdOfCase)) { return result }
		while ('jmpFalse' != (cmdOp this (at seq i))) {
			// scan for the end of the condition test
			i += 1
			if (i > endOfSequence) { return result }
		}
		cmd = (at seq i)
	}
	return result
}

method isOr MicroBlocksDecompiler seq cmd {
	// Return true if the subsequence starting with cmd is was generated by an "or" expression.

	if ('jmpFalse' != (cmdOp this cmd)) { return false }
	i = (+ (cmdIndex this cmd) (cmdArg this cmd) 1)
	cmdBeforeEnd = (cmdAt this seq (i - 1))
	endCmd = (cmdAt this seq i)
	return (and
		(cmdIs this cmdBeforeEnd 'jmp' 1)
		(cmdIs this endCmd 'pushImmediate' false))
}


method cmdAt MicroBlocksDecompiler seq origIndex {
	// Return the command with the given original index in the given sequence.

	for cmd seq {
		if (origIndex == (cmdIndex this cmd)) { return cmd }
	}
	error 'command not found'
}

method targetIndex MicroBlocksDecompiler jmpCmd {
	// Return the target index of the given jump command.

	return (+ (cmdIndex this jmpCmd) (cmdArg this jmpCmd) 1)
}

method loopTypeAt MicroBlocksDecompiler i seq {
	jmpCmd = (cmdOp this (at seq i))
	if ('jmp' == jmpCmd) {
		if ('forLoop' == (cmdOp this (at seq (i - 1)))) {
			return 'for'
		} else {
			return 'forever'
		}
	}
	if ('jmpFalse' == jmpCmd) {
		loopStart = (i + (cmdArg this (at seq i)))
		if ('jmp' == (cmdOp this (at seq loopStart))) {
			return 'repeatUntil'
		} else {
			return 'waitUntil'
		}
	}
	if ('decrementAndJmp' == jmpCmd) { return 'repeat' }
	return 'unknown loop type'
}

// Converting to GP code

method codeForSequence MicroBlocksDecompiler seq {
	code = (list)
	stack = (list)
	for cmd seq {
		processCmd this cmd
	}
	if (and (isEmpty code) ((count stack) == 1)) {
		return (first stack) // result is a single reporter
	} (isEmpty stack) {
		return code // result is a command sequence
	}
	print 'stack:' (count stack) 'commands:' (count code)
	error 'incomplete sequence?'
}

method processCmd MicroBlocksDecompiler cmd {
	op = (cmdOp this cmd)
	cmdArg = (cmdArg this cmd)
	if ('halt' == op) {
		add code (newCommand 'stopTask')
	} (isOneOf op 'pushImmediate' 'pushBigImmediate' 'pushLiteral') {
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
	// loops
	} ('forever' == op) {
		// xxx placeholder
		add code (newCommand (join op '_placeholder'))
	} ('repeat' == op) {
		// xxx placeholder
		add code (newCommand (join op '_placeholder'))
	} ('for' == op) {
		// xxx placeholder
		add code (newCommand (join op '_placeholder'))
	} ('repeatUntil' == op) {
		// xxx placeholder
		add code (newCommand (join op '_placeholder'))
	} ('waitUntil' == op) {
		// xxx placeholder
		add code (newCommand (join op '_placeholder'))
	} ('callFunction' == op) {
		// xxx placeholder
		add code (newCommand (join op '_placeholder'))
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
