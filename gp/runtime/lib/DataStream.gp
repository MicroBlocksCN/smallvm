// DataStream - streaming interface to binary data

defineClass DataStream data position bigEndian

method data DataStream { return data }
method position DataStream { return position }
method remaining DataStream { return ((byteCount data) - position) }
method setPosition DataStream n { position = (clamp n 0 (byteCount data)) }
method bigEndian DataStream { return bigEndian }

to dataStream data bigEndian {
  if (isNil bigEndian) { bigEndian = false }
  return (new 'DataStream' data 0 bigEndian)
}

method atEnd DataStream {
  return (position >= (byteCount data))
}

method skip DataStream n {
  position += n
  if (position < 0) { position = 0 }
}

method nextInt8 DataStream {
  result = (nextUInt16 this)
  if (result > 127) { result += -256 }
  return result
}

method nextUInt8 DataStream {
  position += 1
  result = (byteAt data position)
  return result
}

method nextInt16 DataStream {
  result = (nextUInt16 this)
  if (result > 32767) { result += -65536 }
  return result
}

method nextUInt16 DataStream {
  if bigEndian {
   b1 = (byteAt data (position + 1))
   b2 = (byteAt data (position + 2))
  } else {
   b2 = (byteAt data (position + 1))
   b1 = (byteAt data (position + 2))
  }
  position += 2
  return ((b1 << 8) | b2)
}

method nextInt DataStream {
  // Assumes value fits into a 31-bit GP Integer object. See nextUInt32.
  result = (intAt data (position + 1) bigEndian)
  position += 4
  return result
}

method nextUInt32 DataStream {
  // Returns a LargeInteger if result does not fit into a GP Integer.
  result = (uint32At data (position + 1) bigEndian)
  position += 4
  return result
}

method nextFloat32 DataStream {
  result = (float32At data (position + 1) bigEndian)
  position += 4
  return result
}

method nextData DataStream byteCount {
  result = (newBinaryData byteCount)
  replaceByteRange result 1 byteCount data (position + 1)
  position += byteCount
  return result
}

method nextString DataStream byteCount {
  return (toString (nextData this byteCount))
}

method nextNullTerminatedString DataStream { return (nextStringUpTo this 0) }

method nextStringUpTo DataStream terminator {
  // Return a string consisting of the bytes up to the given terminator byte
  // or stream end. The terminator is consumed, but not included in the result.

  bytes = (list)
  while (not (atEnd this)) {
	ch = (nextUInt8 this)
	if (ch == terminator) {
	  return (toString (toBinaryData (toArray bytes)))
	}
	add bytes ch
  }
  return (toString (toBinaryData (toArray bytes)))
}

method putInt DataStream value {
  if ((position + 4) > (byteCount data)) { grow this }
  intAtPut data (position + 1) value bigEndian
  position += 4
}

method putUInt8 DataStream value {
  if ((position + 1) > (byteCount data)) { grow this }
  position += 1
  byteAtPut data position value
}

method putUInt16 DataStream value {
  if ((position + 2) > (byteCount data)) { grow this }
  if bigEndian {
	byteAtPut data (position + 1) ((value >> 8) & 255)
	byteAtPut data (position + 2) (value & 255)
  } else {
	byteAtPut data (position + 1) (value & 255)
	byteAtPut data (position + 2) ((value >> 8) & 255)
  }
  position += 2
}

method putUInt32 DataStream value {
  if ((position + 4) > (byteCount data)) { grow this }
  uint32AtPut data (position + 1) value bigEndian
  position += 4
}

method putFloat32 DataStream value {
  if ((position + 4) > (byteCount data)) { grow this }
  float32AtPut data (position + 1) value bigEndian
  position += 4
}

method nextPutAll DataStream stringOrData from to {
  if (isNil from) { from = 1 }
  if (isNil to) { to = (byteCount stringOrData) }
  newPos = (position + ((to - from) + 1))
  if (newPos > (byteCount data)) { grow this newPos }
  replaceByteRange data (position + 1) newPos stringOrData from
  position = newPos
}

method grow DataStream delta {
  if (isNil delta) { delta = (max 8 (byteCount data)) }
  newSize = ((byteCount data) + delta)
  newData = (newBinaryData newSize)
  replaceByteRange newData 1 (byteCount data) data
  data = newData
}

method contents DataStream {
  result = (newBinaryData position)
  replaceByteRange result 1 position data
  return result
}

method stringContents DataStream {
  return (stringFromByteRange data 1 position)
}
