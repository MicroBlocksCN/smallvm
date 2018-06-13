// editable input slot for blocks

defineClass InputSlot morph text contents scale color menuSelector isStatic isAuto isID

to newInputSlot default editRule blockColor menuSelector {
  if (isNil default) {default = ''}
  if (isNil editRule) {editRule = 'line'}
  return (initialize (new 'InputSlot') default editRule blockColor menuSelector)
}

method initialize InputSlot default editRule blockColor slotMenu {
  isID = false
  fontName = 'Arial'
  fontSize = 10
  if (global 'stealthBlocks') {
  	fontName = 'Verdana'
  	fontSize = 12
  }
  scale = (global 'scale')
  morph = (newMorph this)
  text = (newText (toString default) fontName (scale * fontSize))
  addPart morph (morph text)
  if ('auto' == editRule) {
	// 'auto' slots switch between number or string depending on their contents
	editRule = 'line'
	isAuto = true
  } else {
	isAuto = false
  }
  setEditRule text editRule
  if (editRule == 'numerical') {
    setBorders text (scale * 5) 0
  } else {
    setBorders text (scale * 3) scale
  }
  if (global 'stealthBlocks') {
    setBorders text (stealthLevel (scale * 3) 0) (stealthLevel scale 0)
  }
  if (editRule == 'static') {
    contents = default
    if (notNil blockColor) { color = (lighter blockColor 75) }
  }
  if ((or (contents == true) (contents == false))) {
    menuSelector = 'boolMenu'
  } else {
    menuSelector = slotMenu
  }
  isStatic = (isOneOf menuSelector 'sharedVarMenu' 'myVarMenu' 'localVarMenu' 'allVarsMenu' 'propertyMenu')
  fixLayout this
  return this
}

method morph InputSlot {return morph}
method setID InputSlot bool {isID = bool}

method contents InputSlot {
  if ((editRule text) == 'numerical') {return (toNumber (text text))}
  if (isAuto == true) {
	if (representsANumber (text text)) {
	  num = (toNumber (text text) nil)
	  if (notNil num) { return num }
	}
	return (text text)
  }
  if ((editRule text) == 'static') {
    if isID {return contents}
    if (isNil menuSelector) { return nil } // default is just a hint; value is nil
    return contents
  }
  return (text text)
}

method setContents InputSlot data {
  contents = data
  if ((or (true == contents) (false == contents))) {
    menuSelector = 'boolMenu'
  }
  setText text (toString data)
  textChanged this
  raise morph 'inputContentsChanged' this // experimental for script editor focus
}

method fixLayout InputSlot {
  h = (height (morph text))
  w = (width (morph text))
  if (notNil menuSelector) {w += (fontSize text)} // leave room for down-arrow
  setPosition (morph text) (left morph) (top morph)
  setExtent morph w h
  raise morph 'layoutChanged' this
}

method redraw InputSlot {
  bm = (newBitmap (width morph) (height morph))
  pen = (newShapeMaker bm)

  isNumber = ((editRule text) == 'numerical')
  if (and (isAuto == true) (representsANumber (text text))) {
    isNumber = (notNil (toNumber (text text) nil))
  }

  if (global 'flatBlocks') {
    border = 0
  } else {
    border = (max 1 (scale / 2))
  }

  if isNumber {
    h = (height morph)
    c = (color 255 255 255)
    if (global 'stealthBlocks') {setAlpha c (stealthLevel 255 0)}
	drawButton pen 0 0 (width morph) h c ((h / 2) - 1) border true
  } ((editRule text) == 'static') {
    c = (color 220 220 220)
    if (notNil color) { c = color }
    if (global 'stealthBlocks') {setAlpha c (stealthLevel 255 0)}
	drawButton pen 0 0 (width morph) (height morph) c scale border true
  } else {
    c = (color 255 255 255)
    if (global 'stealthBlocks') {setAlpha c (stealthLevel 255 0)}
	drawButton pen 0 0 (width morph) (height morph) c scale border true
  }
  if (notNil menuSelector) { // draw down-arrow
    border = scale
    w = (fontSize text)
    h = (w / 2)
    x = ((width bm) - w)
    y = ((height morph) / 2)
    clr = (gray 0)
	if (global 'stealthBlocks') {
	  clr = (gray (stealthLevel 0 180))
	}
	fillArrow pen (rect (x + border) y (w - (border * 2)) (h - border)) 'down' clr
  }
  setCostume morph bm
}

// events

method layoutChanged InputSlot {fixLayout this}

method textChanged InputSlot {
  if (isAuto == true) {
    scale = (global 'scale')
    isNumber = (and (representsANumber (text text)) (notNil (toNumber (text text) nil)))
    if isNumber {
      setBorders text (scale * 5) 0
    } else {
      setBorders text (scale * 3) scale
    }
    if (global 'stealthBlocks') {setBorders text (stealthLevel (scale * 3) 0) (stealthLevel scale 0)}
    redraw this
  }
  raise morph 'inputChanged' this
}

method clicked InputSlot aHand {
  if (notNil menuSelector) {
    if (or ((x aHand) >= ((right morph) - (fontSize text))) isStatic) {
	  menu = (call menuSelector this)
	  if (notNil menu) { popUpAtHand menu (page aHand) }
      return true
    }
  }
  return false
}

method clickedForEdit InputSlot aText {selectAll aText}

method scrubAnyway InputSlot aText {
  if (and (isAuto == true) (representsANumber (text text)) (notNil (toNumber (text aText) nil))) {
    startScrubbing aText
  }
}

method wantsDropOf InputSlot aHandler {
    return (isClass aHandler 'Text')
}

method justReceivedDrop InputSlot aText {
  setText text (text aText)
  destroy (morph aText)
}

// menus

method boolMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'true' true
  addItem menu 'false' false
  return menu
}

method directionsMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'right (0)' 0
  addItem menu 'left (180)' 180
  addItem menu 'up (90)' 90
  addItem menu 'down (-90)' -90
  return menu
}

method imageMenu InputSlot {
  editorM = (ownerThatIsA morph 'ProjectEditor')
  if (isNil editorM) { return }
  menu = (menu nil (action 'setContents' this) true)
  for img (images (project (handler editorM))) {
	addItem menu (name img)
  }
  return menu
}

method soundMenu InputSlot {
  editorM = (ownerThatIsA morph 'ProjectEditor')
  if (isNil editorM) { return }
  menu = (menu nil (action 'setContents' this) true)
  for snd (sounds (project (handler editorM))) {
	addItem menu (name snd)
  }
  return menu
}

method instrumentMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  for instrName (instrumentNames (newSampledInstrument 'piano')) {
	addItem menu instrName
  }
  return menu
}

method classNameMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  for cl (classes) {
    if (isUserDefined cl) {
	  addItem menu (className cl)
	}
  }
  return menu
}

method touchingMenu InputSlot {
  menu = (classNameMenu this)
  addLine menu
  addItem menu 'any class'
  addLine menu
  addItem menu 'edge'
  addItem menu 'mouse'
  return menu
}

method keyDownMenu InputSlot {
  return (keyMenu this true)
}

method keyMenu InputSlot forKeyDown {
  if (isNil forKeyDown) { forKeyDown = false }
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'space'
  addItem menu 'delete'
  addLine menu
  addItem menu 'right arrow'
  addItem menu 'left arrow'
  addItem menu 'down arrow'
  addItem menu 'up arrow'
  addLine menu
  for k (letters '0123456789') { addItem menu k }
  addLine menu
  for k (letters 'abcdefghijklmnopqrstuvwxyz') { addItem menu k }
  addLine menu
  if forKeyDown { // shift keys don't generate keyDown events
	addItem menu 'shift'
  } else {
	addItem menu 'any'
  }
  return menu
}

method sharedVarMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { scripter = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (isNil scripter) { return menu }
  varNames = (copyWithout (variableNames (targetModule (handler scripter))) 'extensions')
  for varName varNames {
	addItem menu varName varName
  }
  return menu
}

method myVarMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)

  scripter = (ownerThatIsA morph 'Scripter')
  if (notNil scripter) {
    targetObj = (targetObj (handler scripter))
	if (notNil targetObj) {
      for varName (fieldNames (classOf targetObj)) {
		if ('morph' != varName) {
		  addItem menu varName varName
		}
      }
	}
  }
  return menu
}

method localVarMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)

  myBlock = (handler (ownerThatIsA morph 'Block'))
  localVars = (collectLocals (expression (topBlock myBlock)))
  for field (fieldNames (classOf targetObj)) { remove localVars field }
  if (notEmpty localVars) {
	localVars = (sorted (keys localVars))
	for varName localVars {
	  addItem menu varName varName
	}
  }
  return menu
}

method allVarsMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)

  // shared vars
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { scripter = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (notNil scripter) {
	varNames = (copyWithout (variableNames (targetModule (handler scripter))) 'extensions')
	for varName varNames {
	  addItem menu varName varName
	}
	if ((count varNames) > 0) { addLine menu }
  }

  // local vars
  myBlock = (handler (ownerThatIsA morph 'Block'))
  localVars = (collectLocals (expression (topBlock myBlock)))
  for field (fieldNames (classOf targetObj)) { remove localVars field }
  if (notEmpty localVars) {
	localVars = (sorted (keys localVars))
	for varName localVars {
	  addItem menu varName varName
	}
  }
  return menu
}

method columnMenu InputSlot {
  // Menu of column names for a table.

  // Look for a table in a field variable
  scripter = (ownerThatIsA morph 'Scripter')
  if (notNil scripter) {
    targetObj = (targetObj (handler scripter))
	myBlock = (handler (ownerThatIsA morph 'Block'))
	myTable = (valueOfFirstVarReporter this myBlock targetObj)
  }
  menu = (menu nil (action 'setContents' this) true)
  if (notNil myTable) {
	for colName (columnNames myTable) {
	  addItem menu colName colName
	}
  } else {
	for i 10 {
	  colName = (join 'C' i)
	  addItem menu colName colName
	}
  }
  return menu
}

method propertyMenu InputSlot {
  // Menu of property names for a sprite.

  // Look for a sprite in a field variable
  scripter = (ownerThatIsA morph 'Scripter')
  if (notNil scripter) {
    targetObj = (targetObj (handler scripter))
	myBlock = (handler (ownerThatIsA morph 'Block'))
	mySprite = (valueOfFirstVarReporter this myBlock targetObj)
	if (isNil mySprite) { mySprite = targetObj }
  }
  menu = (menu nil (action 'setContents' this) true)
  if (hasField mySprite 'morph') { // sprite properties
	for propName (array 'x' 'y') {
	  addItem menu propName propName
	}
	addLine menu
  }
  if (notNil mySprite) {
	for fieldName (fieldNames (classOf mySprite)) {
	  if (fieldName != 'morph') { addItem menu fieldName fieldName }
	}
  }
  return menu
}

method valueOfFirstVarReporter InputSlot aBlock targetObj {
  for arg (argList (expression aBlock)) {
	if (isClass arg 'Reporter') {
	  op = (primName arg)
	  if (isOneOf op 'v' 'my') {
		varName = (first (argList arg))
		if (hasField targetObj varName) {
		  return (getField targetObj varName)
		}
	  } (isOneOf op 'shared' 'global') {
		varName = (first (argList arg))
		return (global varName)
	  }
	}
  }
  return nil
}

method comparisonOpMenu InputSlot {
  // Menu of common comparison operators.

  menu = (menu nil (action 'setContents' this) true)
  for op (array '<' '<=' '=' '!=' '>' '>=') {
	addItem menu op op
  }
  return menu
}

method voiceNameMenu InputSlot {
  voiceNames = (list 'Agnes' 'Albert' 'Alex' 'Alice' 'Allison' 'Alva' 'Amelie' 'Anna' 'Ava' 'Bad News'
  	'Bahh' 'Bells' 'Boing' 'Bruce' 'Bubbles' 'Carmit' 'Cellos' 'Damayanti' 'Daniel' 'Deranged' 'Diego'
	'Ellen' 'Fiona' 'Fred' 'Good News' 'Hysterical' 'Ioana' 'Joana' 'Junior' 'Kanya' 'Karen' 'Kathy' 'Kyoko'
	'Laura' 'Lekha' 'Luciana' 'Maged' 'Mariska' 'Mei-Jia' 'Melina' 'Milena' 'Moira' 'Monica' 'Nora'
	'Paulina' 'Pipe Organ' 'Princess' 'Ralph' 'Samantha' 'Sara' 'Satu' 'Sin-ji' 'Susan' 'Tessa' 'Thomas'
	'Ting-Ting' 'Tom' 'Trinoids' 'Veena' 'Vicki' 'Victoria' 'Whisper' 'Xander' 'Yelda' 'Yuna'
	'Zarvox' 'Zosia' 'Zuzana')

  menu = (menu nil (action 'setContents' this) true)
  for v voiceNames {
	addItem menu v v
  }
  return menu
}

// context menu - type switching

method rightClicked InputSlot aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method contextMenu InputSlot {
  menu = (menu 'Input type:')
  addSlotSwitchItems this menu
  return menu
}

method addSlotSwitchItems InputSlot aMenu {
  rule = (editRule text)
  if isAuto {
	addItem aMenu 'string only' (action 'switchType' this 'editable')
	addItem aMenu 'number only' (action 'switchType' this 'numerical')
  } ('numerical' == rule) {
	addItem aMenu 'string only' (action 'switchType' this 'editable')
	addItem aMenu 'string or number' (action 'switchType' this 'auto')
  } else {
	addItem aMenu 'number only' (action 'switchType' this 'numerical')
	addItem aMenu 'string or number' (action 'switchType' this 'auto')
  }
}

method switchType InputSlot editRule {
  dta = (contents this)
  if (editRule == 'auto') {
	isAuto = true
	setEditRule text 'line'
	dta = (toString dta)
  } else {
	isAuto = false
	setEditRule text editRule
	if (editRule == 'numerical') {
	  dta = (toNumber dta)
	} else {
	  dta = (toString dta)
	}
  }
  setContents this dta
}

// replacement rule

to isReplaceableByReporter anInput {return true}
method isReplaceableByReporter InputSlot {return (not isStatic)}
method setIsStatic InputSlot bool {isStatic = bool}

// keyboard accessability hooks

method trigger InputSlot returnFocus {
  if (notNil menuSelector) {
    menu = (call menuSelector this)
    setField menu 'returnFocus' returnFocus
    popUp menu (page morph) (left morph) (bottom morph)
  } ('static' != (editRule text)) {
    edit (keyboard (page morph)) text 1
    selectAll text
  } else {
    redraw returnFocus
  }
}
