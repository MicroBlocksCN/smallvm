// operations that call functions on arrays and lists

to map func values {
  comment '
	Return an array with the result of calling
	the given function on each element of values.'

  if (isClass func 'String') {
	func = (moduleFunctionOrOp func (module (caller (currentTask))))
  }
  result = (newArray (count values))
  for i (count values) {
    atPut result i (call func (at values i))
  }
  return (toList result)
}

to filter func values {
  comment '
	Return an array or list containing only those elements
	of values for which the function returns true.'

  if (isClass func 'String') {
	func = (moduleFunctionOrOp func (module (caller (currentTask))))
  }
  result = (list)
  for i (count values) {
    v = (at values i)
    if (call func v) { add result v }
  }
  return result
}

to detect func values valueIfNotFound {
  comment '
	Return the first element for which the function returns true.
	Otherwise, return valueIfNotFound.'

  if (isClass func 'String') {
	func = (moduleFunctionOrOp func (module (caller (currentTask))))
  }
  for i (count values) {
    v = (at values i)
    if (call func v) { return v }
  }
  return valueIfNotFound
}

to reduce func values valueIfEmpty {
  comment '
	Combime all elements with a two-argument function.
	If values is empty, return valueIfEmpty.'

  if (isClass func 'String') {
	func = (moduleFunctionOrOp func (module (caller (currentTask))))
  }
  if ((count values) == 0) { return valueIfEmpty }
  for i (count values) {
    if (i == 1) {
      result = (at values i)
    } else {
      result = (call func result (at values i))
    }
  }
  return result
}

to moduleFunctionOrOp opName module {
  // If a function with the given name is defined in module, return it.
  // Otherwise, return opName.

  for f (functions module) {
    if (opName == (functionName f)) { return f }
  }
  return opName
}
