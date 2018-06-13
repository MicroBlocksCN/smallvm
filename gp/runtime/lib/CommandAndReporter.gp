// Command and Reporter

defineClass Command primName lineno fileName cache cachedClassID nextBlock

method primName Command { return primName }
method nextBlock Command { return nextBlock }
method fileName Command { return fileName }
method lineno Command { return lineno }
method toString Command { return (join '<Commmand ' primName '>') }

method eval Command obj module {
  func = (functionFor obj this)
  if (notNil module) { setField func 'module' module }
  return (call func)
}

to newCommand op {
  comment '
	Create a commmand for the given operation. Any additional arguments
	are used as the arguments of the new command.'

  fixedFields = (fieldNameCount (class 'Command'))
  nargs = ((argCount) - 1)
  cmd = (newIndexable 'Command' nargs)
  setField cmd 'primName' op
  setField cmd 'lineno' 1
  setField cmd 'fileName' ''
  for i nargs {
    setField cmd (fixedFields + i) (arg (i + 1))
  }
  return cmd
}

method toReporter Command {
  result = (newIndexable 'Reporter' ((count this) - (fieldNameCount (classOf this))))
  for i (count this) {
    arg = (getField this i)
	if (or (isClass arg 'Command') (isClass arg 'Reporter')) {
	  setField result i (copy arg)
	} else {
      setField result i arg
	}
  }
  return result
}

method isControlStructure Command {
  // Return true if this is a command list or has a command list as an argument.

  if (notNil nextBlock) { return true }
  if (isOneOf primName 'if' 'repeat' 'while' 'for' 'animate' 'waitUntil' 'return' 'uninterruptedly') {
  	return true
  }
  for arg (argList this) {
    if (isClass arg 'Command') { return true }
  }
  return false
}

method copy Command {
  result = (clone this)
  clearCache result
  last = (count this)
  i = (fieldNameCount (classOf this)) // i is index of 'nextBlock' field
  while (i <= last) {
    arg = (getField this i)
	if (or (isClass arg 'Command') (isClass arg 'Reporter')) {
	  setField result i (copy arg)
	}
	i += 1
  }
  return result
}

method clearCache Command {
  cache = nil
  cachedClassID = nil
}

method allBlocks Command result {
  if (isNil result) { result = (list) }
  add result this
  for arg (argList this) {
    if (isAnyClass arg 'Command' 'Reporter') { allBlocks arg result }
  }
  allBlocks nextBlock result
  return result
}

to allBlocks Nil result {
  if (isNil result) { result = (list) }
  return result
}

// equality

method '==' Command other {
  if (this === other) { return true }
  if (not (isClass other 'Command')) { return false }
  if (primName != (primName other)) { return false }
  if (nextBlock != (nextBlock other))  { return false }
  if ((count this) != (count other)) { return false }

  // compare arg lists
  fixedFields = (fieldNameCount (class 'Command'))
  nargs = ((count this) - fixedFields)
  for i nargs {
	argIndex = (fixedFields + i)
    if ((getField this argIndex) != (getField other argIndex)) { return false }
  }
  return true
}

// serialization

method serializedFieldNames Command { return (array 'primName' 'nextBlock') }

method serialize Command {
  fixedFields = (fieldNameCount (classOf this))
  nargs = ((count this) - fixedFields)
  result = (newArray (nargs + 2))
  atPut result 1 primName
  atPut result 2 nextBlock
  for i nargs {
    atPut result (i + 2) (getField this (fixedFields + i))
  }
  return result
}

method deserialize Command fieldNames extraFields {
  fileName = ''
  lineno = 1
  primName = (at fieldNames 'primName')
  nextBlock = (at fieldNames 'nextBlock')
  fixedFields = (fieldNameCount (classOf this))
  for i (count extraFields) {
    setField this (fixedFields + i) (at extraFields i)
  }
  return this
}

defineClass Reporter primName lineno fileName cache cachedClassID nextBlock

method primName Reporter { return primName }
method nextBlock Reporter { return nextBlock }
method fileName Reporter { return fileName }
method lineno Reporter { return lineno }
method toString Reporter { return (join '<Reporter ' primName '>') }
method toReporter Reporter { return this }

method eval Reporter obj module {
  if (isControlStructure this) {
	return (eval (toCommand this) obj module)
  }
  return (eval (newCommand 'return' this) obj module)
}

to newReporter op {
  comment '
	Create a reporter for the given operation. Any additional arguments
	are used as the arguments of the new reporter.'

  fixedFields = (fieldNameCount (class 'Reporter'))
  nargs = ((argCount) - 1)
  rep = (newIndexable 'Reporter' nargs)
  setField rep 'primName' op
  setField rep 'lineno' 1
  setField rep 'fileName' ''
  for i nargs {
    setField rep (fixedFields + i) (arg (i + 1))
  }
  return rep
}

method toCommand Reporter {
  result = (newIndexable 'Command' ((count this) - (fieldNameCount (classOf this))))
  for i (count this) {
    arg = (getField this i)
	if (or (isClass arg 'Command') (isClass arg 'Reporter')) {
	  setField result i (copy arg)
	} else {
      setField result i arg
	}
  }
  return result
}

method isControlStructure Reporter {
  // Return true if this is a command list or has a command list as an argument.

  if (notNil nextBlock) { return true }
  if (isOneOf primName 'if' 'repeat' 'while' 'for' 'animate' 'waitUntil' 'return' 'uninterruptedly') {
  	return true
  }
  for arg (argList this) {
    if (isClass arg 'Command') { return true }
  }
  return false
}

method copy Reporter {
  result = (clone this)
  clearCache result
  last = (count this)
  i = (fieldNameCount (classOf this)) // i is index of 'nextBlock' field
  while (i <= last) {
    arg = (getField this i)
	if (or (isClass arg 'Command') (isClass arg 'Reporter')) {
	  setField result i (copy arg)
	}
	i += 1
  }
  return result
}

method clearCache Reporter {
  cache = nil
  cachedClassID = nil
}

method allBlocks Reporter result {
  if (isNil result) { result = (list) }
  add result this
  for arg (argList this) {
    if (isAnyClass arg 'Command' 'Reporter') { allBlocks arg result }
  }
  allBlocks nextBlock result
  return result
}

// equality

method '==' Reporter other {
  if (this === other) { return true }
  if (not (isClass other 'Reporter')) { return false }
  if (primName != (primName other)) { return false }
  if (nextBlock != (nextBlock other))  { return false }
  if ((count this) != (count other)) { return false }

  // compare arg lists
  fixedFields = (fieldNameCount (class 'Reporter'))
  nargs = ((count this) - fixedFields)
  for i nargs {
	argIndex = (fixedFields + i)
    if ((getField this argIndex) != (getField other argIndex)) { return false }
  }
  return true
}

// serialization

method serializedFieldNames Reporter { return (array 'primName') }

method serialize Reporter {
  fixedFields = (fieldNameCount (classOf this))
  nargs = ((count this) - fixedFields)
  result = (newArray (nargs + 1))
  atPut result 1 primName
  for i nargs {
    atPut result (i + 1) (getField this (fixedFields + i))
  }
  return result
}

method deserialize Reporter fieldNames extraFields {
  fileName = ''
  lineno = 1
  primName = (at fieldNames 'primName')
  fixedFields = (fieldNameCount (classOf this))
  for i (count extraFields) {
    setField this (fixedFields + i) (at extraFields i)
  }
  return this
}

// arguments

to argList cmdOrReporter {
  comment '
	Return the argument list of the given command or reporter.'

  fixedFields = (fieldNameCount (class 'Command'))
  nargs = ((count cmdOrReporter) - fixedFields)
  if (nargs <= 0) { return (array) }
  result = (newArray nargs)
  for i nargs {
    atPut result i (getField cmdOrReporter (fixedFields + i))
  }
  return result
}

to setArg cmdOrReporter n val {
  fixedFields = (fieldNameCount (class 'Command'))
  setField cmdOrReporter (fixedFields + n) val
}
