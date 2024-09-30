// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to scripts and functions
// John Maloney, March, 2020
// Converted to 16-bit instructions, September, 2024

defineClass MicroBlocksDecompiler chunks vars funcs module reporters opcodes controlStructures code stack msgName localNames argNames functionInfo

to newDecompiler {
	return (initialize (new 'MicroBlocksDecompiler'))
}

method initialize MicroBlocksDecompiler {
	chunks = (list) // list of (chunkID, chunkType, chunkData)
	vars = (dictionary) // global var ID -> name
	funcs = (dictionary) // chunk ID -> function name
	return this
}

// Testing

to decompileBytecodes chunkID chunkType chunkData {
	// For testing...
	decompiler = (newDecompiler)
	addNamesFromRuntime decompiler chunkID chunkType chunkData
	return (decompile decompiler chunkID chunkType chunkData)
}

method addNamesFromRuntime MicroBlocksDecompiler {
	// For testing. Add var and fuction names from current project.

	initialize this

	allVars = (allVariableNames (project (scripter (smallRuntime))))
	for i (count allVars) {
		atPut vars (i - 1) (at allVars i)
	}
	for pair (sortedPairs (getField (smallRuntime) 'chunkIDs')) {
		fName = (last pair)
		if (isClass fName 'String') {
			chunkID = (first (first pair))
			atPut funcs chunkID fName
		}
	}
}

// Collecting vars and chunks

method addChunk MicroBlocksDecompiler chunkID chunkType chunkData {
	add chunks (array chunkID chunkType chunkData)
}

method addVar MicroBlocksDecompiler varID varName {
	atPut vars varID varName
}

method decompileProject MicroBlocksDecompiler {
	// Return the decompiled project.
	// Called after collecting chunks and var names from the board.

	project = (newMicroBlocksProject)
	module = (main project)
	for varName (values vars) { addVariable module varName }

	// pass 1: assign function names
	for chunk chunks {
		chunkID = (at chunk 1)
		chunkType = (at chunk 2)
		chunkData = (at chunk 3)
		if (3 == chunkType) {
			atPut funcs chunkID (nameForFunction this chunkID chunkData)
		}
	}

	// pass 2: generate code and add functions and scripts in new project module
	scripts = (list)
	for chunk chunks {
		chunkID = (at chunk 1)
		chunkType = (at chunk 2)
		chunkData = (at chunk 3)
		gpCode = (decompile this chunkID chunkType chunkData)
		if (isClass gpCode 'Function') {
			addFunctionToProject this gpCode chunkID project
		} ('comment' == (primName gpCode)) {
			// ignore stand-alone comments
		} else {
			add scripts (array (rand 50 400) (rand 50 300) gpCode)
		}
	}
	setScripts module scripts

	updatePrimitives project
	fixFunctionLocals project

	return project
}

method addFunctionToProject MicroBlocksDecompiler aFunc chunkID project {
	funcName = (functionName aFunc)
	targetLib = module

	if ((count functionInfo) >= 6) { // use function info if available
		// set the target library for this function
		libName = (at functionInfo 1)
		libCat = (at functionInfo 2)
		if (libName != '') {
			if (isNil (libraryNamed project libName)) { // create library module
				targetLib = (newMicroBlocksModule libName)
				setField targetLib 'moduleCategory' libCat
				setVersion targetLib (array 0 0) // unknown version
				addLibrary project targetLib
			}
			targetLib = (libraryNamed project libName)
		}

		 // create blockspec from function info
		blockType = (at functionInfo 3)
		specString = (at functionInfo 5)
		typeString = (at functionInfo 6)
		defaults = (list)
		spec = (blockSpecFromStrings funcName blockType specString typeString defaults)
	} else { // no function info, so generate a blockspec
		specString = funcName
		typeString = ''
		defaults = (list)
		for argName (argNames aFunc) {
			specString = (join specString ' _')
			typeString = (join typeString ' auto')
		}
		spec = (blockSpecFromStrings funcName ' ' specString typeString defaults)
	}

	// add the function and its blockspec
	addFunction targetLib aFunc
	add (blockList targetLib) funcName
	recordBlockSpec project funcName spec
}

method nameForFunction MicroBlocksDecompiler chunkID chunkData {
	// If the function has a recvBroadcast opcode (i.e. it has no arguments)
	// then use that as the function name. Otherwise, generate a name based on chunkID.

	fName = (extractFunctionName this chunkData)
	if (isNil fName) { fName = (join 'func' chunkID) }
	return fName
}

method extractFunctionName MicroBlocksDecompiler chunkData {
	extractOpcodes this chunkData
	if (and ((count opcodes) >= 3)
			('recvBroadcast' == (cmdOp this (at opcodes 3)))
			('pushLiteral' == (cmdOp this (at opcodes 2)))) {
				return (cmdArg this (at opcodes 2))
	}
	if ((count functionInfo) > 3) { return (at functionInfo 4) }
	return nil
}

// Decompiling

method decompile MicroBlocksDecompiler chunkID chunkType chunkData {
	// Approach:
	//	0. Convert chunkData into sequence of opcode tuples
	//	1. find and replace loops
	//	2. find and replace if's (recursively)
	//	3. walk the entire tree and generate code

	extractOpcodes this chunkData
	controlStructures = (newArray (count opcodes))
	findLoops this
	findIfs this
	fixLocals this

	printChunkInfo = false
	if printChunkInfo {
		fName = ''
		if (3 == chunkType) { fName = (at funcs chunkID 'unknown function') }
		print 'decompiling' chunkID chunkType fName
	}

	debug = false
	if debug {
		print '----'
		printSequence2 this
		print '----'
		printSequence3 this 1 (count opcodes) 0
		print '----'
	}

	if (cmdIs this (last opcodes) 'codeEnd' 0) { removeLast opcodes } // remove final codeEnd
	gpCode = (codeForSequence this 1 (count opcodes))
	gpCode = (removePrefix this gpCode)
	if (3 == chunkType) { gpCode = (removeFinalReturn this gpCode) }
	gpCode = (addHatBlock this chunkID chunkType gpCode)
	if (isNil gpCode) {
		return (newCommand 'comment' 'Stand-alone comment')
	}
	fixBooleanAndColorArgs this gpCode
	if debug { print (prettyPrint this gpCode) }
	return gpCode
}

method extractOpcodes MicroBlocksDecompiler chunkData {
	// 16-bit version

	// build array to map opcode number -> op name
	compiler = (initialize (new 'SmallCompiler'))
	opcodeToName = (range 0 255)
	for p (sortedPairs (opcodes compiler) false) {
		atPut opcodeToName ((first p) + 1) (last p)
	}

	opcodes = (list)
	msgName = nil
	byteCount = (count chunkData)
	i = 1
	while (and (i < byteCount) ('codeEnd' != op)) { // stop if last op was codeEnd
		addr = (round (i / 2)) // 16-bit instruction address (1-based)
		op = (at opcodeToName ((at chunkData i) + 1)) // opcode
		arg = (at chunkData (i + 1)) // arg byte
		extraWords = 0
		primCall = nil
		i += 2
		if ('pushImmediate' == op) { // arg is a boolean or an integer object that fits in 8 bits
			if (1 == (arg & 1)) {
				arg = ((arg << 24) >> 25) // small integer (7 bits, signed)
			} (0 == arg) {
				arg = false
			} (4 == arg) {
				arg = true
			} else {
				print 'cannot decode immediate value:' arg
			}
		} ('pushLargeInteger' == op) { // arg is 24 bit integer object
			arg = (arg | ((at chunkData i) << 8))
			arg = (arg | ((at chunkData (i + 1)) << 16))
			arg = ((arg << 8) >> 9) // convert integer object to integer with sign extenion
			extraWords += 1
		} ('pushHugeInteger' == op) { // 32 bit integer; arg byte ignored
			arg = (at chunkData i)
			arg = (arg | ((at chunkData (i + 1)) << 8))
			arg = (arg | ((at chunkData (i + 2)) << 16))
			arg = (arg | ((at chunkData (i + 3)) << 24))
			arg = (arg >> 1) // convert integer object to integer
			extraWords += 2
		} ('pushLiteral' == op) { // literal string
			offset = (at chunkData i)
			offset = (offset | ((at chunkData (i + 1)) << 8))
			// Use offset to extract the actual literal string.
			startByte = (i + (2 * offset))
			arg = (readLiteral this chunkData startByte)
			extraWords += 1
		} (isOneOf op 'jmp' 'jmpTrue' 'jmpFalse' 'jmpOr' 'jmpAnd' 'decrementAndJmp' 'waitUntil') {
			if (arg == 0) { // extended jump; 16-bit signed offset in following two bytes
				arg = (at chunkData i)
				arg = (arg | ((at chunkData (i + 1)) << 8))
				if (arg > 32767) { arg = (arg - 65536) }
				extraWords += 1
			} else { // arg is 8-bit signed offset
				if (arg > 127) { arg = (arg - 256) }
			}
		} (isOneOf op 'commandPrimitive' 'reporterPrimitive') { // 24 bit arg
			arg = (arg | ((at chunkData i) << 8))
			arg = (arg | ((at chunkData (i + 1)) << 16))

			primSetIndex = ((arg >> 18) & 63) // 6 bits
			primSetName = (keyAtValue (primsets compiler) primSetIndex)
			primNameOffset = ((arg >> 8) & 1023) // offset to primitive name literal string, 10 bits
			primName = (readLiteral this chunkData (i + (2 * primNameOffset)))
			arg = (arg & 255) // argument count, low 8 bits
			primCall = (join '[' primSetName ':' primName ']') // replace op with primitive call
			extraWords += 1
		} ('callFunction' == op) {
			// 16-bit arg is chunk ID (high byte) and arg count (low byte); arg byte ignored
			arg = ((at chunkData i) | ((at chunkData (i + 1)) << 8))
			extraWords += 1
		}
		add opcodes (array addr op arg primCall)
		repeat extraWords { // add temporary placeholders so jump offsets are correct
			add opcodes (array (addr + 1) 'placeholder' 0 nil)
			i += 2
		}
	}
//	hasMetadata = (readDecompilerMetadata this lastInstruction) // xxx To Do
hasMetadata = false
	if (not hasMetadata) { findArgs this } // no metadata; generate argument names if needed
}

method removePrefix MicroBlocksDecompiler gpCode {
	// Remove possible recvBroadcast prefix from parameterless functions and broadcast hats.

	if (isNil gpCode) { return }

	if ('recvBroadcast' == (primName gpCode)) {
		// remove 'recvBroadcast' from a parameterless function
		msgName = (first (argList gpCode)) // record the message name
		gpCode = (nextBlock gpCode)
	}
	return gpCode
}

method removeFinalReturn MicroBlocksDecompiler gpCode {
	// Return possible final 'return false' from the code for a function.

	if (isNil gpCode) { return nil }

	// find the last two commands:
	lastCmd = gpCode
	while (notNil (nextBlock lastCmd)) {
		nextToLastCmd = lastCmd
		lastCmd = (nextBlock lastCmd)
	}

	// if the last command is a 'return false', remove it
	if (and ('return' == (primName lastCmd)) (false == (first (argList lastCmd)))) {
		if (gpCode == lastCmd) { return nil } // the return was the only command
		setField nextToLastCmd 'nextBlock' nil
	}
	return gpCode
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

method opcodeAfter MicroBlocksDecompiler i {
	// Return the index of the opcode after the opcode at i.

	i = (i + 1)
	while ('placeholder' == (at (at opcodes i) 2)) {
		i += 1
	}
	return i
}

method opcodeBefore MicroBlocksDecompiler i {
	// Return the index of the opcode before the opcode at i.

	i = (i - 1)
	while ('placeholder' == (at (at opcodes i) 2)) {
		i += -1
	}
	return i
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

method readLiteral MicroBlocksDecompiler chunkData startByte {
	// Return the literal string starting at the given byte index.

	chunkByteCount = (count chunkData)
	byte0 = (at chunkData startByte)
	objType = (byte0 & 15)
	if (or (objType != 4) ((startByte + 3) > chunkByteCount)) {
		print 'bad string literal type' // should not happen...
		return ''
	}
	wordCount = (byte0 >> 4)
	wordCount += ((at chunkData (startByte + 1)) << 4)
	wordCount += ((at chunkData (startByte + 2)) << 12)
	wordCount += ((at chunkData (startByte + 3)) << 20)
	if ((+ startByte 4 (4 * wordCount)) > chunkByteCount) {
		print 'bad string literal size' // should not happen...
		return ''
	}
	stringBytes = (list)
	i = (startByte + 4)
	end = (i + (4 * wordCount))
	while (i < end) {
		ch = (at chunkData i)
		if (ch != 0) { add stringBytes (at chunkData i) } // skip zero terminator byte(s)
		i += 1
	}
	return (callWith 'string' (toArray stringBytes))
}

method readDecompilerMetadata MicroBlocksDecompiler lastInstruction {
	// Read decompiler metadata, if any, and return true if found.

	localNames = (array)
	argNames = (array)
	functionInfo = (array)

	end = (count opcodes)
	i = lastInstruction
	while (240 != (cmdOp this (at opcodes i))) {
		i += 1
		if (i > end) { return false } // no meta information
	}
	i += 1 // skip the meta info marker (opcode 240)
	if (i < end) {
		s = (readLiteral this i)
		localNames = (splitWith s (string 9))
		i += ((floor ((byteCount s) / 4)) + 2)
	}
	if (i < end) {
		s = (readLiteral this i)
		functionInfo = (splitWith s (string 9))
		i += ((floor ((byteCount s) / 4)) + 2)
	}
	if (i < end) {
		s = (readLiteral this i)
		argNames = (splitWith s (string 9))
		i += ((floor ((byteCount s) / 4)) + 2)
	}
	return true
}

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
		add argNames (join 'A' (i + 1))
		i += 1
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

method addHatBlock MicroBlocksDecompiler chunkID chunkType gpCode {
	// Prefix given code with a hat block based on chunkType and return the result.

	result = gpCode
	// chunk types 1 and 2 are command and reporter blocks without a hat
	if (3 == chunkType) {
		// Note: result is Function object
		if (not (contains funcs chunkID)) {
			// this happens during testing when decompiling a single function
			if ((count functionInfo) > 3) {
				atPut funcs chunkID (at functionInfo 4)
			}
		}
		fName = (at funcs chunkID 'unknown function') // should never see "unknown function"
		result = (newFunction fName argNames gpCode module)
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
				c = (color ((val >> 16) & 255) ((val >> 8) & 255) (val & 255))
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
				loopEnd = (count opcodes)
				conditionStart = 4
				conditionEnd = (opcodeBefore this i)
				bodyStart = (opcodeAfter this i)
				bodyEnd = (opcodeBefore this loopEnd)
				loopRec = (array 'whenCondition' (count opcodes) conditionStart conditionEnd bodyStart bodyEnd)
			} ('repeatUntil' == loopType) {
				bodyStart = (jumpTarget this cmd)
				loopStart = (opcodeBefore this bodyStart)
				conditionStart = (jumpTarget this (at opcodes loopStart))
				conditionEnd = (opcodeBefore this i)
				bodyEnd = (opcodeBefore this conditionStart)
				loopEnd = i
				loopRec = (array 'repeatUntil' loopEnd conditionStart conditionEnd bodyStart bodyEnd)
			} ('waitUntil' == loopType) {
				loopStart = (jumpTarget this cmd)
				loopEnd = i
				conditionStart = loopStart
				conditionEnd = (opcodeBefore this i)
				loopRec = (array 'waitUntil' loopEnd conditionStart conditionEnd)
			} else {
				bodyStart = (jumpTarget this cmd)
				bodyEnd = (opcodeBefore this i)
				loopStart = bodyStart
				loopEnd = i
				if ('for' == loopType) {
					loopStart = (bodyStart - 2)
					bodyStart = (opcodeAfter this bodyStart)
					bodyEnd = (opcodeBefore this (opcodeBefore this i))
					loopEnd = (opcodeAfter this i)
					if (notNil (at controlStructures (bodyStart - 1))) {
						cmd2 = (at controlStructures (bodyStart - 1))
					}
				} ('repeat' == loopType) {
					loopStart = (opcodeBefore this bodyStart)
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
		return 'repeatUntil'
	}
	return 'unknown loop type'
}

// Conditionals

method findIfs MicroBlocksDecompiler {
	// Create entries for all "if" and "if-else" constructs in the opcode sequence.

	for i (count opcodes) {
		cmd = (at opcodes i)
		if (and ('jmpFalse' == (cmdOp this cmd)) ((cmdArg this cmd) >= 0) (not (isAnd this opcodes cmd))) {
			trueStart = (opcodeAfter this i)
			trueEnd = (opcodeBefore this (jumpTarget this cmd))
			lastCmdOfTrue = (at opcodes trueEnd)
			if ('jmp' == (cmdOp this lastCmdOfTrue)) {
				falseStart = (opcodeAfter this trueEnd)
				falseEnd = (opcodeBefore this (jumpTarget this lastCmdOfTrue))
				conditionalRec = (array 'if-else' falseEnd trueStart (opcodeBefore this trueEnd) falseStart falseEnd)
			} else {
				conditionalRec = (array 'if' trueEnd trueStart trueEnd)
			}
			recordControlStructure this i conditionalRec
		}
	}
}

method isAnd MicroBlocksDecompiler seq cmd {
	// Return true if the subsequence starting with cmd was generated by an "and" expression.

	if ('jmpFalse' != (cmdOp this cmd)) { return false }
	i = (jumpTarget this cmd)
	if (i > (count seq)) { return false }
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
			vIndex = (cmdArg this cmd)
			if (not (contains declared vIndex)) {
				atPut cmd 2 'declareLocal'
				add declared vIndex
			}
		}
	}
}

// Decoding

method codeForSequence MicroBlocksDecompiler start end {
	// Decode the given sequence of opcodes and return a GP Reporter (if it is an expression)
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
		if ('placeholder' == op) { // skip placeholders
			i = next
		} ('jmpTrue' == op) { // conditional expression
			i = (decodeConditionalExpression this op i)
		} (isOneOf op 'jmpAnd' 'jmpOr') { // new style "and" or "or" reporter
			i = (decodeNewANDorORreporter this op i)
		} ('callFunction' == op) {
			cmdArg = (cmdArg this cmd)
			argCount = (cmdArg & 255)
			chunkID = ((cmdArg >> 8) & 255)
			fName = (at funcs chunkID 'unknown function') // should never see "unknown function"
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
			// This does a recursive call to codeForSequence, but with one fewer control
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
				body = (codeForSequence this (at cmd 3) (at cmd 4))
				add code (newCommand 'repeat' (removeLast stack) body)
			} ('repeatUntil' == op) {
				condition = (codeForSequence this (at cmd 3) (at cmd 4))
				body = (codeForSequence this (at cmd 5) (at cmd 6))
				add code (newCommand 'repeatUntil' condition body)
			} ('waitUntil' == op) {
				condition = (codeForSequence this (at cmd 3) (at cmd 4))
				add code (newCommand 'waitUntil' condition)
			}
			i = next
		} (isOneOf op 'callCustomCommand' 'callCustomReporter') {
			isReporter = (not (cmdIs this (at opcodes (i + 1)) 'pop' 1))
			decodeCmd this i
			if isReporter {
				i += 1
			} else {
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
			for cmd code { // chain all commands together
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

method decodeNewANDorORreporter MicroBlocksDecompiler op i {
	// Decode an new AND or OR reporter (using jmpAnd/jmpOr).

	if ('jmpAnd' == op) { gpOp = 'and' } else { gpOp = 'or' }
	start = (opcodeAfter this i)
	end = (i + (cmdArg this (at opcodes i)))
	arg1 = (removeLast stack)
	arg2 = (codeForSequence this start end)
	add stack (newReporter gpOp arg1 arg2)
	return (end + 1)
}


method decodeConditionalExpression MicroBlocksDecompiler op i {
	 // Note: The false case comes first in the compiled code.

	start = (opcodeAfter this i)
	endOfFalse = (i + (cmdArg this (at opcodes i))) // jump to end
	end = (endOfFalse + (cmdArg this (at opcodes endOfFalse)))
	arg1 = (removeLast stack)
	arg2 = (codeForSequence this (endOfFalse + 1) end) // true case
	arg3 = (codeForSequence this start (endOfFalse - 1)) // false case
	add stack (newReporter 'ifExpression' arg1 arg2 arg3)
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
	} (isOneOf op 'pushImmediate' 'pushLiteral' 'pushLargeInteger' 'pushHugeInteger') {
		add stack cmdArg

	// Variables
	} ('pushGlobal' == op) {
		add stack (newReporter 'v' (globalVarName this cmdArg))
	} ('storeGlobal' == op) {
		add code (newCommand '=' (globalVarName this cmdArg) (removeLast stack))
	} ('incrementGlobal' == op) {
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

	} ('initLocals' == op) {
		// skip
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

	} (isOneOf op 'commandPrimitive' 'reporterPrimitive') {
		primName = (at cmd 4)
		if ('commandPrimitive' == op) {
			add code (buildCmdOrReporter this primName cmdArg false)
		} else { // reporterPrimitive
			add stack (buildCmdOrReporter this primName cmdArg true)
		}

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

method globalVarName MicroBlocksDecompiler vIndex {
	if (contains vars vIndex) { return (at vars vIndex) }
	return (join 'V' vIndex)
}

method localVarName MicroBlocksDecompiler vIndex {
	if (and (0 <= vIndex) (vIndex < (count localNames))) {
		return (at localNames (vIndex + 1))
	}
	return (join 'L' vIndex)
}

method argName MicroBlocksDecompiler vIndex {
	if (and (0 <= vIndex) (vIndex < (count argNames))) {
		return (at argNames (vIndex + 1))
	}
	return (join 'A' vIndex)
}

// Helper Methods

method buildReporterDictionary MicroBlocksDecompiler {
	// Build a dictionary of the MicroBlocks built-in reporters. This is used to
	// decide whether a given opcode is a reporter or a command.

	reporters = (dictionary)
	add reporters 'pushArgCount'
	add reporters 'getArg'
	for spec (microBlocksSpecs (new 'SmallCompiler')) {
		if (and (isClass spec 'Array') ('r' == (first spec))) {
			op = (at spec 2)
			if (not (beginsWith op '[')) { add reporters (at spec 2) }
		}
	}
}
