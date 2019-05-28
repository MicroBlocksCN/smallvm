defineClass MicroBlocksProject main libraries

to newMicroBlocksProject {
	return (initialize (new 'MicroBlocksProject'))
}

method initialize MicroBlocksProject {
	main = (newMicroBlocksModule 'main')
	libraries = (array)
	return this
}

method blockSpecs MicroBlocksProject { print 'MicroBlocksProject>blockSpecs called'; return (dictionary) }
method extraCategories MicroBlocksProject { print 'MicroBlocksProject>extraCategories called'; return (array) }

method extraCategories MicroBlocksProject { return (array) }
method main MicroBlocksProject { return main }
method libraries MicroBlocksProject { return libraries }
method scripts MicroBlocksProject { return (scripts main) }
method setScripts MicroBlocksProject newScripts { setScripts main newScripts }

method className MicroBlocksProject { return '' } // act like a class when called by Scripter

// Libraries

method addLibrary MicroBlocksProject aMicroBlocksModule {
	removeLibraryNamed this (moduleName aMicroBlocksModule)
	libraries = (copyWith libraries aMicroBlocksModule)
}

method removeLibraryNamed MicroBlocksProject libName {
	newLibs = (list)
	for lib libraries {
		if (libName != (moduleName lib)) { add newLibs lib }
	}
	libraries = (toArray newLibs)
}

// Variables

method variableNames MicroBlocksProject {
	// Return all global variables names in this project.

	result = (dictionary)
	addAll result (variableNames main)
	for each lib libraries {
		addAll result (variableNames lib)
	}
	return (sorted (keys result))
}

defineClass MicroBlocksModule moduleName functions variableNames scripts

method blockSpecs MicroBlocksModule { print 'MicroBlocksModule>blockSpecs called'; return (dictionary) }
method extraCategories MicroBlocksModule { print 'MicroBlocksModule>extraCategories called'; return (array) }

to newMicroBlocksModule modName {
	return (initialize (new 'MicroBlocksModule') modName)
}

method initialize MicroBlocksModule modName {
	if (isNil modName) { modName = '' }
	moduleName = modName
	functions = (array)
	variableNames = (array)
	scripts = (array)
	return this
}

method moduleName MicroBlocksModule { return moduleName }

// methods (needed??? xxx)

method methodNamed MicroBlocksModule s { return nil }

// scripts

method scripts MicroBlocksModule { return scripts }
method setScripts MicroBlocksModule newScripts { scripts = (toArray newScripts) }

// functions

method functions MicroBlocksModule { return functions }

method functionNamed MicroBlocksModule fName {
	for f functions {
		if (fName == (functionName f)) { return f }
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
	for f functions {
		if ((functionName f) == (functionName aFunction)) {
			error (join 'This modue already has a function named' (functionName aFunction))
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
	variableNames = (newArray 0)
}

method addVar MicroBlocksModule varName {
	if (not (contains variableNames varName)) {
		variableNames = (copyWith variableNames varName)
	}
}

method deleteVar MicroBlocksModule varName {
	// Remove the variable with the given name from this module.

	i = (indexOf variableNames varName)
	if (isNil i) { return }
	n = ((count variableNames) - 1)
	newVarNames = (newArray n)
	newVars = (newArray n)

	replaceArrayRange newVarNames 1 (i - 1) variableNames
	replaceArrayRange newVarNames i n variableNames (i + 1)
	variableNames = newVarNames
}

// printing

method toString MicroBlocksModule {
	return (join 'MicroBlocksModule(''' moduleName ''')')
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
			className = (first args) // className is ignored by MicroBlocks
			add scripts (copyFromTo args 2)
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

// saving

method code MicroBlocksModule {
	lf = (newline)
	aStream = (dataStream (newBinaryData 1000))
	nextPutAll aStream 'module'
	if (and (notNil moduleName) (moduleName != '')) {
		nextPutAll aStream ' '
		nextPutAll aStream moduleName
	}
	nextPutAll aStream lf
	printVarNamesOn this aStream

	if (and (notNil functions) ((count functions) > 0)) {
		nextPutAll aStream lf
		printFunctionsOn this aStream
	}
	nextPutAll aStream lf
	nextPutAll aStream (scriptString this)

	return (stringContents aStream)
}

method printVarNamesOn MicroBlocksModule aStream {
	if (and (notNil variableNames) ((count variableNames) > 0)) {
		lf = (newline)
		nextPutAll aStream 'variables'
		for v (sorted variableNames) {
			nextPutAll aStream ' '
			if (containsWhitespace v) {
				nextPutAll aStream (printString v)
			} else {
				nextPutAll aStream v
			}
		}
		nextPutAll aStream lf
	}
}

method printFunctionsOn MicroBlocksModule aStream {
	if (isNil functions) { return }
	lf = (newline)
	pp = (new 'PrettyPrinter')
	list = (sorted
		functions
		(function a b {return ((functionName a) < (functionName b))})
	)
	for f list {
		nextPutAll aStream (prettyPrintFunction pp f)
		if (not (f === (last list))) {
			nextPutAll aStream lf
		}
	}
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
