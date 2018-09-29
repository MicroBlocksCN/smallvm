// Float

method toInteger Float { return (truncate this) }
method toNumber Float { return this }

method floor Float {
  result = (integerPart this)
  if (and (this < 0) ((this - result) < 0)) {
	if (result == -1073741824) { result = (toFloat result) }
    result += -1
  }
  return result
}

method ceiling Float {
  result = (integerPart this)
  if (and (this > 0) ((this - result) > 0)) {
	if (result == 1073741823) { result = (toFloat result) }
    result += 1
  }
  return result
}

method integerPart Float {
  result = (this - (this % 1))
  if (and (-1073741824.0 <= result) (result <= 1073741823.0)) {
	result = (truncate result) // result fits in Integer
  }
  return result
}

method fractionPart Float { return (this % 1) }

method round Float precision {
  // Return the nearest muliple of precision or
  // the nearest integer if precision is nil.

  if (isNil precision) {
	if (this > 0) {
	  return (integerPart (this + 0.5))
	} else {
	  return (integerPart (this - 0.5))
	}
  } else {
	return (precision * (round (this / precision)))
  }
}
