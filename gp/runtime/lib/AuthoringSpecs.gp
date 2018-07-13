defineClass AuthoringSpecs specsList specsByOp opCategory language translationDictionary

method allOpNames AuthoringSpecs {
  result = (toList (keys specsByOp))
  editor = (findProjectEditor)
  if (notNil editor) {
	addAll result (keys (blockSpecs (project editor)))
  }
  return result
}

// initialization

method initialize AuthoringSpecs {
  // Initialize the specsByOp and opCategory dictionaries.
  // Note: specsByOp maps an op to a list of matching specs.

  clear this
  addSpecs this (initialSpecs this)
  return this
}

method clear AuthoringSpecs {
  specsList = (list)
  specsByOp = (dictionary)
  opCategory = (dictionary)
  language = 'English'
  translationDictionary = nil
  return this
}

method addSpecs AuthoringSpecs newSpecs {
  category = ''
  for entry newSpecs {
	add specsList entry
	if (isClass entry 'String') {
	  category = entry
	} else {
	  op = (at entry 2)
	  specsForOp = (at specsByOp op (list))
	  add specsForOp (specForEntry this entry)
	  atPut specsByOp op specsForOp
	  if (not (contains opCategory op)) {
		atPut opCategory op category
	  }
	}
  }
  // special cases for the block finder for blocks that are in multiple categories
  atPut opCategory 'randomColor' 'Color'
  atPut opCategory 'transparent' 'Color'
}

method recordBlockSpec AuthoringSpecs op spec {
  // Record a block spec for the give op. Called when creating/changing functions and methods.
  editor = (findProjectEditor)
  if (isNil editor) { return } // should not happen
  atPut (blockSpecs (project editor)) op spec
}

// queries

method allSpecs AuthoringSpecs {
  result = (list)
  for entry specsList {
	if (isClass entry 'Array') { add result entry }
  }
  return result
}

method specForEntry AuthoringSpecs e {
  // Return a BlockSpec for the given entry array.

  blockType = (at e 1)
  op = (at e 2)
  specString = (at e 3)
  slotTypes = ''
  if ((count e) > 3) { slotTypes = (at e 4) }
  slotDefaults = (array)
  if ((count e) > 4) { slotDefaults = (copyArray e ((count e) - 4) 5) }
  return (blockSpecFromStrings op blockType specString slotTypes slotDefaults)
}

method specForOp AuthoringSpecs op cmdOrReporter {
  // Return a BlockSpec for the given op, or nil if there isn't one.
  // If cmdOrReporter is supplied, use it to disambiguate when there
  // there are multiple blocks specs matching the given op.

  matchingSpecs = (at specsByOp op (array))
  editor = (findProjectEditor)
  if (notNil editor) {
	projectSpecs = (blockSpecs (project editor))
	if (contains projectSpecs op) {
	  // if project defines op, try that first
	  matchingSpecs = (join (array (at projectSpecs op)) matchingSpecs)
    }
  }
  if (isEmpty matchingSpecs) { return nil }
  if (or ((count matchingSpecs) == 1) (isNil cmdOrReporter)) {
	return (translateToCurrentLanguage this (first matchingSpecs))
  }

  // filter by block type
  isReporter = (isClass cmdOrReporter 'Reporter')
  filtered = (list)
  for s matchingSpecs {
	if (isReporter == ('r' == (blockType s))) {
		add filtered s
	}
  }
  if ((count filtered) == 1) { return (translateToCurrentLanguage this (first filtered)) } // unique match
  if (isEmpty filtered) { filtered = matchingSpecs } // revert if no matches

  // filter by arg count
  argCount = (count (argList cmdOrReporter))
  filtered2 = (list)
  for s filtered {
	if (argCount == (slotCount s)) {
		add filtered2 s
	}
  }
  if ((count filtered2) > 0) { return (translateToCurrentLanguage this (first filtered2)) }
  return (translateToCurrentLanguage this (first filtered))
}

method specsFor AuthoringSpecs category {
  // Return a list of BlockSpecs for the given category.

  editor = (findProjectEditor)
  if (notNil editor) {
	if (contains (extraCategories (project editor)) category) {
	  return (specsForCategory (project editor) category)
	}
  }
  result = (list)
  currentCategory = ''
  for entry specsList {
	if (isClass entry 'String') {
	  currentCategory = entry
	} (currentCategory == category) {
	  add result (specForEntry this entry)
	}
  }
  return result
}

method categoryFor AuthoringSpecs op {
  return (at opCategory op)
}

method hasTopLevelSpec AuthoringSpecs op {
  return (contains specsByOp op)
}

// block colors

method blockColorForOp AuthoringSpecs op {
  if (true == (global 'alanMode')) {
	if ('comment' == op) { return (gray 237) }
	c = (blockColorForCategory this (at opCategory op))
	return (alansBlockColorForCategory this (at opCategory op))
  }
  if ('comment' == op) { return (colorHSV 55 0.6 0.93) }
  return (blockColorForCategory this (at opCategory op))
}

method blockColorForCategory AuthoringSpecs cat {
  defaultColor = (color 4 148 220)
  if (isOneOf cat 'Control' 'Functions') {
	if (notNil (global 'controlColor')) { return (global 'controlColor') }
	return (color 230 168 34)
  } ('Variables' == cat) {
	if (notNil (global 'variableColor')) { return (global 'variableColor') }
	return (color 243 118 29)
  } (isOneOf cat 'Operators' 'Math') {
	if (notNil (global 'operatorsColor')) { return (global 'operatorsColor') }
	return (color 98 194 19)
  } ('Obsolete' == cat) {
	return (color 196 15 0)
  }
  if (notNil (global 'defaultColor')) { return (global 'defaultColor') }
  return defaultColor
}

method alansBlockColorForCategory AuthoringSpecs cat {
  defaultColor = (gray 190) // 180
  if (isOneOf cat 'Control' 'Functions') {
	return (gray 200) // 190
  } ('Variables' == cat) {
	return (gray 185) // 175
  } ('Operators' == cat) {
	return (gray 220) // 230
  }
  return defaultColor
}

to setBlockColors c1 c2 c3 c4 {
  // Allows experimentation with block colors.
  setGlobal 'controlColor' c1
  setGlobal 'variableColor' c2
  setGlobal 'operatorsColor' c3
  setGlobal 'defaultColor' c4
  fixBlockColors
}

to setBlockTextColor c {
  setGlobal 'blockTextColor' c
  fixBlockColors
}

to resetBlockColors {
  // Revert to original block colors.
  setGlobal 'controlColor' (color 230 168 34)
  setGlobal 'variableColor' (color 243 118 29)
  setGlobal 'operatorsColor' (color 98 194 19)
  setGlobal 'defaultColor' (color 4 148 220)
  setGlobal 'blockTextColor' (gray 255)
  fixBlockColors
}

to fixBlockColors {
  // update colors of existing blocks
  for b (allInstances (class 'Block')) {
	expr = (expression b)
	if (notNil expr) {
	  setBlockColor b (primName expr)
	  redraw b
	}
	textColor = (global 'blockTextColor')
	if (isNil textColor) { textColor = (gray 0) }
	for m (parts (morph b)) {
	  if (isClass (handler m) 'Text') { setColor (handler m) textColor }
	}
  }
}

// translation

method language AuthoringSpecs { return language }

method setLanguage AuthoringSpecs newLang {
  translationData = (readEmbeddedFile (join 'translations/' newLang '.txt'))
  if (isNil translationData) {
	// if not embedded file, try reading external file
	translationData = (readFile (join 'translations/' newLang '.txt'))
  }
  if (isNil translationData) {
	language = 'English'
	translationDictionary = nil
  } else {
	language = newLang
	installTranslation this translationData
  }
}

method translateToCurrentLanguage AuthoringSpecs spec {
  if (not (needsTranslation this spec)) { return spec }

  newSpecStrings = (list)
  for s (specs spec) {
	add newSpecStrings (at translationDictionary s s)
  }
  result = (clone spec)
  setField result 'specs' newSpecStrings
  return result
}

method needsTranslation AuthoringSpecs spec {
  // Return true if any of the spec strings of spec needs to be translated.

  if (isNil translationDictionary) { return false }
  for s (specs spec) {
	if (contains translationDictionary s) { return true }
  }
  return false
}

method installTranslation AuthoringSpecs translationData {
  // Translations data is string consisting of three-line entries:
  //	original string
  //	translated string
  //	<blank line>
  //	...

  translationDictionary = (dictionary)
  lines = (toList (lines translationData))
  while ((count lines) >= 2) {
	from = (removeFirst lines)
	to = (removeFirst lines)
	atPut translationDictionary from to
	while (and ((count lines) > 0) ((removeFirst lines) != '')) {
	  // skip lines until the next blank line
	}
  }
}

// authoring specs

method initialSpecs AuthoringSpecs {
  return (array
	'Control'
	  (array ' ' 'animate'				'forever _' 'cmd')
	  (array ' ' 'if'					'if _ _ : else if _ _ : ...' 'bool cmd bool cmd')
	  (array ' ' 'repeat'				'repeat _ _' 'num cmd' 10)
	  (array ' ' 'waitSecs'				'wait : _ seconds' 'num' 0.1)
	  (array ' ' 'waitUntil'			'wait until _' 'bool')
	  (array ' ' 'stopTask'				'stop')
	  (array ' ' 'self_stopAll'			'stop all')
	  (array 'h' 'whenKeyPressed'		'when _ key pressed : _' 'menu.keyMenu var' 'space' 'key')
	  (array 'h' 'whenBroadcastReceived' 'when I receive _ : _' 'str var' 'go' 'data')
	  (array ' ' 'broadcast'			'broadcast _ : with _' 'str auto' 'go')
	  (array ' ' 'broadcastAndWait'		'broadcast _ and wait : with _' 'str auto' 'clear')
	  (array ' ' 'send'					'send _ to _ : with _ ' 'str all auto' 'start')
	  (array 'r' 'gather'				'gather _ : from _ : with _' 'str list auto')
	  (array ' ' 'return'				'return _' 'auto')
	  (array ' ' 'for'					'for _ in _ _' 'var num cmd' 'i' 10)
	  (array 'r' 'range'				'range from _ to _ : by _' 'num num num' 1 10 1)
	  (array ' ' 'while'				'while _ _' 'bool cmd')
	  (array 'h' 'whenClicked'			'when clicked')
	  (array 'h' 'whenDropped'			'when dropped')
	  (array 'h' 'whenTracking'			'when tracking _ _' 'var var' 'mouse x' 'mouse y')
	  (array ' ' 'comment'				'comment _' 'str' 'Use this block to explain your code')

	'Functions'
	  (array 'r' 'function'				'function _' 'cmd')
	  (array 'r' 'function'				'function _ _' 'var cmd' 'a')
	  (array 'r' 'function'				'function _ _ _' 'var var cmd' 'a' 'b')
	  (array 'r' 'action'				'action _ : _ : ...' 'str auto auto')
	  (array ' ' 'call'					'call _ : _ : ...' 'str auto auto')
	  (array 'r' 'call'					'call _ : _ : ...' 'str auto auto')
	  (array ' ' 'return'				'return _' 'auto')
	  (array 'r' 'map'					'map _ over _' 'str list' 'func')
	  (array 'r' 'filter'				'filter _ from _' 'str list' 'func')
	  (array 'r' 'detect'				'detect first _ in _' 'str list' 'func')
	  (array 'r' 'reduce'				'reduce _ over _ seed _' 'str list auto' 'twoInputFunc')

	'Variables'
	  (array 'r' 'shared'			'shared _' 'menu.sharedVarMenu' 'score')
	  (array ' ' 'setShared'		'set shared _ to _' 'menu.sharedVarMenu auto' 'score' 0)
	  (array ' ' 'increaseShared'	'change shared _ by _' 'menu.sharedVarMenu num' 'score' 1)
	  (array 'r' 'my'				'my _' 'menu.myVarMenu' 'n')
	  (array ' ' 'setMy'			'set my _ to _' 'menu.myVarMenu auto' 'n' 0)
	  (array ' ' 'increaseMy'		'change my _ by _' 'menu.myVarMenu num' 'n' 1)
	  (array ' ' 'local'			'let _ be _' 'var auto' 'var')
	  (array 'r' 'v'				'_' 'menu.localVarMenu' 'n')
	  (array ' ' '='				'set _ to _' 'menu.localVarMenu auto' 'n' 0)
	  (array ' ' '+='				'change _ by _' 'menu.localVarMenu num' 'n' 1)

	'Operators'
	  (array 'r' '+'				'_ + _ : + _ : ...' 'num num num' 10 2 10)
	  (array 'r' '-'				'_ − _' 'num num' 10 2)
	  (array 'r' '*'				'_ × _ : × _ : ...' 'num num num' 10 2 10)
	  (array 'r' '/'				'_ / _' 'num num' 10 2)
	  (array 'r' '%'				'_ mod _' 'num num' 7 5)
	  (array 'r' 'negate'			'− _' 'num' 10)
	  (array 'r' 'rand'				'random _ : to _' 'num num' 10 20)
	  (array 'r' '<'				'_ < _' 'auto auto' 1 2)
	  (array 'r' '<='				'_ <= _' 'auto auto' 1 2)
	  (array 'r' '=='				'_ == _' 'auto auto' 1 2)
	  (array 'r' '!='				'_ != _' 'auto auto' 1 2)
	  (array 'r' '>='				'_ >= _' 'auto auto' 1 2)
	  (array 'r' '>'				'_ > _' 'auto auto' 1 2)
	  (array 'r' 'isBetween'		'is _ between _ and _ ?' 'num num num' 1 1 3)
	  (array 'r' 'and'				'_ and _ : and _ : ...' 'bool bool bool' true false)
	  (array 'r' 'or'				'_ or _ : or _ : ...' 'bool bool bool' true false)
	  (array 'r' 'not'				'not _' 'bool' true)
	  (array 'r' 'booleanConstant'	'_' 'bool' true)
	  (array 'r' 'abs'				'abs _' 'num' -10)
	  (array 'r' 'truncate'			'truncate _' 'num' 1.9)
	  (array 'r' 'round'			'round _ : to _' 'num num' 123.456 0.01)
	  (array 'r' 'floor'			'floor _' 'num' 1.9)
	  (array 'r' 'ceiling'			'ceiling _' 'num' 1.1)
	  (array 'r' 'max'				'max _ : _ : ...' 'num num' 1 2)
	  (array 'r' 'min'				'min _ : _ : ...' 'num num' 1 2)
	  (array 'r' 'clamp'			'clamp _ between _ and _' 'num num num' 12 1 10)
	  (array 'r' 'sqrt'				'sqrt _' 'num' 81)
	  (array 'r' 'isPrime'			'is _ prime?' 'num' 17)
	  (array 'r' 'isAnyClass'		'_ is class _ : or _ : ...' 'auto str.classNameMenu str str str str' 'Hi!' 'String')
	  (array 'r' 'isNil'			'isNil _' 'obj' nil)
	  (array 'r' 'notNil'			'notNil _' 'obj' nil)
	  (array 'r' 'nil'				'nil')
	  (array 'r' 'distanceFromTo'	'distance from x _ y _ to x _ y _' 'num num num num' 0 0 3 4)
	  (array 'r' 'directionFromTo'	'direction from x _ y _ to x _ y _' 'num num num num' 0 0 3 4)
	  (array 'r' 'sin'				'sin _ degrees' 'num' 90)
	  (array 'r' 'cos'				'cos _ degrees' 'num' 90)
	  (array 'r' 'tan'				'tan _ degrees' 'num' 45)
	  (array 'r' 'atan'				'arctan _ _' 'num num' 1 1)
	  (array 'r' 'toRadians'		'to radians _' 'num' 180)
	  (array 'r' 'toDegrees'		'to degrees _' 'num' 3.14159)
	  (array 'r' 'pi'				'pi')
	  (array 'r' 'logBase'			'log _ : base _' 'num num' 100 10)
	  (array 'r' 'raise'			'_ raised to _' 'num num' 10 2)
	  (array 'r' 'e'				'e')
	  (array 'r' 'ln'				'ln _' 'num' 2.718282)
	  (array 'r' 'exp'				'exp _' 'num' 1)
	  (array 'r' 'toFloat'			'to float _' 'num' 10)
	  (array 'r' 'maxInt'			'maxInt')
	  (array 'r' 'minInt'			'minInt')
	  (array 'r' '&'				'_ & _' 'num num' 5 3)
	  (array 'r' '|'				'_ | _' 'num num' 5 3)
	  (array 'r' '^'				'_ ^ _' 'num num' 5 3)
	  (array 'r' '<<'				'_ << _' 'num num' 10 1)
	  (array 'r' '>>'				'_ >> _' 'num num' 10 1)
	  (array 'r' '>>>'				'_ >>> _' 'num num' -1 20)

	'Data'
	  (array 'r' 'list'				'list : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 1 2 3 4 5 6 7 8 9 10)
	  (array 'r' 'dictionary'		'dictionary')

	  (array 'r' 'count'			'count _' 'str')
	  (array 'r' 'isEmpty'			'is _ empty?' 'data')
	  (array 'r' 'contains'			'does _ contain _ ?' 'data auto')

	  (array 'r' 'first'			'first _' 'list')
	  (array 'r' 'last'				'last _' 'list')
	  (array 'r' 'at'				'_ at _' 'auto auto' nil 1)
	  (array ' ' 'atPut'			'set _ at _ to _' 'data auto auto')
	  (array 'r' 'atRandom'			'at random _' 'str' 'abcde')

	  (array ' ' 'add'				'to _ add _' 'data auto')
	  (array ' ' 'addFirst'			'to _ add _ at start' 'list auto')
	  (array ' ' 'addAll'			'to _ add all _' 'data data')
	  (array ' ' 'remove'			'from _ remove _' 'data auto')

	  (array 'r' 'sorted'			'sorted _' 'data')
	  (array 'r' 'shuffled'			'shuffled _ ' 'data')
	  (array 'r' 'reversed'			'reversed _ ' 'data')
	  (array 'r' 'flattened'		'flattened _ ' 'data')

	  (array 'r' 'join'				'join _ _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto')

	  (array 'r' 'copy'				'copy _ ' 'data')
	  (array 'r' 'copyFromTo'		'copy _ from _ : to _' 'list num num' nil 1 2)

// 	  (array 'r' 'withoutAll'		'copy _ without any of _' 'data data')
// 	  (array 'r' 'union'			'_ union _' 'data data')
// 	  (array 'r' 'intersection'		'_ intersection _' 'data data')

//	  (array ' ' 'addAt'			'_ at _ insert _' 'list num auto')
//	  (array ' ' 'removeAt'			'_ at _ remove' 'list num')

	  (array 'r' 'indexOf'			'in _ find _ : after _' 'list auto num' nil nil 0)
	  (array 'r' 'lastIndexOf'		'in _ find last _ : before _' 'list auto num' nil nil 100)

	  (array 'r' 'toList'			'to list _ ' 'data')

	'Words'
	  (array 'r' 'letters'			'letters _' 'str' 'Hello')
	  (array 'r' 'words'			'words _' 'str' 'The owl and the pussycat')
	  (array 'r' 'lines'			'lines _' 'str' 'Line 1
Line 2')
	  (array 'r' 'quoted'			'“ _ ”' 'str' '123')

	  (array 'r' 'join'				'join _ _ : _ : ...' 'str str str' 'Hello, ' 'World!')
	  (array 'r' 'joinStrings'		'join string list _ : separator _' 'list str' nil ' ')

	  (array 'r' 'count'			'count _' 'str' 'GP Rocks!')
	  (array 'r' 'substring'		'substring _ from _ : to _' 'str num num' 'smiles' 2 5)

	  (array 'r' 'space'			'space')
	  (array 'r' 'tab'				'tab')
	  (array 'r' 'newline'			'newline')
	  (array 'r' 'toString'			'to string _ ' 'auto')
	  (array 'r' 'toNumber'			'to number _' 'str' '123')

	  (array 'r' 'toUpperCase'		'to uppercase _' 'str' 'big')
	  (array 'r' 'toLowerCase'		'to lowercase _' 'str' 'SMALL')
	  (array 'r' 'codePoints'		'text to codes _' 'str' 'Cat')
	  (array 'r' 'stringFromCodePoints'	'codes to text _' 'list')

	  (array 'r' 'self_readFile'	'read file _ : binary _' 'str bool' 'fileName.txt' false)
	  (array ' ' 'self_writeFile'	'write file _ _' 'str str' 'fileName.txt' 'testing 1, 2, 3')

	  (array 'r' 'string'			'character _ : ...' 'num' 65)
	  (array 'r' 'canonicalizedWord' 'canonicalize _ ' 'str' 'Hello GP!')

	'Network'
	  (array 'r' 'getData'			'get cloud data user _ key _' 'str str' 'gp' 'test')
	  (array ' ' 'putData'			'put cloud data user _ key _ data _' 'str str str' 'gp' 'test' 'hello!')
	  (array 'r' 'httpGet'			'http host _ : path _ : port _' 'str str num' 'tinlizzie.org' '/' '80')
	  (array 'r' 'jsonStringify'	'json encode _' 'obj')
	  (array 'r' 'jsonParse'		'json decode _' 'str')

	'Table'
	  (array 'r' 'importTableFromFile'	'table from file _ : has headings _ : delimiter _' 'str bool str' 'fileName' true ',')
	  (array 'r' 'uniqueValuesForColumn' 'unique values of _ in column _' 'table auto.columnMenu')
	  (array 'r' 'summarizeColumn'		'summarize _ column _' 'table auto.columnMenu' 'C1')
	  (array 'r' 'filtered'				'filtered _ where _ _ _ : or _ _ _' 'table auto.columnMenu str.comparisonOpMenu auto' nil 'C1' '<' 30)
	  (array 'r' 'sorted'				'sorted _ by column _ : ascending _' 'table auto.columnMenu bool' nil 'C1' true)
	  (array ' ' 'filterInPlace'		'filter _ where _ _ _ : or _ _ _' 'table auto.columnMenu str.comparisonOpMenu auto' nil 'C1' '<' 30)
	  (array ' ' 'sortInPlace'			'sort _ by column _ : ascending _' 'table auto.columnMenu bool' nil 'C1' true)
	  (array ' ' 'viewTable'			'view _ : title _ ' 'table str' nil 'Table')
	  (array 'r' 'count'				'row count _' 'table')
	  (array 'r' 'columnCount'			'column count _' 'table')
	  (array 'r' 'columnNames'			'column names _' 'table')
	  (array 'r' 'firstRowWhere'		'find row of _ where _ is _ : and _ is _ : ...' 'table auto.columnMenu auto auto.columnMenu auto' nil 'C1' 'USA' 'C2' 10)
	  (array 'r' 'table'				'new table with columns : _ : ...' 'str str str str str str' 'C1' 'C2' 'C3' 'C4' 'C5')
	  (array ' ' 'addRow'				'table _ add row _' 'table data')
	  (array ' ' 'renameColumn'			'table _ rename column _ to _' 'table auto.columnMenu str' nil 'C1')
	  (array ' ' 'insertColumnAfter'	'table _ insert column after _ : named _' 'table auto.columnMenu str' nil 'C1')
	  (array ' ' 'removeColumn'			'table _ remove column _' 'table auto.columnMenu' nil 'C1')
	  (array 'r' 'cellAt'				'cell _ row _ col _' 'table auto auto.columnMenu')
	  (array ' ' 'cellAtPut'			'set cell _ row _ col _ to _' 'table auto auto.columnMenu auto')
	  (array ' ' 'exportCSVToFile'		'save _ to file _ : delimiter _' 'table str str' nil nil ',')

	'Motion'
	  (array ' ' 'self_moveInDirection'	'move _ : direction _' 'num num.directionsMenu' 10 0)
	  (array ' ' 'self_changeRotation'	'turn by _' 'num' 15)
	  (array ' ' 'self_setRotation'		'set direction to _' 'num.directionsMenu' 0)
	  (array 'r' 'self_getRotation'		'direction')
	  (array ' ' 'self_setPosition'		'go to x _ y _' 'num num' 0 0)
	  (array ' ' 'self_setX'			'set x position _' 'num' 0)
	  (array ' ' 'self_setY'			'set y position _' 'num' 0)
	  (array 'r' 'self_getX'			'x position')
	  (array 'r' 'self_getY'			'y position')
	  (array ' ' 'self_moveBy'			'move by x _ y _' 'num num' 10 10)
	  (array ' ' 'self_keepInOwner'		'keep on screen')
	  (array ' ' 'self_bounceOffEdge' 'if on edge, bounce')
	  (array ' ' 'self_setDraggable'	'set grabbable _' 'bool' false)
	  (array ' ' 'self_grab'			'grab : _' 'obj')

	'Structure'
	  (array ' ' 'self_instantiate'		'add an instance of _' 'str.classNameMenu auto' 'MyClass' 0)
	  (array 'r' 'self_instantiate'		'new instance of _' 'str.classNameMenu auto' 'MyClass' 0)
	  (array ' ' 'self_delete'			'delete : _' 'obj')
	  (array 'r' 'self_owner'			'owner : of _' 'obj')
	  (array 'r' 'self_stage'			'stage')
	  (array 'r' 'self_parts'			'parts : of _' 'obj')
	  (array ' ' 'self_addPart'			'add part _ : to _' 'obj obj')
	  (array ' ' 'self_placePart'		'place part _ left inset _ top inset _' 'obj num num' nil 10 10)

	'Looks'
	  (array ' ' 'self_setCostume'		'set costume to _' 'menu.imageMenu' 'GP')
	  (array ' ' 'self_setTextCostume'	'set text costume _ : color _ : fontName _ fontSize _' 'auto color str num' 'Hello!' nil 'Arial Bold Italic' 120)
	  (array ' ' 'self_show'			'show')
	  (array ' ' 'self_hide'			'hide')
	  (array ' ' 'self_say'				'say _' 'str' 'Hello!')
	  (array ' ' 'self_sayNothing'		'say nothing')
	  (array ' ' 'self_setScale'		'set scale to _' 'num' 1)
	  (array ' ' 'self_changeScale'		'change scale by _' 'num' 0.5)
	  (array 'r' 'self_getScale'		'scale')
	  (array ' ' 'self_comeToFront'		'come to front')
	  (array ' ' 'self_goBackBy'		'go back by _' 'num' 1)
	  (array ' ' 'self_setTransparency'	'set transparency _' 'num' 50)
	  (array 'r' 'self_getWidth'		'width : of _' 'menu.imageMenu' 'GP')
	  (array 'r' 'self_getHeight'		'height : of _' 'menu.imageMenu' 'GP')
	  (array ' ' 'self_setStageColor'	'set background color _ : image _' 'color menu.imageMenu' nil 'GP')
	  (array 'r' 'self_costume'			'costume : _' 'menu.imageMenu' 'GP')
	  (array ' ' 'self_snapshotCostume'	'snapshot costume : as _' 'str' 'snapshot')
	  (array ' ' 'self_snapshotStage'	'snapshot stage : as _' 'str' 'snapshot')
	  (array ' ' 'self_setPinXY'		'set rotation point x _ y _' 'num num' 0 0)

	'Drawing'
	  (array ' ' 'self_createCostume'	'set width _ height _ : fill _ ' 'num num color' 100 100)
	  (array ' ' 'self_fillWithColor'	'fill _' 'color')
	  (array ' ' 'self_fillRect'		'fill rectangle x _ y _ w _ h _ _ : roundness _' 'num num num num color num' 10 10 50 50 nil 8)
	  (array ' ' 'self_fillCircle'		'fill circle center x _ y _ radius _ _ : border _ _' 'num num num color num color' 50 50 30 nil 4)
	  (array ' ' 'self_drawLine'		'draw line from _ _ to _ _ _ : width _' 'num num num num color num' 0 0 100 150 nil 3)
	  (array ' ' 'self_drawBitmap'		'draw image _ : x _ y _ : scale _ : alpha _' 'menu.imageMenu num num num num' 'GP' 0 0 1 255)
	  (array 'r' 'randomColor'			'random color')
	  (array 'r' 'transparent'			'transparent')
	  (array 'r' 'self_getWidth'		'width : of _' 'menu.imageMenu' 'GP')
	  (array 'r' 'self_getHeight'		'height : of _' 'menu.imageMenu' 'GP')
	  (array ' ' 'self_setFont'			'set font name _ : size _' 'str num' 'Arial' 24)
	  (array 'r' 'fontHeight'			'font height')
	  (array 'r' 'stringWidth'			'string width _' 'str' 'Hello!')
	  (array ' ' 'self_drawText'		'draw text _ x _ y _ _' 'str num num color' 'Hello!' 10 10)
	  (array ' ' 'self_floodFill'		'paint bucket fill x _ y _ _ : threshold _ ' 'num num color num' 50 50 nil 0)

	'Drawing - Paths'
	  (array ' ' 'self_beginPath'		'begin path x _ y _' 'num num' 10 10)
	  (array ' ' 'self_setPathDirection' 'set path direction _ degrees' 'num' 0)
	  (array ' ' 'self_extendPath'		'extend path by _ : curvature _' 'num num' 100 0)
	  (array ' ' 'self_turnPath'		'turn path by _ degrees : radius _' 'num num' 90 0)
	  (array ' ' 'self_addLineToPath'	'to path add line to x _ y _' 'num num' 50 50)
	  (array ' ' 'self_addCurveToPath'	'to path add curve to x _ y _ cx _ cy _' 'num num num num' 50 50 25 0)
	  (array ' ' 'self_strokePath'		'stroke path _ width _ : joint style _ cap style _' 'color num num num' nil 1 0 0)
	  (array ' ' 'self_fillPath'		'fill path _' 'color')

	'Color'
	  (array 'r' 'colorFromSwatch'		'color _' 'color')
	  (array 'r' 'color'				'color r _ g _ b _ : alpha _' 'num num num num' 200 200 200 255)
	  (array 'r' 'gray'					'gray _ : alpha _' 'num num' 200 255)
	  (array 'r' 'randomColor'			'random color')
	  (array 'r' 'transparent'			'transparent')
	  (array 'r' 'red'					'red of _ ' 'color')
	  (array 'r' 'green'				'green of _ ' 'color')
	  (array 'r' 'blue'					'blue of _ ' 'color')
	  (array 'r' 'alpha'				'alpha of _ ' 'color')
	  (array 'r' 'hue'					'hue of _ ' 'color')
	  (array 'r' 'saturation'			'saturation of _ ' 'color')
	  (array 'r' 'brightness'			'brightness of _ ' 'color')
	  (array 'r' 'colorHSV'				'color h _ s _ b _ : alpha _' 'num num num num' 0 1 1 255)

	'Pixels'
	  (array ' ' 'self_createCostume'	'set width _ height _ : fill _ ' 'num num color' 100 100)
	  (array ' ' 'self_copycostume'	'copy costume from _' 'menu.imageMenu' 'GP')
	  (array 'r' 'self_getPixels'	'pixels : from _' 'menu.imageMenu' 'GP')
	  (array 'r' 'self_getPixelXY'	'pixel at x _ y _ : from _ ' 'num num menu.imageMenu' 1 1 'GP')
	  (array 'r' 'getRed'			'red of _' 'pixel' nil)
	  (array 'r' 'getGreen'			'green of _' 'pixel' nil)
	  (array 'r' 'getBlue'			'blue of _' 'pixel' nil)
	  (array ' ' 'setRed'			'set red of _ to _' 'pixel num' nil 255)
	  (array ' ' 'setGreen'			'set green of _ to _' 'pixel num' nil 255)
	  (array ' ' 'setBlue'			'set blue of _ to _' 'pixel num' nil 255)
	  (array ' ' 'setGray'			'set gray of _ to _' 'pixel num' nil 255)
	  (array 'r' 'getX'				'x position of _' 'pixel' nil)
	  (array 'r' 'getY'				'y position of _' 'pixel' nil)
	  (array 'r' 'getColor'			'color of _' 'pixel' nil)
	  (array ' ' 'setColor'			'set color of _ to _' 'pixel color' nil)
	  (array 'r' 'randomColor'		'random color')
	  (array 'r' 'transparent'		'transparent')
	  (array 'r' 'self_getWidth'	'width : of _' 'menu.imageMenu' 'GP')
	  (array 'r' 'self_getHeight'	'height : of _' 'menu.imageMenu' 'GP')
	  (array 'r' 'self_getPixel'	'pixel color at x _ y _ : in _ ' 'num num image' 1 1)
	  (array ' ' 'self_setPixel'	'set pixel color at x _ y _ to _ : in _' 'num num color image' 1 1)

	'Sensing'
	  (array 'r' 'self_mouseX'				'mouse x')
	  (array 'r' 'self_mouseY'				'mouse y')
	  (array 'r' 'handIsDown'				'mouse is down')
	  (array 'r' 'self_directionToMouse'	'direction to mouse')
	  (array 'r' 'self_distanceToMouse'		'distance to mouse')
	  (array 'r' 'self_localMouseX'			'local mouse x')
	  (array 'r' 'self_localMouseY'			'local mouse y')
	  (array 'r' 'keyIsDown'				'key is down _' 'menu.keyDownMenu' 'right arrow')
	  (array 'r' 'stageWidth'				'stage width')
	  (array 'r' 'stageHeight'				'stage height')
	  (array 'r' 'self_directionToSprite'	'direction to _' 'menu.classNameMenu' 'MyClass')
	  (array 'r' 'self_distanceToSprite'	'distance to _' 'menu.classNameMenu' 'MyClass')
	  (array 'r' 'msecsSinceStart'			'timer')
	  (array 'r' 'localDateAndTime'			'date and time')
	  (array 'r' 'self_touching'			'touching _ ?' 'str.touchingMenu' 'edge')
	  (array 'r' 'self_neighbors'			'neighbors : within _ : class _' 'num str.classNameMenu' 0)
	  (array 'r' 'screenColorAt'			'screen color at x _ y _' 'num num' 0 0)
	  (array 'r' 'askUser'					'ask _ : initial answer _' 'str str' 'What is your favorite color?' '')
	  (array 'r' 'selectFromMenu'			'menu selection from _' 'list')
	  (array 'r' 'self_getProperty'			'get _ : of _' 'str.propertyMenu obj' 'n')

	'Pen'
	  (array ' ' 'self_penDown'			'pen down')
	  (array ' ' 'self_penUp'			'pen up')
	  (array ' ' 'self_setPenColor'		'set pen color _' 'color')
	  (array ' ' 'self_setPenSize'		'set pen width _' 'num' 3)
	  (array ' ' 'self_stampCostume'	'stamp costume : transparency _' 'num' 50)
	  (array ' ' 'self_penFillArea'		'pen fill area at x _ y _ : with _' 'num num color' 0 0)
	  (array ' ' 'self_clear'			'clear stamps and pen trails')

	'Sound'
	  (array ' ' 'playSound'			'play sound _' 'menu.soundMenu' 'pop')
	  (array ' ' 'playNote'				'play note _ : seconds _ : instrument _' 'auto num menu.instrumentMenu' 'c' 1 'piano')
	  (array ' ' 'playABC'				'play tune _ : on _ : speed _ : transpose _' 'str menu.instrumentMenu num num' 'ceg [ceg]2' 'piano' 120 5)
	  (array ' ' 'stopAllSounds'		'stop all sounds')
	  (array 'r' 'samplesForSoundNamed'	'samples for _' 'auto.soundMenu' 'pop')
	  (array ' ' 'playSoundSamples'		'play samples _ : rate _' 'array num' nil 100)
	  (array 'r' 'soundInput'			'sound input')
	  (array 'r' 'fftOfSamples'			'frequencies _ : use window _' 'data bool')

	'Music'
	  (array 'r' 'playerForMIDIFile'	'player for MIDI file _' 'str' 'BachPrelude')
	  (array ' ' 'playScore'			'start player _' 'player')
	  (array 'r' 'scoreTime'			'score time player _' 'player')

	  (array 'r' 'trackCount'			'track count _' 'player')
	  (array 'r' 'instrumentNames'		'instrument names')
	  (array 'r' 'instrumentForTrack'	'instrument player _ track _' 'player num' nil 1)
	  (array ' ' 'setInstrumentForTrack' 'set instrument player _ track _ to _' 'player num menu.instrumentMenu' nil 1 'guitar')
	  (array 'r' 'isTrackMuted'			'is muted player _ track _' 'player num' nil 1)
	  (array ' ' 'setTrackMuted'		'set muted player _ track _ to _' 'player num bool' nil 1 true)
	  (array 'r' 'notesForTrack'		'notes of player _ track _' 'player num' nil 1)

	  (array 'r' 'newScoreNote'			'new note start _ key _ loudness _ duration _' 'num num num num' 0 60 80 300)
	  (array 'r' 'startTime'			'start of note _' 'note')
	  (array 'r' 'endTime'				'end of note _' 'note')
	  (array 'r' 'key'					'key of note _' 'note')
	  (array 'r' 'duration'				'duration of note _' 'note')
	  (array 'r' 'velocity'				'loudness of note _' 'note')

	'Serial Port'
	  (array 'r' 'listSerialPorts'		'list serial ports')
	  (array 'r' 'openSerialPort'		'open serial port _ baud rate _' 'str num' '' 115200)
	  (array 'r' 'isOpenSerialPort'		'is serial port _ open?' 'num' 1)
	  (array ' ' 'closeSerialPort'		'close serial port _' 'num' 1)
	  (array 'r' 'readSerialPort'		'read serial port _ : binary _' 'num bool' 1 true)
	  (array ' ' 'writeSerialPort'		'write serial port _ data _' 'num str' 1)

	'File Stream'
	  (array 'r' 'openFilestream'		'open file stream on file _' 'str')
	  (array 'r' 'filestreamReadByte'	'read byte from file stream _' 'filestream')
	  (array 'r' 'filestreamReadLine'	'read line from file stream _' 'filestream')
	  (array ' ' 'closeFilestream'		'close file stream _' 'filestream')

	'Vector Pen'
	  (array 'r' 'self_newVectorPen'	'new vector pen')
	  (array ' ' 'beginPath'			'begin path _ x _ y _' 'pen num num' nil 100 100)
	  (array ' ' 'setHeading'			'set _ direction _ degrees' 'pen num' nil 0)
	  (array ' ' 'goto'					'_ go to x _ y _' 'pen num num' nil 0 0)
	  (array ' ' 'forward'				'move _ by _ : curvature _' 'pen num num' nil 100 0)
	  (array ' ' 'turn'					'turn _ by _ degrees : radius _' 'pen num num' nil 90 0)
	  (array ' ' 'stroke'				'stroke _ _ : width _ : joint _ : cap _' 'pen color num num num' nil nil 1 0 0)
	  (array ' ' 'fill'					'fill _ _' 'pen color')

	'Debugging'
	  (array ' ' 'halt'					'halt : _' 'str')
	  (array ' ' 'error'				'error : _' 'str')
	  (array ' ' 'openExplorer'			'explore _ ' 'auto')
	  (array ' ' 'print'				'console print _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 'Testing 1, 2, 3')
	  (array ' ' 'showText'				'edit text _' 'str' 'Hello, GP!')
	  (array ' ' 'gc'					'collect garbage')
	  (array 'r' 'mem'					'memory usage')
	  (array 'r' 'allInstances'			'all instances of _' 'str' 'String')

	'Developer'
	  (array ' ' 'setBlockColors'		'set block colors _ _ _ _' 'color color color color')
	  (array ' ' 'setBlockTextColor'	'set block text color _' 'color')
	  (array ' ' 'resetBlockColors'		'reset block colors')

	'Generic'
	  (array ' ' 'initialize'			'initialize _' 'this')

	'Macintosh only'
	  (array ' ' 'speak'				'speak _ : voice _ : speed _' 'str menu.voiceNameMenu num' 'Hey, what''s up?' 'Alex' 150)
	  (array ' ' 'stopSpeaking'			'stop speaking')

	'Obsolete'
	  (array 'r' 'self_touchingMouse'	'touching mouse?')
	  (array ' ' 'self_setAlpha'		'set alpha _' 'num' 0.5)
  )
}

to authoringSpecs {
  // Return the global AuthoringSpecs instance.
  if (isNil (global 'authoringSpecs')) {
	setGlobal 'authoringSpecs' (initialize (new 'AuthoringSpecs'))
  }
  return (global 'authoringSpecs')
}
