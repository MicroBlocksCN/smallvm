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

method choicesFor MicroBlocksProject selector {
	if (contains (choices main) selector) {
		return (at (choices main) selector)
	}
	for lib (values libraries) {
		libChoices = (choices lib)
		if (contains libChoices selector) { return (at libChoices selector) }
	}
	return nil // not found; return empty choices list
}

method extraCategories MicroBlocksProject { return (array) } // called by AuthoringSpecs>specsFor

method hasUserCode MicroBlocksProject {
	if (isNil main) { return false }
	if (and (isEmpty (scripts main)) (isEmpty (functions main)) (isEmpty (variableNames main))) {
		return false
	}
	return true
}

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
	oldLib = (at libraries libName)
	if (notNil oldLib) {
		updatingLibrary oldLib aMicroBlocksModule
	}
	remove libraries libName
	atPut libraries libName aMicroBlocksModule

	// the functions in this new library supersede all earlier versions of those functions
	newFunctionNames = (dictionary)
	for f (functions aMicroBlocksModule) { add newFunctionNames (functionName f) }
	removeSupercededFunctions main newFunctionNames
	for lib (values libraries) {
		if (lib != aMicroBlocksModule) { removeSupercededFunctions lib newFunctionNames }
	}

	// update block specs
	newSpecs = (blockSpecs aMicroBlocksModule)
	for k (keys newSpecs) {
		atPut blockSpecs k (at newSpecs k)
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

	if ('-' == op) { return nil } // ignore dash used as a spacer in library block lists

	for lib (values libraries) {
		if (contains (blockList lib) op) { return (moduleCategory lib) }
	}
	return nil
}

method checkForNewerLibraryVersions MicroBlocksProject autoConfirm {
	// Check for newer versions of libraries used in this project.
	// If true is passed to the optional autoConfirm parameter, update old
	// libraries without asking. Otherwise ask the user for confirmation.

	if (isNil autoConfirm) { autoConfirm = false }

	for libName (keys libraries) {
		newVersion = (getNewerVersion (at libraries libName))
		if (notNil newVersion) {
			if (or
				autoConfirm
				(confirm (global 'page') nil (join
					(localized 'Found a newer version of ') libName (newline)
					(localized 'Do you want me to update the one in the project?')))
			) {
				addLibrary this newVersion
			}
		}
	}
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

method libForFunction MicroBlocksProject aFunc {
	funcName = (functionName aFunc)
	for lib (values libraries) {
		if (notNil (functionNamed lib funcName)) {
			return (moduleName lib)
		}
	}
	return ''
}

method metaInfoForFunction MicroBlocksProject aFunc {
	// Return a tab-delimited block spec string for the given function:
	//	blockType funcName specString argTypes

	funcName = (functionName aFunc)
	spec = (at blockSpecs funcName)
	if (isNil spec) { // no spec (very unlikely), so create one
		specString = funcName
		typeString = ''
		for argName (argNames aFunc) {
			specString = (join specString ' _')
			typeString = (join typeString ' auto')
		}
		defaults = (list)
		spec = (blockSpecFromStrings funcName ' ' specString typeString defaults)
	}

	parts = (toList (argList (first (parse (specDefinitionString spec)))))
	if ((count parts) < 4) {
		add parts '' // add empty arg types string for a parmeterless function
	} else {
		parts = (copyFromTo parts 1 4) // remove any default arg values
	}

	return (joinStrings parts (string 9)) // join fields with tab delimiter
}

// Variables

method allVariableNames MicroBlocksProject {
	// Return a sorted array of all global variables. Use case-insensitive sort.

	result = (dictionary)
	addAll result (variableNames main)
	for lib (values libraries) {
		addAll result (variableNames lib)
	}
	return (sorted
		(keys result)
		(function s1 s2 { return ((toUpperCase s1) < (toUpperCase s2)) }))
}

method addVariable MicroBlocksProject newVar {
	addVariable main newVar
}

method deleteVariable MicroBlocksProject varName {
	for lib (values libraries) {
		deleteVariable lib varName
	}
}

// Variables

method allBroadcasts MicroBlocksProject {
	result = (dictionary)
	for entry (scripts main) {
		for b (allBlocks (last entry)) {
			if (isOneOf (primName b) 'sendBroadcast' 'whenBroadcastReceived') {
				add result (first (argList b))
			}
		}
	}
	return (toList (sorted (keys result)))
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
	fixFunctionLocals this
	return this
}

method loadFromString MicroBlocksProject s updateLibraries {
	// Load project from a string in .ubp format. Keep libraries (modules) together.
	initialize this
	cmdList = (parse s)
	if (and (notEmpty cmdList) ('projectName' == (primName (first cmdList)))) {
		// skip projectName line, if any
		cmdList = (copyFromTo cmdList 2)
	}
	loadSpecs this cmdList
	cmdsByModule = (splitCmdListIntoModules this cmdList)
	isFirst = true
	for cmdList cmdsByModule {
		if isFirst { // main module
			loadFromCmds main cmdList
			isFirst = false
		} else { // library
			lib = (loadFromCmds (newMicroBlocksModule) cmdList true)
			atPut libraries (moduleName lib) lib
		}
	}
	if (isNil updateLibraries) { updateLibraries = true }
	if updateLibraries { checkForNewerLibraryVersions this }
	updatePrimitives this
	fixFunctionLocals this
	return this
}

method addLibraryFromString MicroBlocksProject s libName fileName {
	// Load a library from a string.
	cmdList = (parse s)
	loadSpecs this cmdList
	cmdsByModule = (splitCmdListIntoModules this cmdList)
	for cmdList cmdsByModule {
		lib = (loadFromCmds (newMicroBlocksModule) cmdList)
		if (isNil (moduleName lib)) {
			setModuleName lib libName
		}
		if (beginsWith fileName '//Libraries/') {
			setPath lib (withoutExtension (substring fileName ((count '//Libraries/') + 1)))
		} (beginsWith fileName 'http://') {
			setPath lib fileName
		} (beginsWith fileName (join (gpFolder) '/Libraries')) {
			setPath lib (withoutExtension (substring fileName ((count (join (gpFolder) '/Libraries')) + 1)))
		} else {
			// Local files sourced from places other than the MicroBlocks folder
			// are unsupported as dependencies.
			setPath lib nil
		}
		updatePrimitives lib
		fixFunctionLocals this

		moduleName = (moduleName lib)
		if (notNil (libraryNamed this moduleName)) {
			// updating an existing library: just replace it and don't import dependencies
			removeLibraryNamed this moduleName
		} else {
			importDependencies lib (scripter (smallRuntime))
		}
		addLibrary this lib
	}
	return this
}

method parsedSpecs MicroBlocksProject cmdList {
	specs = (dictionary)
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
			atPut specs op spec
		}
	}
	return specs
}

method loadSpecs MicroBlocksProject cmdList {
	specs = (parsedSpecs this cmdList)
	for k (keys specs) {
		atPut blockSpecs k (at specs k)
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
			m = (list)
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

// Post-load processing

method fixFunctionLocals MicroBlocksProject {
	// Remove project variables for function locals.

	projectVars = (allVariableNames this)
	for f (allFunctions this) { removeFieldsFromLocals f projectVars }
}

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

defineClass MicroBlocksModule moduleName moduleCategory dependencies version author description tags path variableNames blockList functions scripts blockSpecs choices

to newMicroBlocksModule modName {
	return (initialize (new 'MicroBlocksModule') modName)
}

method initialize MicroBlocksModule name {
	moduleName = name
	moduleCategory = 'Library'
	dependencies = (array)
	version = (array 1 0)
	author = 'unknown'
	description = ''
	tags = (array)
	choices = (dictionary)
	variableNames = (array)
	blockList = (list)
	blockSpecs = (dictionary)
	functions = (array)
	scripts = (array)
	return this
}

method blockList MicroBlocksModule { return blockList }
method blockSpecs MicroBlocksModule { return blockSpecs }
method moduleCategory MicroBlocksModule { return moduleCategory }
method moduleName MicroBlocksModule { return moduleName }
method setModuleName MicroBlocksModule modName { moduleName = modName }
method toString MicroBlocksModule { return (join 'MicroBlocksModule(''' moduleName ''')') }
method description MicroBlocksModule { return description }
method version MicroBlocksModule { return (copy version) }
method author MicroBlocksModule { return author }
method tags MicroBlocksModule { return (copy tags) }
method choices MicroBlocksModule { return choices }
method path MicroBlocksModule { return path }
method dependencies MicroBlocksModule { return (copy dependencies) }
method setDependencies MicroBlocksModule deps { dependencies = (toArray (copy deps)) }
method setDescription MicroBlocksModule desc { description = desc }
method setAuthor MicroBlocksModule auth { author = auth }
method setCategory MicroBlocksModule cat { moduleCategory = cat }
method setVersion MicroBlocksModule versionArray {
	atPut version 1 (at versionArray 1)
	atPut version 2 (at versionArray 2)
}
method setTags MicroBlocksModule tagList { tags = (copy (toArray tagList)) }
method setPath MicroBlocksModule aPath { path = aPath }

method dependencyName MicroBlocksModule dep {
	slashPos = (findLast dep '/')
	if (slashPos > 0) { slashPos = (slashPos + 1) }
	poundPos = (findLast dep '#')
	if (poundPos > 0) {
		poundPos = (poundPos - 1)
	} else {
		poundPos = (count dep)
	}
	return (withoutExtension (substring dep slashPos poundPos))
}

method dependencyNames MicroBlocksModule {
	deps = (list)
	for dep dependencies {
		add deps (dependencyName this dep)
	}
	return deps
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
	recompileNeeded (smallRuntime)
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
	recompileNeeded (smallRuntime)
}

method removeFunction MicroBlocksModule aFunction {
	functions = (copyWithout functions aFunction)
	recompileNeeded (smallRuntime)
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

method arrayToDeclaration MicroBlocksModule array title {
	declaration = (list title)
	for i array {
		if (needsQuotes this i) { i = (join '''' i '''') }
		add declaration (toString i)
	}
	add declaration (newline)
	return (joinStrings declaration ' ')
}

method codeString MicroBlocksModule owningProject newLibName {
	// Return a string containing the code for this MicroBlocksModule.
	// If newLibName is not nil, this module is being exported as a library.

	result = (list)
	modName = moduleName
	if (notNil newLibName) { modName = newLibName }
	if (needsQuotes this modName) { modName = (join '''' modName '''') }
	add result (join 'module ' modName)

	if ('Library' != moduleCategory) {
		modCat = moduleCategory
		if (needsQuotes this modCat) { modCat = (join '''' modCat '''') }
		add result (join ' ' modCat)
	}
	add result (newline)

	// add author
	by = author
	if (needsQuotes this author) { by = (join '''' author '''') }
	add result (join 'author ' by (newline))

	add result (arrayToDeclaration this version 'version')

	// add dependency declaration
	if ((count dependencies) > 0) {
		add result (arrayToDeclaration this dependencies 'depends')
	}

	// add tag declaration
	if ((count tags) > 0) {
		add result (arrayToDeclaration this tags 'tags')
	}

	// add choice lists
	if ((count (keys choices)) > 0) {
		for key (keys choices) {
			choice = (list key)
			addAll choice (at choices key)
			add result (arrayToDeclaration this choice 'choices')
		}
	}

	// add description
	add result (join 'description ' (printString description) (newline))

	// add variable declaration
	if ((count variableNames) > 0) {
		add result (arrayToDeclaration this variableNames 'variables')
	}

	add result (newline)

	projectSpecs = (blockSpecs owningProject)
	processed = (dictionary)

	for op blockList {
		if ('-' == op) {
			add result (join '  space' (newline))
		} else {
			spec = (at projectSpecs op)
			if (notNil spec) {
				add result (join '  ' (specDefinitionString spec) (newline))
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
					add result (join '  ' (specDefinitionString spec) (newline))
					add processed op
				}
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

	// Add scripts if not exporting as a library
	if (isNil newLibName) {
		add result (scriptString this)
	}

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
			add result (join '(' (prettyPrint pp expr) ')')
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
	if (isNumber s) { return false }
	if (isOneOf s 'true' 'false') { return true }
	letters = (letters s)
	if (isEmpty letters) { return true }
	firstLetter = (first letters)
	if (or (isDigit firstLetter) ('-' == firstLetter)) { return true }
	if (not (or (isLetter firstLetter) ('_' == firstLetter))) { return true }
	for ch letters {
		if (not (or (isLetter ch) (isDigit ch) ('_' == ch))) { return true }
	}
	return false
}

// loading

method loadFromCmds MicroBlocksModule cmdList {
	loadModuleNameAndCategory this cmdList
	loadVersion this cmdList
	loadAuthor this cmdList
	loadDependencies this cmdList
	loadTags this cmdList
	loadDescription this cmdList
	loadChoices this cmdList
	loadVariables this cmdList
	loadBlockList this cmdList
	loadSpecs this cmdList
	loadFunctions this cmdList
	loadScripts this cmdList
	return this
}

method browserEmbeddedLibs MicroBlocksModule {
	result = (list)
	todo = (list 'Libraries')
	while (notEmpty todo) {
		libpath = (removeFirst todo)
		for dirName (listEmbeddedFiles libpath true) {
			add todo (join libpath '/' dirName)
		}
		for fName (listEmbeddedFiles libpath false) {
			if (endsWith fName '.ubl') {
				add result (join libpath '/' fName)
			}
		}
	}
	return result
}

method getNewerVersion MicroBlocksModule {
	// Return the embedded library with the same name and a newer version or nil if none found.

	if (moduleName == 'main') { return nil }

	embeddedFiles = (listEmbeddedFiles)
	if ('Browser' == (platform)) {
		embeddedFiles = (browserEmbeddedLibs this)
	}

	// Find the embedded lib path
	moduleFileName = (join moduleName '.ubl')
	v1 = version // current version
	for filePath embeddedFiles {
		if ((filePart filePath) == moduleFileName) {
			cmdList = (parse (readEmbeddedFile filePath))
			candidate = (newMicroBlocksModule moduleName)
			loadFromCmds candidate cmdList
			v2 = (version candidate)
			if (or
				((at v2 1) > (at v1 1))
				(and ((at v1 1) == (at v2 1)) ((at v2 2) > (at v1 2)))
			) {
				return candidate
			}
		}
	}
	return nil
}

method updatingLibrary MicroBlocksModule newerModule {
	// Called when updating an existing library (the receiver) to a newer version.
	// Update the block specs of existing functions that are being updated.
	// Retain the block specs for any functions that are being removed
	// and add "obsolete" to their labels to allow them to be identified
	// in any scripts in which they appear.

	newSpecs = (blockSpecs newerModule)
	projectSpecs = (blockSpecs (project (findProjectEditor)))
	for oldSpec (values (blockSpecs this)) { // for each spec in this module
		op = (blockOp oldSpec)
		if (contains newSpecs op) {
			// update exising spec for op
			atPut projectSpecs op (at newSpecs op)
		} else {
			// mark old function as obsolete and append to module
			obsoletedLabel = (join 'obsolete ' (first (specs oldSpec)))
			atPut (specs oldSpec) 1 obsoletedLabel
			atPut projectSpecs op oldSpec
			add (blockList newerModule) op
		}
	}
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

method stringArgs MicroBlocksModule cmd {
	args = (list)
	for arg (argList cmd) {
		if (isClass arg 'String') { // quoted item
			add args arg
		} (isClass arg 'Integer') {
			add args arg
		} else { // unquoted item: mapped to "(v 'varName')" block by the parser
			add args (first (argList arg))
		}
	}
	return args
}

method loadDescription MicroBlocksModule cmdList {
	for cmd cmdList {
		if ('description' == (primName cmd)) {
			description = (first (stringArgs this cmd))
		}
	}
}

method loadChoices MicroBlocksModule cmdList {
	for cmd cmdList {
		if ('choices' == (primName cmd)) {
			i = (list)
			for input (stringArgs this cmd) {
				add i (toString input)
			}
			atPut choices (first (stringArgs this cmd)) (copyFromTo i 2)
		}
	}
}

method loadVersion MicroBlocksModule cmdList {
	for cmd cmdList {
		if ('version' == (primName cmd)) {
			atPut version 1 (at (argList cmd) 1)
			atPut version 2 (at (argList cmd) 2)
		}
	}
}

method loadAuthor MicroBlocksModule cmdList {
	for cmd cmdList {
		if ('author' == (primName cmd)) {
			author = (first (stringArgs this cmd))
		}
	}
}
method loadVariables MicroBlocksModule cmdList {
	varNames = (list)
	for cmd cmdList {
		if (isOneOf (primName cmd) 'variables' 'sharedVariables') {
			for v (stringArgs this cmd) {
				add varNames v
			}
		}
	}
	variableNames = (toArray varNames)
}

method loadDependencies MicroBlocksModule cmdList {
	deps = (list)
	for cmd cmdList {
		if ('depends' == (primName cmd)) {
			for libName (stringArgs this cmd) {
				lib = (toString libName)
				add deps lib
			}
		}
	}
	dependencies = (toArray deps)
}

method importDependencies MicroBlocksModule scripter {
	for dependency dependencies {
		importDependency this dependency scripter
	}
}

method importDependency MicroBlocksModule lib scripter {
	// dependencies look like either:
	// LibName						- Fetch from embedded FS
	// /LibName						- Fetch from ~/MicroBlocks/Libraries
	// http://url/LibName.ubp		- Fetch from server

	// Additionally, one can define version requirements like this:
	// LibName#>1.4					- Needs at least version 1.4
	// /LibName#=2.7				- Needs exactly version 2.7
	// http://url/LibName.ubp#>1.1	- Needs at least version 1.1

	// find version requirements
	vPosition = (findLast lib '#')
	vRequirement = ''
	reqVersion = (array 1 0)
	if (vPosition > 0) {
		vPosition = (vPosition + 1)
		vRequirement = (substring lib vPosition vPosition)
		atPut reqVersion 1 (toInteger (substring lib (vPosition + 1) ((findLast lib '.') - 1)))
		atPut reqVersion 2 (toInteger ((findLast lib '.') + 1))
		lib = (substring lib 1 (vPosition - 2))
	}

	// TODO Make sure we comply with version requirement (ex. >2.3, =1.5)

	if (beginsWith lib 'http') {
		// fetch library from remote URL
		importLibraryFromUrl scripter lib
	} (beginsWith lib '/') {
		// fetch library from [MicroBlocksFolder]/Library
		importLibraryFromFile scripter (join (gpFolder) '/Libraries' lib '.ubl')
	} else {
		// load embedded library
		importEmbeddedLibrary scripter lib
	}
}



method loadTags MicroBlocksModule cmdList {
	t = (list)
	for cmd cmdList {
		if ('tags' == (primName cmd)) {
			for tag (stringArgs this cmd) {
				add t (toLowerCase (toString tag))
			}
		}
	}
	tags = (toArray t)
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
	recompileNeeded (smallRuntime)
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

method loadSpecs MicroBlocksModule cmdList {
	blockSpecs = (parsedSpecs (project (findProjectEditor)) cmdList)
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
	} ('newArray' == oldPrim) { return 'newList'
	} ('fillArray' == oldPrim) { return 'fillList'
	} ('sendBroadcastSimple' == oldPrim) { return 'sendBroadcast'
	} ('split' == oldPrim) { return '[data:split]'
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
