to td {
  b = (block 'command' (color 4 148 220) (newBlockDefinition 'frobnicate' 'Spam'))
  setGrabRule (morph b 'defer')
  h = (block 'hat' (color 230 168 34) 'define' b) // (blockPrototypeForFunction aFunction)
  addPart (global 'page') h
  go
}

to editDefinition aBlock {
  spec = (blockSpec aBlock)
  if (isNil spec) {return}
  func = (functionNamed (blockOp spec))
  argNames = (argNames func)
  b = (block (blockType (blockType spec)) (color 4 148 220) (newBlockDefinition nil nil spec argNames))
  setGrabRule (morph b 'defer')
  h = (block 'hat' (color 230 168 34) 'define' b) // (blockPrototypeForFunction aFunction)
  addPart (global 'page') h
}

// BYOB - support for custom blocks

defineClass BlockDefinition morph type op sections declarations drawer alignment repeater toggle isGeneric isRepeating isShort

to newBlockDefinition aBlockSpec argNames isGeneric {return (initialize (new 'BlockDefinition') aBlockSpec argNames isGeneric)}

method initialize BlockDefinition aBlockSpec argNames generic {
  if (isNil generic) {generic = false}
  op = (blockOp aBlockSpec)
  type = (blockType (blockType aBlockSpec))
  isGeneric = generic
  isShort = true
  morph = (newMorph this)
  alignment = (newAlignment 'column' 0)
  setVPadding alignment (global 'scale')
  setMorph alignment morph
  initializeRepeater this aBlockSpec
  initializeSections this aBlockSpec sec argNames
  if (hasTopLevelSpec (authoringSpecs) op) { // if op matches a top-level spec, don't allow spec changes
    hideDetails this
  } else {
    showDetails this
  }
  return this
}

to blockType blockSpecType {
  if (blockSpecType == 'r') {
    return 'reporter'
  } (blockSpecType == 'h') {
    return 'hat'
  }
  return 'command'
}

method op BlockDefinition {return op}

method initializeSections BlockDefinition aBlockSpec firstSection argNames {
  if (isNil aBlockSpec) {return}
  for i (count (specs aBlockSpec)) {
    if (and (notNil firstSection) (i == 1)) {
      initializeFromSpec firstSection aBlockSpec argNames i (not isGeneric)
    } else {
      sec = (newBlockSectionDefinition)
      if (i == 1) {
        if isGeneric {
          setMin sec 1
        } else {
          setMin sec 2
        }
      }
      initializeFromSpec sec aBlockSpec argNames i (not isGeneric)
      addPart morph (morph sec)
    }
  }
}

method initializeRepeater BlockDefinition aBlockSpec {
  if (isNil aBlockSpec) {
    isRepeating = false
  } else {
    isRepeating = (repeatLastSpec aBlockSpec)
  }
  drawer = (newBlockDrawer this nil 'vertical')
  repeater = (newAlignment 'centered-line' 0 'bounds')
  setMorph repeater (newMorph repeater)
  if isShort {
    hide (morph repeater)
  }
  setPadding repeater (5 * (global 'scale'))

  if (isMicroBlocks) { return } // suppress the ability to make variadic user-defined blocks for now

  addPart (morph repeater) (morph drawer)

  scale = (global 'scale')
  labelColor = (global 'blockTextColor')
  if (isNil labelColor) { labelColor = (gray 255) }

  txt = (newText 'repeat last section:' 'Arial' (10 * scale) labelColor)
  addPart (morph repeater) (morph txt)

  corner = 5
  toggle = (toggleButton (action 'toggleRepeat' this) (action 'isRepeating' this) (scale * 20) (scale * 13) (scale * corner) (max 1 (scale / 2)) false false)
  addPart (morph repeater) (morph toggle)
}

method isRepeating BlockDefinition {return isRepeating}

method toggleRepeat BlockDefinition {
  isRepeating = (not isRepeating)
  raise morph 'updateBlockDefinition' this
}

method fixLayout BlockDefinition {
  addPart morph (morph repeater) // make sure repeater is the last part
  fixLayout drawer
  fixLayout repeater
  fixLayout alignment
  raise morph 'layoutChanged' this
}

method updateBlockDefinition BlockDefinition {
  raise morph 'updateBlockDefinition' this
}

// expanding and collapsing:

method canExpand BlockDefinition {
  return true

  // only allow expansion if the previous
  // section is no longer empty
  // unused for now

  last = (lastSection this)
  return (or
    (isNil last)
    ((count (parts last)) > 1)
  )
}

method lastSection BlockDefinition {
  if ((count (parts morph)) < 1) {return nil}
  return (at (parts morph) (- (count (parts morph)) 1))
}

method canCollapse BlockDefinition {
  return ((count (parts morph)) > 2)
}

method expand BlockDefinition {
  addPart morph (morph (newBlockSectionDefinition))
  raise morph 'updateBlockDefinition' this
}

method collapse BlockDefinition {
  destroy (at (parts morph) ((count (parts morph)) - 1))
  raise morph 'updateBlockDefinition' this
}

method clicked BlockDefinition {
  if (isNil (ownerThatIsA morph 'Block')) {return false}
  if isShort {
    showDetails this
  } else {
    hideDetails this
  }
  // typesMenu this
  return true
}

method rightClicked BlockDefinition aHand {
  if (isNil (ownerThatIsA morph 'Block')) {return false}
  contextMenu this
  return true
}

method typesMenu BlockDefinition {
  menu = (menu nil (action 'setType' this) true)
  for tp (array 'command' 'reporter') {
    addItem menu '' tp tp (fullCostume (morph (block tp (color 4 148 220) '                    ')))
  }
  popUp menu (global 'page') (left morph) (bottom morph)
}

// MicroBlocks context menu

method contextMenu BlockDefinition {
  menu = (menu nil this)
  addItem menu 'hide block definition' 'hideDefinition'
  addLine menu
  addItem menu 'copy to clipboard' (action 'copyToClipboard' (handler (ownerThatIsA morph 'Block'))) 'copy these blocks to the clipboard'
  addItem menu 'copy to clipboard as URL' (action 'copyToClipboardAsURL' (handler (ownerThatIsA morph 'Block'))) 'copy these blocks to the clipboard as a URL'
  addLine menu
  addItem menu 'save picture of script' 'exportAsImage' 'save a picture of this block definition as a PNG file'
  if (devMode) {
    addLine menu
    addItem menu 'show instructions' (action 'showInstructions' this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' this)
    addItem menu 'show call tree' (action 'showCallTree' this)
  }
  addLine menu
  addItem menu 'delete block definition...' 'deleteBlockDefinition'
  popUp menu (global 'page') (left morph) (bottom morph)
}

method exportAsImage BlockDefinition {
  exportAsImageScaled (handler (ownerThatIsA morph 'Block'))
}

method showInstructions BlockDefinition {
  showInstructions (smallRuntime) (handler (owner (owner morph)))
}

method showCompiledBytes BlockDefinition {
  showCompiledBytes (smallRuntime) (handler (owner (owner morph)))
}

method showCallTree BlockDefinition {
  showCallTree (smallRuntime) (handler (owner (owner morph)))
}

method gpContextMenu BlockDefinition {
  menu = (menu nil this)
  if isShort {
    addItem menu 'show details' 'showDetails'
  } else {
    addItem menu 'hide details' 'hideDetails'
  }
  addLine menu
  for tp (array 'command' 'reporter') {
    addItem menu '' (action 'setType' this tp) tp (fullCostume (morph (block tp (color 4 148 220) '                    ')))
  }
  if (devMode) {
   addItem menu 'set method name' 'setMethodNameUI'
  }
  addLine menu
  addItem menu 'export as image' 'exportAsImage'
  addItem menu 'hide definition' 'hideDefinition'
  addLine menu
  addItem menu 'delete' 'deleteDefinition'
  popUp menu (global 'page') (left morph) (bottom morph)
}

method setType BlockDefinition aTypeString {
  type = aTypeString
  prot = (handler (ownerThatIsA morph 'Block'))
  setField prot 'type' aTypeString
  fixLayoutNow prot
  raise morph 'updateBlockDefinition' this
}

// showing and hiding details

method showDetails BlockDefinition {
  if (hasTopLevelSpec (authoringSpecs) op) { return }
  show (morph repeater)
  for each (parts morph) {
    if (isClass (handler each) 'BlockSectionDefinition') {
      showDetails (handler each)
    }
  }
  fixLayout this
  isShort = false
}

method hideDetails BlockDefinition {
  hide (morph repeater)
  for each (parts morph) {
    if (isClass (handler each) 'BlockSectionDefinition') {
      hideDetails (handler each)
    }
  }
  fixLayout this
  isShort = true
}

method deleteDefinition BlockDefinition {
  blockM = (ownerThatIsA morph 'Block')
  if (notNil blockM) { blockM = (owner blockM) } // get the prototype hat block
  if (and (notNil blockM) (isPrototypeHat (handler blockM))) {
	userDestroy blockM
  }
}

method setMethodNameUI BlockDefinition {
  result = (partThatIs morph 'Text')
  if (notNil result) {
    txt = (text (handler result))
  } else {
    txt = 'selector'
  }
  prompt (page morph) 'method name?' txt 'line' (action 'setMethodName' this)
}

method setMethodName BlockDefinition aName {
  scripter = (scripter (findProjectEditor))
  if (isNil scripter) {return}
  targetClass = (classOf (targetObj scripter))
  if (isNil targetClass) {return}
  oldOp = op

  meth = (methodNamed targetClass op)
  if (isNil meth) {return}
  removeMethodNamed targetClass oldOp
  args = (argNames meth)
  body = (cmdList meth)
  result = (addMethod targetClass aName args body)
  h = (handler (owner morph))
  if (and (isClass h 'Block') ((functionName (function h)) == oldOp)) {
    setField h 'function' result
  }
  op = aName
  renameScriptToAPublicName scripter oldOp aName
}

// Hide block defintion

method hideDefinition BlockDefinition {
  // Remove this method/function definition from the scripting area.

  if (not (isMicroBlocks)) { return (gpHideDefinition this) }

  pe = (findProjectEditor)
  if (isNil pe) { return }
  hideDefinition (scripter pe) op
}

method gpHideDefinition BlockDefinition {
  // Remove this method/function definition from the scripting area.

  pe = (findProjectEditor)
  if (isNil pe) { return }
  scripter = (scripter pe)
  targetClass = (targetClass scripter)
  if (isNil targetClass) { return } // shouldn't happen

  saveScripts scripter
  newScripts = (list)
  for entry (scripts targetClass) {
	cmd = (at entry 3)
	if (isOneOf (primName cmd) 'to' 'method') {
	  if (op != (first (argList cmd))) {
		add newScripts entry
	  }
	} else {
	  add newScripts entry
	}
  }
  setScripts targetClass (toArray newScripts)
  restoreScripts scripter
}

// Delete block defintion

method deleteBlockDefinition BlockDefinition {
  if (not (isMicroBlocks)) { return }

  if (not (confirm (global 'page') nil
  	'Are you sure you want to remove this block definition?')) {
		return
  }
  pe = (findProjectEditor)
  if (isNil pe) { return }
  deleteFunction (scripter pe) op
}

// conversion to spec

method specArray BlockDefinition {
  spec = (list op (blockTypeSpec this) (specString this) (typeString this) (defaults this))
  return (toArray spec)
}

method blockTypeSpec BlockDefinition {
  if (type == 'command') {
    return ' '
  }
  return (at type 1)
}

method specString BlockDefinition {
  spec = ''
  delim = ''
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'BlockSectionDefinition') {
      spec = (join spec delim (specString part))
      delim = ' : '
    }
  }
  if isRepeating {
    spec = (join spec ' : ...')
  }
  return spec
}

method typeString BlockDefinition {
  spec = ''
  delim = ''
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'BlockSectionDefinition') {
      spec = (join spec delim (typeString part))
      delim = ' '
    }
  }
  return spec
}

method defaults BlockDefinition {
  spec = (list)
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'BlockSectionDefinition') {
      addDefaultsTo part spec
    }
  }
  return (toArray spec)
}

method inputNames BlockDefinition {
  parms = (list)
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'BlockSectionDefinition') {
      addInputNamesTo part parms
    }
  }
  return (toArray parms)
}

method newInputName BlockDefinition {
  // answer a default input name that isn't already taken
  already = (inputNames this)
  metasyntactic = (array 'foo' 'bar' 'baz' 'quux' 'garply' 'spam' 'frob' 'corge' 'grault' 'waldo' 'ham' 'eggs' 'plugh' 'fred' 'wibble' 'wobble' 'flob' 'inp' 'parm' 'blah' 'blubb')
  for each metasyntactic {
    if (not (contains already each)) {
      return each
    }
  }
  return (join 'input #' (toString (count already)))
}

defineClass BlockSectionDefinition morph drawer alignment minElements

to newBlockSectionDefinition minElements {return (initialize (new 'BlockSectionDefinition'))}

method initialize BlockSectionDefinition {
  minElements = 0
  morph = (newMorph this)
  drawer = (newBlockDrawer this)
  alignment = (newAlignment 'centered-line' 0 'bounds')
  setPadding alignment (5 * (global 'scale'))
  setMorph alignment morph
  fixLayout this
  return this
}

method setMin BlockSectionDefinition num {
  minElements = num
}

method initializeFromSpec BlockSectionDefinition blockSpec argNames index isMethod {
  max = (count (specs blockSpec))
  if (index <= max) {
    specString = (at (specs blockSpec) index)
  } else {
    specString = (at (specs blockSpec) max)
  }

  slotIndex = 1
  for i (index - 1) {
    if (i > max) {
      slotIndex += (countInputSlots blockSpec (at (specs blockSpec) max))
    } else {
      slotIndex += (countInputSlots blockSpec (at (specs blockSpec) i))
    }
  }

  for w (words specString) {
    if ('_' == w) {
      addInputSlot this blockSpec slotIndex argNames
      slotIndex += 1
    } else {
      addLabelText this w
    }
  }
  fixLayout drawer
  fixLayout this
}

method fixLayout BlockSectionDefinition {
  addPart morph (morph drawer) // make sure drawer is the last part
  fixLayout alignment
}

// expanding and collapsing:

method canExpand BlockSectionDefinition {return true}

method canCollapse BlockSectionDefinition {
  return ((count (parts morph)) > (minElements + 1))
}

method expand BlockSectionDefinition {
  lastIdx = ((count (parts morph)) - 1)
  if (lastIdx > 0) {
    last = (at (parts morph) lastIdx)
    if (isClass (handler last) 'Text') {
      addInput this
      return
    }
  }
  expansionMenu this
}

method collapse BlockSectionDefinition {
  destroy (at (parts morph) ((count (parts morph)) - 1))
  fixLayout drawer
  fixLayout this
  raise morph 'updateBlockDefinition' this
}

method expansionMenu BlockSectionDefinition {
  menu = (menu nil this)
  addItem menu 'label' 'addLabel'
  addItem menu 'input' 'addInput'
  popUp menu (global 'page') (left (morph drawer)) (bottom (morph drawer))
}

// showing and hiding details

method showDetails BlockSectionDefinition {
  show (morph drawer)
  fixLayout drawer
  for each (parts morph) {
	h = (handler each)
    if (isClass h 'Block') {
      for element (parts each) {
        if (isClass (handler element) 'InputDeclaration') {
          show element
        }
      }
      fixLayoutNow h
    } (isClass h 'Text') {
      setEditRule h 'line'
      setGrabRule each 'ignore'

    }
  }
  fixLayout this
}

method hideDetails BlockSectionDefinition {
  hide (morph drawer)
  fixLayout drawer
  for each (parts morph) {
	h = (handler each)
    if (isClass h 'Block') {
      for element (parts each) {
        if (isClass (handler element) 'InputDeclaration') {
          hide element
        }
      }
      fixLayoutNow h
    } (isClass h 'Text') {
      setEditRule h 'static'
      setGrabRule each 'defer'
    }
  }
  fixLayout this
}

// more

method addLabel BlockSectionDefinition {
  txt = (labelText this 'label')
  setEditRule txt 'line'
  addPart morph (morph txt)
  fixLayout drawer
  fixLayout this
  page = (page morph)
  if (notNil page) {
    stopEditingUnfocusedText (hand page)
    edit (keyboard page) txt 1
  }
  selectAll txt
  raise morph 'updateBlockDefinition' this
}

method addLabelText BlockSectionDefinition aString {
  // private
  if (aString == (newline)) {
    aString = '#BR#'
  }
  txt = (labelText this aString)
  if (not (isClass txt 'SVGImage')) { 
  	setEditRule txt 'line'
  }
  addPart morph (morph txt)
}

method addInput BlockSectionDefinition {
  def = (ownerThatIsA morph 'BlockDefinition')
  if (isNil def) {
    name = 'input'
  } else {
    name = (newInputName (handler def))
  }
  inp = (toBlock (newReporter 'v' name))
  typ = (newInputDeclaration 'auto' '10')
  setGrabRule (morph inp) 'template'
  addPart (morph inp) (morph typ)
  add (last (getField inp 'labelParts')) typ
  addPart morph (morph inp)
  raise morph 'updateBlockDefinition' this
}

method textChanged BlockSectionDefinition {
  // called editing a text field is complete
  raise morph 'updateBlockDefinition' this
}

method textEdited BlockSectionDefinition {
  // called after every character
  fixLayout this
}

method addInputSlot BlockSectionDefinition blockSpec slotIndex argNames {
  // private
  info = (slotInfoForIndex blockSpec slotIndex)
  slotType = (at info 1)
  default = (at info 3) // hint
  menuSelector = (at info 4)

  if (contains (array 'num' 'str' 'auto' 'menu' 'var') slotType) {
    if (isNil default) {
      default = (at info 2)
    }
  } ('bool' == slotType) {
    default = (at info 2)
    if (isNil default) {default = true}
  } (contains (array 'color' cmd) slotType) {
    default = nil
  }

  if (or (isNil argNames) ((count argNames) < slotIndex)) {
    argName = 'args'
  } else {
    argName = (at argNames slotIndex)
  }

  inp = (toBlock (newReporter 'v' argName))
  typ = (newInputDeclaration slotType default)
  hide (morph typ)
  setGrabRule (morph inp) 'template'
  addPart (morph inp) (morph typ)
  add (last (getField inp 'labelParts')) typ
  fixLayoutNow inp
  addPart morph (morph inp)
  fixLayout this
}

method labelText BlockSectionDefinition aString {
  lbl = (labelText (new 'Block') aString)
  setGrabRule (morph lbl) 'ignore'
  return lbl
}

// spec conversion

method specString BlockSectionDefinition {
  spec = ''
  delim = ''
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'Text') {
	  // remove colons from label (colons are reserved for marking optional parameters in spec)
	  label = (joinStrings (copyWithout (letters (text part)) ':'))
	  if (label != (text part)) { setText part label }
      spec = (join spec delim label)
      delim = ' '
    } (isClass part 'Block') { // input
      spec = (join spec delim '_')
      delim = ' '
    }
  }
  return spec
}

method typeString BlockSectionDefinition {
  spec = ''
  delim = ''
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'Block') { // input
      typeInfo = (handler (last (parts each)))
      spec = (join spec delim (typeString typeInfo))
      delim = ' '
    }
  }
  return spec
}

method addDefaultsTo BlockSectionDefinition aList {
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'Block') { // input
      typeInfo = (handler (last (parts each)))
      add aList (defaultValue typeInfo)
    }
  }
}

method addInputNamesTo BlockSectionDefinition aList {
  for each (parts morph) {
    part = (handler each)
    if (isClass part 'Block') { // input
      add aList (first (argList (expression part)))
    }
  }
}

defineClass InputDeclaration morph type typeString default trigger alignment

to newInputDeclaration type default {
  return (initialize (new 'InputDeclaration') type default)
}

method initialize InputDeclaration typeStr defaultValue {
  morph = (newMorph this)
  alignment = (newAlignment 'centered-line' 0 'bounds')
  setPadding alignment (2 * (global 'scale'))
  setMorph alignment morph

  type = (element this typeStr)
  typeString = typeStr
  setContents type defaultValue
  default = defaultValue
  addPart morph (morph type)

  trigger = (downArrowButton this (action 'typesMenu' this))
  addPart morph (morph trigger)

  fixLayout this
  return this
}

method downArrowButton InputDeclaration action {
  // draw down arrow
  w = (12 * (blockScale))
  h = (7 * (blockScale))
  inset = (2 * (blockScale))
  bm = (newBitmap (w + (2 * inset)) (h + (2 * inset)))
  fillArrow (newShapeMaker bm) (rect inset inset w h) 'down' (gray 0)

  // create and return button
  btn = (new 'Trigger' (newMorph) action)
  setTransparentTouch (morph btn) true
  setHandler (morph btn) btn
  replaceCostumes btn bm bm bm
  return btn
}

method setType InputDeclaration typeStr defaultValue {
  if (isNil defaultValue) {
    if (isOneOf typeStr 'auto' 'num') {
      defaultValue = 10
    } ('str' == typeStr) {
      defaultValue = 'text'
    } ('bool' == typeStr) {
      defaultValue = true
    }
  }
  removeAllParts morph
  type = (element this typeStr)
  typeString = typeStr
  default = defaultValue
  setContents type defaultValue
  addPart morph (morph type)

  trigger = (downArrowButton this (action 'typesMenu' this))
  addPart morph (morph trigger)

  fixLayout this
  raise morph 'layoutChanged'
  raise morph 'updateBlockDefinition' this
}

method setDefault InputDeclaration defaultValue {
  // the default value has been changed by the user

  default = defaultValue
  raise morph 'updateBlockDefinition' this
}

method typeString InputDeclaration {
  if (and ('any' == typeString) ('static' == (editRule (getField type 'text')))) {
    return default
  }
  return typeString
}

method defaultValue InputDeclaration {return default}

method fixLayout InputDeclaration {
  fixLayout alignment
}

method element InputDeclaration typeStr blockColor  {
  // adapted from BlockSpec >> inputSlot
  if (isNil typeStr) {typeStr = type}
  if (isNil blockColor) {blockColor = (blockColorForOp (authoringSpecs) 'if')}
  editRule = 'static'
  slotContent = typeStr
  if ('num' == typeStr) {
    editRule = 'numerical'
    slotContent = 42
  }
  if ('str' == typeStr) {
    editRule = 'editable'
    slotContent = 'text'
  }
  if ('auto' == typeStr) {
    editRule = 'auto'
    slotContent = 'auto'
  }
  if ('bool' == typeStr) {
    slotContent = true
    return (newBooleanSlot true)
  }
  if ('color' == typeStr) {
    return (newColorSlot)
  }
  if ('menu' == typeStr) {
    slotContent = 'menu'
  }
  if ('cmd' == typeStr) {
    return (newCommandSlot blockColor)
  }
  if ('var' == typeStr) {
    rep = (toBlock (newReporter 'v' 'v'))
    setGrabRule (morph rep) 'defer'
    return rep
  }
  return (newInputSlot slotContent editRule blockColor)
}

method typesMenu InputDeclaration {
  // slot types: 'auto' 'num' 'str' 'bool' 'color' 'cmd' 'var' 'menu'
  menu = (menu nil (action 'setType' this) true)
  addItem menu 'number/string' 'auto' 'editable number or string'
  addItem menu '' 'bool' 'boolean switch' (fullCostume (morph (element this 'bool')))
  addItem menu '' 'color' 'color patch' (fullCostume (morph (element this 'color')))
  if (devMode) {
    addLine menu
    addItem menu 'number only' 'num'
    addItem menu 'string only' 'str'
  }
  popUp menu (global 'page') (left morph) (bottom morph)
}
