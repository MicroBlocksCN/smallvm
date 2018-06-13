defineClass Serializer2 verbose stream root classIDs classes clusters modules moduleCode moduleIDs topHash objects objFields objectsToIgnore classTable fieldsForClass prefix postfix version t_nil t_ref t_true t_false t_int t_float t_string t_binary t_array ObjRef Array BinaryData Boolean ExternalReference Float Integer Module Nil String

// Constants

method initConstants Serializer2 {
  version = 2
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

  ObjRef = (class 'ObjRef')
  Array = (class 'Array')
  Boolean = (class 'Boolean')
  BinaryData = (class 'BinaryData')
  ExternalReference = (class 'ExternalReference')
  Float = (class 'Float')
  Integer = (class 'Integer')
  Module = (class 'Module')
  Nil = (class 'Nil')
  String = (class 'String')
}

// Writing

method write Serializer2 rootObj ignoring {
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
    return (array (contents stream) (array))
  }

  gc

  root = rootObj
  clusters = (dictionary)       // {class -> {object -> fields}}
  objects = (dictionary)        // {object -> objectID}
  classIDs = (dictionary)       // {class -> classID}
  classes = (list)              // [class]
  fieldsForClass = (dictionary) // {class -> fields}
  modules = (dictionary)        // {module-instance -> module-code-static-hash}
  moduleCode = (dictionary)     // {module-code-static-hash -> serialized code}
  moduleIDs = (dictionary)      // {module-instance -> moduleID}

  topHash = (codeHash (topLevelModule))

  grow objects 10000

  collectObjects this rootObj
  assignIDs this
  linkObjects this
  gc

  // Note: write prefix and postfix as raw strings to support copy/paste in some text editor
  nextPutAll stream prefix
  writeNext this version
  writeModuleTable this
  writeClassTable this
  writeObjects this
  writeNext this (at objects rootObj)
  nextPutAll stream postfix

  // temporary store a value into a temp
  code = moduleCode

  // free up memory
  classIDs = nil
  classes = nil
  clusters = nil
  modules = nil
  moduleIDs = nil
  moduleCode = nil
  objects = nil
  objFields = nil
  objectsToIgnore = nil
  classTable = nil
  fieldsForClass = nil
  gc

  return (array (contents stream) code topHash)
}

method writeImmediate Serializer2 rootObj {
  nextPutAll stream prefix
  writeNext this version
  writeNext this (array) // empty module table
  writeNext this (array) // empty class table
  writeNext this 1 // object count
  writeNext this rootObj // write an immediate object instead of object table
  nextPutAll stream postfix
}

method collectObjects Serializer2 rootObj {
  modID = 0
  toDo = (list rootObj)
  while (notEmpty toDo) {
    obj = (removeFirst toDo)
    if (not (contains objects obj)) { // obj is not already in the object table; add it
      class = (classOf obj)
      module = (module class)
      if (not (contains clusters class)) {
        atPut clusters class (dictionary)
        atPut fieldsForClass class (serializedFieldNames obj)
        atPut classIDs class ((count classIDs) + 1)
        add classes class
      }
      if (not (contains modules module)) {
        if (not (module === (topLevelModule))) {
          code = (code module)
          hash = (sha256 code)
          atPut modules module hash
          atPut moduleCode hash code
          modID = (modID + 1)
          atPut moduleIDs module modID
          add toDo module
        }
      }
      if (isAnyClass obj 'String' 'BinaryData') {
        // non-pointers
        atPut (at clusters class) obj nil
      } else {
        if (Array === class) {
          // indexable
          fields = (clone obj)
        } else {
          // Assume: (serialize obj) returns a reference to a temporary object, not a
          // subpart of obj, since the returned object is mutated by the serializer
          fields = (serialize obj)
        }
        atPut (at clusters class) obj fields

        // add any references to objects that have not been processed to the toDo list
        for i (count fields) {
          o = (at fields i)
          if ((classOf o) === Module) {
            if (not (contains modules o)) {
              if (o === (topLevelModule)) {
                atPut modules o topHash
                o = nil
              } else {
                code = (code o)
                hash = (sha256 code)
                atPut modules o hash
                atPut moduleCode hash code
                modID = (modID + 1)
                atPut moduleIDs o modID
              }
            }
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
      atPut objects obj 0
    }
  }
}

method isImmediate Serializer2 obj {
  // An immediate object is encoded inline; it does not have an entry in the object table.
  return (isAnyClass obj 'Integer' 'Boolean' 'Float' 'ExternalReference' 'Nil')
}

method assignIDs Serializer2 {
  objID = 0
  for c classes {
    cluster = (at clusters c)
    objs = (keys cluster)
    for obj objs {
      objID = (objID + 1)
      atPut objects obj objID
    }
  }
}

method linkObjects Serializer2 {
  // Replace object references in fields arrays with instances of ObjRef
  // that link to the corresponding object table entry.

  for c classes {
    cluster = (at clusters c)
    objs = (keys cluster)
    for r (count objs) {
      fields = (at cluster (at objs r))
      if (notNil fields) { // object has a fields array
        for i (count fields) {
          obj = (at fields i)
          objID = (at objects obj)
          if (notNil objID) {
            atPut fields i (new ObjRef objID)
          }
        }
      }
    }
  }
}

method writeModuleTable Serializer2 {
  mods = (newArray (count moduleIDs)) // [module-static-hash] indexed by id
  for m (keys moduleIDs) {
    id = (at moduleIDs m)
    atPut mods id (at modules m)
  }
  writeNext this mods
}

method writeClassTable Serializer2 {
  // Write the class table to my stream.

  classTable = (newArray ((count clusters) * 3)) // [id, className, fields]
  for cls classes {
    id = (at classIDs cls)
    atPut classTable (((id - 1) * 3) + 1) (at moduleIDs (module cls))
    atPut classTable (((id - 1) * 3) + 2) (className cls)
    atPut classTable (((id - 1) * 3) + 3) (at fieldsForClass cls)
  }

  writeNext this classTable
}

method writeModules Serializer2 {
  classID = (at classIDs Module)
  cluster = (at clusters Module)

  objs = (keys cluster)
  table = (list)
  add table classID
  add table (count objs)
  add table false
  for obj objs {
    objData = (at cluster obj)
    add table (at moduleIDs obj)
    add table objData
  }
  writeNext this (toArray table)
}

method writeObjects Serializer2 {
  // Write the object table to my stream.

  writeNext this (count objects)
  for c classes {
    if (c === Module) {
      writeModules this
    } else {
      classID = (at classIDs c)
      cluster = (at clusters c)
      isIndexable = (or (c === Array) (c ===  BinaryData) (c === String))
      fieldCount = (count (fieldNames c))
      objs = (keys cluster)
      table = (list)
      add table classID
      add table (count objs)
      add table isIndexable
      for obj objs {
        objData = (at cluster obj)
        if (isNil objData) {  // non-pointer
          objData = obj
        }
        if isIndexable {
          indexableCount = ((objWords obj) - fieldCount)
          add table indexableCount
          add table objData
        } else {
          add table objData
        }
      }
      writeNext this (toArray table)
    }
  }
}

// Reading

method version Serializer2 data {
  initConstants this
  stream = (dataStream data)
  readPrefix this
  return (readNext this)
}

method read Serializer2 data mods {
  // Read and reconstruct a serialized object structure from the given BinaryData.

  initConstants this
  stream = (dataStream data)
  if (notNil mods) {
    moduleCode = mods
  }
  readPrefix this
  readVersion this
  readModuleTable this
  readClassTable this

  if ((count clusters) === 0) {
    v = (readNext this)
    readPostfix this
    return v
  }

  readObjects this
  resolveReferences this
  deserializeObjects this
  rootObj = (readNext this)
  readPostfix this

  return (at objects rootObj)
}

method readPrefix Serializer2 {
  s = (nextString stream (byteCount prefix))
  if (s != prefix) { error 'serialize: bad prefix' }
}

method readVersion Serializer2 {
  v = (readNext this)
  if (v != version) { error (join 'serialize: cannot read object data version' v) }
}

method readPostfix Serializer2 {
  s = (nextString stream (byteCount postfix))
  if (s != postfix) { error 'serialize: bad postfix' }
}

method readModuleTable Serializer2 {
  modulesArray = (readNext this) // [module-static-hash] indexed by id; may have duplicates for multiple instances
  modules = (dictionary)         // {module index -> module instance}
  for i (count modulesArray) {
    m = (loadModuleFromString (initialize (new 'Module')) (at moduleCode (at modulesArray i)))
    atPut modules i m
  }
}

method readClassTable Serializer2 {
  classData = (readNext this)
  clusters = (dictionary)
  fieldsForClass = (dictionary)
  classIDs = (newArray ((count classData) / 3))

  for i ((count classData) / 3) {
    mod = (at modules (at classData ((3 * (i - 1)) + 1)))
    name = (at classData ((3 * (i - 1)) + 2))
    fieldNames = (at classData ((3 * (i - 1)) + 3))
    if (isNil mod) {
      mod = (topLevelModule)
      cls = (class name)
    } else {
      cls = (classNamed mod name)
    }
    if (notNil cls) {
      atPut clusters cls (list)
      atPut fieldsForClass cls fieldNames
      atPut classIDs i cls
    } else {
      error (join 'Missing class ' name ' ' mod ' in Serializer2 readClassTable: corrupted file?')
    }
  }
}

method readObjects Serializer2 {
  totalCount = (readNext this)
  objects = (newArray totalCount)

  objFields = (newArray totalCount)
  ind = 0
  while (totalCount > 0) {
    i = 0
    table = (readNext this)
    i = (i + 1)
    classIndex = (at table i)
    i = (i + 1)
    count = (at table i)
    i = (i + 1)
    isIndexable = (at table i)
    cluster = (newArray count)
    cls = (at classIDs classIndex)
    atPut clusters cls cluster
    totalCount = (totalCount - count)
    if isIndexable {
      for c count {
        i = (i + 1)
        indexableCount = (at table i)
        i = (i + 1)
        objData = (at table i)
        ind = (ind + 1)
        if (cls === Array) {
          inst = objData
          atPut objects ind inst
          atPut objFields  ind inst
          atPut cluster c ind
        } (or (cls === String) (cls === BinaryData)) {
          atPut objects ind objData
          atPut objFields  ind nil
          atPut cluster c ind
        }
      }
    } (cls === Module) {
      for c count {
        i = (i + 1)
        id = (at table i)
        inst = (at modules id)
        i = (i + 1)
        objData = (at table i)
        ind = (ind + 1)
        atPut objects ind inst
        atPut objFields ind objData
        atPut cluster c ind
      }
    } (isOneOf (className cls) 'Command' 'Reporter') {
	  // Workaround because current format doesn't include the number of indexable fields
	  fixedFieldCount = 2
	  if ('Reporter' == (className cls)) { fixedFieldCount = 1 }
      for c count {
        i = (i + 1)
        objData = (at table i)
        ind = (ind + 1)
        atPut objects ind (newIndexable cls ((count objData) - fixedFieldCount))
        atPut objFields ind objData
        atPut cluster c ind
      }
    } else {
      for c count {
        i = (i + 1)
        objData = (at table i)
        ind = (ind + 1)
        atPut objects ind (new cls)
        atPut objFields ind objData
        atPut cluster c ind
      }
    }
  }
}

method resolveReferences Serializer2 {
  // Replace all object references (instances of ObjRef) with
  // references to the corresponding object in the object table.

  keys = (keys clusters)
  for cls keys {
    cluster = (at clusters cls)
    for ind cluster {
      objData = (at objFields ind)
      if (isClass objData Array) {
        for i (count objData) {
          ref = (at objData i)
          if ((classOf ref) === ObjRef) {
            obj = (at objects (objID ref))
            atPut objData i obj
          }
        }
      }
    }
  }
}

method deserializeObjects Serializer2 {
  // Initialize object contents from their field dictionaries.

  empty = (array)

  for c (count classIDs) {
    cls = (at classIDs c)
    fieldNames = (at fieldsForClass cls)
    fieldNameCount = (count fieldNames)
    cluster = (at clusters cls)
    for ind cluster {
      if (not (cls === Array)) {
        obj = (at objects ind)
        fields = (at objFields ind)
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
}

// low-level serialization

method readNext Serializer2 {
  tag = (nextUInt8 stream)
  if (t_nil == tag) { return nil }
  if (t_int == tag) { return (nextInt stream) }
  if (t_ref == tag) { return (new ObjRef (nextUInt32 stream)) }
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

method writeNext Serializer2 obj {
  if (isNil obj) {
    putUInt8 stream t_nil
    return
  }
  if (true === obj) {
    putUInt8 stream t_true
    return
  }
  if (false === obj) {
    putUInt8 stream t_false
    return
  }
  class = (classOf obj)
  if (Integer === class) {
    putUInt8 stream t_int
    putInt stream obj
  } (Float === class) {
    putUInt8 stream t_float
    putFloat32 stream obj
  } (Array === class) {
    putUInt8 stream t_array
    putUInt32 stream (count obj)
    for i (count obj) {
      writeNext this (at obj i)
    }
  } (String === class) {
    putUInt8 stream t_string
    putUInt32 stream (byteCount obj)
    nextPutAll stream obj
  } (ObjRef === class) {
    putUInt8 stream t_ref
    putUInt32 stream (objID obj)
  } (BinaryData === class) {
    putUInt8 stream t_binary
    putUInt32 stream (byteCount obj)
    nextPutAll stream obj
  } (ExternalReference === class) {
    putUInt8 stream t_nil // replace ExternalReferences with nil
  } else {
    error (join 'cannot serialize ' className)
  }
}
