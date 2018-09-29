// basic Morphic text editing handler

defineClass Caret morph target slot originalContents

method slot Caret {return slot}
method originalContents Caret {return originalContents}
method target Caret {return target}

method initialize Caret aText initialSlot {
  morph = (newMorph this)
  setFPS morph 2
  if (notNil aText) {
    edit this aText initialSlot
	showKeyboard true
  }
}

method redraw Caret {
  setCostume morph (newBitmap (width morph) (height morph) (color))
}

method step Caret {
  if (isVisible morph) {
    hide morph
  } else {
    show morph
  }
  if ('Browser' == (platform)) {
	s = (browserGetDroppedText)
	if (notNil s) { insertRight this s }
  }
}

method edit Caret aText initialSlot {
  slot = initialSlot
  if (isNil slot) {slot = 1}
  target = aText
  setCaret target this
  originalContents = (text target)
  unmark target
  adjustSize this
  addPart (morph target) morph
  gotoSlot this
}

method adjustSize Caret {
  setFont (fontName target) (fontSize target)
  setExtent morph 2 (fontHeight)
}

method gotoSlot Caret index {
  // index is optional, and can be used to set the slot
  if (notNil index) {slot = index}
  pos = (slotPosition target slot)
  setPosition morph (at pos 1) (at pos 2)
  updateMark this
  scrollIntoView this
}

method scrollIntoView Caret {
  parent = (parentHandler (morph target))
  if (isClass parent 'ScrollFrame') {
    scrollIntoView parent (bounds morph)
  }
}

// events

method keyDown Caret evt keyboard {
  parent = (parentHandler (morph target))
  if (not (isAnyClass parent 'ScriptFocus' 'BlockSearchBox')) {
    closeUnclickedMenu (page keyboard) this
  }

  charCode = (at evt 'char')
  if (and (32 <= charCode) (charCode < 127)) {
  	ch = (string (at evt 'char'))
	code = -1
  } else {
	ch = ''
	code = (at evt 'keycode')
  }

  modifiers = (at evt 'modifierKeys')
  shiftDown = ((modifiers & 1) != 0) // shift flag = 1
  cmdOrControl = ((modifiers & 10) != 0) // control flag = 2, cmd flag = 8
  editingCode = ((editRule target) == 'code')

  if (8 == code) { deleteLeft this // delete
  }  (9 == code) { tabToNextEntryField this shiftDown // tab
  } (13 == code) { enterKey this // enter
  } (27 == code) { // escape
	cancel this
	raise (morph target) 'cancelled' target
  } (37 == code) { moveLeft this shiftDown // left arrow
  } (38 == code) { moveUp this shiftDown // up arrow
  } (39 == code) { moveRight this shiftDown // right arrow
  } (40 == code) { moveDown this shiftDown // down arrow'
  } (46 == code) { deleteRight this // Window's Delete key
  } (76 == code) { deleteRight this // incorrect Window's Delete key code before v250

  } (and ('a' == ch) cmdOrControl) {
    selectAll target
    gotoSlot this (1 + (count (text target)))
  } (and ('c' == ch) cmdOrControl) {
    copyToClipboard this false
  } (and ('s' == ch) cmdOrControl) {
    raise (morph target) 'accepted' target
    accept this
    gotoSlot this (1 + (count (text target)))
  } (and ('v' == ch) cmdOrControl) {
    pasteFromClipboard this
  } (and ('x' == ch) cmdOrControl) {
    copyToClipboard this true
  } (and ('z' == ch) cmdOrControl) {
    cancel this
    raise (morph target) 'cancelled' target
  } (and ('b' == ch) cmdOrControl editingCode) {
    blockifyIt target
  } (and ('m' == ch) cmdOrControl editingCode) {
    browseImplementors target
  } (and ('d' == ch) cmdOrControl editingCode) {
    doIt target
  } (and ('p' == ch) cmdOrControl editingCode) {
    printIt target
  } (and ('i' == ch) cmdOrControl editingCode) {
    inspectIt target
  } (and ('e' == ch) cmdOrControl editingCode) {
    exploreIt target
  }
}

method keyUp Caret evt keyboard {
  nop
}

method textinput Caret evt keyboard {
  old = (text target)
  insertRight this (at evt 'text')
  if (and ('numerical' == (editRule target)) (not (representsANumber (text target)))) {
	setText target old
	moveLeft this
  }
}

method moveRight Caret shiftDown {
  updateMarkingMode this shiftDown
  slot += 1
  slot = (min slot (+ 1 (count (text target))))
  gotoSlot this
}

method moveLeft Caret shiftDown {
  updateMarkingMode this shiftDown
  slot += -1
  slot = (max slot 1)
  gotoSlot this
}

method moveDown Caret shiftDown {
  if ((editRule target) == 'line') {
    raise (morph target) 'downArrow' target
    return
  }
  if ((+ 1 (bottom morph) (borderY target) (abs (shadowOffsetY target))) > (bottom (morph target))) {return}
  updateMarkingMode this shiftDown
  slot = (slotAt target (+ 5 (left morph)) (+ 1 (bottom morph)))
  gotoSlot this
}

method moveUp Caret shiftDown {
  if ((editRule target) == 'line') {
    raise (morph target) 'upArrow' target
    return
  }
  updateMarkingMode this shiftDown
  slot = (slotAt target (+ 5 (left morph)) (+ -1 (top morph)))
  gotoSlot this
}

method insertRight Caret string {
  if (notNil (startMark target)) {
    em = (endMark target)
    if (isNil em) {em = (startMark target)}
    begin = (min (startMark target) em)
    end = (max (startMark target) em)
    before = (substring (text target) 1 (begin - 1))
    after = (substring (text target) end)
    setText target (join before string after)
    slot = (begin + (count string))
  } else {
    before = (substring (text target) 1 (slot - 1))
    after = (substring (text target) slot)
    setText target (join before string after)
    slot += (count string)
  }
  slot = (min slot ((count (text target)) + 1))
  gotoSlot this
}

method deleteLeft Caret {
  if (and (notNil (startMark target)) (notNil (endMark target))) {
    begin = (min (startMark target) (endMark target))
    end = (max (startMark target) (endMark target))
    before = (substring (text target) 1 (begin - 1))
    after = (substring (text target) (max 1 end))
    setText target (join before after)
    slot = begin
  } else {
    slot += -1
    if (slot < 1) {
      slot = 1
      return
    }
    before = (substring (text target) 1 (slot - 1))
    after = (substring (text target) (slot + 1))
    setText target (join before after)
  }
  gotoSlot this
}

method deleteRight Caret {
  if (and (notNil (startMark target)) (notNil (endMark target))) {
	deleteLeft this
	return
  }
  before = (substring (text target) 1 (slot - 1))
  after = (substring (text target) (slot + 1))
  setText target (join before after)
}

method enterKey Caret {
  if (or ((editRule target) == 'editable') ((editRule target) == 'code')){
    insertRight this (newline)
    showKeyboard true  // keep keyboard up on iOS
  } else {
    raise (morph target) 'accepted' target
    accept this
  }
}

method tabToNextEntryField Caret shiftDown {
  page = (page morph)
  isEditField = (function item {return (and (isClass (handler item) 'Text') ((editRule (handler item)) != 'static'))})
  fields = (filter isEditField (allMorphs (morph page)))
  idx = (indexOf fields (morph target))
  if shiftDown {
    idx += -1
    if (idx < 1) {idx = (count fields)}
  } else {
    idx += 1
    if (idx > (count fields)) {idx = 1}
  }
  stopEditingUnfocusedText (hand page)
  trgt = (handler (at fields idx))
  edit (keyboard page) trgt 1
  selectAll trgt
}

method accept Caret {
  stopEditing target
  raise (morph target) 'textChanged' target
}

method cancel Caret {
  setText target originalContents
  parent = (parentHandler (morph target))
  stopEditing target
  if (isClass parent 'ScriptFocus') {
    cancelled parent
  }
}

// clipboard

method copyToClipboard Caret cutFlag {
  selected = (selected target)
  if (selected != '') {
    setClipboard selected
	if cutFlag { deleteLeft this }
  }
}

method pasteFromClipboard Caret {
  s = (getClipboard)
  if (s != '') { insertRight this s }
}

// marking

method updateMarkingMode Caret shiftPressed {
  if shiftPressed {
    if (isNil (startMark target)) {setStartMark target slot}
  } else {
    unmark target
  }
}

method updateMark Caret {
  if (isNil (startMark target)) {return}
  setEndMark target slot
  redraw target
}

// destroying

method destroy Caret {
  parent = (parentHandler (morph target))
  unmark target
  setCaret target nil
  showKeyboard false
  destroy morph
  if (isClass parent 'ScriptFocus') {
    destroy parent
  }
}

