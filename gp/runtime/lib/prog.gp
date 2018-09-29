// code statistics

to codeStats {
  comment '
	Print statistics about the number classes and functions.'

  classNames = (list)
  methodCount = 0
  classes = (classes)
  for i (count classes) {
    c = (at classes i)
	add classNames (className c)
    methodCount += (count (methods c))
  }
  print (count classNames) 'classes,' methodCount 'methods,' (count (functions)) 'generic functions,' (count (primitives)) 'primitives'
  classNames = (sorted (toArray classNames))
  for i (count classNames) {
    cName = (at classNames i)
    print '  ' cName '--' (count (methods (class cName))) 'methods'
  }
}

// class documentation

to documentationFor className {
  comment '
	Return a string containing a commented list of methods for the given clas.
	If className is omitted, return documentation for the generic functions.'
  if (notNil className) {
    functionList = (methods (class className))
  } else {
    functionList = (functions)
  }
  result = (list)
  for i (count functionList) {
    f = (at functionList i)
	comment = (firstComment f)
	add result (functionName f)
	if (notNil comment) { add result comment }
	add result (newline)
	add result (newline)
  }
  return (joinStringArray (toArray result))
}

to firstComment func {
  comment '
	If the first command of the given function is a comment command,
	return its argument (typically a string). Otherwise, return nil.'

  firstCmd = (cmdList func)
  if (isClass firstCmd 'Command') {
    args = (argList firstCmd)
    if (and ('comment' == (primName firstCmd)) ((count args) > 0)) {
	  result = (at args 1)
	  if (isClass result 'String') { return result }
	}
  }
  return nil
}

// cache clearing

to clearMethodCaches {
  // Clear inline caches and global method cache.

  for cmd (allInstances 'Command') { clearCache cmd }
  for r (allInstances 'Reporter') { clearCache r }
  clearMethodCache
}

// primitive check

to hasPrimitive primName {
  return (not (beginsWith (call 'help' primName) 'Unknown'))
}

to primitiveHelpString primName {
  // Return the primitive help string.
  setFont 'Arial' (12 * (global 'scale'))
  return (joinStrings (wordWrapped (call 'help' primName) 300) (newline))
}

// callers and implementors

to containsCall script calleeName {
  // Returns true if the given script includes a call to callee.

	for cmdOrReporter (allBlocks script) {
		blockSpec = (specForOp (authoringSpecs) (primName cmdOrReporter))
		if (notNil blockSpec) {
			for spec (specs blockSpec) {
				if ((find (letters spec) (letters calleeName)) != 0) {
					return true
				}
			}
		}
	}
	return false
}

to callers calleeName {
  comment '
	Return a list of functions (methods) that call the given function.'

  results = (list)
  classes = (classes)
  for i (count classes) {
    c = (at classes i)
	for j (count (methods c)) {
	  m = (at (methods c) j)
	  if (contains (allCalls m) calleeName) {
	    add results (array (className c) (functionName m))
	  }
    }
  }
  for i (count (functions)) {
    f = (at (functions) i)
	if (contains (allCalls f) calleeName) {
      add results (array '<generic>' (functionName f))
    }
  }
  return (toArray results)
}

to implementors funcName {
  comment '
	Return a list of classes that implement the given function.'

  results = (list)
  classes = (classes)
  for i (count classes) {
    c = (at classes i)
	for j (count (methods c)) {
	  m = (at (methods c) j)
	  if ((functionName m) == funcName) {
	    add results (className c)
	  }
    }
  }
  for i (count (functions)) {
    f = (at (functions) i)
	if ((functionName f) == funcName) {
      add results '<generic>'
    }
  }
  if (contains (primitives) funcName) { addFirst results '<primitive>' }
  return (toArray results)
}

to uncalledAndUnimplemented {
  // Print lists of functions that are not called and
  // functions that are called but not implemented.

  allCalled = (dictionary)
  allImplemented = (dictionary)
  addAll allImplemented (primitives)
  classes = (classes)
  for i (count classes) {
    c = (at classes i)
	for j (count (methods c)) {
	  m = (at (methods c) j)
	  addAll allCalled (keys (allCalls m))
	  add allImplemented (functionName m)
    }
  }
  for i (count (functions)) {
    f = (at (functions) i)
	addAll allCalled (keys (allCalls f))
	add allImplemented (functionName f)
  }

  uncalled = (dictionary)
  names = (keys allImplemented)
  for i (count names) {
    n = (at names i)
	if (not (contains allCalled n)) {
	  add uncalled n
	}
  }
  removeAll uncalled (primitives)

  unimplemented = (dictionary)
  names = (keys allCalled)
  for i (count names) {
    n = (at names i)
	if (not (contains allImplemented n)) {
      add unimplemented n
    }
  }

  print (count uncalled) 'uncalled functions: ' (toString (keys uncalled) 10000)
  print (count unimplemented) 'unimplemented functions: ' (toString (keys unimplemented) 10000)
}

// deep copy

to deepCopy anObject ignore copyDict {
  if (isNil ignore) { ignore = (array) }
  if (isNil copyDict) { copyDict = (dictionary) }
  if (contains ignore anObject) { return nil }
  if (isAnyClass anObject 'Boolean' 'ExternalReference' 'Float' 'Integer' 'Nil' 'String') {
	return anObject
  }
  if (contains copyDict anObject) { return (at copyDict anObject) }
  dup = (clone anObject)
  if (isClass anObject 'Texture') { dup = (copyTexture anObject) }
  atPut copyDict anObject dup
  if (isClass dup 'BinaryData') { return dup }
  for i (objWords dup) {
	setField dup i (deepCopy (getField dup i) ignore copyDict)
  }
  return dup
}
