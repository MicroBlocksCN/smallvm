// Array

// queries

method contains Array element {
  comment '
	Return true if any element equals the input.'
  for el this {
    if (el == element) { return true }
  }
  return false
}

method first Array { return (at this 1) }
method last Array { return (at this (count this)) }

method indexOf Array obj startIndex {
  // Return the index of the first occurrence of the given object after
  // startIndex, or nil if not found. startIndex is optional.

  if (isNil startIndex) { startIndex = 0 }
  i = (startIndex + 1) // index *after* startIndex
  if (i < 1) { i = 1 }
  end = (count this)
  while (i <= end) {
    if (obj == (at this i)) { return i }
	i += 1
  }
  return nil
}

method lastIndexOf Array obj startIndex {
  // Return the index of the last occurrence of the given object before
  // startIndex, or nil if not found. startIndex is optional.

  if (isNil startIndex) { startIndex = ((count this) + 1) }
  i = (startIndex - 1) // index *before* startIndex
  if (i > (count this)) { i = (count this) }
  while (i > 0) {
    if (obj == (at this i)) { return i }
	i += -1
  }
  return nil
}

// equality

method '==' Array other {
  if (this === other) { return true }
  if (not (isClass other 'Array')) {
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

method '<' Array other {
  n = (min (count this) (count other))
  for i n {
    if ((at this i) < (at other i)) {
      return true
    }
  }
  return ((count this) < (count other))
}

method '<=' Array other { return (or (this < other) (this == other)) }
method '>' Array other { return (and (not (this < other)) (not (this == other))) }
method '>=' Array other { return (not (this < other))}

// searching

method find Array target startIndex {
  // Return the starting index of next occurence of the target
  // array or string following the given index. If target is a
  // string it is converted to an array letters. If startIndex
  // is omitted, it defaults to 1. Return 0 if no match found.

  if (isClass target 'String') { target = (letters target) }
  if (isNil startIndex) { startIndex = 1 }
  if ((count target) == 0) { error 'The target array or string must not be empty' }

  targetFirst = (at target 1)
  targetCount = (count target)
  last = (((count this) - targetCount) + 1)
  i = startIndex
  while (i <= last) {
    if ((at this i) == targetFirst) {
	  match = true
	  j = 2
	  while match {
	    if (j > targetCount) { return i } // found a match!
		if ((at target j) != (at this (+ i j -1))) { match = false }
		j += 1
	  }
	}
	i += 1
  }
  return 0
}

// converting/combining

method toList Array {
  return (new 'List' 1 (count this) (copyArray this) )
}

method toArray Array { return this }

method toBinaryData Array {
  // Return a binary data object with the unsigned byte values in this array.
  // Assume all values in this array are integers in the range [0..255].
  result = (newBinaryData (count this))
  for i (count this) {
	byteAtPut result i (at this i)
  }
  return result
}

method toString Array limit visited {
  if (isNil limit) { limit = 100 }
  if (isNil visited) { visited = (dictionary) }
  if (contains visited this) { return '(array ...)' }
  add visited this
  if (limit > (count this)) { limit = (count this) }
  s = '(array'
  for i limit {
    s = (join s ' ' (toString (at this i) nil visited))
  }
  if (limit < (count this)) { s = (join s ' ...') }
  s = (join s ')')
  return s
}

method copy Array {
  return (copyArray this)
}

method copyWith Array newEl {
  result = (copyArray this ((count this) + 1))
  atPut result (count result) newEl
  return result
}

method copyWithout Array omitEl {
  // Return a copy of this array without any instances of omitEl.
  result = (list)
  for el this {
    if (omitEl != el) { add result el }
  }
  return (toArray result)
}

method copyFromTo Array start end {
  if (and (isNil start) (isNil end)) { return (copyArray this) }
  if (isNil start) { start = 1 }
  if (isNil end) { end = (count this) }
  count = ((end - start) + 1)
  if (count <= 0) { return (array) }
  result = (newArray count)
  for i count {
	atPut result i (at this ((start + i) - 1))
  }
  return result
}

method reversed Array {
  comment '
	Return a copy of this array with the elements in the reverse order.'

  result = (copyArray this)
  n = (count this)
  for i n { atPut result (n - (i - 1)) (at this i) }
  return result
}

method join Array args... {
  comment '
	Return an array with the elements of this array and the argument arrays (or lists) concatenated.'

  count = 0
  for i (argCount) { count += (count (arg i)) }
  result = (newArray count)

  dst = 1
  for i (argCount) {
	arg = (toArray (arg i))
	replaceArrayRange result dst (dst + ((count arg) - 1)) arg
	dst += (count arg)
  }
  return result
}

method joinStrings Array delimiter {
  comment '
	Assuming this is an array of strings, return the result of joining those strings.'

	return (joinStringArray this delimiter)
}

// sorting

method sorted Array sortFunction {
  // Return a sorted version of this array. If sortFunction
  // is not provided, use '<' (i.e. ascending order).
  //
  // Mergesort vs. Quicksort:
  // Quicksort is about 8% faster than MergeSort when using the '<' primitive
  // on a randomly shuffled array of integers (a common case) and about 40%
  // faster if the array is already sorted. However:
  //   1. Mergesort is 45% faster when using a custom sort function (it does fewer comparisions)
  //   2. Mergesort is stable, meaning that the order of equal elements is preserved
  //   3. Mergesort is 49% faster on the worst case for Quicksort (identical elements)

  return (mergeSorted this sortFunction)
}

method isSorted Array {
  for i ((count this) - 1) {
	if ((at this i) > (at this (i + 1))) { return false }
  }
  return true
}

method quicksort Array from to sortFunction {
  // Sort my elements in place. Elements must be comparable using "<", "==", and "!=".'

  if (isNil from) { from = 1 }
  if (isNil to) { to = (count this) }
  if (notNil sortFunction) {
	quicksortCustom this from to sortFunction
	return
  }
  if (to <= from) {
    return nil
  } ((from + 1) == to) {
    if ((at this to) < (at this from)) {
      t = (at this to)
      atPut this to (at this from)
      atPut this from t
    }
    return nil
  }
  v = (at this (half (from + to)))
  bottom = from
  top = to
  while (bottom < top) {
    while ((at this bottom) < v) {
      bottom = (bottom + 1)
    }
    while (v < (at this top)) {
      top = (top - 1)
    }
    if (bottom < top) {
      equal = ((at this bottom) == (at this top))
      if (not equal) {
        t = (at this bottom)
        atPut this bottom (at this top)
        atPut this top t
      }
      if (or ((at this bottom) != v) equal) {
        bottom = (bottom + 1)
      }
      if (or ((at this top) != v) equal) {
        top = (top - 1)
      }
    }
  }
  quicksort this from bottom
  quicksort this (bottom + 1) to
}

method quicksortCustom Array from to sortFunction {
  // Sort my elements in place using sortFunction.

  if (to <= from) {
    return nil
  } ((from + 1) == to) {
    if (call sortFunction (at this to) (at this from)) {
      t = (at this to)
      atPut this to (at this from)
      atPut this from t
    }
    return nil
  }
  v = (at this (half (from + to)))
  bottom = from
  top = to
  while (bottom < top) {
    while (call sortFunction (at this bottom) v) {
      bottom = (bottom + 1)
    }
    while (call sortFunction v (at this top)) {
      top = (top - 1)
    }
    if (bottom < top) {
      equal = ((at this bottom) == (at this top))
      if (not equal) {
        t = (at this bottom)
        atPut this bottom (at this top)
        atPut this top t
      }
      if (or ((at this bottom) != v) equal) {
        bottom = (bottom + 1)
      }
      if (or ((at this top) != v) equal) {
        top = (top - 1)
      }
    }
  }
  quicksortCustom this from bottom sortFunction
  quicksortCustom this (bottom + 1) to sortFunction
}

method mergeSorted Array sortFunction {
  // Return a copy of this array sorted using the given sortFunction or
  // with '<' if sortFunction is not provided.

  n = (count this)
  a = (mergeSortedFirstPass this sortFunction)
  b = (copyArray this) // working copy
  runLen = 2 // start with runs of length 2 (already sorted); merge and double runLen at each step
  while (runLen < n) {
	if (isNil sortFunction) {
	  merge a runLen b
	} else {
	  mergeCustom a runLen b sortFunction
	}
	// swap a and b
	tmp = a
	a = b
	b = tmp
    runLen = (2 * runLen)
  }
  return a
}

method mergeSortedFirstPass Array sortFunction {
  // Return a copy of this array with pairs of adjacent elements in sorted
  // order. This is an optimization of the first step of mergeSort.
  // Optimization: Separate loop using '<' if no sortFunction.

  n = (count this)
  result = (newArray n)
  if ((n % 2) == 1) { atPut result n (at this n) } // odd length; copy last element
  i = 1
  if (isNil sortFunction) {
	while (i < n) {
	  a = (at this i)
	  b = (at this (i + 1))
	  if (b < a) {
		atPut result i b
		atPut result (i + 1) a
	  } else {
		atPut result i a
		atPut result (i + 1) b
	  }
	  i += 2
	}
  } else {
	while (i < n) {
	  a = (at this i)
	  b = (at this (i + 1))
	  if (call sortFunction b a) {
		atPut result i b
		atPut result (i + 1) a
	  } else {
		atPut result i a
		atPut result (i + 1) b
	  }
	  i += 2
	}
  }
  return result
}

method merge Array runLen out {
  // Merge runs of length runLen into out.
  n = (count this)
  i = 1
  while (i <= n) {
	// Merge runs [i..i+runLen) and [i+runLen..i+2*runLen) into out
	end = ((i + (2 * runLen)) - 1)
	if (end > n) { end = n }
	left = i
	right = (i + runLen)
	rightStart = right
	j = left
	while (j <= end) {
	  if (left >= rightStart) {
		replaceArrayRange out j end this right
		j = end
	  } (right > end) {
		replaceArrayRange out j end this left
		j = end
	  } else {
		if ((at this right) < (at this left)) {
		  atPut out j (at this right)
		  right += 1
		} else {
		  atPut out j (at this left)
		  left += 1
		}
	  }
	  j += 1
	}
	i += (2 * runLen)
  }
}

method mergeCustom Array runLen out sortFunction {
  // Merge runs of length runLen into out.
  n = (count this)
  i = 1
  while (i <= n) {
	// Merge runs [i..i+runLen) and [i+runLen..i+2*runLen) into out
	end = ((i + (2 * runLen)) - 1)
	if (end > n) { end = n }
	left = i
	right = (i + runLen)
	rightStart = right
	j = left
	while (j <= end) {
	  if (left >= rightStart) {
		replaceArrayRange out j end this right
		j = end
	  } (right > end) {
		replaceArrayRange out j end this left
		j = end
	  } else {
		if (call sortFunction (at this right) (at this left)) {
		  atPut out j (at this right)
		  right += 1
		} else {
		  atPut out j (at this left)
		  left += 1
		}
	  }
	  j += 1
	}
	i += (2 * runLen)
  }
}

// shifting and replacing

method arrayShift Array shift {
  comment '
	Shift the elements of this array in place right by shift positions.
	If shift is negative, shift left by the absolute value of shift.'

  if (or (isNil shift) (shift == 0)) { return this }

  if (shift > 0) {
    replaceArrayRange this (shift + 1) (count this) this 1
	fillArray this nil 1 shift
  } else {
    end = ((count this) + shift)
    replaceArrayRange this 1 end this ((abs shift) + 1)
	fillArray this nil (end + 1) (count this)
  }
  return this
}

// operations for indexable collections

to isEmpty collection { return ((count collection) == 0) }
to notEmpty collection { return ((count collection) > 0) }

to atRandom collection { return (at collection (rand 1 (count collection))) }

to flattened collection result {
  if (isNil result) { result = (list) }
  for elem collection {
    if (or (isClass elem 'Array') (isClass elem 'List')) {
      flattened elem result
    } else {
      add result elem
    }
  }
  return result
}

to shuffled collection {
  // Return a shuffled copy of the given collection.

  if (isClass collection 'Array') {
	result = (copyArray collection)
  } else {
	result = (toArray collection)
  }
  n = (count result)
  for i n {
	j = (rand i n)
	tmp = (at result j)
	atPut result j (at result i)
	atPut result i tmp
  }
  if (isClass collection 'List') {
	result = (toList result)
  }
  return result
}

// set operations for indexable collections

to union c1 c2 {
  // Return a list containing every element that appears in either c1 or c2.

  if (isClass c1 'Dictionary') { c1 = (keys c1) }
  if (isClass c2 'Dictionary') { c2 = (keys c2) }
  seen = (dictionary)
  result = (list)
  for el (join c1 c2) {
	if (not (contains seen el)) {
	  add result el
	  add seen el
	}
  }
  return result
}

to intersection c1 c2 {
  // Return a list containing the elements that appears in both c1 or c2.

  if (isClass c1 'Dictionary') { c1 = (keys c1) }
  if (isClass c2 'Dictionary') { c2 = (keys c2) }
  result = (list)
  d = (dictionary)
  if ((count c1) < (count c2)) {
	addAll d c1
	src = c2
  } else {
	addAll d c2
	src = c1
  }
  for el src {
	if (contains d el) { add result el }
  }
  return result
}

to withoutAll c1 c2 {
  // Return a list containing the elements of c1 without any of the elements in c2.

  if (isClass c2 'Dictionary') {
	d = c2
  } else {
	d = (dictionary)
	addAll d c2
  }
  result = (list)
  for el c1 {
	if (not (contains d el)) { add result el }
  }
  return result
}
