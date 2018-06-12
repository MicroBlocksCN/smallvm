defineClass Module moduleName classes functions expanders variableNames variables exports codeHash

method initialize Module modName {
  if (isNil modName) { modName = '' }
  moduleName = modName
  classes = (array)
  functions = (array)
  expanders = nil
  variableNames = (array)
  variables = (array)
  exports = (dictionary)
  codeHash = nil
  return this
}

// accessors

method classes Module { return classes }
method functions Module { return functions }

method codeHash Module {
  if ((topLevelModule) === this) {
	if (isNil codeHash) {
	  codeHash = (sha256 (code this))
	}
  }
  return codeHash
}

// module exports

method at Module k {
  // Return the given exported item or nil.

  item = (at exports k)
  if (isClass item 'String') { // item is a variable
	i = (indexOf variableNames item)
	return (at variables i) // return the current value
  }
  return item
}

method keys Module {
  // Return an array containing the names of all exported items.

  return (keys exports)
}

// classes

method addClass Module aClass {
  classes = (copyWith classes aClass)
}

method removeClass Module aClass {
  remove exports (className aClass)
  classes = (copyWithout classes aClass)
}

method classNamed Module name {
  if (this === (topLevelModule)) { return (class name) }
  if (isNil classes) {return nil}
  for c classes {
	if ((className c) == name) {
	  return c
	}
  }
  return nil
}

method unusedClassName Module baseName {
  if (isNil (classNamed this baseName)) { return baseName }
  id = 2
  while true {
	className = (join baseName id)
	if (isNil (classNamed this className)) { return className }
	id += 1
  }
}

method defineClassInModule Module className fields... {
  cls = (classNamed this className)
  if (isNil cls) {
	fields = (list)
	for i ((argCount) - 2) {
	  add fields (arg (i + 2))
	}
	cls = (newClass className fields this)
	classes = (copyWith classes cls)
  }
  clearCaches cls
  return cls
}

// functions

method functionNamed Module fName {
  for f functions {
	if (fName == (functionName f)) { return f }
  }
  return nil
}

method defineFunctionInModule Module funcName funcParams funcBody {
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

method addFunction Module aFunction {
  if (notNil (indexOf functions aFunction)) { return } // already there
  for f functions {
	if ((functionName f) == (functionName aFunction)) {
	  error (join 'This modue already has a function named' (functionName aFunction))
	}
  }
  setField aFunction 'module' this
  functions = (copyWith functions aFunction)
}

method removeFunction Module aFunction {
  functions = (copyWithout functions aFunction)
  clearMethodCaches
}

// variables

method variableNames Module { return (copy variableNames) }

method removeAllVariables Module {
  variableNames = (newArray 0)
  variables = (newArray 0)
}

method addVar Module varName {
  if (not (contains variableNames varName)) {
	variableNames = (copyWith variableNames varName)
	variables = (copyWith variables 0)
  }
}

method deleteVar Module varName {
  // Remove the variable with the given name from this module.

  i = (indexOf variableNames varName)
  if (isNil i) { return }
  n = ((count variableNames) - 1)
  newVarNames = (newArray n)
  newVars = (newArray n)

  replaceArrayRange newVarNames 1 (i - 1) variableNames
  replaceArrayRange newVarNames i n variableNames (i + 1)
  replaceArrayRange newVars 1 (i - 1) variables
  replaceArrayRange newVars i n variables (i + 1)

  variableNames = newVarNames
  variables = newVars
}

// printing

method toString Module {
  list = (list)
  add list 'Module('
  if (notNil moduleName) { add list (toString moduleName) }
  add list ')'
  return (joinStringArray (toArray list))
}

// loading

to loadModule fileName args... {
  if (not (contains (letters fileName) '/')) {
	fileName = (join 'modules/' fileName)
  }
  if (not (endsWith fileName '.gpm')) {
	fileName = (join fileName '.gpm')
  }
  modName = (withoutExtension (filePart fileName))

  s = (readFile fileName)
  if (isNil s) {
	s = (readFile (join (directoryPart (appPath)) 'modules/' (filePart fileName)))
  }
  if (isNil s) {
	s = (readFile (join (directoryPart (appPath)) 'runtime/modules/' (filePart fileName)))
  }
  if (isNil s) { s = (readEmbeddedFile fileName) }
  if (isNil s) { error 'module file not found' fileName }

  result = (initialize (new 'Module') modName)
  loadModuleFromString result s

  // collect module args and call initializer
  args = (list)
  for i (argCount) {
	if (i > 1) { add args (arg i) }
  }
  callInitializer result args
  return result
}

method loadModuleFromString Module s {
  cmds = (parse s)
  loadClassDefinitions this cmds
  loadMethods this cmds
  loadScripts this cmds
  loadFunctions this cmds
  loadModuleVariables this cmds
  loadModuleExports this cmds
  clearMethodCache
  return this
}

method loadClassDefinitions Module cmdList {
  classDefs = (dictionary)
  for cmd cmdList {
	if ('defineClass' == (primName cmd)) {
	  args = (toList (argList cmd))
	  className = (removeFirst args)
	  if (contains classDefs className) {
		print 'Warning: Multple definitions of class' className 'in module' moduleName
	  } else {
		atPut classDefs className (list)
	  }
	  fields = (at classDefs className)
	  for n args {
		if (not (contains fields n)) { add fields n }
	  }
	}
  }
  for className (keys classDefs) {
	cl = (newClass className (at classDefs className) this)
	classes = (copyWith classes cl)
  }
}

method loadMethods Module cmdList {
  moduleClasses = (dictionary)
  for cl classes { atPut moduleClasses (className cl) cl }

  for cmd cmdList {
	if ('method' == (primName cmd)) {
	  args = (toList (argList cmd))
	  methodName = (removeFirst args)
	  className = (removeFirst args)

	  // create method
	  addFirst args 'this'
	  m = (callWith 'functionFor' (toArray args))
	  setField m 'functionName' methodName
	  setField m 'module' this

	  // install method in a module class or as an expander
	  cl = (at moduleClasses className)
	  if (notNil cl) {
		setField m 'classIndex' (classIndex cl)
		setField cl 'methods' (appendFunction this (methods cl) m)
	  } else {
		cl = (class className)
		setField m 'classIndex' (classIndex cl)
		if (isNil expanders) { expanders = (array) }
		  appendExpander this m cl
	  }
	  // remove field names from locals
	  removeFieldsFromLocals m (fieldNames cl)
	}
  }
}

method loadScripts Module cmdList {
  moduleClasses = (dictionary)
  for cl classes { atPut moduleClasses (className cl) cl }
  scriptsForClass = (dictionary) // className -> list of scripts

  for cmd cmdList {
	if ('script' == (primName cmd)) {
	  args = (argList cmd)
	  className = (first args)
	  scripts = (at scriptsForClass className)
	  if (isNil scripts) {
		scripts = (list)
		atPut scriptsForClass className scripts
	  }
	  add scripts (copyFromTo args 2)
	}
  }

  for className (keys scriptsForClass) {
	cl = (at moduleClasses className)
	if (notNil cl) {
	  setScripts cl (at scriptsForClass className)
	} else {
	  print 'Ignorning scripts for unknown class:' className
	}
  }
}

method appendFunction Module anArray f {
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

method appendExpander Module func cls {
  functionName = (functionName func)
  clsIdx = (classIndex cls)
  for i (count expanders) {
	item = (at expanders i)
	if (and ((functionName item) == functionName) (clsIdx == (classIndex item))) {
	  print 'Warning: There are multiple definitions of' functionName
	  atPut expanders i func
	  return
	}
  }
  expanders = (copyWith expanders func)
}

method loadFunctions Module cmdList {
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

method loadModuleVariables Module cmdList {
  varNames = (list)
  for cmd cmdList {
	if ('moduleVariables' == (primName cmd)) {
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
  variables = (newArray (count varNames))
}

method loadModuleExports Module cmdList {
  for cmd cmdList {
	if ('moduleExports' == (primName cmd)) {
	  for v (argList cmd) {
		itemName = (first (argList v))
		item = (itemForExport this itemName)
		if (isNil item) {
		  print 'Error: Unknown exported item' itemName
		} else {
		  atPut exports itemName item
		}
	  }
	}
  }
}

method itemForExport Module itemName {
  result = nil
  for cl classes {
	if ((className cl) == itemName) {
	  result = cl
	}
  }
  for f functions {
	if ((functionName f) == itemName) {
	  if (notNil result) { print 'Warning: Ambiguous export' itemName }
	  result = f
	}
  }
  for v variableNames {
	if (v == itemName) {
	  if (notNil result) { print 'Warning: Ambiguous export' itemName }
	  result = v
	}
  }
  if (isNil result) {
	for e expanders {
	  if ((functionName e) == itemName) {
		print 'Error: You cannot export' (join '"' itemName '"') 'because its class is not defined in this module'
	  }
	}
  }
  return result
}

method callInitializer Module argList {
  // Call the module initializer, if any, with the given arguments.
  if (isNil argList) { argList = (array) }
  initFunc = nil
  for f functions {
	if ('initializeModule' == (functionName f)) {
	  if (isNil initFunc) {
		initFunc = f
	  } else {
		print 'Warning: Multiple initializeModule functions in' moduleName
	  }
	}
  }
  if (notNil initFunc) { callWith initFunc (toArray argList) }
}

// saving

method code Module {
  lf = (newline)
  aStream = (dataStream (newBinaryData 1000))
  nextPutAll aStream 'module'
  if (and (notNil moduleName) (moduleName != '')) {
	nextPutAll aStream ' '
	nextPutAll aStream moduleName
  }
  nextPutAll aStream lf

  printVarNamesOn this aStream
  printExportsOn this aStream

  // the above three lines come without extra blank lines

  if (and (notNil functions) ((count functions) > 0)) {
	nextPutAll aStream lf
	printFunctionsOn this aStream
  }
  if (and (notNil classes) ((count classes) > 0)) {
	nextPutAll aStream lf
	printClassesOn this aStream
	printScriptsOn this aStream
  }
  if (and (notNil expanders) ((count expanders) > 0)) {
	nextPutAll aStream lf
	printExpandersOn this aStream
  }
  return (stringContents aStream)
}

method printVarNamesOn Module aStream {
  if (and (notNil variableNames) ((count variableNames) > 0)) {
	lf = (newline)
	nextPutAll aStream 'moduleVariables'
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

method printExportsOn Module aStream {
  if (and (notNil exports) ((count exports) > 0)) {
	lf = (newline)
	nextPutAll aStream 'moduleExports'
	for v (sorted (keys exports)) {
	 nextPutAll aStream ' '
	 nextPutAll aStream v
	}
	nextPutAll aStream lf
  }
}

method printFunctionsOn Module aStream {
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

method printClassesOn Module aStream {
  if (isNil classes) { return }
  lf = (newline)
  pp = (new 'PrettyPrinter')
  list = (sorted
	classes
	(function a b {return ((className a) < (className b))})
  )
  for c classes {
	nextPutAll aStream (prettyPrintClass pp c)
	if (not (c === (last classes))) {
	  nextPutAll aStream lf
	}
  }
}

method printScriptsOn Module aStream {
  if (isNil classes) { return }
  for c classes {
	if (notNil (scripts c)) {
	  nextPutAll aStream (scriptString c)
	}
  }
}

method printExpandersOn Module aStream {
  if (isNil expanders) {return}
  lf = (newline)
  pp = (new 'PrettyPrinter')
  cls = (dictionary)
  allClasses = (classes)
  for e expanders {
	n = (className (at allClasses (classIndex e)))
	if (isNil (at cls n)) {
	  atPut cls n (list)
	}
	add (at cls n) e
  }
  cNameList = (sorted (keys cls))
  cList = (newArray (count cNameList))
  for i (count cNameList) {
	n = (at cNameList i)
	atPut cList i (at cls n)
  }
  for ms cList {
	mList = (sorted (toArray ms) function a b {return ((functionName a) <= (functionName b))})
	for m mList {
	  nextPutAll aStream (prettyPrintMethod pp m)
	  if (not (m === (last mList))) {
		nextPutAll aStream lf
	  }
	}
	if (not (ms === (last cList))) {
	  nextPutAll aStream lf
	}
  }
}

// serialization

method serializedFieldNames Module {
  return (getField this 'variableNames')
}

method serialize Module {
  return (copy (getField this 'variables'))
}

method deserialize Module fieldDict {
  for k variableNames {
    setShared k (at fieldDict k) this
  }
}
