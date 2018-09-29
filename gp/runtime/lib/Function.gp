defineClass Function functionName classIndex argNames localNames cmdList module

method functionName Function { return functionName }
method primName Function { return functionName }
method classIndex Function { return classIndex }
method argNames Function { return argNames }
method localNames Function { return localNames }
method cmdList Function { return cmdList }
method module Function { return module }
method setModule Function m { module = m }
method isMethod Function { return (0 != classIndex) }

method toString Function {
  if (isNil functionName) { return '<Function>' }
  return (join '<Function ' functionName '>')
}

method allCalls Function {
  comment '
	Return a dictionary with the names of all functions called by this one.'

  result = (dictionary)
  if (isNil cmdList) { return result }
  todo = (list cmdList)
  while ((count todo) > 0) {
    cmd = (removeFirst todo)
    add result (primName cmd)
    args = (argList cmd)
	for i (count args) {
      arg = (at args i)
      if (isClass arg 'Command') { add todo arg }
      if (isClass arg 'Reporter') { add todo arg }
	}
	if (notNil (nextBlock cmd)) { add todo (nextBlock cmd) }
  }
  return result
}

method varsUsed Function {
  comment '
	Return a list of all variable names referenced by this function.'

  varNameIndex = ((fieldNameCount (class 'Command')) + 1)
  vars = (dictionary)
  for ref (allVariableRefs this) {
    add vars (getField ref varNameIndex)
  }
  return (keys vars)
}

method refsOfVariable Function varName {
  comment '
	Return a list of all commands and reporters that reference the given variable.'

  varNameIndex = ((fieldNameCount (class 'Command')) + 1)
  result = (list)
  for ref (allVariableRefs this) {
    if ((getField ref varNameIndex) == varName) { add result ref }
  }
  return result
}

method allVariableRefs Function {
  comment '
	Return a list of all commands and reporters that reference variables.'

  result = (list)
  if (isNil cmdList) { return result }
  todo = (list cmdList)
  while ((count todo) > 0) {
    cmd = (removeFirst todo)
	op = (primName cmd)
    args = (argList cmd)
    if (isOneOf op 'v' '=' '+=' 'local' 'for') { add result cmd }
	for i (count args) {
      arg = (at args i)
      if (isClass arg 'Command') { add todo arg }
      if (isClass arg 'Reporter') { add todo arg }
	}
	if (notNil (nextBlock cmd)) { add todo (nextBlock cmd) }
  }
  return result
}

method returnsValue Function {
  comment '
	Return true if this function contains a return statement with an argument.'

  if (isNil cmdList) { return false }
  todo = (list cmdList)
  while ((count todo) > 0) {
    cmd = (removeFirst todo)
	if (and ('return' == (primName cmd)) ((count (argList cmd)) > 0)) {
	  return true
	}
    args = (argList cmd)
	for i (count args) {
      arg = (at args i)
      if (isClass arg 'Command') { add todo arg }
      if (isClass arg 'Reporter') { add todo arg }
	}
	if (notNil (nextBlock cmd)) { add todo (nextBlock cmd) }
  }
  return false
}

method updateCmdList Function newCmdList {
  // Update the command list of this function or method after editing.
  // If the list of local variables used in the command list has
  // changed, update localNames.

  for b (allBlocks cmdList) { clearCache b }
  if (isNil newCmdList) {
	localNames = (array)
	cmdList = nil
	return
  }
  if (isClass newCmdList 'Reporter') {
	newCmdList = (toCommand newCmdList)
  }
  cmdList = newCmdList
  newLocals = (collectLocals cmdList)
  removeAll newLocals argNames
  if (isMethod this) {
	removeAll newLocals (fieldNames (class classIndex))
  }
  newLocals = (sorted (keys newLocals))
  if (newLocals != (sorted localNames)) {
	localNames = newLocals
  }
  for b (allBlocks cmdList) { clearCache b }
}

// copying

method copy Function {
  body = nil
  if (notNil cmdList) {
	body = (copy cmdList)
  }
  return (new 'Function'
    functionName
    classIndex
    (copy argNames)
    (copy localNames)
    body
    module
  )
}

// function creation

to newFunction funcName paramNames body module {
  if (isNil paramNames) { paramNames = (array) }
  if (not (or (isNil body) (isClass body 'Command'))) {
	error 'Function body must be a Command or nil'
  }
  localVars = (toList (keys (collectLocals body)))
  removeAll localVars paramNames
  if (isNil module) { module = (topLevelModule) }
  return (new 'Function' funcName 0 (copy (toArray paramNames)) (toArray localVars) body module)
}

to functionFor obj args... {
  // Return an anonymous function to be run in the context of the given object,
  // thus allowing the function to access the object's instance variables.
  // The last argument, which must be a Command, is the body of the function.
  // Any arguments between the first and last argument are addional argument
  // names for the function.

  if ((argCount) < 2) { error 'Not enough arguments' }

  argNames = (list)
  if (notNil obj) { add argNames 'this' }
  if ((argCount) > 2) {
    for i (range 2 ((argCount) - 1)) {
      add argNames (arg i)
	}
  }

  body = (arg (argCount))
  if (not (or (isNil body) (isClass body 'Command'))) {
	error 'Function body must be a Command or nil'
  }

  localVars = (toList (keys (collectLocals body)))
  removeAll localVars argNames
  removeAll localVars (fieldNames (classOf obj))

  if (isNil obj) {
	classIndex = 0 // function is not attached to any class
	mod = (thisModule)
  } else {
	classIndex = (classIndex (classOf obj))
	mod = (module (classOf obj))
  }
  return (new 'Function' '' classIndex (toArray argNames) (toArray localVars) body mod)
}

to collectLocals cmdOrReporter result {
  // Return a dictionary of all local variables used in the given command or
  // reporter, but do not include variables inside function or method definitions.

  if (isNil result) { result = (dictionary) }
  if (isNil cmdOrReporter) { return result }
  argList = (argList cmdOrReporter)
  op = (primName cmdOrReporter)
  if (isOneOf op 'v' '=' '+=' 'local' 'for') {
	if ((count argList) > 0) {
	  varName = (first argList)
	  if (varName != 'this') { add result varName }
	}
  }
  if (not (isOneOf (primName cmdOrReporter) 'function' 'method')) {
	for arg argList {
	  if (isAnyClass arg 'Command' 'Reporter') { collectLocals arg result }
	}
  }
  if (notNil (nextBlock cmdOrReporter)) { collectLocals (nextBlock cmdOrReporter) result }
  return result
}

to collectLocals2 cmdOrReporter cls result defs used strBuffer {
  // Return a dictionary of all local variables used in the given command or
  // reporter, but do not include variables inside function or method definitions.

  if (isNil cmdOrReporter) { // empty function/method body
	if (isNil result) { return (dictionary) }
	return result
  }
  argList = (argList cmdOrReporter)
  primName = (primName cmdOrReporter)
  if (isNil defs) {
    wasTopLevel = true
    result = (dictionary)
    defs = (dictionary)
    used = (dictionary)
    argNames = (argNames cmdOrReporter)
    if (isClass cmdOrReporter 'Function') { addAll defs argNames }
    if (notNil cls) { addAll defs (fieldNames cls) }

    strBuffer = (list) // of lines
  }

  if ((count argList) > 0) {
    varName = (first argList)
    if ('=' == primName) {
//      if (varName != 'this') { add result varName }
      add defs varName
    } ('+=' == primName) {
//      if (varName != 'this') { add result varName }
      if (isNil (at defs varName)) { add strBuffer (join 'variable ' varName ' used before initialized') }
    } ('for' == primName) {
//      if (varName != 'this') { add result varName }
      if (notNil (at defs varName)) { add strBuffer (join 'variable ' varName ' used in nested for loops') }
      add defs varName
    } ('v' == primName) {
      if (varName != 'this') {
        if (isNil (at defs varName)) { add strBuffer (join 'variable ' varName ' used before initialized') }
        add used varName
      }
    }
  }

  if (isClass cmdOrReporter 'Function') {
    collectLocals2 (cmdList cmdOrReporter) cls result defs used strBuffer
  } else {
	isAnonymousFunction = (and ('function' == primName) (isClass (last argList) 'Command'))
    if (not (or (isOneOf primName 'to' 'method') isAnonymousFunction)) {
      for arg argList {
        if (isAnyClass arg 'Command' 'Reporter') { collectLocals2 arg cls result defs used strBuffer }
      }
      if ('for' == primName) { remove defs varName }
    }
    if (notNil (nextBlock cmdOrReporter)) { collectLocals2 (nextBlock cmdOrReporter) cls result defs used strBuffer }
  }
  if wasTopLevel {
    for c (keys used) { remove defs c }
    remove defs 'this'
    if (notNil cls) { removeAll defs (fieldNames cls) }
    for d (keys defs) {
      if ((indexOf argNames d) > 0) {
        // If you want to check unused arguments for functions, uncomment below.
        // add strBuffer (join 'variable ' d ' passed but not used.')
      } else {
        add strBuffer (join 'variable ' d ' defined but not used.')
      }
    }
    if ((count strBuffer) > 0) {
      if (notNil cls) {
        print (join (functionName cmdOrReporter) ' of ' (className cls) ' has:')
      } else {
        print (join (functionName cmdOrReporter) ' has:')
      }
      for s strBuffer { print '  ' s }
    }
  }
  return result
}

to checkUninitializedVariables {
  a = 42
  for c (classes) {
    for m (methods c) {
      collectLocals2 m c
    }
  }
  for f (functions) {
    collectLocals2 f
  }
}

method removeFieldsFromLocals Function fieldNames {
  // Remove the given field names from this function's localNames.
  newLocals = (toList localNames)
  for f fieldNames { remove newLocals f }
  localNames = (toArray newLocals)
}

// finding functions

to functions { return (globalFuncs) }

to functionNamed funcName module {
  comment '
	Return a generic function with the given name, or nil if the function is not found.
	If module is provided, search only that module for the function.'

  functionList = (list)
  if (notNil module) {
	functionList = (functions module)
  } else {
	editor = (findProjectEditor)
	if (notNil editor) {
	  addAll functionList (functions (module (project editor)))
	}
	addAll functionList (functions (topLevelModule))
	addAll functionList (functions (sessionModule)) // for use during debugging from console
  }
  for i (count functionList) {
    f = (at functionList i)
    if ((functionName f) == funcName) { return f }
  }
  if (contains (primitives) funcName) { return funcName }
  return nil
}
