// basic Morphic text handler and renderer

to menuStringImage aString fontName fontSize color bgColor {
  // answer a new bitmap depicting a string rendered
  // with the specified font settings and alignment
  // the bitmap's width and height resemble the exact
  // bounding box's dimensions of the rendered text
  // borderX and borderY resemble optional space around the text

  if (isNil aString) {aString = ''}
  if (aString == '') {aString = ' '}
  if (not (isClass aString 'String')) {aString = (toString aString)}
  if (isNil fontName) {fontName = 'Arial'}
  if (isNil fontSize) {fontSize = 12}
  if (isNil color) {color = (color)}

  if (isNil bgColor) {
    bgColor = (copy color)
    setAlpha bgColor 0
  }

  setFont fontName fontSize

  // determine width
  w = (stringWidth aString)

  // determine height
  h = (fontHeight)

  // create bitmap
  bm = (newBitmap w h bgColor)

  // render the actual text
  drawString bm aString color 0 0
  return bm
}

to stringImage aString fontName fontSize color alignment shadowColor shadowOffsetX shadowOffsetY borderX borderY bgColor minWidth minHeight flat {
  // answer a new bitmap depicting a string rendered
  // with the specified font settings and alignment
  // the bitmap's width and height resemble the exact
  // bounding box's dimensions of the rendered text
  // borderX and borderY resemble optional space around the text

  if (isNil aString) {aString = ''}
  if (aString == '') {aString = ' '}
  if (not (isClass aString 'String')) {aString = (toString aString)}
  if (isNil fontName) {fontName = 'Arial'}
  if (isNil fontSize) {fontSize = 12}
  if (isNil color) {color = (color)}
  if (isNil alignment) {alignment = 'left'}
  if (isNil shadowOffsetX) {shadowOffsetX = 0}
  if (isNil shadowColor) {
    if (shadowOffsetX != 0) {shadowColor = (color 230 230 230)}
  }
  if (isNil shadowOffsetY) {shadowOffsetY = shadowOffsetX}
  if (isNil flat) {flat = true}
  flat = true // force flat text

  if flat {
    shadowOffsetX = 0
    shadowOffsetY = 0
    shadowColor = nil
  }

  if (isNil borderX) {borderX = 0}
  if (isNil borderY) {borderY = 0}
  if (isNil bgColor) {
    if (notNil shadowColor) {
      bgColor = (copy shadowColor)
    } else {
      bgColor = (copy color)
    }
    setAlpha bgColor 0
  }

  lines = (lines aString)
  widths = (newArray (count lines))
  setFont fontName fontSize

  // determine width
  w = 0
  if (notNil minWidth) { w = minWidth }
  for i (count lines) {
    lw = (+ (stringWidth (at lines i)) (borderX * 2))
	if (lw > 4000) { lw = 4000 } // truncate really wide strings
    atPut widths i lw
    w = (max w lw)
  }

  // determine height
  lineHeight = (fontHeight)
  h = (+ (borderY * 2) ((count lines) * lineHeight))
  if (notNil minHeight) { h = (max h minHeight) }

  // create bitmap
  bm = (newBitmap (+ w (abs shadowOffsetX)) (+ h (abs shadowOffsetY)) bgColor)

  // render the shadow, if any
  if (or (shadowOffsetX != 0) (shadowOffsetY != 0)) {
    for i (count lines) {
      if (shadowOffsetX < 0) {
        offsetX = 0
      } else {
        offsetX = shadowOffsetX
      }
      if (shadowOffsetY < 0) {
        offsetY = 0
      } else {
        offsetY = shadowOffsetY
      }
      if (alignment == 'right') {
        startX = (w - (at widths i))
      } (alignment == 'center') {
        startX = (half (w - (at widths i)))
      } else {
        startX = 0
      }
      drawString bm (at lines i) shadowColor (+ startX offsetX borderX) (+ ((i - 1) * lineHeight) offsetY borderY)
    }
  }

  // render the actual text
  for i (count lines) {
    if (shadowOffsetX >= 0) {
      offsetX = 0
    } else {
      offsetX = (abs shadowOffsetX)
    }
    if (shadowOffsetY >= 0) {
      offsetY = 0
    } else {
      offsetY = (abs shadowOffsetY)
    }
    if (alignment == 'right') {
      startX = (w - (at widths i))
    } (alignment == 'center') {
      startX = (half (w - (at widths i)))
    } else {
      startX = 0
    }
    drawString bm (at lines i) color (+ startX offsetX borderX) (+ ((i - 1) * lineHeight) offsetY borderY)
  }

  return bm
}

defineClass Text morph text fontName fontSize color alignment shadowColor shadowOffsetX shadowOffsetY borderX borderY editRule bgColor isFlat minWidth minHeight caret startMark endMark codeContext scrubValue clickedForEdit cachedBM

to newText aString fontName fontSize color alignment shadowColor shadowOffsetX shadowOffsetY borderX borderY editRule bgColor flat {
  scale = (global 'scale')
  if (isNil aString) {aString = ''}
  if (isNil fontName) {fontName = 'Arial'}
  if (isNil fontSize) {fontSize = (scale * 12)}
  if (isNil color) {color = (color)}
  if (isNil alignment) {alignment = 'left'}
  if (isNil shadowOffsetX) {shadowOffsetX = 0}
  if (isNil shadowColor) {
    if (shadowOffsetX != 0) {shadowColor = (color 230 230 230)}
  }
  if (isNil shadowOffsetY) {shadowOffsetY = shadowOffsetX}
  if (isNil borderX) {borderX = 0}
  if (isNil borderY) {borderY = 0}
  if (isNil editRule) {editRule = 'static'}

  txt = (new 'Text' nil aString fontName fontSize color alignment shadowColor shadowOffsetX shadowOffsetY borderX borderY editRule bgColor flat)
  morph = (newMorph txt)
  setTransparentTouch morph true
  setMorph txt morph
  fixLayout txt
  return txt
}

method initialize Text {
  scale = (global 'scale')
  if (isNil scale) { scale = 1 }
  text = 'Text'
  fontName = 'Arial'
  fontSize = (scale * 12)
  color = (gray 0)
  alignment = 'left'
  shadowColor = nil
  shadowOffsetX = 0
  shadowOffsetY = 0
  borderX = 0
  borderY = 0
  editRule = 'static'
  minWidth = 0
  minHeight = 0
  clickedForEdit = false
  return this
}

method fieldInfo Text fieldName {
  info = (dictionary)
  if ('editRule' == fieldName) {
    atPut info 'type' 'options'
    atPut info 'options' (array 'static' 'editable' 'code' 'numerical' 'line')
    return info
  } ('alignment' == fieldName) {
    atPut info 'type' 'options'
    atPut info 'options' (array 'left' 'center' 'right')
    return info
  }
  return nil
}

method text Text {return text}

method setText Text aString {
  text = aString
  startMark = nil
  endMark = nil
  fixLayout this
  raise morph 'textEdited' this
}

method fontName Text {return fontName}
method fontSize Text {return fontSize}

method setFont Text name size {
  if (isNil name) {name = fontName}
  if (isNil size) {size = fontSize}
  if (and (name == fontName) (size == fontSize)) { return } // no change
  fontName = name
  fontSize = size
  fixLayout this
}

method color Text {return color}
method shadowColor Text {return shadowColor}
method bgColor Text {return bgColor}

method setColor Text textColor shadeColor backgroundColor {
  if (isNil textColor) {textColor = color}
  if (isNil shadeColor) {shadeColor = shadowColor}
  if (isNil backgroundColor) {backgroundColor = bgColor}
  color = textColor
  shadowColor = shadeColor
  bgColor = backgroundColor
  changed morph
}

method alignment Text {return alignment}

method align Text optionString {
  // optionString can be 'left', 'center' or 'right'
  alignment = optionString
  fixLayout this
}

method shadowOffsetX Text {return shadowOffsetX}
method shadowOffsetY Text {return shadowOffsetY}

method setShadowOffset Text x y {
  if (isNil x) {x = shadowOffsetX}
  if (isNil y) {y = shadowOffsetY}
  shadowOffsetX = x
  shadowOffsetY = y
  fixLayout this
}

method borderX Text {return borderX}
method borderY Text {return borderY}

method setBorders Text x y silently {
  if (isNil x) {x = borderX}
  if (isNil y) {y = borderY}
  borderX = x
  borderY = y
  if silently {return}
  fixLayout this
}

method editRule Text {return editRule}

method setEditRule Text string {
  // governs whether and how the text element is editable:
  // 'static' - cannot be edited
  // 'editable' - editable without restrictions (multi-line, alphanumerical)
  // 'code' - unrestricted multi-line editing with EVAL-bindings and menu
  // 'numerical' - accepts only keystrokes that can be used within a number
  // 'line' - blocks multi-line editing (which is possible by default)
  editRule = string
}

method codeContext Text {return codeContext}
method setCodeContext Text anObjectOrNil {codeContext = anObjectOrNil}
method setMinWidth Text w {minWidth = (max 0 (truncate w))}
method setMinHeight Text h {minHeight = (max 0 (truncate h))}

method drawOn Text ctx {
// 	h = (handler (owner morph))
// 	if (or (isClass h 'Block') (isClass h 'InputSlot')) {
// 		if (isNil cachedBM) {
// 			cachedBM = (newBitmap (width morph) (height morph) (color h))
// 			bmCtx = (newGraphicContextOn cachedBM)
// 			setFont bmCtx fontName fontSize // set font before getting fontHeight
// 			drawString bmCtx (first (lines text)) color 0 0
// 		}
// 		drawBitmap ctx cachedBM (left morph) (top morph)
// 		return
// 	}

  setFont ctx fontName fontSize // set font before getting fontHeight
  lineHeight = (fontHeight)
  w = ((width morph) - (2 * borderX))
  if (notNil bgColor) {
    r = (insetBy (bounds morph) borderX borderY)
    fillRect ctx bgColor (left r) (top r) (width r) (height r) 1
  }

  x = ((left morph) + borderX)
  y = ((top morph) + borderY)
  for s (lines text) {
	if (alignment == 'right') {
	  inset = (w - (stringWidth s))
	} (alignment == 'center') {
	  inset = (half (w - (stringWidth s)))
	} else {
	  inset = 0
	}
	drawString ctx s color (x + inset) y
	y += lineHeight
  }
  drawSelectionOn this ctx
}

method drawSelectionOn Text ctx {
	if ((count text) == 0) { return }
	if (or (isNil startMark) (isNil endMark)) { return }
	begin = (min startMark endMark)
	end = ((max startMark endMark) - 1)
	marked = (substring text begin end)
	lines = (lines marked)
	setFont ctx fontName fontSize
	lineHeight = (fontHeight)
	slot = begin
	for row (count lines) {
		s = (at lines row)
		pos = (relativeSlotPosition this slot)
		xPos = ((left morph) + (at pos 1))
		yPos = ((top morph) + (at pos 2))
		fillRect ctx (color 0 0 100) xPos yPos (stringWidth s) lineHeight
		drawString ctx s (gray 255) xPos yPos
		slot += ((count (at lines row)) + 1)
	}
}

method fixLayout Text {
  changed morph
  computeBounds this
  changed morph
  raise morph 'layoutChanged' this
}

method computeBounds Text {
  lines = (lines text)
  setFont fontName fontSize

  // determine width
  w = 0
  if (notNil minWidth) { w = minWidth }
  for s lines {
    lw = ((stringWidth s) + (2 * borderX))
	if (lw > 4000) { lw = 4000 } // truncate really wide strings
    w = (max w lw)
  }
  setWidth (bounds morph) w

  // determine height
  lineHeight = (fontHeight)
  h = (((count lines) * lineHeight) + (2 * borderY))
  if (notNil minHeight) { h = (max h minHeight) }
  setHeight (bounds morph) h
}

method adjustSizeToScrollFrame Text aScrollFrame {
  ca = (clientArea aScrollFrame)
  computeBounds this
  bnds = (bounds morph)
  setWidth bnds (max (width bnds) (width ca))
  setHeight bnds (max (height bnds) (height ca))
}

// events

method clicked Text hand {
  return (notNil caret)
}

method doubleClicked Text hand {
  if (isNil caret) {return false}
  selectWordAt this (slotAt this (x hand) (y hand))
  return true
}

method handDownOn Text hand {
  scrubValue = nil
  clickedForEdit = false
  if ('static' != editRule) {
    if (isNil caret) {
      clickedForEdit = true
      edit this hand
    }
    if (shiftKeyDown (keyboard (page hand))) {
      if (isNil startMark) {startMark =  (slot caret)}
      gotoSlot caret (slotAt this (x hand) (y hand))
    } else {
      pos = (max 1 (slotAt this (x hand) (y hand)))
      unmark this
      gotoSlot caret pos
      startMark = (slot caret)
    }
    if  clickedForEdit {raise morph 'clickedForEdit' this}
    return true
  }
  return false
}

method handMoveOver Text hand {
  if (isNil caret) {return}
  closeUnclickedMenu (page hand) this
  if (isNil startMark) {startMark = (slot caret)}
  gotoSlot caret (max 1 (slotAt this (x hand) (y hand)))
}

method touchHold Text hand {
  if (notNil caret) { // edited
    if ('numerical' == editRule) {
      startScrubbing this hand
      return true
    }
    raise morph 'scrubAnyway' this
    return true
  }
  return false
}

method rightClicked Text hand {
  if (notNil caret) { // edited
    popUpAtHand (contextMenu this) (page hand) true // no focus
    return true
  }
  return false
}

method handEnter Text aHand {
  if (editRule != 'static') {
	setCursor 'text'
  }
}

method handLeave Text aHand {
  // handEnter happens before handLeave, so cursor wouldn't go back to finger
  // when you move between two buttons without any space in between. A temporary
  // solution is to re-trigger handEnter on the new morph under the hand.
  if (isNil caret) {
	setCursor 'default'
	handEnter (objectAt aHand) aHand
  }
}

// context menu

method contextMenu Text {
  menu = (menu nil this)
  if (and (editRule == 'code') ((count (selected this)) > 0)) {
    addItem menu 'do it...' 'doIt' 'execute the marked text as GP code'
    addItem menu 'print it...' 'printIt' 'insert the result of executing the marked text as GP code'
    // addItem menu 'inspect it...' 'inspectIt' 'open a window on the result of executing the marked text as GP code'
    addItem menu 'explore it...' 'exploreIt' 'open an explorer on the result of executing the marked text as GP code'
    addItem menu 'blockify it...' 'blockifyIt' 'create a graphical block representing the marked text as GP code'
    addItem menu 'definitions...' 'browseImplementors' 'lookup the implementations of the selected expression'
    addLine menu
  }
  edits = false
  if ((selected this) != '') {
    edits = true
    addItem menu 'cut' (action 'copyToClipboard' caret true)
    addItem menu 'copy' (action 'copyToClipboard' caret false)
  }
  txt = (readClipboard)
  if (txt != '') {
    edits = true
    addItem menu 'paste' (action 'insertRight' caret txt)
  }
  if edits {addLine menu}
  if ((originalContents caret) != text) {
    addItem menu 'accept' (action 'accept' caret)
    addItem menu 'revert' (action 'cancel' caret)
  } else {
    addItem menu 'stop editing' 'stopEditing'
  }
  addItem menu 'select all' 'selectAll'
  if (isClass (handler (owner morph)) 'InputSlot') {
	addLine menu
	addSlotSwitchItems (handler (owner morph)) menu
  }
  return menu
}

// editing

method edit Text hand keepFocus {
  root = (handler (root morph))
  if (isClass root 'Page') {edit (keyboard root) this (slotAt this (x hand) (y hand)) keepFocus}
  setCursor 'text'
}

method stopEditing Text {
  unmark this
  root = (handler (root morph))
  if (isClass root 'Page') {stopEditing (keyboard root) this}
  setCursor 'default'
}

// measuring

method extent Text aFontSize xBorder yBorder {
  // answer a rectangle describing the area actually used by the text
  // at a hypothetical fontsize and border coordinates
  if (isNil aFontSize) {aFontSize = fontSize}
  if (isNil xBorder) {xBorder = borderX}
  if (isNil yBorder) {yBorder = borderY}
  w = 0
  lines = (lines text)
  setFont fontName aFontSize
  lineHeight = (fontHeight)
  for line lines {
    w = (max w (stringWidth line))
  }
  return (rect (left morph) (top morph) (w + (xBorder * 2)) (((count lines) * lineHeight) + (yBorder * 2)))
}

method columnRow Text slot {
  // answer the logical position of the given index ("slot")
  if (slot == 1) {return (array 1 1)}
  idx = 1
  lines = (lines text)
  for row (count lines) {
    for col (count (at lines row)) {
      if (idx == slot) {return (array col row)}
      idx += 1
    }
    if (isNil col) {col = 0}
    if (idx == slot) {return (array (col + 1) row)}
    idx += 1
  }
  return (array (+ 1 (count (at lines (count lines)))) (count lines))
}

method slotPosition Text slot {
  // answer a two-element array representing the physical coordinates of the given
  // index ("slot"), where the caret should be placed
  relative = (relativeSlotPosition this slot)
  return (array (+ (left morph) (at relative 1)) (+ (top morph) (at relative 2)))
}

method relativeSlotPosition Text slot {
  // answer a two-element array representing the physical coordinates of the given
  // index ("slot") relative to the morph's origin
  lines = (lines text)
  if ((count lines) == 0) {return (array borderX borderY)}
  colRow = (columnRow this slot)
  col = (at colRow 1)
  row = (at colRow 2)
  setFont fontName fontSize
  lineHeight = (fontHeight)
  indent = 0
  extent = (extent this)
  if (alignment == 'center') {
    indent = (half (((width extent) - (borderX * 2)) - (stringWidth (at lines row))))
  } (alignment == 'right') {
    indent = (((width extent) - (borderX * 2)) - (stringWidth (at lines row)))
  }
  if ((count (at lines row)) == 0) {
    xOffset = (+ borderX indent)
  } else {
    xOffset = (+ (stringWidth (substring (at lines row) 1 (col - 1))) borderX indent)
  }
  yOffset = (((row - 1) * lineHeight) + borderY)
  return (array xOffset yOffset)
}

method slotAt Text x y {
  // answer the slot (index) closest to the given coordinates
  // so the caret can be moved accordingly
  slot = 0
  lines = (lines text)
  setFont fontName fontSize
  lineHeight = (fontHeight)

  row = 0
  lineY = (+ (top morph) borderY)
  while (and (lineY < y) (row <= (count lines))) {
    if (row > 0) {slot += (+ 1 (count (at lines row)))}
    row += 1
    lineY = (+ (top morph) borderY (row * lineHeight))
  }
  row = (max 1 (min row (count lines)))
  line = (at lines row)
  col = 0
  indent = 0
  if (alignment == 'center') {
    indent = (half ((width morph) - (stringWidth line)))
  } (alignment == 'right') {
    indent = ((width morph) - (stringWidth line))
  }
  lineX = (+ (left morph) borderX indent)
  while (lineX < x) {
    slot += 1
    col += 1
    if (col > (count line)) {return (min slot ((count text) + 1))}
    lineX = (+ (left morph) borderX indent (stringWidth (substring line 1 col)))
  }
  return (min slot ((count text) + 1))
}

// marking

method startMark Text {return startMark}
method endMark Text {return endMark}
method setStartMark Text aSlotOrNil {startMark = aSlotOrNil}
method setEndMark Text aSlotOrNil {endMark = aSlotOrNil}
method caret Text {return caret}
method setCaret Text caretOrNil {caret = caretOrNil}

method selected Text {
  if (or (isNil startMark) (isNil endMark)) {return ''}
  begin = (min startMark endMark)
  end = ((max startMark endMark) - 1)
  return (substring text begin end)
}

method unmark Text {
  if (notNil startMark) {
    startMark = nil
    endMark = nil
    changed morph
  }
}

method selectAll Text {
  startMark = 1
  endMark = ((count text) + 1)
  changed morph
}

method selectWordAt Text slot {
  letters = (letters text)
  while (and (slot > 1) (not (isWhiteSpace (at letters (min (slot - 1) (count letters)))))) {slot += -1}
  startMark = slot
  slot += 1
  while (and (slot <= (count text)) (not (isWhiteSpace (at letters slot)))) {slot += 1}
  slot = (min slot ((count text) + 1))
  endMark = slot
  changed morph
}

// evaluating

method doIt Text {
  page = (handler (root morph))
  expr = (selected this)
  unmark this
  editor = (findProjectEditor)
  mod = nil
  if (notNil editor) {
    mod = (module (project editor))
  }
  launch page (newReporter 'eval' expr codeContext mod)
}

method printIt Text {
  page = (handler (root morph))
  expr = (selected this)
  mod = nil
  editor = (findProjectEditor)
  if (notNil editor) {
    mod = (module (project editor))
  }
  launch page (newReporter 'eval' expr codeContext mod) nil (action 'printResult' this)
}

method printResult Text result {
  if (isNil caret) {
    page = (handler (root morph))
    edit (keyboard page) this 1
	selectAll this
  }
  gotoSlot caret (max startMark endMark)
  startMark = nil
  start = (slot caret)
  insertRight caret (join ' ' (printString result))
  startMark = start
  endMark = (slot caret)
  fixLayout this
}

method inspectIt Text {
  page = (handler (root morph))
  expr = (selected this)
  mod = nil
  editor = (findProjectEditor)
  if (notNil editor) {
    mod = (module (project editor))
  }
  launch page (newReporter 'eval' expr codeContext mod) nil (action 'inspectResult' this)
}

method exploreIt Text {
  page = (handler (root morph))
  expr = (selected this)
  mod = nil
  editor = (findProjectEditor)
  if (notNil editor) {
    mod = (module (project editor))
  }
  launch page (newReporter 'eval' expr codeContext mod) nil (action 'exploreResult' this)
}

method inspectResult Text result {
  page = (handler (root morph))
  ins = (inspectorOn result)
  setPosition (morph ins) (x (hand page)) (y (hand page))
  addPart page ins
  keepWithin (morph ins) (bounds (morph page))
  stopEditing this
}

method exploreResult Text result {
  page = (handler (root morph))
  ins = (explorerOn result)
  setPosition (morph ins) (x (hand page)) (y (hand page))
  addPart page ins
  keepWithin (morph ins) (bounds (morph page))
  stopEditing this
}

method blockifyIt Text {
  parsed = (parse (selected this))
  if (isEmpty parsed) {return}
  element = (at parsed 1)
  if (isAnyClass element 'Command' 'Reporter') {
    stopEditing this
    page = (handler (root morph))
	if (and (isClass element 'Reporter') (isControlStructure element)) {
	  element = (toCommand element)
	}
    block = (toBlock element)
    setPosition (morph block) (x (hand page)) (y (hand page))
    addPart page block
    keepWithin (morph block) (bounds (morph page))
  }
}

method browseImplementors Text {
  name = (selected this)
  implementors = (implementors name)
  menu = (menu (join 'implementations of' (newline) name) (action 'openClassBrowser' this name) true) // reverse call
  for each implementors {
    addItem menu (join each '...') each
  }
  popUpAtHand menu (global 'page')
}

method openClassBrowser Text functionName aClassName {
  browseClass aClassName functionName
}

// scrubbing

method startScrubbing Text hand {
  if (isNil hand) {hand = (hand (page morph))}
  stopEditing this
  scrubValue = (toNumber text)
  focusOn hand this
}

method handUpOn Text hand {
  if (notNil scrubValue) {
    changed = (scrubValue != (toNumber text))
    scrubValue = nil
    if changed { return true }
  }
  return false
}

method handMoveFocus Text hand {
  if (notNil scrubValue) {scrub this hand}
}

method scrub Text hand {
  stopEditing this

  // scrub delta is vertical distance (positive or negative) from center
  delta = (truncate (((vCenter (bounds morph)) - (y hand)) / (3 * (global 'scale'))))
  setText this (toString (scrubValue + delta))
  raise morph 'textChanged' this
}

// Line wrapping
// Note: This is a hack. CR characters are used to mark soft line wraps.
// Before the text is reflowed, the newlines are removed.

method wrapLinesToWidth Text wrapWidth {
  newline = (newline)
  cr = (cr)
  result = (list)
  lines = (lines (contentsWithoutCRs this))
  if (and ((count lines) > 0) ((count (last lines)) == 0)) {
	// if the last line is empty, remove it
	lines = (copyArray lines ((count lines) - 1))
  }
  setFont fontName fontSize
  for line lines {
	remaining = line
	while (remaining != '') {
	  end = (findLineBreak this remaining wrapWidth)
	  add result (substring remaining 1 end)
	  remaining = (substring remaining (end + 1))
	  if (remaining != '') {
		add result cr // soft line break
	  }
	}
	add result newline // hard line break
  }
  setText this ''
  setText this (joinStringArray (toArray result))
}

method contentsWithoutCRs Text {
  // Return my contents without CR characters (soft line breaks).
  cr = (cr)
  result = (list)
  for ch (letters text) {
	if (ch != cr) { add result ch }
  }
  return (joinStringArray (toArray result))
}

method findLineBreak Text s wrapWidth {
  len = (count s)
  if (len < 2) { return len }

  w = (stringWidth s)
  if (w < wrapWidth) { return len }

  avgLetterWidth = (w / len)
  initializeGuess = (max (truncate (wrapWidth / avgLetterWidth)) 1)
  i = (wordEndAfter this s initializeGuess)

  // find the end of the first word beyond wrapWidth
  while (and (i < len) ((stringWidth (substring s 1 i)) < wrapWidth)) {
  	i = (wordEndAfter this s (i + 1))
  }

  // back up by words until the line fits
  i = (wordEndBefore this s i)
  while (and (i > 1) ((stringWidth (substring s 1 i)) > wrapWidth)) {
  	i = (wordEndBefore this s i)
  }

  if (i == 1) { // no word break before wrapWidth, break the word
	while (and (i < len) ((stringWidth (substring s 1 i)) < wrapWidth)) {
	  i += 1
	}
  }

  // skip whitespace (leave terminating whitespace at end of line)
  space = 32
  while (and (i < len) ((byteAt s (i + 1)) <= space)) {
  	i += 1
  }

  return i
}

method wordEndAfter Text s i {
  space = 32
  len = (count s)
  // skip whitespace
  while (and (i < len) ((byteAt s i) <= space)) {
  	i += 1
  }
  // find word end
  while (and (i < len) ((byteAt s (i + 1)) > space)) {
  	i += 1
  }
  return i
}

method wordEndBefore Text s i {
  space = 32
  // skip whitespace
  while (and (i > 1) ((byteAt s i) <= space)) {
  	i += -1
  }
  // find word start
  while (and (i > 1) ((byteAt s i) > space)) {
  	i += -1
  }
  // find end of the previous word
  while (and (i > 1) ((byteAt s i) > space)) {
  	i += -1
  }
  return i
}

// HTML export

method toHTML Text {
  // Experimental. Return an absolute-positioned HTML <p> element representing this text.
  scale = (global 'scale')
  fontColor = (toStringBase16 (pixelRGB color))
  tag = (format '<p style="left:%px;top:%px;font-family:''%'';font-size:%px;color:#%;position:absolute;margin:0px">'
	(truncate ((left morph) / scale)) (truncate ((top morph) / scale)) fontName (truncate (fontSize / scale)) fontColor)
  return (join tag text '</p>')
}
