// Float32Array and UInt32Array

defineClass Float32Array data

to float32Array args... {
  data = (newBinaryData (4 * (argCount)))
  for i (argCount) {
    float32AtPut data ((4 * i) - 3) (arg i)
  }
  return (new 'Float32Array' data)
}

method at Float32Array index {
  return (float32At data ((4 * (index - 1)) + 1))
}

method atPut Float32Array index value {
  float32AtPut data ((4 * (index - 1)) + 1) value
}

method count Float32Array {
  return ((byteCount data) / 4)
}

// converting

to toFloat32Array aCollection {
  data = (newBinaryData (4 * (count aCollection)))
  for i (count aCollection) {
    float32AtPut data ((4 * i) - 3) (at aCollection i)
  }
  return (new 'Float32Array' data)
}

method toArray Float32Array {
  result = (newArray (count this))
  for i (count this) { atPut result i (at this i) }
  return result
}

method toString Float32Array {
  list = (list)
  add list '('
  for i (count this) {
    add list (toString (at this i))
    if (i < (count this)) {
       add list ' '
    }
  }
  add list ')'
  return (joinStringArray (toArray list))
}

// UInt32Array

defineClass UInt32Array data

method at UInt32Array index {
  return (uint32At data ((4 * (index - 1)) + 1))
}

method atPut UInt32Array index value {
  uint32AtPut data ((4 * (index - 1)) + 1) value
}

method count UInt32Array {
  return ((byteCount data) / 4)
}

method join UInt32Array otherArray {
  if ((classOf otherArray) != (classOf this)) {error 'data class mismatch'}
  otherData = (getField otherArray 'data')
  newData = (newBinaryData ((byteCount data) + (byteCount otherData)))
  replaceByteRange newData 1 (byteCount data) data
  replaceByteRange newData ((byteCount data) + 1) (byteCount newData) otherData
  return (new (classOf this) newData)
}

method fillArray UInt32Array val startIndex endIndex {
  if (isNil startIndex) {startIndex = 1}
  if (isNil endIndex) {endIndex = ((byteCount data) / 4)}
  for i ((endIndex - startIndex) + 1) {
    atPut this ((i + startIndex) - 1) val
  }
}

// converting

to toUInt32Array aCollection {
  data = (newBinaryData (4 * (count aCollection)))
  for i (count aCollection) {
    uint32AtPut data ((4 * i) - 3) (at aCollection i)
  }
  return (new 'UInt32Array' data)
}

method toArray UInt32Array {
  result = (newArray (count this))
  for i (count this) { atPut result i (at this i) }
  return result
}

method toString UInt32Array {
  list = (list)
  add list '('
  for i (count this) {
    add list (toString (at this i))
    if (i < (count this)) {
       add list ' '
    }
  }
  add list ')'
  return (joinStringArray (toArray list))
}
