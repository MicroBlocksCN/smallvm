// Serializer.gp - Object structure serialization/deserialization
//
// The serializer packs an arbitrary graph of objects into a binary
// representation that can be saved in a file or transmitted to another
// computer, allowing a copy of the original object graph to be reconstructed
// later or elsewhere.
//
// The API has two top level functions:
//
//	write - takes the root of an object structure and an optional list of
//	  objects to ignore and returns the serialization (a BinaryData object)
//
//	read - converts a serialization (BinaryData) into a reconstruction of the
//		original object structure and returns the root of that structure
//
// The API calls write and read a single root object, but multiple of objects
// can be handled simply by serializing a list or array.
//
// Implementation Details
//
// A serialization has the following structure:
//
//	prefix string
//	class table (className, class field names)
//	object table (classIndex, indexable field count or nil, field values)
//    OR an immediate value
//	postfix string
//
// The prefix and postfix strings are human-readable and designed to allow
// serialized object data to be embedded in a text file and possibly copied
// and pasted as a unit into some other text file using a generic text editor.
// (The binary data in between appears as gibberish, of course, and can't be
// meaningfully edited as text.)
//
// Except for the pre- and postfix strings, all data in the file is rendered
// as a sequence of low-level data objects (numbers, strings, arrays, etc.)
// represented as a tag byte followed by zero or more data bytes. Higher level
// structures such as the class and object tables are built out of low-level objects.
//
// Classes can control their serialized representation by implementing three methods:
//
//	serialize - returns an array of field values (including unnamed indexable fields)
//	serializedFieldNames - returns an array of field names
//  deserialze - called on an uninitialized instance with a dictionary of fieldName, fieldValue pairs
//
// Default serialization behavior is suppled generic versions of these functions
// that simply save and restore all the fields of the object's class.
//
// Although there is no explicit class version number, this representation is fairly
// robust in the face of class evolution. For example, a class in the destination
// system can have its fields in a different order than the system that created
// the serialization, or it can have missing or extra fields. Furthermore, the
// deserialization method can tell from the dictionary keys that a field is
// missing and can supply a default or computed value.
//
// Any classes mentioned in the class table that do not exist in the destination
// system are created as "stubs" with the given field names. This allows instances
// of those classes to be deserialized as simple records, even though the stub
// class has no behavior. This allows the deserialized objects to be inspected.
// Behavior can be added the stub class incrementally to bring these objects to life.
//
// As mentioned, the write call takes an optional list of objects that should
// not be included in the serialization. All references to these objects will be
// replaced by nils in the serialization.

// Default serialization methods (classes may override to customize serialized data)

to serializedFieldNames obj {
  // Return an array of field names for this object's serialization array.
  // This default method just returns the field names for the object's class.

  return (fieldNames (classOf obj))
}

to serialize obj {
  // Return an array that captures the state of this object,
  // where the array entries correspond to serializedFieldNames.

  result = (list)
  for fieldName (serializedFieldNames obj) {
    add result (getField obj fieldName)
  }
  return (toArray result)
}

to deserialize obj fieldDict {
  // Initialize this object from the given dictionary.

  for k (fieldNames (classOf obj)) {
	setField obj k (at fieldDict k)
  }
}

defineClass ObjRef objID

method objID ObjRef { return objID }

defineClass Serializer verbose stream objectTable objects objectsToIgnore classTable classes fieldsForClass prefix postfix version t_nil t_ref t_true t_false t_int t_float t_string t_binary t_array

// Constants

method initConstants Serializer {
  version = 1
  crlf = (string 13 10)
  prefix = (join '~=== Begin GP Object Data ===~' crlf)
  postfix = (join crlf '~=== End GP Object Data ===~')
  verbose = false
  t_nil = 0
  t_true = 1
  t_false = 2
  t_int = 3
  t_float = 4
  t_string = 5
  t_binary = 6
  t_array = 7
  t_ref = 255
}

// Writing

method write Serializer rootObj ignoring {
  // Serialize the given object and all objects reachable from it
  // and return the resulting BinaryData. Objects in the optional
  // parameter 'ignoring' will be omitted from the serialization.

  if (notNil ignoring) {
	objectsToIgnore = (dictionary)
	addAll objectsToIgnore ignoring
  }
  initConstants this
  stream = (dataStream (newBinaryData 100000))
  if (isImmediate this rootObj) {
	writeImmediate this rootObj
	return (contents stream)
  }
  gc
  objectTable = (table 'object' 'className' 'fields')
  objects = (dictionary)
  grow objects 10000
  classes = (dictionary)
  fieldsForClass = (dictionary)

  collectObjects this rootObj
  linkObjects this
  gc

  // Note: write prefix and postfix as raw strings to support copy/paste in text editor
  nextPutAll stream prefix
  writeNext this version
  writeClassTable this
  writeObjectTable this
  nextPutAll stream postfix

  // free up memory
  objectTable = nil
  objects = nil
  classes = nil
  gc

  return (contents stream)
}

method writeImmediate Serializer rootObj {
  nextPutAll stream prefix
  writeNext this version
  writeNext this (array) // empty class table
  writeNext this rootObj // write an immediate object instead of object table
  nextPutAll stream postfix
}

method collectObjects Serializer rootObj {
  toDo = (list rootObj)
  while (notEmpty toDo) {
    obj = (removeFirst toDo)
    if (not (contains objects obj)) { // obj is not already in the object table; add it

	  className = (className (classOf obj))
	  if (not (contains classes className)) {
		// record this class and its serializedFieldNames
		classID = ((count classes) + 1)
		atPut classes className classID
		atPut fieldsForClass className (serializedFieldNames obj)
	  }

	  if (isOneOf className 'String' 'BinaryData') {
		add objectTable obj className nil
	  } else {
		if ('Array' == className) {
		  fields = (clone obj)
		} else {
		  fields = (serialize obj)
		}
		add objectTable obj className fields

		// add any references to objects that have not been processed to the toDo list
		for i (count fields) {
		  o = (at fields i)

		  if (isClass o 'Module') {
			// don't follow references to Modules
			if (not (isOneOf o (topLevelModule) (sessionModule))) {
			  // print warning if reference is not to the top or session module
			  print 'warning: Serializer is ignoring reference to module' o 'from' obj
			}
			atPut fields i nil
			o = nil
		  }

		  if (and (notNil objectsToIgnore) (contains objectsToIgnore o)) {
			// nil out references to objects in the 'ignore' list
		    atPut fields i nil
			o = nil
		  }
		  if (and (notNil o) (not (isImmediate this o)) (not (contains objects o))) {
			add toDo o
		  }
		}
	  }
	  objID = (rowCount objectTable)
	  atPut objects obj objID
	}
  }
}

method isImmediate Serializer obj {
  // An immediate object is encoded inline; it does not have an entry in the object table.
  return (isAnyClass obj 'Integer' 'Boolean' 'Float' 'ExternalReference' 'Nil')
}

method linkObjects Serializer {
  // Replace object references in fields arrays with instances of ObjRef
  // that link to the corresponding object table entry.

  for r (rowCount objectTable) {
    fields = (cellAt objectTable r 'fields')
	if (notNil fields) { // object has a fields array
	  for i (count fields) {
		obj = (at fields i)
		objID = (at objects obj)
		if (notNil objID) {
		  atPut fields i (new 'ObjRef' objID)
		}
	  }
	}
  }
}

method writeClassTable Serializer {
  // Write the class table to my stream.

  if verbose {
	print 'Writing class table,' (count classes) 'classes:'
  }
  classTable = (list)
  for p (sortedPairs classes) {
    className = (last p)
	add classTable className
	add classTable (at fieldsForClass className)
	if verbose { print '   ' className (at fieldsForClass className) }
  }
  writeNext this (toArray classTable)
  if verbose {
    print 'Wrote class table,' (position stream) 'bytes.'
  }
}

method writeObjectTable Serializer {
  // Write the object table to my stream.

  if verbose {
	print 'Writing object table,' (rowCount objectTable) 'objects:'
  }
  table = (list)
  for r (rowCount objectTable) {
	indexableCount = nil
    obj = (cellAt objectTable r 'object')
	className = (cellAt objectTable r 'className')
	objData = (cellAt objectTable r 'fields')
	if (isNil objData) {  // binary data
	  objData = obj
	} ('Array' != className) {
	  indexableCount = ((objWords obj) - (count (fieldNames (classOf obj))))
	  if (indexableCount == 0) { indexableCount = nil }
	}
	add table (at classes className)
	add table indexableCount
	if verbose { print '  ' className }
    add table objData
  }
  startPos = (position stream)
  writeNext this (toArray table)
  if verbose {
	print 'Wrote object table,' ((position stream) - startPos) 'bytes.'
  }
}

// Reading

method version Serializer data {
  initConstants this
  stream = (dataStream data)
  readPrefix this
  return (readNext this)
}

method read Serializer data {
  // Read and reconstruct a serialized object structure from the given BinaryData.

  initConstants this
  stream = (dataStream data)
  readPrefix this
  readVersion this
  readClassTable this
  ensureClassesDefined this
  readObjectTable this
  resolveReferences this
  deserializeObjects this
  fixMethodsAndMonitors this
  readPostfix this
  return (cellAt objectTable 1 'object')
}

method readPrefix Serializer {
  s = (nextString stream (byteCount prefix))
  if (s != prefix) { error 'serialize: bad prefix' }
}

method readVersion Serializer {
  v = (readNext this)
  if (v != version) { error (join 'serialize: cannot read object data version' v) }
}

method readPostfix Serializer {
  s = (nextString stream (byteCount postfix))
  if (s != postfix) { error 'serialize: bad postfix' }
}

method readClassTable Serializer {
  // Read the class table, an array of (className, fieldList) pairs.

  classArray = (readNext this)
  classTable = (list)
  fieldsForClass = (list)
  i = 1
  if verbose { print 'Reading' ((count classArray) / 2) 'classes:' }
  repeat ((count classArray) / 2) {
	add classTable (at classArray i)
	add fieldsForClass (at classArray (i + 1))
	if verbose { print '  ' (count classTable) (at classArray i) (at classArray (i + 1)) }
    i += 2
  }
  classTable = (toArray classTable)
  fieldsForClass = (toArray fieldsForClass)
}

method ensureClassesDefined Serializer {
  // Ensure that all the classes in the class table are defined.

  existingClasses = (dictionary)
  for c (classes) { add existingClasses (className c) }

  for i (count classTable) {
    className = (at classTable i)
	if (not (contains existingClasses className)) {
	  callWith 'defineClass' (join (array className) (at fieldsForClass i))
	  clearCaches (class className)
	}
  }
}

method readObjectTable Serializer {
  // Read the object array, instantiate objects, and build the object table.

  objectTable = (table 'classIndex' 'className' 'fields' 'object')
  objArray = (readNext this)
  if (not (isClass objArray 'Array')) { // serialized object is an immediate value
	add objectTable nil nil nil objArray
	return
  }
  i = 1
  if verbose { print 'Reading' ((count objArray) / 3) 'objects' }
  repeat ((count objArray) / 3) {
	classIndex = (at objArray i)
	indexableCount = (at objArray (i + 1))
	fields = (at objArray (i + 2))
	className = (at classTable classIndex)
	if (and (isClass fields 'Array') ('Array' != className)) {
	  // instantiate objects that are neither binary objects nor Arrays
	  if (notNil indexableCount) {
		object = (newIndexable className indexableCount)
	  } else {
		object = (new className)
	  }
	} else {
	  object = fields
	}
	add objectTable classIndex className fields object
	i += 3
  }
}

method resolveReferences Serializer {
  // Replace all object references (instances of ObjRef) with
  // references to the corresponding object in the object table.

  for r (rowCount objectTable) {
    fields = (cellAt objectTable r 'fields')
	if (isClass fields 'Array') {
	  for i (count fields) {
		ref = (at fields i)
		if (isClass ref 'ObjRef') {
		  obj = (cellAt objectTable (objID ref) 'object')
		  atPut fields i obj
		}
	  }
	}
  }
}

method deserializeObjects Serializer {
  // Initialize object contents from their field dictionaries.

  empty = (array)
  for r (rowCount objectTable) {
    obj = (cellAt objectTable r 'object')
	if (and (not (isAnyClass obj 'Array' 'String' 'BinaryData')) (notNil (cellAt objectTable r 'classIndex')))  {
	  // build a field dictionary and call deserialize
	  fieldNames = (at fieldsForClass (cellAt objectTable r 'classIndex'))
	  fieldNameCount = (count fieldNames)
	  fields = (cellAt objectTable r 'fields')
	  fieldCount = (count fields)
	  d = (dictionary)
	  for i (min fieldNameCount fieldCount) {
		atPut d (at fieldNames i) (at fields i)
	  }
	  extraCount = (fieldCount - fieldNameCount)
	  if (extraCount > 0) {
		extraFields = (copyArray fields extraCount (fieldNameCount + 1))
	  } else {
	    extraFields = empty
	  }
	  deserialize obj d extraFields
	}
  }
}

// low-level serialization

method readNext Serializer {
  tag = (nextUInt8 stream)
  if (t_nil == tag) { return nil }
  if (t_int == tag) { return (nextInt stream) }
  if (t_ref == tag) { return (new 'ObjRef' (nextUInt32 stream)) }
  if (t_true == tag) { return true }
  if (t_false == tag) { return false }
  if (t_float == tag) { return (nextFloat32 stream) } // need prim for double
  if (t_array == tag) {
    count = (nextUInt32 stream)
	result = (newArray count)
	for i count {
	  atPut result i (readNext this)
	}
	return result
  } (t_string == tag) {
	count = (nextUInt32 stream)
	return (nextString stream count)
  } (t_binary == tag) {
    count = (nextUInt32 stream)
	return (nextData stream count)
  } else {
	error 'unknown tag; serialized data corrupted?'
  }
}

method writeNext Serializer obj {
  if (isNil obj) { putUInt8 stream t_nil; return }
  if (true === obj) { putUInt8 stream t_true; return }
  if (false === obj) { putUInt8 stream t_false; return }
  className = (className (classOf obj))
  if ('Integer' == className) {
    putUInt8 stream t_int
	putInt stream obj
  } ('Float' == className) {
    putUInt8 stream t_float
	putFloat32 stream obj
  } ('Array' == className) {
    putUInt8 stream t_array
	putUInt32 stream (count obj)
	for i (count obj) {
	  writeNext this (at obj i)
	}
  } ('String' == className) {
    putUInt8 stream t_string
	putUInt32 stream (byteCount obj)
	nextPutAll stream obj
  } ('ObjRef' == className) {
    putUInt8 stream t_ref
	putUInt32 stream (objID obj)
  } ('BinaryData' == className) {
    putUInt8 stream t_binary
	putUInt32 stream (byteCount obj)
	nextPutAll stream obj
  } ('ExternalReference' == className) {
	putUInt8 stream t_nil // replace ExternalReferences with nil
  } else {
    error (join 'cannot serialize ' className)
  }
}

// tests

method lowLevelTest Serializer {
  // lowLevelTest (new 'Serializer')
  testData = (array nil true false 1 0.5 'GP Rocks!' (array 1 2 3))
  initConstants this
  verbose = true
  stream = (dataStream (newBinaryData 100))

  for datum testData {
	setPosition stream 0
	writeNext this datum
	setPosition stream 0
	out = (readNext this)
	assert out datum
  }

  setPosition stream 0
  writeNext this (newBinaryData 10)
  writeNext this (new 'ObjRef' 42)
  writeNext this testData
  setPosition stream 0

  out = (readNext this)
  assert (classOf out) (class 'BinaryData')
  assert (byteCount out) 10

  out = (readNext this)
  assert (classOf out) (class 'ObjRef')
  assert (objID out) 42

  out = (readNext this)
  assert (classOf out) (class 'Array')
  assert (count out) (count testData)
}

// work-around for serialized methods

method fixMethodsAndMonitors Serializer {
  // The serializer does not yet handle functions with non-zero
  // classIndex fields (i.e. methods). The index of the desired
  // class may be different when it is deserialized, so references
  // to classes should be stored in some other form (e.g. module + class name).
  // Until then, method object should not be serialized at all but, in
  // case they are, then their class index is set to zero when deserialized
  // to avoid being associated with an unexpected (or non-existant) class.
  // Some old projects have Monitor objects with (broken) method
  // objects in them, so this method replaces the actions of those
  // Monitors with noops, allowing the project to be opened so that
  // the broken Monitors can be replaced.

  // First, fix the monitors
  for r (rowCount objectTable) {
    if ('Monitor' == (cellAt objectTable r 'className')) {
	  monitor = (cellAt objectTable r 'object')
	  if (hasMethod this (getField monitor 'getAction')) {
		setField monitor 'getAction' (action 'noop')
	  }
	}
  }

  // Then, fix the methods
  for r (rowCount objectTable) {
	if ('Function' == (cellAt objectTable r 'className')) {
	  fnc = (cellAt objectTable r 'object')
	  setField fnc 'classIndex' 0
	}
  }
}

method hasMethod Serializer action {
  if (not (isClass action 'Action')) { return false }
  fnc = (function action)
  return (and (isClass fnc 'Function') (isMethod fnc))
}

// debugging

method traceFunctionRefs Serializer {
  for r (rowCount objectTable) {
    cl = (cellAt objectTable r 'className')
	if ('Function' == cl) {
	  showTrace this r 0 (dictionary)
	}
  }
}

method showTrace Serializer objIndex indent visited {
  // For debugging. Trace the path to the given object.
  add visited objIndex
  prefix = (joinStringArray (newArray indent '  '))
  print prefix objIndex (cellAt objectTable objIndex 'className')
  for r (allRefs this objIndex) {
	if (not (contains visited r)) {
	  showTrace this r (indent + 1) visited
	}
  }
}

method allRefs Serializer objIndex {
  result = (list)
  for r (rowCount objectTable) {
    fields = (cellAt objectTable r 'fields')
	if (isClass fields 'Array') {
	  for ref fields {
		if (and (isClass ref 'ObjRef') ((objID ref) == objIndex)) {
		  add result r
		}
	  }
	}
  }
  return result
}
