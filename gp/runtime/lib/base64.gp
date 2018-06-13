to base64Encode data {
  digits = (letters 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
  newline = (newline)
  result = (list)
  last = ((byteCount data) - 2)
  i = 1
  while (i <= last) {
	n = (+ ((byteAt data i) << 16) ((byteAt data (i + 1)) << 8) (byteAt data (i + 2)))
	add result (at digits (((n >> 18) & 63) + 1))
	add result (at digits (((n >> 12) & 63) + 1))
	add result (at digits (((n >> 6) & 63) + 1))
	add result (at digits ((n & 63) + 1))
	i += 3
	if (((i - 1) % 60) == 0) { add result newline }
  }
  extra = ((byteCount data) % 3)
  if (2 == extra) {
	n = (+ ((byteAt data i) << 16) ((byteAt data (i + 1)) << 8))
	add result (at digits (((n >> 18) & 63) + 1))
	add result (at digits (((n >> 12) & 63) + 1))
	add result (at digits (((n >> 6) & 63) + 1))
	add result '='
  } (1 == extra) {
	n = ((byteAt data i) << 16)
	add result (at digits (((n >> 18) & 63) + 1))
	add result (at digits (((n >> 12) & 63) + 1))
	add result '=='
  }
  return (joinStrings result)
}

to base64Decode aString {
  stream = (dataStream (newBinaryData (byteCount aString)))
  buf = 0
  bufCount = 0
  for ch (letters aString) {
	if (and ('A' <= ch) (ch <= 'Z')) {
	  sixBits = ((byteAt ch 1) - 65)
	} (and ('a' <= ch) (ch <= 'z')) {
	  sixBits = (((byteAt ch 1) - 97) + 26)
	} (and ('0' <= ch) (ch <= '9')) {
	  sixBits = (((byteAt ch 1) - 48) + 52)
	} ('+' == ch) {
	  sixBits = 62
	} ('/' == ch) {
	  sixBits = 63
	} else {
	  sixBits = nil
	}
	if (notNil sixBits) {
	  buf = ((buf << 6) + sixBits)
	  bufCount += 1
	}
	if (bufCount == 4) {
	  putUInt8 stream ((buf >> 16) & 255)
	  putUInt8 stream ((buf >> 8) & 255)
	  putUInt8 stream (buf & 255)
	  buf = 0
	  bufCount = 0
	}
  }
  if (bufCount > 0) { // write partial buffer (bufCount = 2 or 3)
	buf = (buf << ((4 - bufCount) * 6)) // zero-pad on right
	putUInt8 stream ((buf >> 16) & 255)
	if (bufCount > 2) { putUInt8 stream ((buf >> 8) & 255) }
  }
  return (contents stream)
}
