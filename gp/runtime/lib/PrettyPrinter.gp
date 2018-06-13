defineClass PrettyPrinter gen offset

// public methods

method prettyPrint PrettyPrinter block generator {
  gen = generator
  offset = ((fieldNameCount (class 'Command')) + 1)
  if (isNil gen) {
    gen = (new 'PrettyPrinterGenerator' (list) 0 true true)
  }
  printCmd this block
  return (joinStringArray (toArray (getField gen 'result')))
}

method prettyPrintFunction PrettyPrinter func generator {
  gen = generator
  offset = ((fieldNameCount (class 'Command')) + 1)
  if (isNil gen) {
    gen = (new 'PrettyPrinterGenerator' (list) 0 true true)
  }
  printFunction this func
  return (joinStringArray (toArray (getField gen 'result')))
}

method prettyPrintMethod PrettyPrinter func generator {
  gen = generator
  offset = ((fieldNameCount (class 'Command')) + 1)
  if (isNil gen) {
    gen = (new 'PrettyPrinterGenerator' (list) 0 true true)
  }
  printFunction this func (className (class (classIndex func)))
  return (joinStringArray (toArray (getField gen 'result')))
}

method prettyPrintList PrettyPrinter block generator {
  gen = generator
  offset = ((fieldNameCount (class 'Command')) + 1)
  if (isNil gen) {
    gen = (new 'PrettyPrinterGenerator' (list) 0 true true)
  }

  currentBlock = block
  early = true
  while (notNil currentBlock) {
    tab gen
    early = (printCmd this currentBlock early)
    early = (early == true)
    crIfNeeded gen
    currentBlock = (getField currentBlock 'nextBlock')
  }
  return (joinStringArray (toArray (getField gen 'result')))
}

method prettyPrintString PrettyPrinter aString {
  commands = (parse aString)
  output = (list)
  for i (count commands) {
    add output (prettyPrint this (at commands i))
    if (i < (count commands)) {
      add output (newline)
    }
  }
  return (joinStringArray (toArray output))
}

method prettyPrintFile PrettyPrinter aFileName {
  return (prettyPrintString this (readFile aFileName))
}

method prettyPrintClass PrettyPrinter aClass withoutDefinition generator {
  offset = ((fieldNameCount (class 'Command')) + 1)
  gen = generator
  if (isNil gen) {
    gen = (new 'PrettyPrinterGenerator' (list) 0 true true)
  }

  if (not (withoutDefinition === false)) {
    control gen 'defineClass'
    varName gen (className aClass)
    for f (fieldNames aClass) {
      varName gen f
    }
    crIfNeeded gen
    cr gen
  }

  mList = (sorted (methods aClass) (function a b {return ((functionName a) < (functionName b))}))
  for f mList {
    printFunction this f (className aClass)
    if (not (f === (last mList))) {
      cr gen
    }
  }
  return (joinStringArray (toArray (getField gen 'result')))
}

method prettyPrintFileToFile PrettyPrinter aFileName newFileName {
  writeFile newFileName (prettyPrintFile this aFileName)
}

// private methods

method infixOp PrettyPrinter token {
  return (or ('=' == token) ('+=' == token)
             ('+' == token) ('-' == token) ('*' == token) ('/' == token) ('%' == token)
             ('<' == token) ('<=' == token) ('==' == token)
             ('!=' == token) ('>=' == token) ('>' == token) ('===' == token)
             ('&' == token) ('|' == token) ('^' == token)
             ('<<' == token) ('>>' == token) ('>>>' == token)
	     ('->' == token))
}

method allAlphaNumeric PrettyPrinter letters {
  for c letters {
    if (not (or (isLetter c) (isDigit c) ('_' == c))) { return false }
  }
  return true
}

method quoteOp PrettyPrinter value {
  if (isClass value 'String') {
    if (or (infixOp this value) (not (isLetter value))
           (value == 'false') (value == 'true') (value == 'nil') (value == 'else')) {
      return (join '''' value '''')
    }

    token = (toList (letters value))
    removeLast token
    if (allAlphaNumeric this token) { return value }
    return (join '''' value '''')
  }
}

method op PrettyPrinter value {
  if (isClass value 'String') {
    if (or (infixOp this value) (isLetter value)) {
      token = (toList (letters value))
      removeLast token
      if (allAlphaNumeric this token) { return value }
    }
  }
  return (join '''' value '''')
}

method printValue PrettyPrinter block {
  if (isClass block 'Reporter') {
    if ((primName block) == 'v') {
	  varRef = (getField block offset)
	  if (contains (letters varRef) ' ') {
		varRef = (join '(v ''' varRef ''')')
	  }
      symbol gen varRef
    } else {
      openParen gen
      printCmd this block
      closeParen gen
    }
  } (isClass block 'Command') {
    printCmdList this block
  } (isClass block 'String') {
    const gen (printString block)
  } (isClass block 'Float') {
	const gen (toString block 20)
  } (isClass block 'Color') {
	c = block
	const gen (join '(colorSwatch ' (red c) ' ' (green c) ' ' (blue c) ' ' (alpha c) ')')
  } else {
	const gen (toString block)
  }
}

method printFunction PrettyPrinter func aClass {
  if (isNil aClass) {
    if (notNil (functionName func)) {
      control gen 'to'
      functionName gen (quoteOp this (functionName func))
    } else {
      control gen 'function'
    }
    for i (count (argNames func)) {
      varName gen (at (argNames func) i)
    }
  } else {
    control gen 'method'
    functionName gen (quoteOp this (primName func))
    for i (count (argNames func)) {
      if (i == 1) {
        varName gen aClass
      } else {
        varName gen (at (argNames func) i)
      }
    }
  }
  printCmdList this (cmdList func)
}

method printReporter PrettyPrinter block {
  prim = (primName block)
  if (and (infixOp this prim) ((count block) == (offset + 1))) {
    printValue this (getField block offset)
    symbol gen prim
    printValue this (getField block (offset + 1))
  } (prim == 'v') {
    varName gen (getField block offset)
  } else {
    printOp this prim
    for i (count block) {
      if (i >= offset) {
        printValue this (getField block i)
      }
    }
  }
}

method printOp PrettyPrinter block {
  functionName gen (op this block)
}

method printCmdList PrettyPrinter block inIf {
  openBrace gen
  addTab gen
  crIfNeeded gen
  currentBlock = block
  early = true
  while (notNil currentBlock) {
    tab gen
    early = (printCmd this currentBlock early)
    early = (early == true)
    crIfNeeded gen
    currentBlock = (getField currentBlock 'nextBlock')
  }
  decTab gen
  tab gen
  closeBrace gen
  if (inIf != true) {
    crIfNeeded gen
  }
}

method printCmdListInControl PrettyPrinter block {
  if (isClass block 'Reporter') {
    printValue this block
  } (isClass block 'Command') {
    printCmdList this block
    crIfNeeded gen
  } else { // empty body
    openBrace gen
    closeBrace gen
    crIfNeeded gen
  }
}

method isShort PrettyPrinter bodyBlock {
  // Return true if the body of an 'if' command is empty or a single command that should
  // be put on the same line as the test.
  return (or (isNil bodyBlock) (isNil (nextBlock bodyBlock)))
}

method printCmdListShort PrettyPrinter block {
  openBrace gen
  skipSpace gen
  if (notNil block) { printCmd this block }
  closeBrace gen
  crIfNeeded gen
}

method printCmd PrettyPrinter block early {
  prim = (primName block)
  if (prim == 'to') {
    op = (getField block offset)
    control gen prim
    functionName gen (quoteOp this op)
    for i (count block) {
      if (and (i >= (offset + 1)) (i < (count block))) {
        varName gen (getField block i)
      }
    }
    printCmdListInControl this (getField block (count block))
  } (prim == 'function') {
    control gen prim
    for i (count block) {
      if (and (i >= offset) (i < (count block))) {
        varName gen (getField block i)
      }
    }
    printCmdListInControl this (getField block (count block))
  } (prim == 'defineClass') {
    control gen prim
    varName gen (getField block offset)
    for i (count block) {
      if (and (i >= (offset + 1)) (i <= (count block))) {
        varName gen (getField block i)
      }
    }
    crIfNeeded gen
  } (prim == 'method') {
    control gen prim
    symbol gen (quoteOp this (getField block offset))
    varName gen (getField block (offset + 1))
    for i (count block) {
      if (and (i >= (offset + 2)) (i < (count block))) {
        varName gen (getField block i)
      }
    }
    printCmdListInControl this (getField block (count block))
  } (prim == 'for') {
    control gen prim
    varName gen (getField block offset)
    printValue this (getField block (offset + 1))
    printCmdListInControl this (getField block (offset + 2))
  } (prim == 'while') {
    control gen prim
    printValue this (getField block offset)
    printCmdListInControl this (getField block (offset + 1))
  } (prim == 'if') {
    if (and (early == true) (((count block) - offset) == 1)
         (isShort this (getField block (offset + 1)))) {
      control gen prim
      printValue this (getField block (offset + 0))
      printCmdListShort this (getField block (offset + 1))
      return true
    } else {
      control gen prim
      ind = 0
      while ((offset + ind) < (count block)) {
        cond = (getField block (offset + ind))
        body = (getField block ((offset + ind) + 1))
        printed = false
        if ((offset + ind) == ((count block) - 1)) {
          if (cond == true) {
            symbol gen 'else'
            printed = true
          }
        }
        if (not printed) {
          printValue this cond
        }
        printCmdList this body true
        ind += 2
      }
    }
  } (prim == '=') {
    varName gen (getField block offset)
    symbol gen prim
    printValue this (getField block (offset + 1))
  } (prim == '+=') {
    varName gen (getField block offset)
    symbol gen prim
    printValue this (getField block (offset + 1))
  } else {
    printReporter this block
  }
}

defineClass PrettyPrinterGenerator result tabLevel hadCr hadSpace

method closeBrace PrettyPrinterGenerator {
  nextPutAll this '}'
}

method addTab PrettyPrinterGenerator {
  tabLevel = (tabLevel + 1)
}

method closeParen PrettyPrinterGenerator {
  nextPutAll this ')'
}

method const PrettyPrinterGenerator value {
  nextPutAllWithSpace this value
}

method control PrettyPrinterGenerator value {
  nextPutAll this value
}

method crIfNeeded PrettyPrinterGenerator {
  if (not hadCr) {
    cr this
  }
}

method cr PrettyPrinterGenerator {
  nextPutAll this (newline)
  hadCr = true
}

method skipSpace PrettyPrinterGenerator {
  hadSpace = true
}

method decTab PrettyPrinterGenerator {
  tabLevel = (tabLevel - 1)
}

method functionName PrettyPrinterGenerator value {
  if (not (isClass value 'String')) {
    error 'non string'
  }
  nextPutAllWithSpace this value
}

method varName PrettyPrinterGenerator value {
  if (contains (letters value) ' ') {
	value = (printString value) // enclose in quotes
  }
  nextPutAllWithSpace this value
}

method nextPutAll PrettyPrinterGenerator value {
  add result value
  if ((count value) > 0) {
    last = (last (letters value))
    hadSpace = (or (last == ' ') (last == (newline)) (last == '('))
    hadCr = (last == (newline))
  }
}

method nextPutAllWithSpace PrettyPrinterGenerator value {
  if (not hadSpace) {
    nextPutAll this ' '
  }
  nextPutAll this value
}

method openBrace PrettyPrinterGenerator {
  nextPutAllWithSpace this '{'
}

method openParen PrettyPrinterGenerator {
  nextPutAllWithSpace this '('
}

method symbol PrettyPrinterGenerator value {
  nextPutAllWithSpace this value
}

method tab PrettyPrinterGenerator {
  repeat tabLevel {
    repeat 2 {
      nextPutAll this ' '
    }
  }
}
