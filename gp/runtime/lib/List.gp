defineClass List first last contents

to list args... {
  if (0 == (argCount)) {
	// common case of calling list with no arguments: client is building up a list
	// return an empty list with capacity to add a few items before growing
	return (new 'List' 1 0 (newArray 4))
  }
  result  = (new 'List' 1 0 (newArray (argCount)))
  for i (argCount) { add result (arg i) }
  return result
}

// queries

method count List { return ((last - first) + 1) }

method isEmpty List { return (last < first) }
method notEmpty List { return (last >= first) }

method contains List obj {
  // Return true if any element equals the given object.
  for i (count this) {
    if ((at this i) == obj) { return true }
  }
  return false
}

// adding

method add List obj {
  // Add obj to the end of this list.
  if (last == (count contents)) { // no room at end
    if (first > 1) {
	  // shift contents down to 1
	  arrayShift contents (1 - first)
	  last = ((last - first) + 1)
	  first = 1
	} else {
	  // grow contents (to double size, min 8)
	  n = (count contents)
	  if (n < 4) { n = 4 }
	  contents = (copyArray contents (2 * n))
	}
  }
  last += 1
  atPut contents last obj
}

method addFirst List obj {
  // Add obj to the start of this list.
  if (first == 1) { // no room at first
    if (last == (count contents)) {
	  // grow contents (to double size, min 8)
	  n = (count contents)
	  if (n < 4) { n = 4 }
	  contents = (copyArray contents (2 * n))
    }
	// shift contents to the end
	shift = ((count contents) - last)
	arrayShift contents shift
	last = (last + shift)
	first = (first + shift)
  }
  first = (first - 1)
  atPut contents first obj
  return obj
}

method addAll List other {
  for each other {
	add this each
  }
}

method addAt List index obj {
  if (index <= 1) { return (addFirst this obj) }
  if (index > (count this)) { return (add this obj) }
  if (last == (count contents)) {
    contents = (copyArray contents (2 * (count contents)))
  }
  i = ((first + index) - 1)
  replaceArrayRange contents (i + 1) (last + 1) contents i
  atPut contents i obj
  last += 1
  return obj
}

// removing

method remove List obj {
  idx = (indexOf this obj)
  while (notNil idx) {
    removeAt this idx
    idx = (indexOf this obj idx)
  }
}

method removeAt List index {
  if (or (index < 1) (index > (count this))) { return }
  if (index == 1) {
	atPut contents first nil
    first += 1
  } else {
    i = (first + (index - 1))
    replaceArrayRange contents i (last - 1) contents (i + 1)
    atPut contents last nil
    last += -1
  }
}

method removeAll List other {
  if (isNil other) { // remove all elements
    first = 1
	last = 0
	contents = (newArray 10)
  } else {
    for i (count other) {
      remove this (at other i)
	}
  }
}

// indexed access

method at List index {
  i = ((first + index) - 1)
  if (or (i < first) (i > last)) { error 'List index out of range:' index }
  return (at contents i)
}

method atPut List index obj {
  i = ((first + index) - 1)
  if (or (i < first) (i > last)) { error 'List index out of range:' index }
  atPut contents ((first + index) - 1) obj
}

method first List {
  if (last < first) { error 'List is empty' }
  return (at contents first)
}

method last List {
  if (last < first) { error 'List is empty' }
  return (at contents last)
}

method removeFirst List {
  if (last < first) { error 'List is empty' }
  result = (at contents first)
  atPut contents first nil
  first += 1
  return result
}

method removeLast List {
  if (last < first) { error 'List is empty' }
  result = (at contents last)
  atPut contents last nil
  last += -1
  return result
}

method indexOf List obj startIndex {
  // Return the index of the first occurrence of the given object after
  // startIndex, or nil if not found. startIndex is optional.

  if (isNil startIndex) { startIndex = 0 }
  i = (first + startIndex) // index *after* startIndex
  if (i < 1) { i = 1 }
  while (i <= last) {
    if (obj == (at contents i)) { return ((i - first) + 1) }
	i += 1
  }
  return nil
}

method lastIndexOf List obj startIndex {
  // Return the index of the last occurrence of the given object before
  // startIndex, or nil if not found. startIndex is optional.

  if (isNil startIndex) { startIndex = ((count this) + 1) }
  i = ((first + startIndex) - 2) // index *before* startIndex
  if (i > (count this)) { i = (count this) }
  while (i >= first) {
    if (obj == (at contents i)) { return ((i - first) + 1) }
	i += -1
  }
  return nil
}

// equality

method '==' List other {
  if (this === other) { return true }
  if (not (isClass other 'List')) {
    return false
  }
  if ((count this) != (count other)) {
    return false
  }
  for i (count this) {
    if ((at this i) != (at other i)) {
      return false
    }
  }
  return true
}

// comparison

method '<' List other {
  n = (min (count this) (count other))
  for i n {
    if ((at this i) < (at other i)) {
      return true
    }
  }
  return ((count this) < (count other))
}

method '<=' List other { return (or (this < other) (this == other)) }
method '>' List other { return (and (not (this < other)) (not (this == other))) }
method '>=' List other { return (not (this < other))}

// converting

method toArray List {
  result = (newArray (count this))
  for i (count this) {
    atPut result i (at this i)
  }
  return result
}

method toList List { return this }

method toString List limit visited {
  if (isNil limit) { limit = 100 }
  if (isNil visited) { visited = (dictionary) }
  if (contains visited this) { return '(list ...)' }
  add visited this
  if (limit > (count this)) { limit = (count this) }
  s = '(list'
  for i limit {
    s = (join s ' ' (toString (at this i) nil visited))
  }
  if (limit < (count this)) { s = (join s ' ...') }
  s = (join s ')')
  return s
}

method reversed List {
  result = (list)
  size = (count this)
  for i size {
    add result (at this (size - (i - 1)))
  }
  return result
}

method join List args... {
  comment '
	Return a new list that contains the contents of this list and the
	contents of all argument lists or arrays (i.e. concatenate all lists/arrays).'

  result = (list)
  for i (argCount) { addAll result (arg i) }
  return result
}

method joinStrings List delimiter {
  comment '
	Assuming this is a list of strings, return the result of joining those strings.'

  if (last < first) { return '' }
  return (joinStringArray contents delimiter first last)
}

method copy List {
  result = (clone this)
  setField result 'contents' (copyArray contents)
  return result
}

method copyFromTo List start end {
  if (and (isNil start) (isNil end)) {
	return (copy this)
  }
  if (isNil start) { start = 1 }
  if (isNil end) { end = (count this) }
  count = ((end - start) + 1)
  if (count <= 0) { return (list) }
  result = (list)
  for i count {
	add result (at this ((start + i) - 1))
  }
  return result
}

// sorting

method sorted List sortFunction {
  comment '
	Return a sorted copy of this list.'

  return (toList (sorted (toArray this) sortFunction))
}

// serialization

method serializedFieldNames List { return (array) }
method serialize List { return (toArray this) }

method deserialize List fieldDict extraFields {
  contents = extraFields
  first = 1
  last = (count contents)
}
