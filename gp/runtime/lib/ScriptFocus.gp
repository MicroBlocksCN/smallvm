// Block editing handler

defineClass ScriptFocus morph editor element atEnd options menu

method initialize ScriptFocus aScriptEditor initialElementOrNil x y {
  atEnd = false
  morph = (newMorph this)
  setFPS morph 2
  if (notNil aScriptEditor) {
    edit this aScriptEditor initialElementOrNil x y
    return this
  }
}

method redraw ScriptFocus {
  clr = (gray 255)
  if (notNil editor) {
    scale = (global 'scale')
    h = (scale * 5)
    bigger = (scale * 12)
    if (global 'stealthBlocks') {
      h = (stealthLevel (scale * 5) (scale * 3))
      bigger = (stealthLevel (scale * 12) (scale * 4))
      clr = (gray (255 - ((global 'stealthLevel') * 1.8)))
    }
    if (and (isClass element 'Block') ((type element) != 'reporter')) { // command or hat block types
      setHeight (bounds morph) h
      if atEnd {
          top = (bottom (morph element))
      } else {
          top = ((top (morph element)) - ((height morph) / 2))
      }
      setPosition morph (left (morph element)) top
      setCostume morph (newBitmap (width (morph element)) h clr)
    } (isClass element 'CommandSlot') {
      setHeight (bounds morph) h
      nb = (nested element)
      top = (+ (top (morph element)) (scaledCorner element))
      if (isNil nb) {top += (scaledCorner element)}
      setPosition morph (+ (scaledCorner element) (left (morph element))) top
      setCostume morph (newBitmap (width (morph element)) h clr)
    } (isClass element 'ScriptEditor') {
        setHeight (bounds morph) h
        atEnd = false
        setCostume morph (newBitmap (scale * 100) h clr)
    } else {
      if (global 'stealthBlocks') {
        setAlpha clr 80
      } else {
        setAlpha clr 150
      }
      setBounds morph (expandBy (bounds (morph element)) bigger)
      area = (rect 0 0 (width morph) (height morph))
      bm = (newBitmap (width area) (height area))
	  radius = (10 * scale)
	  border = (3 * scale)
	  borderColor = (gray 255)
	  fillRoundedRect (newShapeMaker bm) area radius clr border borderColor borderColor
      setCostume morph bm
    }
    addPart (morph editor) morph // come to front
    show morph
    scrollIntoView morph
  }
}

method step ScriptFocus {
  if (or (and (isAnyClass element 'CommandSlot' 'ScriptEditor') (isEmpty (parts morph))) (and (isClass element 'Block') ((type element) != 'reporter') (isEmpty (parts morph)))) { // command or hat block types
    if (isVisible morph) {
      hide morph
    } else {
      show morph
    }
  } (not (isVisible morph)) {
    show morph
  }
}

method edit ScriptFocus anEditor anElement x y {
  if (isNil anEditor) {return}
  editor = anEditor
  element = anElement
  if (isClass element 'ScriptEditor') {
    setPosition morph x y
    redraw this
    return
  }
  scripts = (sortedScripts editor)
  if (isEmpty scripts) {return}
  if (isNil element) {element = (first scripts)}
  if (and (notNil x) (notNil y)) {
    setPosition morph x y
  }
  redraw this
  if (onHat this) {nextCommand this true} // no shift
}

// events

method keyDown ScriptFocus evt keyboard {
  closeUnclickedMenu (page keyboard) this
  code = (at evt 'keycode')
  shiftDown = (1 == (at evt 'modifierKeys'))

  if (8 == code) { deleteLeft this // delete
  } (9 == code) { // tab
    if shiftDown {
        lastScript this
    } else {
        nextScript this
    }
  } (13 == code) { enterKey this // enter
  } (27 == code) { cancel this // escape
  } (32 == code) { spaceKey this // escape
  } (37 == code) { lastElement this // left arrow
  } (38 == code) { lastCommand this // up arrow
  } (39 == code) { nextElement this // right arrow
  } (40 == code) { nextCommand this // down arrow
  } (not (isClass element 'BlockDrawer')) {
	charCode = (at evt 'char')
	if (and (32 < charCode) (charCode < 127)) {
	  findBlock this (string charCode)
	}
  }
}

method keyUp ScriptFocus evt keyboard {
  nop
}

method textinput ScriptFocus evt keyboard {
  nop
}

method nextScript ScriptFocus {
  scripts = (sortedScripts editor)
  if (isEmpty scripts) {return}
  if (isClass element 'ScriptEditor') {
    element = (first scripts)
  }
  tb = (topBlock (handler (ownerThatIsA (morph element) 'Block')))
  next = ((indexOf scripts tb) + 1)
  if (next > (count scripts)) {next = 1}
  element = (at scripts next)
  scrollIntoView (morph element)
  atEnd = false
  if (onHat this) {
      nextElement this
      return
  }
  redraw this
}

method lastScript ScriptFocus {
  scripts = (sortedScripts editor)
  if (isEmpty scripts) {return}
  if (isClass element 'ScriptEditor') {
    element = (first scripts)
  }
  tb = (topBlock (handler (ownerThatIsA (morph element) 'Block')))
  next = ((indexOf scripts tb) - 1)
  if (next < 1) {next = (count scripts)}
  element = (at scripts next)
  scrollIntoView (morph element)
  atEnd = false
  if (onHat this) {
      nextElement this true // ignore shift-key
      return
  }
  redraw this
}

method nextCommand ScriptFocus noShift {
  if (or (isClass element 'ScriptEditor') (shiftKeyDown (keyboard (global 'page')))) {
    if (not (noShift == true)) {
      shiftScript this 0 50
      return
    }
  }
  cm = (commandParentOf this element)
  if (isNil cm) {return}
  if atEnd {
    cs = (ownerThatIsA (morph cm) 'CommandSlot')
    if (isNil cs) {
      tb = (commandParentOf this (topBlock cm))
      if (notNil tb) {
        element = tb
        atEnd = false
        if (onHat this) {
          nextCommand this
        }
      }
    } else {
      element = (commandParentOf this (handler cs))
      atEnd = false
      nextCommand this
    }
  } else {
    nb = (next cm)
    if (isNil nb) {
      element = cm
      atEnd = true
    } else {
      element = nb
    }
  }
  redraw this
}

method lastCommand ScriptFocus {
  cm = (commandParentOf this element)
  if (isNil cm) {
    if (isClass element 'ScriptEditor') {
      shiftScript this 0 -50
    }
    return
  }
  if (shiftKeyDown (keyboard (global 'page'))) {
    shiftScript this 0 -50
    return
  }
  if (and (isClass element 'Block') (!= 'reporter' (type element))) {
    if atEnd {
      atEnd = false
    } else {
      pb = (commandParentOf this (handler (owner (morph cm))))
      if (isNil pb) {
        pb = (bottomBlock (topBlock cm))
        if (notNil pb) {
          element = pb
          atEnd = true
        }
      } else {
        element = pb
      }
    }
  } else {
    element = cm
    atEnd = false
  }
  if (and (not atEnd) (onHat this)) {
    lastCommand this
  }
  redraw this
}

method nextElement ScriptFocus ignoreShift {
  if (isNil ignoreShift) {ignoreShift = false}
  items = (items this)
  if (and (not ignoreShift) (or (isEmpty items) (shiftKeyDown (keyboard (global 'page'))))) {
    shiftScript this 50 0
    return
  }
  idx = ((indexOf items element) + 1)
  if (idx > (count items)) {
    idx = 1
  }
  atEnd = false
  element = (at items idx)
  if (isClass element 'CommandSlot') {
    nb = (nested element)
    if (notNil nb) {element = nb}
  } (onHat this) {
    if ((count items) == 1) {
      atEnd = true
    } else {
      nextElement this
    }
  }
  redraw this
}

method lastElement ScriptFocus {
  items = (items this)
  if (or (isEmpty items) (shiftKeyDown (keyboard (global 'page')))) {
    shiftScript this -50 0
    return
  }
  if atEnd {
    element = (last items)
    atEnd = false
  } else {
    idx = ((indexOf items element) - 1)
    if (idx < 1) {idx = (count items)}
    element = (at items idx)
  }
  if (and (isClass element 'CommandSlot') (notNil (nested element))) {
    lastElement this
  } (onHat this) {
    if (> (count items) 1) {
      lastElement this
    } else {
      atEnd = true
    }
  }
  redraw this
}

method deleteLeft ScriptFocus {
  if (isClass element 'Block') {
    b = element
    if atEnd {
      element = (handler (owner (morph element)))
    } (== 'reporter' (type element)) {
      lastElement this
    } else { // 'command' or 'hat'
      if (isClass (handler (owner (morph b))) 'CommandSlot') {return}
      b = (previous b)
      if (isNil b) {return}
    }
    delete b
    if (isEmpty (sortedScripts editor)) {
      stopEditing editor
      return
    }
    redraw this
  } (isClass element 'BlockDrawer') {
    b =  (handler (ownerThatIsA (morph element) 'Block'))
    collapse element
    inp = (inputs b)
    if (notEmpty inp) {
      element = (last (inputs b))
      nextElement this
    } else {
      element = b
      lastElement this
    }
  } (isClass element 'BooleanSlot') {
    setToFalse element
  }
}

method enterKey ScriptFocus {
  keyb = (keyboard (global 'page'))
  if (shiftKeyDown keyb) {
    if (commandKeyDown keyb) {
      runScript this
    } else {
      newScript this
    }
    return
  } (isClass element 'BlockDrawer') {
    b =  (handler (ownerThatIsA (morph element) 'Block'))
    trigger element
    inp = (inputs b)
    if (notEmpty inp) {
      element = (last (inputs b))
      nextElement this
    } else {
      element = b
      lastElement this
    }
  } (isClass element 'InputSlot') {
    destroy morph
    trigger element this
  } (isAnyClass element 'Block' 'BooleanSlot' 'ColorSlot') {
    trigger element
  }
  setField editor 'focus' this
}

method spaceKey ScriptFocus {
  if (isClass element 'BlockDrawer') {
    b =  (handler (ownerThatIsA (morph element) 'Block'))
    trigger element
    inp = (inputs b)
    if (notEmpty inp) {
      element = (last (inputs b))
      nextElement this
    } else {
      element = b
      lastElement this
    }
  } (isAnyClass element 'Block' 'BooleanSlot' 'ColorSlot' 'InputSlot') {
    trigger element
  }
  setField editor 'focus' this
}

method cancel ScriptFocus {
  stopEditing editor
}

method runScript ScriptFocus {
  if (isClass element 'ScriptEditor') {return}
  page = (page morph)
  block = (handler (ownerThatIsA (morph element) 'Block'))
  tb = (topBlock block)
  cmdList = (expression tb)
  // if this block is in a Scripter, run it in the context of the Scriptor's targetObj
  scripter = (ownerThatIsA (morph tb) 'Scripter')
  if (notNil scripter) { targetObj = (targetObj (handler scripter)) }
  if (isRunning page cmdList targetObj) {
    stopRunning page cmdList targetObj
  } else {
    launch page cmdList targetObj (action 'showResult' tb)
  }
}

method newScript ScriptFocus {
  if (isClass element 'ScriptEditor') {return}
  block = (handler (ownerThatIsA (morph element) 'Block'))
  tb = (topBlock block)
  fb = (fullBounds (morph tb))
  setPosition morph (left fb) (+ (bottom fb) (50 * (global 'scale')))
  element = editor
  redraw this
}

// identifying elements

method onHat ScriptFocus {return (and (isClass element 'Block') (== 'hat' (type element)))}

method commandParentOf ScriptFocus handler {
  if (isNil handler) {handler = element}
  cm = handler
  if (cm == editor) {return nil}
  while (not (and (isClass cm 'Block') (!= 'reporter' (type cm)))) {
    cm = (handler (owner (morph cm)))
    if (cm == editor) {return nil}
  }
  return cm
}

// moving scripts

method shiftScript ScriptFocus x y {
  if (isNil x) {x = 0}
  if (isNil y) {y = 0}
  x = (x * (global 'scale'))
  y = (y * (global 'scale'))
  if (isClass element 'ScriptEditor') {
    moveBy morph x y
  } else {
    tb = (topBlock (handler (ownerThatIsA (morph element) 'Block')))
    if (notNil tb) {
      moveBy (morph tb) x y
    }
  }
  justGrabbedPart editor // update sliders
  redraw this
}

// navigating

method items ScriptFocus {
  if (isClass element 'ScriptEditor') {return (list)}
  b = (ownerThatIsA (morph element) 'Block')
  all = (allMorphs (morph (topBlock (handler b))))
  result = (list)
  for each all {
    if (isAnyClass (handler each) 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'BlockDrawer') {
      add result (handler each)
    }
  }
  return result
}

// destroying

method destroy ScriptFocus {
  setFocus editor nil
  // showKeyboard false
  if (notNil menu) {destroy (morph menu)}
  destroy morph
}

// finding matching blocks

method findBlock ScriptFocus spec {
  scale = (global 'scale')
  removeAllParts morph
  if (isNil spec) {spec = ''}
  searchText = (newText spec)
  setFont searchText nil (scale * 15)
  setEditRule searchText 'line'
  setGrabRule (morph searchText) 'ignore'
  setColor searchText nil (color 240 240 240) (color 240 240 240)
  setBorders searchText (scale * 2) (scale * 2) true
  setLeft (morph searchText) ((left morph) + (scale * 5))
  setYCenter (morph searchText) (vCenter (bounds morph))
  addPart morph (morph searchText)
  edit searchText (hand (page morph)) true // keep focus
  gotoSlot (caret searchText) ((count spec) + 1)
  changed (morph searchText)
  textEdited this searchText
}

method textEdited ScriptFocus aText {
  if (and (isClass element 'Block') (or ('command' == (type element)) (and atEnd ('hat' == (type element))))) {
    searchTypes = (list ' ')
  } (isClass element 'CommandSlot') {
    searchTypes = (list ' ')
  } (isClass element 'ScriptEditor') {
    searchTypes = nil
  } (not (and (isClass element 'Block') ('hat' == (type element)))) {
    searchTypes = (list 'r')
  } else {
    return
  }
  specList = (findSpecsMatching this (text aText) searchTypes 5)
  menu = (menu nil this)
  setField menu 'returnFocus' this
  for spec specList {
    if (isClass spec 'Array') { // field name or temporary variable
      blck = (toBlock (newReporter 'v' (first spec)))
    } else {
      blck = (blockForSpec spec)
    }
    addBlock this blck menu
  }
  popUp menu (page morph) (left (morph aText)) (bottom (morph aText)) true // suppress focus
  selectFirstItem menu
}

method accepted ScriptFocus aText {
  trigger menu
  return
}

method cancelled ScriptFocus aText {
  edit editor element this
  redraw this
}

method downArrow ScriptFocus aText {
  selectNextItem menu
}

method upArrow ScriptFocus aText {
  selectPreviousItem menu
}

method addBlock ScriptFocus aBlock aMenu {addItem aMenu (fullCostume (morph aBlock)) (action 'insert' this aBlock)}

method insert ScriptFocus aBlock {
  spec = (blockSpec aBlock)
  if (notNil spec) {showBlockCategory (categoryFor (authoringSpecs) (blockOp spec))}
  if (isClass element 'ScriptEditor') {
    setCenter (morph aBlock) (hCenter (bounds morph)) (vCenter (bounds morph))
    addPart (morph editor) (morph aBlock)
  } (isClass element 'CommandSlot') {
    setNested element aBlock
  } (isClass element 'Block') {
    if (and (not atEnd) ('command' == (type element))) {
      parent = (handler (owner (morph element)))
      if (isClass parent 'CommandSlot') {
        setNested parent aBlock
      } else {
        p = (previous element)
        if (notNil p) {
          setNext p aBlock
        } else { // at the top
          if ('reporter' != (type aBlock)) {
            addPart (morph editor) (morph aBlock)
            setBottom (morph aBlock) (bottom (morph element))
            setLeft (morph aBlock) (left (morph element))
            setNext aBlock element
          }
        }
      }å
    } atEnd {
      setNext element aBlock
    }
  } else { // must be an input
    b = (handler (ownerThatIsA (owner (morph element)) 'Block'))
    replaceInput b element aBlock
  }
  edit editor aBlock this
  element = aBlock
  nextElement this
}

method findSpecsMatching ScriptFocus prefix types max {
  result = (list)
  if ('' == prefix) { return result }

  // find matching variables
  if (or (isNil types) (contains types 'r')) {
    localVars = (list)
    targetObj = (targetObj this)
    if (notNil targetObj) {
      add localVars 'this'
      addAll localVars (fieldNames (classOf targetObj))
    }
    if (not (isClass element 'ScriptEditor')) {
      block = (ownerThatIsA (morph element) 'Block')
      if (notNil block) {
        tb = (topBlock (handler block))
        for each (keys (collectLocals (expression tb))) {
          if (not (contains localVars) each) {
            add localVars each
          }
        }
        // find formal parameters, if any
        def = (editedDefinition tb)
        if (notNil def) {
          for each (inputNames def) {
            if (not (contains localVars) each) {
              add localVars each
            }
          }
        }
      }
    }
    for name localVars {
      if (beginsWith name prefix) {
        add result (array name)
      }
    }
  }

  // find matching blocks
  entries = (dictionary)
  authoringSpecs = (authoringSpecs)
  for entry (allSpecs authoringSpecs) {
    fType = (at entry 1)
    if (or (isNil types) (contains types fType)) {
      fName = (at entry 2)
      spec = (at entry 3)
      if (beginsWith fName prefix) {
        if (not (contains entries fName)) {
          add entries fName
          add result (specForEntry authoringSpecs entry)
        }
      } else {
        specWords = (copyWithout (words spec) '_')
        s = (joinStringArray specWords ' ')
        if (or (beginsWith s prefix) (allWordsMatch this (words prefix) specWords)) {
          if (not (contains entries fName)) {
            add entries fName
            add result (specForEntry authoringSpecs entry)
          }
        }
      }
      if ((count result) >= max) {return result}
    }
  }
  return result
}

method allWordsMatch ScriptFocus patterns words {
  for each patterns {
    if (not (anyWordBeginsWith this words each)) {
      return false
    }
  }
  return true
}

method anyWordBeginsWith ScriptFocus words matchString {
  for each words {
    if (beginsWith each matchString) {
      return true
    }
  }
  return false
}

method targetObj ScriptFocus {
  if (notNil editor) {
    sm = (ownerThatIsA morph 'Scripter')
    if (notNil sm) {return (targetObj (handler sm))}
  }
  return nil
}
