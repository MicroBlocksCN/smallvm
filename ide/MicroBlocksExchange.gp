// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2022 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksExchange.gp - A textual representation for exchanging scripts between projects.
// John Maloney, February, 2022

defineClass MicroBlocksExchange mbProject functionsUsed libsUsed

to newMicroBlocksExchange aProject {
	return (new 'MicroBlocksExchange')
}

// Script export

method exportScripts MicroBlocksExchange aMicroBlocksScripter blockList {
	// Return a string representation for the given scripts (a list of Block morphs).

	mbProject = (project aMicroBlocksScripter)
	result = (list)

	analyzeCalls this blockList
	add result (libraryDepencies this)
	add result (newline)
	addAll result (functionDefinitions this)

	scale = (blockScale)
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

method libraryDepencies MicroBlocksExchange {
	// Return a string listing the library dependencies, if any.

	if (isEmpty libsUsed) { return '' }
	result = (list 'depends')
	for lib libsUsed {
		add result (join ' ''' lib '''')
	}
	add result (newline)
	return (joinStrings result)
}

method functionDefinitions MicroBlocksExchange {
	// Return a list containing the specs and definitions of functions used, if any'

	result = (list)
	for funcName functionsUsed {
		spec = (at (blockSpecs mbProject) funcName)
		if (notNil spec) {
			add result (join 'spec ' (specDefinitionString spec) (newline))
		}
		func = (functionNamed mbProject funcName)
		add result (prettyPrintFunction (new 'PrettyPrinter') func)
		add result (newline)
	}
	return result
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

// Script analysis to collect function calls and library references

method analyzeCalls MicroBlocksExchange blockList {
	// Collect all the user-defined functions (i.e. blocks defined in the main project)
	// and libraries used by the given list of blocks.

	functionsUsed = (dictionary)
	libsUsed = (dictionary)
	for m blockList {
		if (isClass (handler m) 'Block') {
			analyzeCallsInExpression this (expression (handler m))
		}
	}
	functionsUsed = (sorted (keys functionsUsed))
	libsUsed = (sorted (keys libsUsed))
}

method analyzeCallsInExpression MicroBlocksExchange cmdOrReporter {
	// Collect all function calls and library references by the given command or reporter.

	for cmdOrReporter (allBlocks cmdOrReporter) {
		op = (primName cmdOrReporter)
		if (isFunctionCall this op) {
			if (isUserDefined this op) {
				add functionsUsed op
			} else {
				for lib (values (libraries mbProject)) {
					if (notNil (functionNamed lib op)) {
						add libsUsed (moduleName lib)
					}
				}
			}
		}
	}
}

method isFunctionCall MicroBlocksExchange funcName {
	return (notNil (functionNamed mbProject funcName))
}

method isUserDefined MicroBlocksExchange funcName {
	return (notNil (functionNamed (main mbProject) funcName))
}

// Script import

method importScripts MicroBlocksExchange aMicroBlocksScripter scriptString dstX dstY {
	mbProject = (project aMicroBlocksScripter)
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

	scriptsPane = (scriptEditor aMicroBlocksScripter)
	if (isNil dstX) { dstX = ((left (morph scriptsPane)) + (100 * (global 'scale'))) }
	if (isNil dstY) { dstY = ((top (morph scriptsPane)) + (100 * (global 'scale'))) }
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
			for libName args {
				installLibraryNamed aMicroBlocksScripter libName
			}
		}
	}
	// add block specs contained in scripts
	loadSpecs mbProject scripts
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
