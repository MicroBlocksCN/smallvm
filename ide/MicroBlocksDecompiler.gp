// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to blocks
// John Maloney, March, 2020

to decompileBytecodes bytecodes {
	return (decompile (initialize (new 'MicroBlocksDecompiler')) bytecodes)
}

defineClass MicroBlocksDecompiler opcodes lastInstruction

method initialize MicroBlocksDecompiler {
	return this
}

method decompile MicroBlocksDecompiler bytecodes {
	opcodes = (list)
	for i (range 1 (count bytecodes) 4) {
		op = (at bytecodes i)
		arg = (+
			((at bytecodes (i + 3)) << 16)
			((at bytecodes (i + 2)) << 8)
			 (at bytecodes (i + 1)))
		arg = ((arg << 7) >> 7) // shift to sign-extend arg
		add opcodes (array op arg)
	}
	findLastInstruction this
print 'last instruction:' lastInstruction
	getOpNames this
	decodeImmediates this

// show opcode list
	for i (count opcodes) {
		print (join '' i ':') (at opcodes i)
	}
// 	findLoops this
}

method findLastInstruction MicroBlocksDecompiler {
	// Find the index of the last instruction in opcodes. The last instruction
	// may be followed by literal values such as strings.

	pushLiteral = 4
	lastInstruction = (count opcodes)
	for i (count opcodes) {
		if (i > lastInstruction) { return }
		instr = (at opcodes i)
		if (pushLiteral == (first instr)) {
			literalIndex = (+ i (at instr 2) 1)
			if (literalIndex <= lastInstruction) {
				lastInstruction = (literalIndex - 1)
			}
			atPut instr 2 (readLiteral this literalIndex) // insert the literal into instruction
		}
	}
}

method readLiteral MicroBlocksDecompiler literalIndex {
	lowByte = (first (at opcodes literalIndex))
	if (4 != (lowByte & 15)) {
		print 'bad string literal (should not happen)'
		return ''
	}
	highBytes = (last (at opcodes literalIndex))
	wordCount = ((highBytes << 2) | (lowByte >> 6))
	bytes = (list)
	for i (range (literalIndex + 1) (literalIndex + wordCount)) {
		pair = (at opcodes i)
		add bytes (first pair)
		highBytes = (last pair)
		add bytes (highBytes & 255)
		add bytes ((highBytes >> 8) & 255)
		add bytes ((highBytes >> 16) & 255)
	}
	while (and (notEmpty bytes) (0 == (at bytes (count bytes)))) {
		removeLast bytes	// remove trailing zero bytes
	}
	return (callWith 'string' (toArray bytes))
}

method getOpNames MicroBlocksDecompiler {
	opcodeDefs = (opcodes (initialize (new 'SmallCompiler')))
	opcodeToName = (range 0 255)
	for p (sortedPairs opcodeDefs false) {
		atPut opcodeToName ((first p) + 1) (last p)
	}
	for i lastInstruction {
		instr = (at opcodes i)
		op = (at opcodeToName ((first instr) + 1))
		atPut instr 1 op
	}
}

method decodeImmediates MicroBlocksDecompiler {
	for i lastInstruction {
		instr = (at opcodes i)
		if ('pushImmediate' == (first instr)) {
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
			atPut instr 2 decoded
		}
	}
}

method findLoops MicroBlocksDecompiler {
print 'Loops:'
	for i (count opcodes) {
		instr = (at opcodes i)
		if (isOneOf (first instr) 'jmp' 'jmpTrue' 'jmpFalse' 'decrementAndJmp') {
			jumpTarget = (+ i offset 1)
print (join '' i ':') (first instr) offset jumpTarget
		}
	}
}
