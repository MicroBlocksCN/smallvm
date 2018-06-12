// BinaryData

// equality

method '==' BinaryData other {
  if (this === other) {
	return true
  } (not (isClass other 'BinaryData')) {
    return false
  } ((byteCount this) != (byteCount other)) {
    return false
  }
  for i (byteCount this) {
    if ((byteAt this i) != (byteAt other i)) {
      return false
    }
  }
  return true
}

// copying

method copyFromTo BinaryData startIndex endIndex {
  if (isNil startIndex) { startIndex = 1 }
  if (isNil endIndex) { endIndex = (byteCount this) }
  byteCount = ((endIndex - startIndex) + 1)
  if (byteCount <= 0) { return (newBinaryData 0) }
  result = (newBinaryData byteCount)
  replaceByteRange result 1 byteCount this startIndex
  return result
}

method join BinaryData other {
  // Return the concatenation of this BinaryData and the argument.

  result = (newBinaryData ((byteCount this) + (byteCount other)))
  replaceByteRange result 1 (byteCount this) this
  replaceByteRange result ((byteCount this) + 1) (byteCount result) other
  return result
}

// converting

method toArray BinaryData {
  result = (newArray (byteCount this))
  for i (byteCount this) { atPut result i (byteAt this i) }
  return result
}

method toString BinaryData {
  return (stringFromByteRange this 1 (byteCount this))
}

method printString BinaryData {
  return (join 'BinaryData' '(' (byteCount this) ' bytes)')
}

// zlib

method zlibEncode BinaryData {
  adler32 = (crc this true)
  compressed = (deflate this)
  result = (newBinaryData ((byteCount compressed) + 6))
  strm = (dataStream result true)
  putUInt8 strm 120
  putUInt8 strm 156 // indicates default compression
  nextPutAll strm compressed
  putUInt32 strm adler32
  return result
}

method zlibDecode BinaryData {
  strm = (dataStream this true)
  header1 = (nextUInt8 strm)
  ignore header1
  header2 = (nextUInt8 strm)
  if ((header2 & 32) > 0) {
	error 'zlib with a preset dictionary is not supported'
  }
  compressed = (nextData strm ((byteCount this) - 6))
  result = (inflate compressed)
  adler32 = (nextUInt32 strm)
  if (adler32 != (crc result true)) {
	error 'bad adler32 checksum in zlib data'
  }
  return result
}
