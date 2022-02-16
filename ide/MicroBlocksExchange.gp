// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksExchange.gp - A textual representation for exchanging scripts between projects.
// John Maloney, February, 2022

defineClass MicroBlocksExchange mbProject

to newMicroBlocksExchange aProject {
	return (initialize (new 'MicroBlocksExchange') aProject)
}

method initialize MicroBlocksExchange aProject {
	mbProject = aProject
	return this
}

// Script export

method exportScripts MicroBlocksExchange blockList {
	// Return a string representation of the give scripts. blockList is a list of Block morphs.
	// ToDo:
	// [ ] add user-defined block definitions
	// [ ] add specs for user-defined blocks
	// [ ] add library dependencies

	scale = (blockScale)
	result = (list)
	add result 'depends ''foo'' ''bar'''
	add result (newline)
	add result 'spec '' '' ''myBlock'' ''my block _'' ''bool'' true'
	add result (newline)
	for m blockList {
		if (isClass (handler m) 'Block') {
			expr = (expression (handler m))
			x = (round ((left m) / scale))
			y = (round ((top m)/ scale))
			add result (scriptText this expr x y)
		}
	}
	return (joinStrings result)
}

method scriptText MicroBlocksExchange cmdOrReporter x y useSemicolons {
	if (isNil x) { x = 10 }
	if (isNil y) { y = 10 }
	if (isNil useSemicolons) { useSemicolons = false }

	pp = (new 'PrettyPrinter')
	if useSemicolons { useSemicolons pp }
	result = (list)
	add result (join 'script ' x ' ' y ' ')
	if (isClass cmdOrReporter 'Reporter') {
		if ('v' == (primName cmdOrReporter)) {
			varName = (first (argList cmdOrReporter))
			if (contains (letters varName) ' ') {
				varName = (printString varName) // enclose varName in quotes
			}
			add result (join '(v ' varName ')')
		} else {
			add result (join '(' (prettyPrint pp cmdOrReporter) ')')
		}
		if (not useSemicolons) { add result (newline) }
	} else {
		add result '{'
		if (not useSemicolons) { add result (newline) }
		add result (prettyPrintList pp cmdOrReporter)
		add result '}'
		if (not useSemicolons) { add result (newline) }
	}
	if (not useSemicolons) { add result (newline) }
	return (joinStrings result)
}

// Script import

method importScripts MicroBlocksExchange scriptString scriptsPane dstX dstY {
print 'MicroBlocksExchange importScripts'

	scripts = (parse scriptString)
	if (isNil scripts) { return }

	// find origin of scripts to be pasted
	scriptsX = 10000
	scriptsY = 10000
	for entry scripts {
		args = (argList entry)
		if (and ('script' == (primName entry)) (3 == (count args))) {
			scriptsX = (min scriptsX (at args 1))
			scriptsY = (min scriptsY (at args 2))
		}
	}

	for entry scripts {
		args = (argList entry)
		if (and ('script' == (primName entry)) (3 == (count args)) (notNil (last args))) {
			script = (last args)
			addGlobalsFor this script
			if ('to' == (primName script)) {
				cmd = (copyFunction this script nil)
				block = (scriptForFunction (functionNamed mbProject (first (argList cmd))))
			} else {
				block = (toBlock script)
			}
			fixBlockColor block
			blockX = (round (dstX + ((blockScale) * ((at args 1) - scriptsX))))
			blockY = (round (dstY + ((blockScale) * ((at args 2) - scriptsY))))
			fastMoveBy (morph block) blockX blockY
			addPart (morph scriptsPane) (morph block)
		} ('depends' == (primName entry)) {
print 'depends' args
		} ('spec' == (primName entry)) {
print 'spec' args
		}
	}
}

method addGlobalsFor MicroBlocksExchange script {
	globalVars = (toList (allVariableNames mbProject))
	varRefs = (list)
	localVars = (list)
	for b (allBlocks script) {
		args = (argList b)
		if (notEmpty args) {
			varName = (first args)
			if (isOneOf (primName b) 'v' '=' '+=') { add varRefs varName }
			if (isOneOf (primName b) 'local' 'for') { add localVars varName }
		}
	}
	for v varRefs {
		if (and (not (contains globalVars v)) (not (contains localVars v))) {
			// add new global variable
			addVariable (main mbProject) v
		}
	}
	variablesChanged (smallRuntime)
}
