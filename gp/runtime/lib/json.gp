// json.gp - Parse and generate JSON

to jsonFormat s {
  // Return a formatted version of the given JSON string.

  return (jsonStringify (jsonParse s) true)
}

to jsonParse s {
  // Return the result of parsing the given JSON string.

  return (readValue (initialize (new 'JSONReader') s))
}

to jsonStringify obj formatFlag {
  // Encode the given JSON-encodable object as a JSON string. A JSON-encodable object
  // can be nil, a boolean/string/number, or an Array or Dictionary containing
  // JSON-encodable objects. If formatFlag is true, the result will be formatted with
  // space, tabs, and newlines to make it more readable by humans.

  return (stringify (initialize (new 'JSONWriter')) obj formatFlag)
}

// *** JSONReader ***

defineClass JSONReader src srcCount index

method initialize JSONReader s {
  src = (letters s)
  srcCount = (count src)
  index = 1
  return this
}

method notAtEnd JSONReader n {
  return (index <= srcCount)
}

method peek JSONReader {
  if (index > srcCount) { return nil }
  return (at src index)
}

method next JSONReader n {
  if (index > srcCount) { return nil }
  if (isNil n) { // return next character
	result = (at src index)
	index += 1
	return result
  }
  last = (min ((index + n) - 1) srcCount)
  result = (joinStrings (copyFromTo src index last))
  index += n
  return result
}

method skip JSONReader { index += 1 }

method skipWhiteSpace JSONReader n {
  while (and (index <= srcCount) ((byteAt (at src index) 1) <= 32)) {
	index += 1
  }
}

method readValue JSONReader {
  skipWhiteSpace this
  ch = (peek this)
  if (or (and ('0' <= ch) (ch <= '9')) ('-' == ch)) {
	return (readNumber this)
  } ('"' == ch) {
	return (readString this)
  } ('[' == ch) {
	return (readArray this)
  } ('{' == ch) {
	return (readObject this)
  } ('t' == ch) {
	if ('true' == (next this 4)) { return true }
	error 'Expected "true"'
  } ('f' == ch) {
	if ('false' == (next this 5)) { return false }
	error 'Expected "false"'
  } ('n' == ch) {
	if ('null' == (next this 4)) { return nil }
	error 'Expected "null"'
  } (isNil ch) {
	error 'Incomplete JSON data'
  } else {
	error 'Bad JSON character' ch
  }
}

method readNumber JSONReader {
  numStr = ''
  isFloat = false
  if ('-' == (peek this)) {
	skip this
	numStr = (join '-' (readDigits this))
	if ((count numStr) < 2) {
	  error 'At least one digit expected'
	}
  } else {
	numStr = (readDigits this)
  }
  if ('.' == (peek this)) {
	isFloat = true
	skip this
	numStr = (join numStr '.' (readDigits this))
  }
  ch = (peek this)
  if (or ('e' == ch) ('E' == ch)) {
	skip this
	isFloat = true
	numStr = (join numStr 'E')
	ch = (peek this)
	if ('+' == ch) {
	  skip this
	} ('-' == ch) {
	  skip this
	  numStr = (join numStr '-')
	}
	numStr = (join numStr (readDigits this))
  }
  if isFloat {
	num = (toNumber numStr)
  } else {
	num = (toNumber (join numStr '.0')) // parse as a Float to handle a larger range
	if (and (-1073741824.0 <= num) (num <= 1073741823.0)) {
	  num = (toInteger num)
	}
  }
  return num
}

method readDigits JSONReader {
  result = (list)
  while true {
	ch = (peek this)
	if (and ('0' <= ch) (ch <= '9')) {
	  add result ch
	  index += 1
	} else {
	  return (joinStrings result)
	}
  }
}

method readString JSONReader {
  result = (list)
  skip this // opening quote
  while (notAtEnd this) {
	ch = (next this)
	if ('"' == ch) {
	  return (joinStrings result)
	} ('\' == ch) {
	  add result (readEscapedChar this)
	} else {
	  add result ch
	}
  }
  error 'Incomplete string'
}

method readEscapedChar JSONReader {
  ch = (next this)
  if ('b' == ch) {
	return (string 8)
  } ('f' == ch) {
	return (string 12)
  } ('n' == ch) {
	return (string 10)
  } ('r' == ch) {
	return (string 13)
  } ('t' == ch) {
	return (string 9)
  } ('u' == ch) {
	return (hex (next this 4))
  } else {
	return ch // handles back slash, forward slash (solidus), double-quote
  }
}

method readArray JSONReader {
  result = (list)
  skip this // opening '['
  done = false
  while (notAtEnd this) {
	skipWhiteSpace this
	if (']' == (peek this)) {
	  skip this
	  return result
	}
	add result (readValue this)
	skipWhiteSpace this
	ch = (peek this)
	if (',' == ch) {
	  skip this
	} (']' != ch) {
	  error 'Missing comma in array'
	}
  }
  error 'Incomplete array'
}

method readObject JSONReader {
  result = (dictionary)
  skip this // opening '{'
  done = false
  while (notAtEnd this) {
	skipWhiteSpace this
	if ('}' == (peek this)) {
	  skip this
	  return result
	}
	if ('"' != (peek this)) { error 'Bad object syntax: keys must be strings' }
	key = (readString this)
	skipWhiteSpace this
	if (':' == (peek this)) {
	  skip this
	} else {
	  error 'Bad object syntax: missing colon'
	}
	skipWhiteSpace this
	value = (readValue this)
	atPut result key value

	skipWhiteSpace this
	if (',' == (peek this)) {
	  skip this
	} ('}' != (peek this))  {
	  error 'Missing comma in object'
	}
  }
  error 'Incomplete object'
}

// *** JSONWriter ***

defineClass JSONWriter buf tabs needsComma doFormatting

method initialize JSONWriter s {
  buf = (list)
  tabs = ''
  needsComma = false
  doFormatting = false
  return this
}

method stringify JSONWriter obj formatFlag {
  if (isNil formatFlag) { formatFlag = false }
  doFormatting = formatFlag
  writeObject this obj
  return (joinStrings buf)
}

method writeObject JSONWriter obj {
  if (isAnyClass obj 'Integer' 'Float' 'Boolean' 'Nil') {
	add buf (toString obj)
	return
  } (isClass obj 'String') {
	writeString this obj
  } (isClass obj 'Array') {
	writeArray this obj
  } (isClass obj 'Dictionary') {
	writeDictionary this obj
  } (isClass obj 'List') {
	writeArray this (toArray obj)
  } else {
	error (join 'JSON cannot represent objects of class ' (className (classOf obj)))
  }
}

method writeArray JSONWriter array {
  add buf '['
  count = (count array)
  for i count {
	writeObject this (at array i)
	if (i < count) { add buf ', ' }
  }
  add buf ']'
}

method writeDictionary JSONWriter dictionary {
  indent this
  lineStart = (join (newline) tabs)
  add buf '{'
  keys = (sorted (keys dictionary))
  count = (count keys)
  for i count {
	key = (at keys i)
	if doFormatting { add buf lineStart }
	writeString this key
	add buf ': '
	writeObject this (at dictionary key)
	if (i < count) { add buf ', ' }
  }
  outdent this
  if doFormatting { add buf (join (newline) tabs) }
  add buf '}'
}

method indent JSONWriter {
  tabs = (join tabs (string 9))
}

method outdent JSONWriter {
  if ((count tabs) > 0) {
	tabs = (substring tabs 1 ((count tabs) - 1))
  }
}

method writeString JSONWriter s {
  letters = (letters s)
  if (needsEscapes this letters) { s = (escape this letters) }
  add buf (join '"' s '"')
}

method needsEscapes JSONWriter letters {
  for ch letters {
	if (or (ch == '"') (ch == '\') ((byteAt ch 1) < 32)) {
	  return true
	}
  }
  return false
}

method escape JSONWriter letters {
  result = (list)
  for ch letters {
	if (or (ch == '"') (ch == '\')) {
	  add result '\'
	  add result ch
	}
	ascii = (byteAt ch 1)
	if (ascii < 32) {
	  add result '\'
	  if (8 == ascii) {
		add result 'b'
	  } (9 == ascii) {
		add result 't'
	  } (10 == ascii) {
		add result 'n'
	  } (12 == ascii) {
		add result 'f'
	  } (13 == ascii) {
		add result 'r'
	  } else {
		hex = (toStringBase16 ascii)
		while ((count hex) < 4) {
		  hex = (join '0' hex)
		}
		add result 'u'
		add result hex
	  }
	}
  }
  return (joinStrings result)
}
