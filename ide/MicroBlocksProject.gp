// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksProject.gp - Representation of a MicroBlocks project and its libraries

to mbProj {
	// Just for debugging. Find the currently installed project.
	gc
	projects = (allInstances 'MicroBlocksProject')
	if ((count projects) > 1) {
		print 'multiple MicroBlocksProject instances'
	}
	return (first projects)
}

to newProjTest fileName {
	// Test that saving and reading projects in the new format preserves the project content.

	print (filePart fileName) '...'
	projectData = (readFile fileName true)
	project = (newMicroBlocksProject)
	if (endsWith fileName '.gpp') {
		// read old project
		mainClass = nil
		oldProj = (readProject (emptyProject) projectData)
		if ((count (classes (module oldProj))) > 0) {
			mainClass = (first (classes (module oldProj)))
			loadFromOldProjectClassAndSpecs project mainClass (blockSpecs oldProj)
		} else {
			error 'no class in old project'
		}
	} else {
		loadNewProjectFromData project (toString projectData)
	}
	if (not (saveLoadTest project)) { print '	FAILED!' }
}

// MicroBlocksProject Class

defineClass MicroBlocksProject main libraries blockSpecs

to newMicroBlocksProject {
	return (initialize (new 'MicroBlocksProject'))
}

method initialize MicroBlocksProject {
	main = (newMicroBlocksModule 'main')
	libraries = (dictionary)
	blockSpecs = (dictionary)
	return this
}

// Support

method extraCategories MicroBlocksProject { return (array) } // called by AuthoringSpecs>specsFor

// Block Specs

method blockSpecs MicroBlocksProject { return blockSpecs }

method recordBlockSpec MicroBlocksProject opName spec {
	atPut blockSpecs opName spec
}

method deleteBlockSpecFor MicroBlocksProject functionName {
	remove blockSpecs functionName
}

// Libraries

method main MicroBlocksProject { return main }
method libraries MicroBlocksProject { return libraries }
method libraryNamed MicroBlocksProject name { return (at libraries name) }

method addLibrary MicroBlocksProject aMicroBlocksModule {
	libName = (moduleName aMicroBlocksModule)
	remove libraries libName
	atPut libraries libName aMicroBlocksModule

	// the functions in this new library supercede all earlier versions of those functions
	newFunctionNames = (dictionary)
	for f (functions aMicroBlocksModule) { add newFunctionNames (functionName f) }
	removeSupercededFunctions main newFunctionNames
	for lib (values libraries) {
		if (lib != aMicroBlocksModule) { removeSupercededFunctions lib newFunctionNames }
	}
}

method removeLibraryNamed MicroBlocksProject libName {
	lib = (at libraries libName)
	if (isNil lib) { return }
	remove libraries libName
	for f (functions lib) {
		remove blockSpecs (functionName f)
	}
}

method categoryForOp MicroBlocksProject op {
	// Return the category for the give op if it is in one of my libraries.

	for lib (values libraries) {
		if (contains (blockList lib) op) { return (moduleCategory lib) }
	}
	return nil
}

// Functions

method allFunctions MicroBlocksProject {
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

// Variables

method allVariableNames MicroBlocksProject {
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

// Loading

method loadFromOldProjectClassAndSpecs MicroBlocksProject aClass specList {
	// Used when reading projects in the old .gpp format.

	initialize this
	for f (functions (module aClass)) { addFunction main f }
	for v (variableNames (module aClass)) { addVariable main v }
	for k (keys specList) { atPut blockSpecs k (at specList k) }
	setScripts main (copy (scripts aClass))
	updatePrimitives this
	return this
}

method loadFromString MicroBlocksProject s {
	// Load project from a string in .ubp format. Keep libraries (modules) together.

	initialize this
	cmdList = (parse s)
	loadSpecs this cmdList
	cmdsByModule = (splitCmdListIntoModules this cmdList)
	isFirst = true
	for cmdList cmdsByModule {
		if isFirst {
			loadFromCmds main cmdList
			isFirst = false
		} else {
			lib = (loadFromCmds (newMicroBlocksModule) cmdList)
			atPut libraries (moduleName lib) lib
		}
	}
	updatePrimitives this
	return this
}

method addLibraryFromString MicroBlocksProject s fileName {
	// Load a library from a string.

	cmdList = (parse s)
	loadSpecs this cmdList
	cmdsByModule = (splitCmdListIntoModules this cmdList)
	for cmdList cmdsByModule {
		lib = (loadFromCmds (newMicroBlocksModule) cmdList)
		if (isNil (moduleName lib)) {
			setModuleName lib fileName
		}
		updatePrimitives lib
		addLibrary this lib
	}
	return this
}

method loadSpecs MicroBlocksProject cmdList {
	for cmd cmdList {
		if ('spec' == (primName cmd)) {
			args = (argList cmd)
			blockType = (at args 1)
			op = (at args 2)
			specString = (at args 3)
			slotTypes = ''
			if ((count args) > 3) { slotTypes = (at args 4) }
			slotDefaults = (array)
			if ((count args) > 4) { slotDefaults = (copyArray args ((count args) - 4) 5) }
			spec = (blockSpecFromStrings op blockType specString slotTypes slotDefaults)
			atPut blockSpecs op spec
		}
	}
}

method splitCmdListIntoModules MicroBlocksProject cmdList {
	// Split the list of commands into a list of command lists for each module of the project.
	// Each module after the first (main) module begins with a 'module' command.

	result = (list)
	m = (list)
	for cmd cmdList {
		if ('module' == (primName cmd)) {
			if (not (isEmpty m)) { add result m }
			m = (list cmd)
		}
		add m cmd
	}
	add result m // add final module
	return result
}

// Saving

method codeString MicroBlocksProject {
	// Return a string representing this project in the new .ubp format.

	// sort libraries by name (this canonicalizes their order)
	sortedLibs = (sorted
		(values libraries)
		(function a b {return ((moduleName a) < (moduleName b))}))

	result = (list)
	add result (codeString main this)
	for lib sortedLibs {
		add result (newline)
		add result (codeString lib this)
	}
	return (joinStrings result)
}

method libraryCodeString MicroBlocksProject modName {
	// Return a string containing the code for this project formatted as a library.

	setModuleName main modName // rename main to module name for saving
	result = (codeString this)
	setModuleName main 'main'
	return result
}

// Updating primitives

method updatePrimitives MicroBlocksProject {
	// Update primitives that have been replaced with newer versions.

	updatePrimitives main
	for lib (values libraries) { updatePrimitives lib }
}

// save/load test

method saveLoadTest MicroBlocksProject {
	// Verify that this project can be saved and reloaded.

	s1 = (codeString this)
	p2 = (loadFromString (newMicroBlocksProject) s1)
	s2 = (codeString p2)
	if (s1 != s2) { print 'second codeString does not match first'; return false }
	if (not (equal this p2)) { print 'second project does not match first'; return false }
	return true
}

// equality

method equal MicroBlocksProject proj {
	// Return true if the given project has the same contents as this one.

	if (not (equal main (main proj))) { return false }
	for lib (values libraries) {
		if (not (equal lib (libraryNamed proj (moduleName lib)))) {
			print '	libs not equal:' (moduleName lib)
			return false
		}
	}
	sortedKeys = (sorted (keys blockSpecs))
	if (sortedKeys != (sorted (keys (blockSpecs proj)))) {
		print '	spec keys mismatch'
		return false;
	}
	for k sortedKeys {
		s1 = (specDefinitionString (at blockSpecs k))
		s2 = (specDefinitionString (at (blockSpecs proj) k))
		if (s1 != s2) {
			print '	spec mismatch' k
			return false
		}
	}
	return true
}

// MicroBlocksModule Class

defineClass MicroBlocksModule moduleName moduleCategory variableNames blockList functions scripts

to newMicroBlocksModule modName {
	return (initialize (new 'MicroBlocksModule') modName)
}

method initialize MicroBlocksModule name {
	moduleName = name
	moduleCategory = ''
	variableNames = (array)
	blockList = (array)
	functions = (array)
	scripts = (array)
	return this
}

method blockList MicroBlocksModule { return blockList }
method moduleCategory MicroBlocksModule { return moduleCategory }
method moduleName MicroBlocksModule { return moduleName }
method setModuleName MicroBlocksModule modName { moduleName = modName }
method toString MicroBlocksModule { return (join 'MicroBlocksModule(''' moduleName ''')') }

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
}

method removeSupercededFunctions MicroBlocksModule superceded {
	for f (copy functions) {
		if (contains superceded (functionName f)) {
			removeFunction this f
		}
	}
	newBlockList = (list)
	for op blockList {
		if (not (contains superceded op)) { add newBlockList op }
	}
	blockList = (toArray newBlockList)
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

// saving

method codeString MicroBlocksModule owningProject {
	// Return a string containing the code for this MicroBlocksModule.

	result = (list)
	modName = moduleName
	if (needsQuotes this modName) { modName = (join '''' modName '''') }
	add result (join 'module ' modName)

	if ('' != moduleCategory) {
		modCat = moduleCategory
		if (needsQuotes this modCat) { modCat = (join '''' modCat '''') }
		add result (join ' ' modCat)
	}
	add result (newline)

	// add variable declaration
	if ((count variableNames) > 0) {
		varDeclaration = (list 'variables')
		for v variableNames {
			if (needsQuotes this v) { v = (join '''' v '''') }
			add varDeclaration v
		}
		add result (joinStrings varDeclaration ' ')
		add result (newline)
	}
	add result (newline)

	projectSpecs = (blockSpecs owningProject)
	processed = (dictionary)

	for op blockList {
		if ('space' != op) {
			spec = (at projectSpecs op)
			if (notNil spec) {
				add result (join '	' (specDefinitionString spec) (newline))
				add processed op
			}
		}
	}

	if (not (isEmpty functions)) {
		// sort functions by name (this canonicalizes function order)
		sortedFunctions = (sorted
			functions
			(function a b {return ((functionName a) < (functionName b))})
		)
		// add function block specs
		for func sortedFunctions {
			op = (functionName func)
			if (not (contains processed op)) {
				spec = (at projectSpecs op)
				if (notNil spec) {
					add result (join '	' (specDefinitionString spec) (newline))
					add processed op
				}
				add result (newline)
			}
		}
		add result (newline)

		// add function definitions
		pp = (new 'PrettyPrinter')
		for func sortedFunctions {
			add result (prettyPrintFunction pp func)
			add result (newline)
		}
	}

	// Add scripts
	add result (scriptString this)

	return (joinStrings result)
}

method scriptString MicroBlocksModule {
	if (isEmpty scripts) { return '' }

	// sort scripts so the scriptString does not depend on z-ordering of scripts
	sortedScripts = (sorted scripts
		(function e1 e2 {
			if ((at e1 2) == (at e2 2)) {
				return ((at e1 1) < (at e2 1)) // y's equal, sort by x
			} else {
				return ((at e1 2) < (at e2 2)) // sort by y
			}
		}))

	result = (list)
	pp = (new 'PrettyPrinter')
	for entry sortedScripts {
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
			add result (newline)
		} else {
			add result (join '{' (newline))
			add result (prettyPrintList pp expr)
			add result (join '}' (newline))
		}
		add result (newline)
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

method loadFromCmds MicroBlocksModule cmdList {
	loadModuleNameAndCategory this cmdList
	loadVariables this cmdList
	loadBlockList this cmdList
	loadFunctions this cmdList
	loadScripts this cmdList
	return this
}

method loadModuleNameAndCategory MicroBlocksModule cmdList {
	if (not (isEmpty cmdList)) {
		cmd = (first cmdList)
		if ('module' == (primName cmd)) {
			arg = (first (argList cmd))
			if (isClass arg 'String') { // quoted var name
				moduleName = arg
			} else { // unquoted var: mapped to "(v 'varName')" block by the parser
				moduleName = (first (argList arg))
			}
			if ((count (argList cmd)) > 1) {
				cat = (at (argList cmd) 2)
				if (isClass cat 'Reporter') { cat = (first (argList cat)) } // unquoted var (see above)
				moduleCategory = cat
			}
		}
	}
}

method loadVariables MicroBlocksModule cmdList {
	varNames = (list)
	for cmd cmdList {
		if (isOneOf (primName cmd) 'variables' 'sharedVariables') {
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

method loadScripts MicroBlocksModule cmdList {
	scripts = (list)
	for cmd cmdList {
		if ('script' == (primName cmd)) {
			add scripts (argList cmd)
		}
	}
}

method loadBlockList MicroBlocksModule cmdList {
	// The blockList is a list of blocks for this library's palette in order
	// of appearance. It is derived from the module specs. The 'space' keyword
	// can be used to add some space between groups of blocks.

	blockList = (list)
	for cmd cmdList {
		if ('space' == (primName cmd)) {
			add blockList '-' // spacer
		} ('spec' == (primName cmd)) {
			add blockList (at (argList cmd) 2)
		}
	}
}

// Updating primitives

method updatePrimitives MicroBlocksModule {
	// Update primitives that have been replaced with newer versions.

	for f functions {
		for b (allBlocks (cmdList f)) {
			newPrim = (newPrimFor this (primName b))
if (notNil newPrim) { print (primName b) '->' newPrim }
			if (notNil newPrim) { setField b 'primName' newPrim }
		}
	}
	for entry scripts {
		for b (allBlocks (at entry 3)) {
			newPrim = (newPrimFor this (primName b))
if (notNil newPrim) { print (primName b) '->' newPrim }
			if (notNil newPrim) { setField b 'primName' newPrim }
		}
	}
}

method newPrimFor MicroBlocksModule oldPrim {
	if ('mbDisplay' == oldPrim) { return '[display:mbDisplay]'
	} ('mbDisplayOff' == oldPrim) { return '[display:mbDisplayOff]'
	} ('mbPlot' == oldPrim) { return '[display:mbPlot]'
	} ('mbUnplot' == oldPrim) { return '[display:mbUnplot]'
	} ('mbDrawShape' == oldPrim) { return '[display:mbDrawShape]'
	} ('mbShapeForLetter' == oldPrim) { return '[display:mbShapeForLetter]'
	} ('neoPixelSetPin' == oldPrim) { return '[display:neoPixelSetPin]'
	} ('neoPixelSend' == oldPrim) { return '[display:neoPixelSend]'
	} ('mbTiltX' == oldPrim) { return '[sensors:tiltX]'
	} ('mbTiltY' == oldPrim) { return '[sensors:tiltY]'
	} ('mbTiltZ' == oldPrim) { return '[sensors:tiltZ]'
	} ('mbTemp' == oldPrim) { return '[sensors:temperature]'
	}
	return nil
}

// equality

method equal MicroBlocksModule otherMod {
	// Return true if the given module has the same content as this one.

	if (moduleName != (moduleName otherMod)) { return false }
	if (variableNames != (variableNames otherMod)) { return false }
	if ((count functions) != (count (functions otherMod))) { return false }
	if ((count scripts) != (count (scripts otherMod))) { return false }

	for i (count functions) {
		if (not (functionsEqual this (at functions i) (at (functions otherMod) i))) {
			print 'function mismatch:' (functionName (at functions i))
			return false
		}
	}

	// sort script entries by position
	scriptSortFunc = (function e1 e2 {
		if ((at e1 2) == (at e2 2)) {
			return ((at e1 1) < (at e2 1)) // y's equal, sort by x
		} else {
			return ((at e1 2) < (at e2 2)) // sort by y
		}
	})
	sortedScripts1 = (sorted scripts scriptSortFunc)
	sortedScripts2 = (sorted (scripts otherMod) scriptSortFunc)

	for i (count sortedScripts1) {
		e1 = (at sortedScripts1 i)
		e2 = (at sortedScripts2 i)
		if (not (and ((at e1 1) == (at e2 1))
					 ((at e1 2) == (at e2 2))
					 ((at e1 3) == (at e2 3))
					 )) {
			print 'script mismatch' e1 e2
			return false
		}
	}
	return true
}

method functionsEqual MicroBlocksModule f1 f2 {
	if ((functionName f1) != (functionName f1)) { return false }
	if ((classIndex f1) != (classIndex f1)) { return false }
	if ((argNames f1) != (argNames f1)) { return false }
	if ((localNames f1) != (localNames f1)) { return false }
	if ((cmdList f1) != (cmdList f1)) { return false }
	if ((module f1) != (module f1)) { return false }
	return true
}
