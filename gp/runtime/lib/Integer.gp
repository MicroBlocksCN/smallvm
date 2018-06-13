// Integer

// truncation and rounding

method floor Integer { return this }
method ceiling Integer { return this }
method integerPart Integer { return this }
method fractionPart Integer { return 0 }

method round Integer precision {
  // Return the nearest muliple of precision or this integer if precision is nil.

  if (isNil precision) { return this }
  return (integerPart (round (toFloat this) precision))
}

// conversion

method toInteger Integer { return this }
method toNumber Integer { return this }

method toStringDisabled Integer {
  comment '
	Convert an integer to a string. This is disabled since the toString primitive
	handles that and, when printing large arrays of numbers, performance can matter.
	But it''s good to have a GP version of this code. When we have a Squeak-like primitive
	mechanism that falls through to the GP code we can reinstate this method, prefixed by
	a call to the primitive.'

  if (this == 0) {
    return '0'
  }
  if (this < 0) {
    return (join '-' (abs this))
  }
  result = (list)
  v = this
  while (v > 0) {
    r = (v % 10)
    addFirst result (at (array '0' '1' '2' '3' '4' '5' '6' '7' '8' '9') (r + 1))
    v = (truncate (v / 10))
  }
  return (joinStringArray (toArray result))
}

method toStringBase16 Integer {
  comment '
	Convert an integer to a hexadecimal string.'

  if (this == 0) { return '0' }
  if (this < 0) { return (join '-' (toStringBase16 (abs this))) }
  hexDigits = (array '0' '1' '2' '3' '4' '5' '6' '7' '8' '9' 'A' 'B' 'C' 'D' 'E' 'F')
  result = (list)
  n = this
  while (n > 0) {
    addFirst result (at hexDigits ((n % 16) + 1))
    n = (truncate (n / 16))
  }
  return (joinStringArray (toArray result))
}

method toStringBase2 Integer {
  comment '
	Convert this integer to a binary string.'

  result = (list)
  n = this
  if (n == 0) { return '0' }
  negative = (n < 0)
  if negative { n = (0 - n) }
  while (n > 0) {
	if ((n & 1) == 1) {
	  addFirst result '1'
	} else {
	  addFirst result '0'
	}
	n = (n >> 1)
  }
  if negative { addFirst result '-' }
  return (joinStringArray (toArray result))
}

// divisors

method gcd Integer num {
  x = (abs this)
  y = (abs num)
  if (y > x) {
    temp = x
    x = y
    y = temp
  }
  while true {
    x = (% x y)
    if (x == 0) { return y }
    y = (% y x)
    if (y == 0) { return x }
  }
}

method lcm Integer num {
  return ((this * num) / (gcd this num))
}

method primeFactors Integer {
  n = (abs this)
  if (n < 2) { return (list n) }
  last = (toInteger (sqrt n))
  result = (list)
  factor = 2
  while (factor <= last) {
	while (0 == (n % factor)) {
	  add result factor
	  n = (n / factor)
	}
	factor += 1
  }
  if (n != 1) { add result n }
  return result
}

method isPowerOfTwo Integer {
  if (this < 1) { return false }
  return (0 == (this & (this - 1)))
}

// prime numbers

method isPrime Integer {
  n = this
  if (n < 2) { return false }
  if (n == 2) { return true }
  if ((n % 2) == 0) { return false }
  i = 3
  while ((i * i) <= n) {
    if ((n % i) == 0) { return false }
    i += 2
  }
  return true
}

method primeAfter Integer {
  n = this
  while (not (isPrime n)) { n += 1 }
  return n
}

// bit operations

method highBit Integer {
  shifted = this
  bitNo = 0
  while (shifted >= 65536) {
    shifted = (shifted >> 16)
    bitNo = (bitNo + 16)
  }
  if (shifted >= 256) {
    shifted = (shifted >> 8)
    bitNo = (bitNo + 8)
  }
  return (bitNo + (highBitOfByte shifted))
}

method highBitOfByte Integer {
  //highBitOfByteArray = (array 0 1 2 2 3 3 3 3 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8)
  if (this == 0) {
    return 0
  } (this < 2) {
    return 1
  } (this < 4) {
    return 2
  } (this < 8) {
    return 3
  } (this < 16) {
    return 4
  } (this < 32) {
    return 5
  } (this < 64) {
    return 6
  } (this < 128) {
    return 7
  } else {
    return 8
  }
}

method digitLength Integer {
  if (and (this < 256) (this > -256)) {return 1}
  if (and (this < 65536) (this > -65536)) {return 2}
  if (and (this < 16777216) (this > -16777216)) {return 3}
  return 4
}

method digitAt Integer index {
  // Compatibility with LargeInteger.  Significant bytes are at higher indices
  if (index > 4) {return 0}
  if (this < 0) {
    if (this == -1073741824) {
      // Can't negate minVal -- treat specially
      return (at (array 0 0 0 64) index)
    }
    v = (0 - this)
  } else {
    v = this
  }
  return ((v >> ((index - 1) * 8)) & 255)
}
