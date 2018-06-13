// Concatenating

method join String args... {
  // Return a string that joins the string representations of all arguments.

  strings = (list)
  for i (argCount) { add strings (toString (arg i)) }
  return (joinStringArray (toArray strings))
}

// Testing

method beginsWith String prefix {
  n = (byteCount prefix)
  if (n > (byteCount this)) { return false }
  for i n {
    b1 = (byteAt this i)
    b2 = (byteAt prefix i)
    if (b1 != b2) { return false }
  }
  return true
}

method endsWith String postfix {
  i = (((byteCount this) - (byteCount postfix)) + 1)
  if (i < 1) { return false }
  j = 1
  repeat (byteCount postfix) {
    b1 = (byteAt this i)
    b2 = (byteAt postfix j)
    if (b1 != b2) { return false }
	i += 1
	j += 1
  }
  return true
}

method isLetter String {
  // Just for now, afterwards, it'd have to look at the Unicode attributes
  return (or (and ('A' <= this) (this <= 'Z'))
             (and ('a' <= this) (this <= 'z')))
}

method isUpperCase String {
  // Just for now, afterwards, it'd have to look at the Unicode attributes
  return (and ('A' <= this) (this <= 'Z'))
}

method isLowerCase String {
  // Just for now, afterwards, it'd have to look at the Unicode attributes
  return (and ('a' <= this) (this <= 'z'))
}

method isDigit String {
  // Just for now, afterwards, it'd have to look at the Unicode attributes
  return (and ('0' <= this) (this <= '9'))
}

method isSymbol String {
  // Return true if this character is an ASCII symbol
  return (or (and ('!' <= this) (this <= '/'))
             (and (':' <= this) (this <= '@'))
             (and ('[' <= this) (this <= '`'))
             (and ('{' <= this) (this <= '~')))
}

method isWhiteSpace String {
  // Just for now, afterwards, it'd have to look at the Unicode attributes
  return (this <= ' ')
}

method containsWhitespace String {
  space = 32
  for i (byteCount this) {
	if ((byteAt this i) <= space) { return true }
  }
  return false
}

// Splitting file paths

method directoryPart String {
  // Return the directory part of the given full file name.
  // The directory part is everything up to and including the last '/'.
  // If there is no '/', return the empty string.

  i = (findLast this '/')
  if (isNil i) { return '' }
  return (substring this 1 i)
}

method filePart String {
  // Return the file part of the given full file name or URL.
  // The directory part is everything after the last '/'.
  // If there is no '/' return the entire string.

  i = (findLast this '/')
  if (isNil i) { return this }
  return (substring this (i + 1))
}

method parentDir String {
  // Return a path to the parent directory of the given path.

  if (or ('/' == this) ('' == this)) { return '/' }
  pathParts = (splitWith this '/')
  if ((count pathParts) < 2) { return '' }
  if ('' == (last pathParts)) { // path ended with '/')
	pathParts = (copyFromTo pathParts 1 ((count pathParts) - 1))
  }
  pathParts = (copyFromTo pathParts 1 ((count pathParts) - 1)) // remove last dir in path
  if (and ('' == (first pathParts)) ((count pathParts) == 1)) { return '/' }
  return (joinStrings pathParts '/')
}

method withoutExtension String {
  // Return this string without any file extension. (A file extension
  // is a '.' followed by a suffix indicating the file type). If there
  // is no '.' in the string, return the entire string.

  i = (findLast this '.')
  if (isNil i) { return this }
  return (substring this 1 (i - 1))
}

method findFirst String ch {
  // Return the index of the first instance of ch or nil if not found.

  letters = (letters this)
  count = (count letters)
  i = 1
  while (i <= count) {
	if ((at this i) == ch) { return i }
	i += 1
  }
  return nil // ch not found
}

method findLast String ch {
  // Return the index of the last instance of ch or nil if not found.

  letters = (letters this)
  i = (count letters)
  while (i > 0) {
	if ((at this i) == ch) { return i }
	i += -1
  }
  return nil // ch not found
}

// Searching

method findSubstring String stringToSearch startIndex {
  // Return the index of the next instance of this string found in stringToSearch,
  // or nil if not found. If startIndex is provided, the search starts there.

  if (isNil startIndex) { startIndex = 1 }
  if (0 == (count this)) { error 'Pattern string cannot be empty' }
  firstByte = (byteAt this 1)
  end = (((byteCount stringToSearch) + 1) - (byteCount this))
  i = startIndex
  while (i <= end) {
	if (firstByte == (byteAt stringToSearch i)) {
	  if (foundMatch this stringToSearch i) { return i }
	}
	i += 1
  }
  return nil
}

method foundMatch String stringToSearch matchIndex {
  j = matchIndex
  for i (byteCount this) {
	if ((byteAt this i) != (byteAt stringToSearch j)) { return false }
	j += 1
  }
  return true
}

method findAllMatches String stringToSearch {
  result = (list)
  i = 1
  while true {
	match = (findSubstring this stringToSearch i)
	if (isNil match) { return result }
	add result match
	i = (match + (byteCount this))
  }
  return result
}

// Indexed access

method at String index {
  // Return the letter of this string at the given index.
  // Note: For heavy use, it is more efficient to covert the string
  // to an array of letters once and work with that.

  return (at (letters this) index)
}

// White space characters

to space { return (string 32) }
to tab { return (string 9) }
to newline { return (string 10) }
to cr { return (string 13) }

// Converting

method toBinaryData String {
  byteCount = (byteCount this)
  result = (newBinaryData byteCount)
  if (byteCount > 0) { replaceByteRange result 1 byteCount this }
  return result
}

method toInteger String {
  letters = (letters this)
  n = (count letters)
  if (n == 0) { return 0 }
  result = 0
  sign = 1
  index = 1
  if ((at letters 1) == '-') {
    sign = -1
    index = 2
  }
  while (index <= n) {
    c = (at letters index)
	if (isDigit c) {
	  digit = ((byteAt c 1) - (byteAt '0' 1))
	} else {
	  error 'this string does not represent an integer'
	}
    result = ((10 * result) + digit)
    index += 1
  }
  return (sign * result)
}

method toNumber String failValue {
  // Return this string as a number, if possible.
  // Otherwise, return failValue (0 by default).

  if ((argCount) < 2) { failValue = 0 } // allow nil as failValue
  if (')' == this) { return failValue } // suppress parse warning
  a = (parse this)
  if ((count a) != 1) { return failValue }
  n = (first a)
  if (or (isClass n 'Integer') (isClass n 'Float')) { return n }
  return failValue
}

method separateCamelCase String {
  words = (list)
  thisWord = (list)
  for ch (letters this) {
    if (isUpperCase ch) {
	  if ((count thisWord) > 0) {
	    add words (joinStringArray (toArray thisWord))
		thisWord = (list)
	  }
	  ch = (string ((byteAt ch 1) + 32))
	}
	add thisWord ch
  }
  if ((count thisWord) > 0) {
    add words (joinStringArray (toArray thisWord))
  }
  return (joinStringArray (toArray words) ' ')
}

// Printing and Formatting

method toString String { return this }

method printString String {
  // Returns a parsable version of this string, enclosed in single
  // quotes and with any embedded single quotes doubled.

  singleQuote = ''''
  cr = (cr)
  newline = (newline)
  result = (list)
  add result singleQuote
  for c (letters this) {
    if (c == singleQuote) {
      add result singleQuote
      add result singleQuote
    } (c == cr) {
	  add result newline // replace CR with newline
    } else {
      add result c
    }
  }
  add result singleQuote
  return (joinStringArray (toArray result))
}

method format String args... {
  in = (splitWith this '%')
  inP = 1
  argP = 2
  out = (list)
  while (inP < (count in)) {
    add out (at in inP)
    add out (toString (arg argP))
    inP += 1
    argP += 1
  }
  if ((at in inP) != '') {
    add out (at in inP)
  }
  return (joinStringArray (toArray out))
}

// parsing and evalution

method eval String obj module {
  // Evaluate the given string. If obj is supplied, evaluate the
  // string in the context of that object.
  // If module is supplied, evaluate the string in the module
  if (this == '') { return nil }
  if (this == 'nil') { return nil }
  if (not (isClass module 'Module')) { module = nil }
  if (isNil module) { module = (module (classOf obj)) }
  parseResult = (parse this)
  if (isEmpty parseResult) {
    print 'Could not parse' (printString this) '; syntax error?'
	return nil
  }
  for p parseResult {
    cmdList = p
    if (isClass cmdList 'Command') {
      if (not (isControlStructure cmdList)) {
        cmdList = (newCommand 'return' (toReporter cmdList))
      }
    } (isClass cmdList 'Reporter') {
	  if (isControlStructure cmdList) {
		cmdList = (toCommand cmdList)
	  } else {
		cmdList = (newCommand 'return' cmdList)
	  }
    } else {
      return cmdList // literal value
    }
    if (isNil obj) {
      func = (function cmdList)
	  if (notNil module) { setField func 'module' module }
      val = (call func)
    } else {
      // Evaluate in the context of an object
        found = false
      for v (fieldNames (classOf obj)) {
        // field name by itself? return field value
        if (and ((primName p) == v) (isNil (nextBlock p))) {
          found = true
          val = (getField obj v)
        }
      }
      if (and (not found) ((primName p) == 'this') (isNil (nextBlock p))) {
          found = true
          val = obj
      }
	  if (not found) {
        func = (functionFor obj cmdList)
		if (notNil module) { setField func 'module' module }
        val = (call func obj)
      }
    }
  }
  return val
}

// Handy Utilities

method splitWith String delimiter {
  in = (letters this)
  inP = 1
  inCount = (count in)
  if (inCount == 0) { return (array) }
  out = (list)
  start = 1
  if ((at in inP) == delimiter) {
    add out ''
    inP += 1
    start = 2
  }
  while (inP <= inCount) {
    c = (at in inP)
    if (c == delimiter) {
      add out (joinStringArray (toArray (copyArray in (inP - start) start)))
      start = (inP + 1)
    }
    inP += 1
  }
  add out (joinStringArray (toArray (copyArray in (inCount - (start - 1)) start)))
  return (toArray out)
}

method trim String {
  // Return a copy of this string without leading and trailing whitespace.

  space = 32
  end = (byteCount this)
  if (0 == end) { return this }
  if (and ((byteAt this 1) > space) ((byteAt this end) > space)) { return this }
  start = 1
  while (and (start <= end) ((byteAt this start) <= space)) { start += 1 }
  while (and (end > start) ((byteAt this end) <= space)) { end += -1 }
  return (substring this start end)
}

method wordWrapped String width {
  // Return a list of lines word-wrapped to the given width
  // using the current font.
  if (isNil width) { width = 500 }
  result = (list)
  for line (lines this) {
	addAll result (wordWrappedLine line width)
  }
  return (toArray result)
}

method wordWrappedLine String width {
  // Return a list of lines word-wrapped to the given width
  // using the current font, ignoring line endings.
  if (isNil width) { width = 150 }
  width = (width * (global 'scale'))
  result = (list)
  line = (list)
  for w (words this) {
	add line w
	lineWidth = (stringWidth (joinStrings line ' '))
	if (lineWidth > width) {
	  if ((count line) > 1) {
		removeLast line
		add result (joinStrings line ' ')
		line = (list w)
	  } else {
		add result (joinStrings line ' ')
		line = (list)
	  }
    }
  }
  if ((count line) > 0) {
	add result (joinStrings line ' ')
  }
  return result
}

method containsSubString String target start {
  count = (byteCount target)
  if (or ((count this) == 0) (count == 0)) {return 0}
  if (isNil start) {start = 1}
  if ((byteCount this) < ((start - 1) + count)) {return 0}
  for i (range start (((byteCount this) - count) + 1)) {
    in = true
    j = 1
    while (and in (j <= count)) {
      if (not ((byteAt this (+ i j -1)) === (byteAt target j))) {
        in = false
      }
      j += 1
    }
    if in {
      return i
    }
  }
  return 0
}

method splitWithString String terminator {
  result = (list)
  ind = 1
  more = true
  while (and more (ind <= (byteCount this))) {
    pos = (containsSubString this terminator ind)
    if (pos > 0) {
      add result (stringFromByteRange this ind (pos - 1))
      ind = (pos + (byteCount terminator))
    } else {
      more = false
    }
  }
  if (not more) {
    // xabc
    if (ind < (byteCount this)) {
      add result (stringFromByteRange this ind (byteCount this))
    }
  } else {
    if (ind == ((byteCount this) + 1)) {
      add result ''
    }
  }
  return (toArray result)
}

method toUpperCase String {
  result = (list)
  offset = ((byteAt 'a' 1) - (byteAt 'A' 1))
  for c (letters this) {
    if (isLowerCase c) {
      c = (string ((byteAt c 1) - offset))
    }
    add result c
  }
  return (joinStringArray (toArray result))
}

method toLowerCase String {
  result = (list)
  offset = ((byteAt 'a' 1) - (byteAt 'A' 1))
  for c (letters this) {
    if (isUpperCase c) {
      c = (string ((byteAt c 1) + offset))
    }
    add result c
  }
  return (joinStringArray (toArray result))
}

method leftPadded String desiredLength char {
  if (isNil char) { char = (string 32) } // space
  result = this
  while ((count result) < desiredLength) { result = (join '' char result) }
  return result
}

method rightPadded String desiredLength char {
  if (isNil char) { char = (string 32) } // space
  result = this
  while ((count result) < desiredLength) { result = (join result char) }
  return result
}

method escapeDoubleQuotes String {
  if ('' == this) { return this }
  result = (list)
  for ch (letters this) {
	if ('"' == ch) { add result '\' }
	add result ch
  }
  return (joinStrings result)
}

// Unicode encoding

method codePoints String {
  result = (list)
  i = 1
  while (i <= (byteCount this)) {
	c1 = (byteAt this i)
	if (c1 <= 127) {
	  add result c1
	  i += 1
	} ((c1 & 224) == 192) {
	  c2 = (byteAt this (i + 1))
	  add result (((c1 & 31) << 6) + (c2 & 63))
	  i += 2
	} ((c1 & 240) == 224) {
	  c2 = (byteAt this (i + 1))
	  c3 = (byteAt this (i + 2))
	  add result (+ ((c1 & 15) << 12) ((c2 & 63) << 6) (c3 & 63))
	  i += 3
	} ((c1 & 248) == 240) {
	  c2 = (byteAt this (i + 1))
	  c3 = (byteAt this (i + 2))
	  c4 = (byteAt this (i + 3))
	  add result (+ ((c1 & 7) << 18) ((c2 & 63) << 12) ((c3 & 63) << 6) (c4 & 63))
	  i += 4
	} else {
	  error 'Bad UTF-8 string'
	}
  }
  return result
}

to stringFromCodePoints codePoints {
  result = (list)
  for cp codePoints {
    addAll result (bytesForCodePoint cp)
  }
  return (toString (toBinaryData (toArray result)))
}

to bytesForCodePoint codePoint {
  if (codePoint < 128) { return (array codePoint) }
  masks = (array 128 192 224 240 248 252 254 255)
  result = (list)
  nBytes = (truncate (((highBit codePoint) + 3) / 5))
  mask = (at masks nBytes)
  shift = ((nBytes - 1) * 6)
  add result (mask | (codePoint >> shift))
  repeat (nBytes - 1) {
	shift = (shift - 6)
	add result (128 | ((codePoint >> shift) & 63))
  }
  return (toArray result)
}

method quoted String { return this }

method canonicalizedWord String {
  // Return a string containing only lower-case ASCII letters,
  // (no digits, symbols, or extended characters).

  result = (list)
  for ch (letters this) {
	if (or (isLetter ch) (ch == '-')) {
	  if (isUpperCase ch) {
		ch = (string ((byteAt ch 1) + 32))
	  }
	  add result ch
    }
  }
  while (and ((count result) > 0) ((last result) == '-')) { removeLast result }
  return (joinStringArray (toArray result))
}

method urlEncode String {
  result = (list)
  for ch (toArray (toBinaryData this)) {
	if (and (32 < ch) (ch < 127)) {
	   add result (string ch)
	} else {
	  add result (join '%' (toStringBase16 ch))
	}
  }
  return (joinStringArray (toArray result))
}

method withoutTrailingDigits String {
  i = (count this)
  while (and (i > 0) (isDigit (at this i))) {
	i += -1
  }
  return (substring this 1 i)
}

method representsANumber String {
  hasDecimalPoint = false
  hasExponent = false
  lastC = nil
  for c (letters this) {
	if ('-' == c) {
	  if (not (or (isNil lastC) (isOneOf lastC 'e' 'E'))) {
		return false
	  }
	} ('+' == c) {
	  if (not (isOneOf lastC 'e' 'E')) {
		return false
	  }
	} ('.' == c) {
	  if hasDecimalPoint { return false }
	  if (not (or (isNil lastC) (isDigit lastC))) {
	  	return false
	  }
	  hasDecimalPoint = true
	} (isOneOf c 'e' 'E') {
	  if hasExponent { return false }
	  if (not (and (notNil lastC) (isDigit lastC))) {
		return false
	  }
	  hasExponent = true
	} (not (isDigit c)) {
	  return false
	}
	lastC = c
  }
  return true
}
