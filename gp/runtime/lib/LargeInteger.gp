defineClass LargeInteger data negative

method '==' LargeInteger other {
  if (this === other) { return true }
  if (isClass other 'LargeInteger') {
    oData = (getField other 'data')
    if ((negative == true) != ((getField other 'negative') == true)) {return false}
    if ((byteCount data) != (byteCount oData)) {return false}
    for i (byteCount data) {
      if ((byteAt data i) != (byteAt oData i)) {return false}
    }
    return true
  }
  return (other == this)
}

method '<<' LargeInteger amount {
  if (amount < 0) {return (this >> (0 - amount))}
  count = (byteCount data)
  bitOffset = (amount % 8)
  if (((byteAt data 1) << bitOffset) >= 256) {
    extra = 1
  } else {
    extra = 0
  }
  byteOffset = ((truncate (amount / 8)) + extra)
  newCount = (count + byteOffset)
  new = (newBinaryData newCount)

  carry = 0
  for i count {
    j = (count - (i - 1))
    byte = (byteAt data j)
    shifted = (byte << bitOffset)
    byteAtPut new (j + extra) ((shifted & 255) + carry)
    carry = ((shifted >> 8) & 255)
  }
  if (extra == 1) {byteAtPut new 1 carry}
  return (normalize (new 'LargeInteger' new))
}

method '>>>' LargeInteger amount { return (this >> amount) }

method '>>' LargeInteger amount {
  if (amount < 0) {return (this << (0 - amount))}
  count = (byteCount data)
  bitOffset = (amount % 8)
  if (((byteAt data 1) >> bitOffset) == 0) {
    extra = 1
  } else {
    extra = 0
  }
  byteOffset = ((truncate (amount / 8)) + extra)
  newCount = (- count byteOffset)
  new = (newBinaryData newCount)

  if (extra == 1) {
    byte = (byteAt data 1)
    carry = ((byte & ((1 << bitOffset) - 1)) << (8 - bitOffset))
  } else {
    carry = 0
  }
  for i newCount {
    byte = (byteAt data (i + extra))
    shifted = (byte >> bitOffset)
    byteAtPut new i (carry + shifted)
    carry = ((byte & ((1 << bitOffset) - 1)) << (8 - bitOffset))
  }
  return (normalize (new 'LargeInteger' new))
}

method '|' LargeInteger ... {
  max = (byteCount data)
  for i (argCount) {
    bc = (digitLength (arg i))
    if (max < bc) {max = bc}
  }
  new = (newBinaryData max)
  replaceByteRange new ((max - (byteCount data)) + 1) (byteCount new) data 1
  for i ((argCount) - 1) {
    other = (arg (i + 1))
    if ((classOf other) == (classOf 1)) {
      oData = (getField (toLargeInteger other) 'data')
    } else {
      oData = (getField other 'data')
    }
    for j (byteCount oData) {
      oInd = ((byteCount oData) - (j - 1))
      ind = (max - (j - 1))
      byteAtPut new ind ((byteAt new ind) | (byteAt oData oInd))
    }
  }
  return (normalize (new 'LargeInteger' new))
}

method '&' LargeInteger ... {
  max = (byteCount data)
  for i (argCount) {
    bc = (digitLength (arg i))
    if (max < bc) {max = bc}
  }
  new = (newBinaryData max)
  replaceByteRange new ((max - (byteCount data)) + 1) (byteCount new) data 1
  for i ((argCount) - 1) {
    other = (arg (i + 1))
    if ((classOf other) == (classOf 1)) {
      oData = (getField (toLargeInteger other) 'data')
    } else {
      oData = (getField other 'data')
    }
    diff = (max - (byteCount oData))
    for j diff {
      byteAtPut new j 0
    }
    for j (byteCount oData) {
      oInd = ((byteCount oData) - (j - 1))
      ind = (max - (j - 1))
      byteAtPut new ind ((byteAt new ind) & (byteAt oData oInd))
    }
  }
  return (normalize (new 'LargeInteger' new))
}

method '^' LargeInteger other {
  // bit xor. placeholder for crc 32
  new = (newBinaryData 4)
  for i 4 {
    byteAtPut new (5 - i) (((digitAt this i) ^ (digitAt other i)) & 255)
  }
  return (normalize (new 'LargeInteger' new))
}

method normalize LargeInteger {
  i = 1
  count = (byteCount data)
  while (and (i <= count) ((byteAt data i) == 0)) {
    i += 1
  }
  digits = (count - (i - 1))
  if (or (digits <= 3) (and (digits == 4) ((byteAt data 1) < 64))) {
    val = 0
    for j count {
      val = (val << 8)
      val += (byteAt data j)
    }
    return val
  }
  if (i == 1) {return this}
  new = (newBinaryData (count - (i - 1)))
  replaceByteRange new 1 (byteCount new) data i
  data = new
  return this
}

method digitLength LargeInteger {
  return (byteCount data)
}

method digitAt LargeInteger i {
  // significant bytes are at the higher indices
  c = (byteCount data)
  if (i > c) { return 0 }
  return (byteAt data ((c - i) + 1))
}

method toString LargeInteger {
  return (join '<LargeInteger 0x' (toStringBase16 this) '>')
}

method toStringBase16 LargeInteger {
  if ((byteCount data) == 0) {return '0'}
  digits = (array '0' '1' '2' '3' '4' '5' '6' '7' '8' '9' 'A' 'B' 'C' 'D' 'E' 'F')
  result = (newArray ((byteCount data) * 2))
  for i (byteCount data) {
    byte = (byteAt data i)
    atPut result ((i * 2) - 1) (at digits ((truncate (byte / 16)) + 1))
    atPut result (i * 2)       (at digits ((byte % 16) + 1))
  }
  return (joinStringArray result)
}

to largeInteger ... {
  data = (newBinaryData (argCount))
  for i (argCount) {
    byteAtPut data i (arg i)
  }
  return (new 'LargeInteger' data)
}

to toLargeInteger anInteger {
  if ((classOf anInteger) == (class 'LargeInteger')) {return anInteger}
  count = (digitLength anInteger)
  data = (newBinaryData count)
  for i count {
    j = (count - (i - 1))
    byteAtPut data j (anInteger % 256)
    anInteger = (truncate (anInteger / 256))
  }
  return (new 'LargeInteger' data)
}
