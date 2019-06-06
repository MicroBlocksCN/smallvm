defineClass MicroBlocksProject main libraries

to mbProj {
	gc
	projects = (allInstances 'MicroBlocksProject')
	if ((count projects) > 1) {
		print 'multiple MicroBlocksProject instances'
	}
	return (first projects)
}

to newMicroBlocksProject {
	return (initialize (new 'MicroBlocksProject'))
}

method initialize MicroBlocksProject {
	main = (newMicroBlocksModule 'main')
	libraries = (dictionary)
	return this
}

method extraCategories MicroBlocksProject { return (array) } // called by AuthoringSpecs>specsFor
method main MicroBlocksProject { return main }
method libraries MicroBlocksProject { return libraries }

// Block Specs

method blockSpecs MicroBlocksProject {
	result = (copy (blockSpecs main))
	for lib (values libraries) {
		specs = (blockSpecs lib)
		for k (keys specs) {
			atPut result k (at specs k)
		}
	}
	return result
}

// Functions

method functions MicroBlocksProject {
	result = (list)
	addAll result (functions main)
	for lib (values libraries) {
		addAll result (functions lib)
	}
	return result
}

method functionNamed MicroBlocksProject functionName {
	f = (functionNamed main functionName)
	if (notNil f) { return f }
	for lib (values libraries) {
		f = (functionNamed lib functionName)
		if (notNil f) { return f }
	}
	return nil
}

method functionDeleted MicroBlocksProject functionName {
  print 'functionDeleted' functionName
  // xxx remove definition (could be in a library)
}

// Libraries

method addLibrary MicroBlocksProject aMicroBlocksModule {
	libName = (moduleName aMicroBlocksModule)
	remove libraries libName
	atPut libraries libName aMicroBlocksModule
}

method removeLibraryNamed MicroBlocksProject libName {
	remove libraries libName
}

// Variables

method variableNames MicroBlocksProject {
	result = (dictionary)
	addAll result (variableNames main)
	for lib (values libraries) {
		addAll result (variableNames lib)
	}
	return (sorted (keys result))
}

method addVariable MicroBlocksProject newVar {
	addVariable main newVar
}

method deleteVariable MicroBlocksProject varName {
	for lib (values libraries) {
		deleteVariable lib varName
	}
}

// Saving

method codeString MicroBlocksProject {
  result = (list)
  add result (codeString main)
  add result (newline)
  for lib (values libraries) {
	add result (codeString lib)
	add result (newline)
  }
  return (joinStrings result)
}

defineClass MicroBlocksModule moduleName blockSpecs functions variableNames scripts

to newMicroBlocksModule modName {
	return (initialize (new 'MicroBlocksModule') modName)
}

method initialize MicroBlocksModule modName {
	if (isNil modName) { modName = '' }
	moduleName = modName
	blockSpecs = (dictionary)
	functions = (array)
	variableNames = (array)
	scripts = (array)
	return this
}

method className MicroBlocksModule { return moduleName }
method moduleName MicroBlocksModule { return moduleName }

method blockSpecs MicroBlocksModule { return blockSpecs }
method setBlockSpecs MicroBlocksModule specs { blockSpecs = specs }

method initFromOldProjectClassAndSpecs MicroBlocksModule aClass specList {
	for k (keys specList) { atPut blockSpecs k (at specList k) }
	for func (functions (module aClass)) { addFunction this func }
	for varName (variableNames (module aClass)) { addVariable this varName }
	setScripts this (copy (scripts aClass))
}

// scripts

method scripts MicroBlocksModule { return scripts }
method setScripts MicroBlocksModule newScripts { scripts = (toArray newScripts) }

// functions

method functions MicroBlocksModule { return functions }

method functionNamed MicroBlocksModule functionName {
	for f functions {
		if (functionName == (functionName f)) { return f }
	}
	return nil
}

method defineFunctionInModule MicroBlocksModule funcName funcParams funcBody {
	f = (newFunction funcName funcParams funcBody this)
	for i (count functions) {
		if ((functionName (at functions i)) == funcName) {
			atPut functions i f
			return f
		}
	}
	functions = (copyWith functions f)
	return f
}

method addFunction MicroBlocksModule aFunction {
	if (notNil (indexOf functions aFunction)) { return } // already there
	for f (copy functions) {
		if ((functionName f) == (functionName aFunction)) {
			removeFunction this f
		}
	}
	setField aFunction 'module' this
	functions = (copyWith functions aFunction)
}

method removeFunction MicroBlocksModule aFunction {
	functions = (copyWithout functions aFunction)
	clearMethodCaches
}

// variables

method variableNames MicroBlocksModule { return (copy variableNames) }

method removeAllVariables MicroBlocksModule {
	variableNames = (array)
}

method addVariable MicroBlocksModule newVar {
	if (not (contains variableNames newVar)) {
		variableNames = (copyWith variableNames newVar)
	}
}

method deleteVariable MicroBlocksModule varName {
	variableNames = (copyWithout variableNames varName)
}

// printing

method toString MicroBlocksModule {
	return (join 'MicroBlocksModule(''' moduleName ''')')
}

// saving

method codeString MicroBlocksModule {
	// Return a string containing the code for this MicroBlocksModule.

	result = (list)

	// Add variable declaration
	if ((count variableNames) > 0) {
		varDeclaration = (list 'variables')
		for v variableNames {
			if (needsQuotes this v) { v = (join '''' v '''') }
			add varDeclaration v
		}
		add result (joinStrings varDeclaration ' ')
		add result (newline)
		add result (newline)
	}

	// Add block specs for functions
	sortedFunctions = (sorted
		functions
		(function a b {return ((functionName a) < (functionName b))})
	)
	for func sortedFunctions {
		spec = (specForOp (authoringSpecs) (functionName func))
		if (notNil spec) {
			add result (specDefinitionString spec)
		}
		add result (newline)
	}
	add result (newline)

	// Add function definitions
	pp = (new 'PrettyPrinter')
	for func sortedFunctions {
		add result (prettyPrintFunction pp func)
		add result (newline)
	}

	// Add scripts
	if (not (isEmpty scripts)) { add result (scriptString this) }

	return (joinStrings result)
}

method scriptString MicroBlocksModule {
	newline = (newline)
	result = (list)
	pp = (new 'PrettyPrinter')
	for entry scripts {
		x = (toInteger (at entry 1))
		y = (toInteger (at entry 2))
		expr = (at entry 3)
		add result (join 'script ' x ' ' y ' ')
		if (isClass expr 'Reporter') {
			if (isOneOf (primName expr) 'v' 'my') {
				add result (join '(v ' (first (argList expr)) ')')
			} else {
				add result (join '(' (prettyPrint pp expr) ')')
			}
			add result newline
		} else {
			add result (join '{' newline)
			add result (prettyPrintList pp expr)
			add result (join '}' newline)
		}
		add result newline
	}
	return (joinStrings result)
}

method needsQuotes MicroBlocksModule s {
	// Return true if the given string needs to be quoted in order to be parsed as
	// a variable or function name.

	letters = (letters s)
	if (isEmpty letters) { return true }
	firstLetter = (first letters)
	if (not (or (isLetter firstLetter) ('_' == firstLetter))) { return true }
	for ch letters {
		if (not (or (isLetter ch) (isDigit ch) ('_' == ch))) { return true }
	}
	return false
}

// loading

method loadModuleFromString MicroBlocksModule s {
	cmds = (parse s)
	loadScripts this cmds
	loadFunctions this cmds
	loadVariables this cmds
	clearMethodCache
	return this
}

method loadScripts MicroBlocksModule cmdList {
	scripts = (list)
	for cmd cmdList {
		if ('script' == (primName cmd)) {
			args = (argList cmd)
			add scripts (copyFromTo args 2) // className (first arg) is ignored by MicroBlocks
		}
	}
}

method appendFunction MicroBlocksModule anArray f {
	// Append function f to the given array of functions and return the new array. If the
	// array already contains a function with the same name, replace it and issue a warning.

	functionName = (functionName f)
	for i (count anArray) {
		item = (at anArray i)
		if ((functionName item) == functionName) {
			print 'Warning: There are multiple definitions of' functionName
			atPut anArray i f
			return anArray
		}
	}
	return (copyWith anArray f)
}

method loadFunctions MicroBlocksModule cmdList {
	for cmd cmdList {
		if ('to' == (primName cmd)) {
			args = (toList (argList cmd))
			functionName = (removeFirst args)
			addFirst args nil
			f = (callWith 'functionFor' (toArray args))
			setField f 'functionName' functionName
			setField f 'module' this
			functions = (appendFunction this functions f)
		}
	}
}

method loadVariables MicroBlocksModule cmdList {
	varNames = (list)
	for cmd cmdList {
		if ('variables' == (primName cmd)) {
			for v (argList cmd) {
				if (isClass v 'String') { // quoted var name
					add varNames v
				} else { // unquoted var: mapped to "(v 'varName')" block by the parser
					add varNames (first (argList v))
				}
			}
		}
	}
	variableNames = (toArray varNames)
}

// saving (old)

// method code MicroBlocksModule {
// 	lf = (newline)
// 	aStream = (dataStream (newBinaryData 1000))
// 	nextPutAll aStream 'module'
// 	if (and (notNil moduleName) (moduleName != '')) {
// 		nextPutAll aStream ' '
// 		nextPutAll aStream moduleName
// 	}
// 	nextPutAll aStream lf
// 	printVarNamesOn this aStream
//
// 	if (and (notNil functions) ((count functions) > 0)) {
// 		nextPutAll aStream lf
// 		printFunctionsOn this aStream
// 	}
// 	nextPutAll aStream lf
// 	nextPutAll aStream (scriptString this)
//
// 	return (stringContents aStream)
// }
//
// method printVarNamesOn MicroBlocksModule aStream {
// 	if (and (notNil variableNames) ((count variableNames) > 0)) {
// 		lf = (newline)
// 		nextPutAll aStream 'variables'
// 		for v (sorted variableNames) {
// 			nextPutAll aStream ' '
// 			if (containsWhitespace v) {
// 				nextPutAll aStream (printString v)
// 			} else {
// 				nextPutAll aStream v
// 			}
// 		}
// 		nextPutAll aStream lf
// 	}
// }
//
// method printFunctionsOn MicroBlocksModule aStream {
// 	if (isNil functions) { return }
// 	lf = (newline)
// 	pp = (new 'PrettyPrinter')
// 	list = (sorted
// 		functions
// 		(function a b {return ((functionName a) < (functionName b))})
// 	)
// 	for f list {
// 		nextPutAll aStream (prettyPrintFunction pp f)
// 		if (not (f === (last list))) {
// 			nextPutAll aStream lf
// 		}
// 	}
// }
