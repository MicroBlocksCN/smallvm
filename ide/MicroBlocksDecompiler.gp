// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to blocks
// John Maloney, March, 2020

// To do:
// [x] save comments (implmented but not yet enabled)
// [x] remove the final "return false" of reporter functions
// [x] remove recvBroadcast from functions
// [ ] make test method that compiles and decompiles all code in a project and checks result
// [ ] make test method that clears current scripts then fetched and decompiles code from board
// [ ] make compiler store local names
// [ ] use local names
// [ ] store function spec and parameter names

to decompileBytecodes bytecodes chunkType {
	return (decompile (new 'MicroBlocksDecompiler') bytecodes chunkType)
}

defineClass MicroBlocksDecompiler reporters opcodes controlStructures endOfLiterals code stack msgName argNames

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
	if (0 == endOfLiterals) { endOfLiterals = ((count opcodes) + 1) }
	getOpNames this lastInstruction
	decodeImmediates this lastInstruction
	opcodes = (bodyOpcodes this lastInstruction chunkType)
	controlStructures = (newArray (count opcodes))
	findArgs this
	findLoops this
	findIfs this
	fixLocals this

	debug = true
	if debug {
		print '----'
		printSequence2 this
		print '----'
		printSequence3 this 1 (count opcodes) 0
		print '----'
	}

	if (cmdIs this (last opcodes) 'halt' 0) { removeLast opcodes }
	gpCode = (addHatBlock this chunkType (codeForSequence this 1 (count opcodes)))
	if (isNil gpCode) {
		inform (global 'page') 'No decompiled code'
		return
	}
	fixBooleanAndColorArgs this gpCode
	if debug { print (prettyPrint this gpCode) }
	return gpCode
}

method bodyOpcodes MicroBlocksDecompiler lastInstruction chunkType {
	// Return the range of opcodes for the body of the script.
	// Omit the initial initLocals and the final halt instructions for normal scripts
	// and the prefix and postfix of functions.

	msgName = '' // default message name
	start = 1
	end = lastInstruction
	if ('initLocals' == (cmdOp this (at opcodes 1))) { start += 1 }
	if (3 == chunkType) {
		if ('recvBroadcast' == (cmdOp this (at opcodes 3))) { // when received or user-defined block
			msgName = (cmdArg this (at opcodes 2))
			start = 4
		}
		// remove final 'return false'
		if (and
			('returnResult' == (cmdOp this (at opcodes end)))
			(cmdIs this (at opcodes (end - 1)) 'pushImmediate' false)) {
				end += -2
		}
	} else {
		if ('halt' == (cmdOp this (at opcodes end))) {
			end += -1
		}
	}
	return (copyFromTo opcodes start end)
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
		atPut controlStructures i nil // avoid infinite recursion on 'forever' and 'waitUntil'
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
			} ('waitUntil' == op) {
				print (join spaces 'wait until')
				printSequence3 this (at ctrl 3) (at ctrl 4) (indent + 4)
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
	} (isClass expression 'Function') {
		return (prettyPrintFunction pp expression)
	} else {
		return (prettyPrintList pp expression)
	}
	return '???' // should not get here
}

// Helper methods

method findArgs MicroBlocksDecompiler {
	maxArgIndex = -1
	for cmd opcodes {
		if (isOneOf (cmdOp this cmd) 'pushArg' 'storeArg' 'incrementArg') {
			argIndex = (cmdArg this cmd)
			if (argIndex > maxArgIndex) { maxArgIndex = argIndex }
		}
	}
	argNames = (list)
	i = 0
	while (i <= maxArgIndex) {
		add argNames (join 'arg' (i + 1))
	}
}

method findLastInstruction MicroBlocksDecompiler {
	// Find the index of the last instruction in opcodes. The last instruction
	// may be followed by literal values such as strings. Replace the offsets
	// in 'pushLiteral' instructions with the referenced literal string.

	endOfLiterals = 0
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
			literalString = (readLiteral this literalIndex)
			atPut instr 3 literalString // insert the literal into instruction
			litWords = (floor (((byteCount literalString) + 3) / 4))
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
	endOfLit = (+ literalIndex wordCount 1)
	if (endOfLit > endOfLiterals) { endOfLiterals = endOfLit }
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

method recordControlStructure MicroBlocksDecompiler i newRec {
	// Record a control structure record for the given index.
	// When multiple control structures share the same starting index
	// (e.g. nested 'forever' loops), collect them in a 'multiple' record.

	existing = (at controlStructures i)
	if (isNil existing) { // most common case
		atPut controlStructures i newRec
		return
	}
	// handle multiple control structures with the same starting index
	newEnd = (max (at existing 2) (at newRec 2))
	if ('multiple' == (first existing)) {
		// append to existing 'multiple' record
		add existing newRec
		atPut existing 2 newEnd
	} else {
		// convert to a 'multiple' record listing both existing and new records
		atPut controlStructures i (list 'multiple' newEnd existing newRec)
	}
}

// GPCode transformations

method addHatBlock MicroBlocksDecompiler chunkType gpCode {
	// Prefix given code with a hat block based on chunkType and return the result.

	result = gpCode
	// chunk types 1 and 2 are command and reporter blocks without a hat
	if (3 == chunkType) {
		// Note: result is Function object
		project = (project (scripter (smallRuntime)))
		module = (main project)
		funcName = msgName
		if (isNil funcName) { funcName = 'anonymous' }
		result = (newFunction funcName argNames gpCode module)
	} (4 == chunkType) {
		result = (newCommand 'whenStarted')
		setField result 'nextBlock' gpCode
	} (5 == chunkType) {
		// whenCondition hat; already added
	} (6 == chunkType) {
		result = (newCommand 'whenBroadcastReceived' msgName)
		setField result 'nextBlock' gpCode
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

method fixBooleanAndColorArgs MicroBlocksDecompiler gpCode {
	for block (allBlocks gpCode) {
		spec = (specForOp (authoringSpecs) (primName block))
		if (isNil spec) {
			// make up a default spec
			spec = (blockSpecFromStrings (primName block) '' '' '' (array))
		}
		args = (argList block)
		for i (min (slotCount spec) (count args)) {
			slotType = (first (slotInfoForIndex spec i))
			val = (at args i)
			if (and ('color' == slotType) (isClass val 'Integer')) {
				c = (color ((val >> 16) & 255)  ((val >> 8) & 255) (val & 255))
				setArg block i c
			} (and ('bool' != slotType) (isClass val 'Boolean') ) {
				setArg block i (newReporter 'booleanConstant' val)
			}
			info = (slotInfoForIndex spec i)
		}
	}
}

// Loops

method findLoops MicroBlocksDecompiler {
	// Create entries for all loop constructs in the opcode sequence.

	i = 1
	while (i <= (count opcodes)) {
		cmd = (at opcodes i)
		if (and (isOneOf (cmdOp this cmd) 'jmp' 'jmpFalse' 'decrementAndJmp' 'waitUntil')
				((cmdArg this cmd) < 0)) {
			// a jump instruction with a negative offset marks the end of a loop
			loopType = (loopTypeAt this i opcodes)
			if ('ignore' == loopType) {
				loopRec = nil
				loopEnd = i
			} ('whenCondition' == loopType) {
				loopStart = 2
				loopEnd = i
				conditionStart = 4
				conditionEnd = (i - 1)
				bodyStart = (i + 1)
				bodyEnd = ((count opcodes) - 1)
				loopRec = (array 'whenCondition' (count opcodes) conditionStart conditionEnd bodyStart bodyEnd)
			} ('repeatUntil' == loopType) {
				bodyStart = (jumpTarget this cmd)
				loopStart = (bodyStart - 1)
				conditionStart = (jumpTarget this (at opcodes loopStart))
				conditionEnd = (i - 1)
				bodyEnd = (conditionStart - 1)
				loopEnd = i
				loopRec = (array 'repeatUntil' loopEnd conditionStart conditionEnd bodyStart bodyEnd)
			} ('waitUntil' == loopType) {
				loopStart = (jumpTarget this cmd)
				loopEnd = i
				conditionStart = loopStart
				conditionEnd = (i - 1)
				loopRec = (array 'waitUntil' loopEnd conditionStart conditionEnd)
			} else {
				bodyStart = (jumpTarget this cmd)
				bodyEnd = (i - 1)
				loopStart = bodyStart
				loopEnd = i
				if ('for' == loopType) {
					loopStart = (bodyStart - 3)
					bodyEnd = (i - 2)
					loopEnd = (i + 1)
					if (notNil (at controlStructures (bodyStart - 1))) {
						cmd2 = (at controlStructures (bodyStart - 1))
						if ('repeatUntil' == (first cmd2)) {
							// fix waitUntil (xxx can be removed eventually)
							rec = (array 'waitUntil' (at cmd2 6) (at cmd2 5) ((at cmd2 6) - 1))
							recordControlStructure this bodyStart rec
							atPut controlStructures (bodyStart - 1) nil
						}
					}
				} ('repeat' == loopType) {
					loopStart = (bodyStart - 1)
				}
				loopRec = (array loopType loopEnd bodyStart bodyEnd)
				if ('for' == loopType) {
					forIndexVar = (cmdArg this (at opcodes (i - 1)))
					loopRec = (copyWith loopRec forIndexVar)
				}
			}
			if (notNil loopRec) { recordControlStructure this loopStart loopRec }
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
	if ('waitUntil' == op) { return 'waitUntil' }
	if ('jmp' == op) {
		if ('forLoop' == (cmdOp this (at seq (i - 1)))) {
			return 'for'
		} (and (i == (count opcodes)) (2 == (jumpTarget this cmd))) {
			return 'ignore' // ignore the final jump of a 'whenCondition'
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
			// xxx remove this test once compiler generates 'waitUntil' opcodes
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
			recordControlStructure this i conditionalRec
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

// Locals

method fixLocals MicroBlocksDecompiler {
	// Replace the first "set" of a local variable with "declareLocal".

	declared = (dictionary)
	for cmd opcodes {
		if ('storeLocal' == (cmdOp this cmd)) {
			varIndex = (cmdArg this cmd)
			if (not (contains declared varIndex)) {
				atPut cmd 2 'declareLocal'
				add declared varIndex
			}
		}
	}
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
				add stack (buildCmdOrReporter this fName argCount true)
				i += 1
			} else {
				add code (buildCmdOrReporter this fName argCount false)
				i += 2
			}
		} ('multiple' == op) {
			// Remove and process the outer-most control structure (the last one in the list).
			// This does  a recursive call to codeForSequence, but with one fewer control
			// structures in the 'multiple' list. Recursion terminates when there are no more
			// control structures.
			cmd = (removeLast ctrl)
			if ((count ctrl) < 3) { atPut controlStructures i nil }
			op = (first cmd)
			next = ((at cmd 2) + 1)
			if ('forever' == op) {
				body = (codeForSequence this (at cmd 3) (at cmd 4))
				add code (newCommand 'forever' body)
			} ('repeat' == op) {
				if (and ((count ctrl) > 2) ('repeatUntil' == (first (last ctrl)))) {
					// fix waitUntil inside a repeat (xxx can remove eventually)
					cmd2 = (removeLast ctrl)
					rec = (array 'waitUntil' (at cmd2 6) (at cmd2 5) ((at cmd2 6) - 1))
					recordControlStructure this (i + 1) rec
				}
				body = (codeForSequence this (at cmd 3) (at cmd 4))
				add code (newCommand 'repeat' (removeLast stack) body)
			} ('repeatUntil' == op) {
				if (and ((count ctrl) > 2) ('repeatUntil' == (first (last ctrl)))) {
					// fix waitUntil inside a repeat (xxx can remove eventually)
					cmd2 = (removeLast ctrl)
					rec = (array 'waitUntil' (at cmd2 6) (at cmd2 5) ((at cmd2 6) - 1))
					recordControlStructure this (i + 1) rec
				}
				condition = (codeForSequence this (at cmd 3) (at cmd 4))
				body = (codeForSequence this (at cmd 5) (at cmd 6))
				add code (newCommand 'repeatUntil' condition body)
			} ('waitUntil' == op) {
				condition = (codeForSequence this (at cmd 3) (at cmd 4))
				add code (newCommand 'waitUntil' condition)
			}
			i = next
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
		add stack (newReporter 'v' (globalVarName this cmdArg))
	} ('storeVar' == op) {
		add code (newCommand '=' (globalVarName this cmdArg) (removeLast stack))
	} ('incrementVar' == op) {
		add code (newCommand '+=' (globalVarName this cmdArg) (removeLast stack))
	} ('pushArgCount' == op) {
		add stack (newReporter 'pushArgCount')
	} ('pushArg' == op) {
		add stack (newReporter 'v' (argName this cmdArg))
	} ('storeArg' == op) {
		add code (newCommand '=' (argName this cmdArg) (removeLast stack))
	} ('incrementArg' == op) {
		add code (newCommand '+=' (argName this cmdArg) (removeLast stack))
	} ('pushLocal' == op) {
		add stack (newReporter 'v' (localVarName this cmdArg))
	} ('storeLocal' == op) {
		add code (newCommand '=' (localVarName this cmdArg) (removeLast stack))
	} ('incrementLocal' == op) {
		add code (newCommand '+=' (localVarName this cmdArg) (removeLast stack))
	} ('declareLocal' == op) {
		add code (newCommand 'local' (localVarName this cmdArg) (removeLast stack))

	} ('pop' == op) {
		add code (buildCmdOrReporter this 'ignoreArgs' cmdArg false)
	} ('returnResult' == op) {
		add code (buildCmdOrReporter this 'return' 1 false)
	} ('digitalSet' == op) {
		add code (newCommand 'digitalWriteOp' cmdArg true)
	} ('digitalClear' == op) {
		add code (newCommand 'digitalWriteOp' cmdArg false)

	} ('if' == op) {
		add code (newCommand 'if'
			(removeLast stack)
			(codeForSequence this (at cmd 3) (at cmd 4)))
	} ('if-else' == op) {
		ifPart = (codeForSequence this (at cmd 3) (at cmd 4))
		elsePart = (codeForSequence this (at cmd 5) (at cmd 6))
		if (and (notNil elsePart) ('if' == (primName elsePart))) {
			// combine nested if's
			argList = (list 'if' (removeLast stack) ifPart)
			addAll argList (argList elsePart)
			add code (callWith 'newCommand' (toArray argList))
		} else {
			add code (newCommand 'if' (removeLast stack) ifPart true elsePart)
		}
	} ('for' == op) {
		body = (codeForSequence this (at cmd 3) (at cmd 4))
		indexVarName = (localVarName this (at cmd 5))
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

	// everything else
	} (contains reporters op) {
		add stack (buildCmdOrReporter this op cmdArg true)
	} else {
		add code (buildCmdOrReporter this op cmdArg false)
	}
	if (notNil ctrl) { atPut controlStructures i ctrl } // restore ctrl to controlStructure
}

method buildCmdOrReporter MicroBlocksDecompiler op argCount isReporter {
	// Return a GP Command or Reporter for the given op taking argCount items from the stack.
	// If optional isReporter arg is not supplied, look up the op in the reporters dictionary.

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

method globalVarName MicroBlocksDecompiler varIndex {
	varNames = (allVariableNames (project (scripter (smallRuntime))))
	if (and (0 <= varIndex) (varIndex < (count varNames))) {
		return (at varNames (varIndex + 1))
	}
	return (join 'v' varIndex)
}

method localVarName MicroBlocksDecompiler varIndex {
	return (join 'l' varIndex)
}

method argName MicroBlocksDecompiler varIndex {
	if (and (0 <= varIndex) (varIndex < (count argNames))) {
		return (at argNames (varIndex + 1))
	}
	return (join 'arg' varIndex)
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
