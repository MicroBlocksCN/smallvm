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
			if ('to' == (primName expr)) {
				// save block definition in scripting area as 'to' command with a nil body
				// all function definitions are saved separately as a top-level 'to' commands
				callArgs = (join (list 'to') (argList expr))
				atPut callArgs (count callArgs) nil // replace the body with nil
				expr = (callWith 'newCommand' (toArray callArgs))
			}
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
			add result (join (specDefinitionString spec) (newline))
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
			if (varMustBeQuoted varName) {
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

	main = (main mbProject)
	todo = (list cmdOrReporter)
	while (notEmpty todo) {
		cmd = (removeFirst todo)
		for cmdOrReporter (allBlocks cmd) {
			op = (primName cmdOrReporter)
			if (isFunctionCall this op) {
				if (libraryDefines this main op) {
					if (not (contains functionsUsed op)) {
						add functionsUsed op
						func = (functionNamed main op)
						if (notNil func) {
							add todo (cmdList func)
						}
					}
				} else {
					for lib (values (libraries mbProject)) {
						if (libraryDefines this lib op) {
							add libsUsed (moduleName lib)
						}
					}
				}
			} ('to' == op) {
				add functionsUsed (first (argList cmdOrReporter))
			}
		}
	}
}

method isFunctionCall MicroBlocksExchange funcName {
	return (or
		(notNil (functionNamed mbProject funcName)) // function call
		(and (beginsWith funcName '[') (endsWith funcName ']'))) // primitive call
}

method isUserDefined MicroBlocksExchange funcName {
	return (notNil (functionNamed (main mbProject) funcName))
}

method libraryDefines MicroBlocksExchange lib funcName {
	if (notNil (functionNamed lib funcName)) { return true } // lib defines function
	if (contains (blockSpecs lib) funcName) {
		// lib has spec (funcName is a primitive call)
		return true
	}
	return false
}

// Script import

method importScripts MicroBlocksExchange aMicroBlocksScripter scriptString dstX dstY {
	mbProject = (project aMicroBlocksScripter)
	scriptCmds = (parse scriptString)
	if (isNil scriptCmds) { return }

	// add block specs
	loadSpecs mbProject scriptCmds

	// add libraries and function definitions
	for entry scriptCmds {
		if ('depends' == (primName entry)) {
			for libName (argList entry) {
				installLibraryNamed aMicroBlocksScripter libName
			}
		} ('to' == (primName entry)) {
			args = (argList entry)
			funcName = (first args)
			parameterNames = (copyFromTo args 2 ((count args) - 1))
			body = (last args)
			addGlobalsFor this body parameterNames
			defineFunctionInModule (main mbProject) funcName parameterNames body
		}
	}

	// find the origin of scripts to be pasted
	scriptsX = 10000
	scriptsY = 10000
	for entry scriptCmds {
		args = (argList entry)
		if (and ('script' == (primName entry)) (3 == (count args))) {
			scriptsX = (min scriptsX (at args 1))
			scriptsY = (min scriptsY (at args 2))
		}
	}

	// add scripts to the scripts pane
	scriptsPane = (scriptEditor aMicroBlocksScripter)
	for entry scriptCmds {
		args = (argList entry)
		if (and ('script' == (primName entry)) (3 == (count args)) (notNil (last args))) {
			script = (last args)
			addGlobalsFor this script
			if ('to' == (primName script)) {
				funcName = (first (argList script))
				f = (functionNamed mbProject funcName)
				block = (scriptForFunction f)
			} else {
				block = (toBlock script)
			}
			fixBlockColor block
			blockX = (round (dstX + ((blockScale) * ((at args 1) - scriptsX))))
			blockY = (round (dstY + ((blockScale) * ((at args 2) - scriptsY))))
			fastMoveBy (morph block) blockX blockY
			addPart (morph scriptsPane) (morph block)
		}
	}
	saveAllChunksAfterLoad (smallRuntime)
}

method addGlobalsFor MicroBlocksExchange script parameterNames {
	globalVars = (toList (allVariableNames mbProject))
	varRefs = (list)
	localVars = (list)
	if (notNil parameterNames) { addAll localVars parameterNames }
	for b (allBlocks script) {
		args = (argList b)
		if (notEmpty args) {
			varName = (first args)
			if (isOneOf (primName b) 'v' '=' '+=') { add varRefs varName }
			if (isOneOf (primName b) 'local' 'for') { add localVars varName }
		}
	}
	varsChanged = false
	for v varRefs {
		if (and (not (contains globalVars v)) (not (contains localVars v))) {
			// add new global variable
			addVariable (main mbProject) v
			varsChanged = true
		}
	}
	if varsChanged { variablesChanged (smallRuntime) }
}
