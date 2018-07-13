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
  fixLayout this
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
  addPart (morph repeater) (morph drawer)

  scale = (global 'scale')
  if (global 'stealthBlocks') {
    labelColor = (gray (stealthLevel 255 0))
  } else {
    labelColor = (global 'blockTextColor')
    if (isNil labelColor) { labelColor = (gray 255) }
  }
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
  redraw drawer
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
  fixLayout this
  raise morph 'updateBlockDefinition' this
}

method collapse BlockDefinition {
  destroy (at (parts morph) (- (count (parts morph)) 1))
  fixLayout this
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

// method doubleClicked BlockDefinition {
//    if (isNil (ownerThatIsA morph 'Block')) {return false}
//    hideDetails this
//    return true
// }

method typesMenu BlockDefinition {
  menu = (menu nil (action 'setType' this) true)
  for tp (array 'command' 'reporter') {
    addItem menu '' tp tp (fullCostume (morph (block tp (color 4 148 220) '                    ')))
  }
  popUp menu (global 'page') (left morph) (bottom morph)
}

method contextMenu BlockDefinition {
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
  redraw prot
  fixLayout prot
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

method exportAsImage BlockDefinition {
  blockM = (ownerThatIsA morph 'Block')
  if (notNil blockM) { blockM = (owner blockM) } // get the prototype hat block
  if (or (isNil blockM) (not (isPrototypeHat (handler blockM)))) { return }
  fName = (uniqueNameNotIn (listFiles (gpFolder)) 'scriptImage' '.png')
  fName = (fileToWrite fName '.png')
  if ('' == fName) { return }
  if (not (endsWith fName '.png')) { fName = (join fName '.png') }
  gc
  bnds = (fullBounds blockM)
  bm = (newBitmap (width bnds) (height bnds))
  draw2 blockM bm (- (left bnds)) (- (top bnds))
  pixelsPerInch = (72 * (global 'scale'))
  writeFile fName (encodePNG bm pixelsPerInch)
}

method hideDefinition BlockDefinition {
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
// 	  if (or (not isMethod) (slotIndex > 1)) {
// print 'suppressing "this" in block definition' // xxx
		addInputSlot this blockSpec slotIndex argNames
//       }
      slotIndex += 1
    } else {
      addLabelText this w
    }
  }
  redraw drawer
  fixLayout this
}

method fixLayout BlockSectionDefinition {
  addPart morph (morph drawer) // make sure drawer is the last part
  fixLayout alignment
  def = (ownerThatIsA morph 'BlockDefinition')
  if (notNil def) {fixLayout (handler def)}
}

method layoutChanged BlockSectionDefinition {fixLayout this}

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
  destroy (at (parts morph) (- (count (parts morph)) 1))
  redraw drawer
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
  for each (parts morph) {
    if (isClass (handler each) 'Block') {
      for element (parts each) {
        if (isClass (handler element) 'InputDeclaration') {
          show element
        }
      }
      fixLayout (handler each)
    } (isClass (handler each) 'Text') {
      setEditRule (handler each) 'line'
      setGrabRule each 'ignore'

    }
  }
  fixLayout this
}

method hideDetails BlockSectionDefinition {
  hide (morph drawer)
  for each (parts morph) {
    if (isClass (handler each) 'Block') {
      for element (parts each) {
        if (isClass (handler element) 'InputDeclaration') {
          hide element
        }
      }
      fixLayout (handler each)
    } (isClass (handler each) 'Text') {
      setEditRule (handler each) 'static'
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
  redraw drawer
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
  txt = (labelText this aString)
  setEditRule txt 'line'
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
  fixLayout inp
  addPart morph (morph inp)
  redraw drawer
  fixLayout this
  raise morph 'updateBlockDefinition' this
}

method textChanged BlockSectionDefinition {
  raise morph 'updateBlockDefinition' this
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
  fixLayout inp
  addPart morph (morph inp)
}

method labelText BlockSectionDefinition aString {
  scale = (global 'scale')
  fontName =  'Verdana Bold'
  fontSize = (11 * scale)
  off = (scale / 2)
  if (global 'stealthBlocks') {
    labelColor = (gray (stealthLevel 255 0))
    if ((red labelColor) < 100) {
      fontName = (first (words fontName))
      fontSize += (2 * scale)
    }
  } else {
    labelColor = (global 'blockTextColor')
    if (isNil labelColor) { labelColor = (gray 255) }
  }
  lbl = (newText aString fontName fontSize labelColor nil (darker labelColor 80) (off * -1) (off * -1) nil nil nil nil (global 'flatBlocks'))
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
      spec = (join spec delim (text part))
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


defineClass InputType morph type

to newInputType type {
  return (initialize (new 'InputType') type)
}

method initialize InputType typeString {
  if (isNil typeString) {typeString = 'auto'}
  morph = (newMorph this)
  setTransparentTouch morph true
  setScale morph 0.8
  setType this typeString
  return this
}

method setType InputType typeString {
  type = typeString
  redraw this
  raise morph 'layoutChanged'
}

method redraw InputType {
  setCostume morph (fullCostume (morph (element this)))
}

method clicked InputType {return false}

method element InputType typeString blockColor  {
  // adapted from BlockSpec >> inputSlot
  if (isNil typeString) {typeString = type}
  if (isNil blockColor) {blockColor = (blockColorForOp (authoringSpecs) 'if')}
  slotContent = typeString
  return (newInputSlot slotContent 'static' blockColor)
}


defineClass InputDeclaration morph type typeString default trigger alignment

to newInputDeclaration type default {
  return (initialize (new 'InputDeclaration') type default)
}

method initialize InputDeclaration typeStr defaultValue {
  morph = (newMorph this)
  alignment = (newAlignment 'centered-line' 0 'bounds')
  setPadding alignment (5 * (global 'scale'))
  setMorph alignment morph

  type = (element this typeStr)
  typeString = typeStr
  setContents type defaultValue
  default = defaultValue
  addPart morph (morph type)

  trigger = (downArrowButton (color) (action 'typesMenu' this))
  addPart morph (morph trigger)

  fixLayout this
  return this
}

method setType InputDeclaration typeStr defaultValue {
  if (isNil defaultValue) {
    if ('auto' == typeStr) {
      defaultValue = 10
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

  trigger = (downArrowButton (color) (action 'typesMenu' this))
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
  block = (ownerThatIsA morph 'Block')
  if (notNil block) {fixLayout (handler block)}
}

method layoutChanged InputDeclaration {fixLayout this}

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
    if (not (global 'stealthBlocks')) {
      return (newBooleanSlot true)
    }
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
    // addHighlight (morph rep) ( 3 * (global 'scale'))
    return rep
  }
  return (newInputSlot slotContent editRule blockColor)
}

method typesMenu InputDeclaration {
  menu = (menu nil (action 'setType' this) true)
// slot types: 'auto' 'num' 'str' 'bool' 'color' 'cmd' 'var' 'menu'
  addItem menu 'number/string' 'auto' 'editable number or string'
  addItem menu '' 'bool' 'boolean switch' (fullCostume (morph (element this 'bool')))
  addItem menu '' 'color' 'color patch' (fullCostume (morph (element this 'color')))
  popUp menu (global 'page') (left morph) (bottom morph)
}
