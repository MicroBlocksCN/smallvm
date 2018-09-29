// Dictionary

defineClass Dictionary tally keys values

classComment Dictionary '
A Dictionary is a flexible data object that can be used:

  1. to associate names with values (use atPut/at with string keys)
  2. as a set of unique objects (use add/remove/contains)
  3. as a sparse array (use atPut/at with integer keys)
  4. as a histogram to record the number times a particular value occurs (use add/remove/sortedPairs)'

classComment Dictionary '
Implementation details: A Dictionary is repesented as a hash table.
Keys and values are kept in two parallel arrays, with values[i] being the
value associated with key[i]. When used as a set or histogram, the presence
of a key indicates inclusion of that key in the set and the value is the
number of times that key has been added.'

to dictionary args... {
  comment '
    Return a new Dictionary containing the given keys.'
  keys = (newArray 20)
  values = (newArray 20)
  result = (new 'Dictionary' 0 keys values)
  for i (argCount) { add result (arg i) }
  return result
}

method count Dictionary {
  comment '
	Return the number of items in this dictionary.'

	return tally
}

method contains Dictionary k {
  comment '
	Return true if this dictionary has an entry for the given key.'

  i = (scanForKeyOrNil this k)
  return (notNil (at keys i))
}

method at Dictionary k defaultValue {
  comment '
	Return the value associated with the given key or defaultValue
	if there is no entry for that key.'

  i = (scanForKeyOrNil this k)
  v = (at values i)
  if (isNil v) { return defaultValue }
  return v
}

method atPut Dictionary k v {
  comment '
	Add a key and value to this dictionary.'

  i = (scanForKeyOrNil this k)
  if (isNil (at keys i)) {
    atNewIndexPut this i k v
  } else {
    atPut values i v
  }
}

method add Dictionary k n {
  comment '
	Add the given key. This method allows a Dictionary be used like a set.
	Also, count how many times a given key has been added. This can be useful
	for building building histograms (e.g. the number of times the word
	"the" appears in set of words.) The optional second parameter allows
	the count for a key to be incremented by numbers other than one.'

  if (isNil n) { n = 1 }
  i = (scanForKeyOrNil this k)
  if (isNil (at keys i)) {
    newValue = n
  } else {
    newValue = ((at values i) + n)
  }
  atPut this k newValue
}

method addAll Dictionary elements {
  comment '
	Add the contents of the given dictionary, list, or array.'

  if (isClass elements 'Dictionary') {
    newKeys = (keys elements)
	for k (count newKeys) {
	  atPut this k (at elements k)
	}
  } else {
    if (not (or (isClass elements 'Array') (isClass elements 'List'))) {
      elements = (toArray elements)
    }
    for i (count elements) { add this (at elements i) }
  }
}

method remove Dictionary k {
  comment '
	Remove the given key and its associated value.'

  i = (scanForKeyOrNil this k)
  if (isNil (at keys i)) { return } // key not found
  atPut keys i nil
  atPut values i nil
  tally = (tally - 1)
  fixCollisions this i
}

method removeAll Dictionary elements {
  comment '
	Remove the contents of the given dictionary, list, or array.'

  if (isClass elements 'Dictionary') {
    elements = (keys elements)
  }
  if (not (or (isClass elements 'Array') (isClass elements 'List'))) {
    elements = (toArray elements)
  }
  for i (count elements) { remove this (at elements i) }
}

// converting

method copy Dictionary {
  result = (clone this)
  setField result 'keys' (copyArray keys)
  setField result 'values' (copyArray values)
  return result
}

method keys Dictionary {
  comment '
	Return an array containing all keys (unsorted).'

  result = (list)
  for i (count keys) {
    k = (at keys i)
	if (notNil k) { add result k }
  }
  return (toArray result)
}

method values Dictionary {
  comment '
	Return an array with all values (unsorted).'

  result = (list)
  for i (count keys) {
    k = (at keys i)
	if (notNil k) { add result (at values i) }
  }
  return (toArray result)
}

method keyAtValue Dictionary value {
  comment '
	Return a key that has the given value, or nil if there is none.
	Note: Does linear search of the keys, so can be slow for large Dictionaries.'

  for i (count keys) {
	if ((at values i) == value) { return (at keys i) }
  }
  return nil
}

method sortedPairs Dictionary sortByKey {
  comment '
	Return a sorted array of pairs (two-element arrays) for my contents.
	If sortByKey is true, the pairs are (key, value).
	Otherwise, the pairs are (value, key). Either way,
	the pairs are sorted by their first element.'

  result = (list)
  if (true == sortByKey) {
    for i (count keys) {
      if (notNil (at keys i)) { add result (array (at keys i) (at values i)) }
    }
  } else {
    for i (count keys) {
      if (notNil (at keys i)) { add result (array (at values i) (at keys i)) }
    }
  }
  sortFunction = (function a b { return ((at a 1) <= (at b 1)) })
  result = (sorted (toArray result) sortFunction)
  return result
}

method toString Dictionary limit visited {
  if (isNil limit) { limit = 200 }
  if (isNil visited) { visited = (dictionary) }
  if (contains visited this) { return '(dictionary ...)' }
  add visited this
  result = (list '(dictionary')
  for pair (reversed (sortedPairs this)) {
	if ((count result) > limit) {
	  add result ')'
	  return (joinStrings result)
	}
	count = (at pair 1)
	k = (at pair 2)
	if (and (isClass k 'String') (k <= ' ')) { k = (printString k) } // quote whitespace characters
	add result (join '   '  (toString k nil visited) ' ' (toString count nil visited) )
  }
  add result ')'
  return (joinStrings result)
}

// serialization

method serializedFieldNames Dictionary { return (array) }

method serialize Dictionary {
  result = (list)
  for k (keys this) {
    add result k
	add result (at this k)
  }
  return (toArray result)
}

method deserialize Dictionary fieldDict extraFields {
  // Details: extraFields is an array of alternating keys and values.

  count = (count extraFields)
  tally = 0
  keys = (newArray (max count 5))
  values = (newArray (max count 5))

  i = 1
  while (i < count) {
    atPut this (at extraFields i) (at extraFields (i + 1))
	i += 2
  }
}

// implementation helpers

method atNewIndexPut Dictionary i k v {
  comment '
	Add new key and value pair at the given index (assumed to currently
	contain nil). Increase the tally and grow if more than 3/4 full.'

  atPut keys i k
  atPut values i v
  tally += 1
  if (((count keys) * 3) < (tally * 4)) {
    comment 'Double in size if over 3/4 full to avoid performance degradation'
    grow this (2 * (count keys))
  }
}

method grow Dictionary newSize {
  comment '
	Grow to the given size. Dictionaries grow automatically as entries are added,
	so this method is usually not called by the client. However, when building
	very large dictionaries (thousands of entries), it can improve performance
	by a factor of two or more to grow the dictionary in advance to about 1.5
	times the expected number of entries.'

  newSize = (max newSize (2 * (count keys)))
  oldKeys = keys
  oldValues = values
  keys = (newArray newSize)
  values = (newArray newSize)
  tally = 0
  for i (count oldKeys) {
    k = (at oldKeys i)
    if (notNil k) { atPut this k (at oldValues i) }
  }
}

method scanForKeyOrNil Dictionary k {
  comment '
	Return the index for k, or the index of a nil slot
	if k is not in this dictonary.'

  useEquality = (isAnyClass k 'String' 'Float' 'Integer' 'LargeInteger')
  i = (((hash k) % (count keys)) + 1)
  end = (i - 1)
  if (end == 0) { end = (count keys) }
  while true {
    thisKey = (at keys i)
    if (isNil thisKey) { return i }
	if (k === thisKey) { return i }
	if (and useEquality (thisKey == k)) { return i }
	if (i == end) { error 'no free space' }
	i = ((i % (count keys)) + 1)
  }
}

method fixCollisions Dictionary freeIndex {
  comment '
	Called when a key is removed, leaving an empty slot.
	Find a key that was pushed down due to collisions
	and move it into the free slot. This may need to
	be done repeatedly to handle a chain of collisions.
	The process stops when it reaches an empty slot.'

  i = ((freeIndex % (count keys)) + 1)
  while true {
    k = (at keys i)
    if (isNil k) { return } // found an empty slot, so done!
	if ((((hash k) % (count keys)) + 1) != i) {
	  if ((scanForKeyOrNil this k) == freeIndex) {
        atPut keys freeIndex k
	    atPut values freeIndex (at values i)
		atPut keys i nil
	    atPut values i nil
		freeIndex = i
	  }
    }
	i = ((i % (count keys)) + 1)
  }
}
