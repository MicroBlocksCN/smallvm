// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksDecompiler.gp - Decompiles bytecodes back to blocks
// John Maloney, March, 2020

to decompileBytecodes bytecodes {
	return (decompile (initialize (new 'MicroBlocksDecompiler')) bytecodes)
}

defineClass MicroBlocksDecompiler

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
		add opcodes (array op arg)
	}
	print opcodes
}
