defineClass Class className classIndex fieldNames methods comments scripts module

method className Class { return className }
method classIndex Class { return classIndex }
method fieldNames Class { return fieldNames }
method methods Class { return methods }
method comments Class { return comments }
method scripts Class { return scripts }
method module Class { return module }
method setScripts Class newScripts { scripts = (toArray newScripts) }

// creation

to newClass name fields module {
  // Create a new class and install it in the class table.

  if (isNil fields) { fields = (array) }
  cl = (new 'Class')
  setField cl 'className' name
  setField cl 'classIndex' i
  setField cl 'fieldNames' (copy (toArray fields))
  setField cl 'methods' (array)
  setField cl 'comments' (array)
  setField cl 'scripts' nil
  setField cl 'module' module
  addClass cl // install class in the class table
  return cl
}

// utilities

method fieldNameCount Class {
  return (count fieldNames)
}

method setName Class newName {
  if (not (canChange this)) { return (problem this 'You cannot modify this class') }
  if (className == newName) { return } // no change
  if (notNil (classNamed module newName)) {
	return (problem this (join 'There is already a class named "' newName '"'))
  }
  className = newName
}

method canChange Class {
  // You can only change (i.e. add/remove/rename instance variables) a class
  // if the virtual machine does not depend it having a particular format.

  return (classIndex > (classIndex (class 'LargeInteger')))
}

method toString Class {
  return (join '<Class ' className '>')
}

// method operations

method methodNames Class {
  result = (list)
  for f methods {
    add result (functionName f)
  }
  return result
}

method methodNamed Class methodName {
  for f methods {
    if ((functionName f) == methodName) { return f }
  }
  return nil
}

method removeMethodNamed Class methodName {
  mList = (list)
  for m methods {
    if ((functionName m) != methodName) { add mList m }
  }
  methods = (toArray mList)
  clearMethodCaches
}

method addMethod Class methodName parameterNames body {
  // Add a method with the given name, parameter names, and body, and return it.
  // The last argument, which must be nil or a Command, is the body of the method.

  if ((argCount) < 2) { error 'A method name is required.' }
  if (and (notNil body) (not (isClass body 'Command'))) {
	error 'Method body must be a Command'
  }
  if (and (notNil parameterNames) ((count parameterNames) > 0)) {
	atPut parameterNames 1 'this' // replace Class name in parameter list with 'this'
  } else {
	parameterNames = (array 'this')
  }

  localVars = (toList (keys (collectLocals body)))
  removeAll localVars parameterNames
  removeAll localVars fieldNames

  // add this method, replacing the old version, if any
  result = (new 'Function' methodName classIndex (toArray parameterNames) (toArray localVars) body module)
  if (notNil (methodNamed this methodName)) {
	removeMethodNamed this methodName
  }
  methods = (copyWith methods result)

  return result
}

// user-defined classes

method isUserDefined Class {
  return (not (module === (topLevelModule)))
}

// field operations

method addField Class fieldName {
  // Add a new field to a class (at the end), updating all extant instances.

  if (not (canChange this)) { return (problem this 'You cannot modify this class') }
  if (not (isClass fieldName 'String')) { return (problem this 'The field name must be a string') }
  if (contains fieldNames fieldName) { return } // already has that field
  oldInstances = (toArray (allInstances this))
  fieldNames = (copyWith fieldNames fieldName)
  newInstances = (newArray (count oldInstances))
  for i (count oldInstances) {
    oldObj = (at oldInstances i)
    newObj = (new this)
	for j (objWords oldObj) {
	  setField newObj j (getField oldObj j)
	}
    atPut newInstances i newObj
  }
  replaceObjects oldInstances newInstances
  gc
  clearCaches this
}

method deleteField Class fieldName {
  // Delete a field from a class, updating all extant instances.

  if (not (canChange this)) { return (problem this 'You cannot modify this class') }
  if (varReferenced this fieldName false) {
    return (problem this (join 'Field name still in use: ' fieldName))
  }
  deletedIndex = (indexOf fieldNames fieldName)
  if (isNil deletedIndex) { return } // fieldName already deleted

  oldInstances = (toArray (allInstances this))
  newInstances = (newArray (count oldInstances))

  fieldNames = (copyWithout fieldNames fieldName)
  for i (count oldInstances) {
    oldObj = (at oldInstances i)
    newObj = (new this)
	dst = 1
	for j (objWords oldObj) {
	  if (j != deletedIndex) {
		if (dst <= (objWords newObj)) { // in case of oldObj is a larger, obsolete instance
		  setField newObj dst (getField oldObj j)
		}
	    dst += 1
	  }
	}
    atPut newInstances i newObj
  }
  replaceObjects oldInstances newInstances
  oldInstances = nil
  newInstances = nil
  gc
  clearCaches this
}

method renameField Class oldName newName {
  // Rename a field, updating all references to that variable in
  // all methods of this class.

  if (not (canChange this)) { return (problem this 'You cannot modify this class') }
  if (not (and (isClass oldName 'String') (isClass newName 'String'))) {
    return (problem this 'Field names must be strings')
  }
  if (or (contains fieldNames newName) (varReferenced this newName true)) {
    return (problem this (join 'Field name already in use: ' newName))
  }

  i = (indexOf fieldNames oldName)
  if (isNil i) {
    return (problem this (join 'Class does not have a field named: ' oldName))
  }

  atPut fieldNames i newName // change field name

  // update references to oldName in all methods
  varNameIndex = ((fieldNameCount (class 'Command')) + 1)
  for m methods {
    for ref (refsOfVariable m oldName) {
	  setField ref varNameIndex newName
	  clearCache ref
	}
  }
  clearCaches this
}

method clearCaches Class {
  // Clear the caches in all my methods. This must be done when fields
  // are added to or removed from the class.

  for m methods {
	for b (allBlocks (cmdList m)) { clearCache b }
  }
}

method problem Class reason {
  page = (global 'page')
  if (isNil page) {
    error reason
  } else {
    inform page reason
  }
  return nil
}

method varReferenced Class varName forRename {
  // Return true if the given variable name is referenced by any method in this class.

  for m methods {
    if (contains (argNames m) varName) { return true }
    if (contains (localNames m) varName) { return true }
  }
  if (notNil scripts) {
	for entry scripts {
	  cmd = (at entry 3)
	  for b (allBlocks cmd) {
		if (isOneOf (primName b) 'v' 'my' '=' '+=') {
		  if (varName == (first (argList b))) { return true }
		}
		if (and forRename (isOneOf (primName b) 'local' 'for')) {
		  // when renaming a field variable, avoid conflicts with local variables
		  if (varName == (first (argList b))) { return true }
		}
	  }
	}
  }
  return false
}

// scripts

method scriptString Class oldFormat {
  if (isNil oldFormat) { oldFormat = false }
  newline = (newline)
  result = (list)

  // add class definition
  if oldFormat {
	add result (join 'defineClass ' (printString className))
	for fn fieldNames {
	  add result (join ' ' (printString fn))
	}
	add result (join newline newline)
  }
  if (isNil scripts) { return (joinStrings result) }

  // add scripts
  pp = (new 'PrettyPrinter')
  for entry scripts {
    x = (toInteger (at entry 1))
    y = (toInteger (at entry 2))
    expr = (at entry 3)
    if oldFormat {
	  add result (join 'script ' x ' ' y ' ')
    } else {
	  add result (join 'script ' (printString className) ' ' x ' ' y ' ')
	}
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

// Class copy/paste

method scriptStringWithDefinitionBodies Class {
  if (isNil scripts) { return '' }

  newline = (newline)
  result = (list)

  // add scripts
  pp = (new 'PrettyPrinter')
  for entry scripts {
	x = (toInteger (at entry 1))
	y = (toInteger (at entry 2))
	expr = (at entry 3)
	add result (join 'script ' (printString className) ' ' x ' ' y ' ')

	if (isClass expr 'Reporter') {
	  op = (primName expr)
	  if (isOneOf op 'v' 'my') {
		add result (join '(v ' (first (argList expr)) ')')
	  } else {
		add result (join '(' (prettyPrint pp expr) ')')
	  }
	  add result newline
	} else {
	  add result (join '{' newline)
	  op = (primName expr)
	  if ('method' == op) {
		add result (prettyPrintMethod pp (methodNamed this (first (argList expr))))
	  } ('to' == op) {
		add result (prettyPrintFunction pp (functionNamed (first (argList expr))))
	  } else {
		add result (prettyPrintList pp expr)
	  }
	  add result (join '}' newline)
	}
	add result newline
  }
  return (joinStrings result)
}

// Class exporting

method defStringForFunctionsDefinedInClass Class {
  // For class export. Return a string containing the definition of
  // any shared functions included in this class's scripting area.

  result = (list)
  pp = (new 'PrettyPrinter')
  for fName (functionsDefinedInClass this) {
	add result (prettyPrintFunction pp (functionNamed fName))
	add result (newline)
  }
  return (joinStrings result)
}

method specStringForFunctionsAndMethodsDefinedInClass Class {
  // Return a string containing the specs for all methods of this class
  // plus any shared functions included in its scripting area.

  newline = (newline)
  result = (list)
  for m methods {
	spec = (specForOp (authoringSpecs) (functionName m))
	if (notNil spec) {
	  add result (specDefinitionString spec className)
	}
  }
  for fName (functionsDefinedInClass this) {
	spec = (specForOp (authoringSpecs) fName)
	add result (specDefinitionString spec)
  }
  add result (newline)
  return (joinStrings result (newline))
}

method functionsDefinedInClass Class {
  // Return a list of names for all functions defined in this class.

  result = (list)
  for entry scripts {
	expr = (at entry 3)
	if (and (isClass expr 'Command') ('to' == (primName expr))) {
	  add result (first (argList expr))
	}
  }
  return result
}
