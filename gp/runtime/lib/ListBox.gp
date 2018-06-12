// Morphic ListBox handler

defineClass ListBox morph collection onSelect getEntry selection bgColor fontName fontSize txtClrNormal bgClrNormal txtClrReady bgClrReady txtClrSelected bgClrSelected normalAlpha paddingX paddingY itemWidth minWidth onDoubleClick getHint highlighted

to listBox aCollection getEntry onSelect bgColor onDoubleClick getHint normalAlpha {
  if (isNil getEntry) {getEntry = 'id'}
  if (isNil onSelect) {onSelect = 'nop'}
  if (isNil bgColor) {bgColor = (color 255 255 255)}
  if (isNil normalAlpha) {normalAlpha = 255}

  lb = (new 'ListBox' nil aCollection onSelect getEntry nil bgColor)
  onDoubleClick lb onDoubleClick
  setField lb 'getHint' getHint
  initialize lb normalAlpha
  buildMorph lb
  return lb
}

method initialize ListBox alpha {
  scale = (global 'scale')
  fontName = 'Arial'
  fontSize = (scale * 12)
  txtClrNormal = (color)
  bgClrNormal = bgColor
  txtClrReady = txtClrNormal
  bgClrReady = (darker bgClrNormal 8)
  txtClrSelected = bgClrNormal
  bgClrSelected = (darker bgClrNormal 55)
  paddingX = (scale * 6)
  paddingY = scale
  minWidth = 0
  normalAlpha = alpha
}

method collection ListBox { return collection }
method selection ListBox {return selection}
method isSelecting ListBox anObject {return (selection == anObject)}
method onSelect ListBox anAction {onSelect = anAction}
method onDoubleClick ListBox anAction {onDoubleClick = anAction}
method highlighted ListBox {return highlighted}
method setNormalAlpha ListBox num {normalAlpha = num}

method buildMorph ListBox {
  if (notNil morph) {destroy morph}
  morph = (newMorph this)
  setTransparentTouch morph true
  updateMorphContents this
}

method selectionIndex ListBox {
  for i (count (parts morph)) {
    item = (handler (at (parts morph) i))
	if (isOn item) { return i }
  }
  return nil
}

method select ListBox aListItem silently {
  if (isNil silently) {silently = false}
  selection = aListItem
  for i (count (parts morph)) {
    hdl = (handler (at (parts morph) i))
    if (implements hdl 'refresh') {refresh hdl true}
  }
  if (not silently) {
    if (notNil selection) {call onSelect selection}
  }
}

method selectedMorph ListBox {
  // private - answer the currently selected morph
  // so it can be scrolled into view
  for item (parts morph) {if (isOn (handler item)) {return item}}
  return nil
}

method highlightOn ListBox aListItem {highlighted = aListItem}

method highlightOff ListBox aListItem {
  if (highlighted === aListItem) {
    highlighted = nil
  }
}

method setCollection ListBox aCollection anActionForHint {
  if (isNil anActionForHint) {anActionForHint = getHint}
  collection = aCollection
  getHint = anActionForHint
  updateMorphContents this
}

method setHint ListBox listItem aStringOrNil {setHint (listItem this listItem) aStringOrNil}

method setFont ListBox fName fSize {
  if (notNil fName) { fontName = fName }
  if (notNil fSize) { fontSize = ((global 'scale') * fSize) }
  updateMorphContents this
}

method updateMorphContents ListBox {
  // remove all existing list items, if any
  repeat (count (parts morph)) {destroy (at (parts morph) 1)}
  setWidth (bounds morph) 1

  // create and position items and measure dimensions
  itemWidth = 0
  height = 0
  setFont fontName fontSize
  x = (left morph)
  y = ((top morph) + (3 * (global 'scale')))
  for item collection {
    lbl = (normalCostume this item)
    li = (listItem this item)
    setHeight (bounds (morph li)) (height lbl)
    replaceCostumes li lbl
    setPosition (morph li) x y
    addPart morph (morph li)
    itemWidth = (max itemWidth (width lbl))
    height += (height lbl)
    y += (height lbl)
  }
  setWidth (bounds morph) (max itemWidth minWidth)
  setHeight (bounds morph) height

  // create a new background bitmap/texture
  // --- commented out to preserve resources ---
  // bg = (newBitmap (max 1 (width morph)) (max 1 height) bgColor)
  // setCostume morph bg false true // don't resize

  // set width and refresh every item
  for i (count (parts morph)) {
    item = (handler (at (parts morph) i))
    setWidth (bounds (morph item)) (width morph)
    refresh item
  }

  // update sliders, if any
  owner = (owner morph)
  if (and (notNil owner) (isClass (handler owner) 'ScrollFrame'))  {updateSliders (handler owner)}
}

method setMinWidth ListBox newWidth {
  if (newWidth == minWidth) {return}
  minWidth = (max newWidth itemWidth)
  setWidth (bounds morph) minWidth

  // create a new background bitmap/texture
  // --- commented out to preserve resources ---
  // bg = (newBitmap (max 1 (width morph)) (max 1 (height morph)) bgColor)
  // setCostume morph bg false true // don't resize

  for i (count (parts morph)) {
    item = (handler (at (parts morph) i))
    removeCostume item 'highlight'
    removeCostume item 'pressed'
    setWidth (bounds (morph item)) minWidth
    refresh item
  }
}

method itemWidth ListBox {return itemWidth}

method allWidth ListBox {
  // answer the ideal width which can show every item without scrolling horizontally
  w = (+ itemWidth (2 * paddingX))
  parent = (handler (owner morph))
  if (isClass parent 'ScrollFrame') {
    += w (width (morph (getField parent 'vSlider')))
  }
  return w
}

method listItem ListBox item {
  tr = (new 'Trigger' nil (action 'select' this item))
  if (notNil onDoubleClick) {onDoubleClick tr (action onDoubleClick item)}
  if (notNil getHint) {setHint tr (call getHint item)}
  setData tr item
  setRenderer tr this
  m = (newMorph)
  setMorph tr m
  setTransparentTouch m true
  li = (new 'Toggle' m tr (action 'isSelecting' this item) 'handEnter')
  setHandler m li
  return li
}

method normalCostume ListBox data accessor {
  // optimized for text list items
  // oldCode: {return (itemCostume this data txtClrNormal nil normalAlpha accessor)}

  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'String') {
    return (stringImage dta fontName fontSize txtClrNormal nil nil nil nil paddingX paddingY)
  } (isClass dta 'Bitmap') {
    bm = (newBitmap (+ (* 2 paddingX) (width dta)) (+ (height dta) (* 2 paddingY)) bgClrNormal)
    drawBitmap bm dta paddingX paddingY normalAlpha
    return bm
  }
  return (itemCostume this dta txtClrNormal nil normalAlpha 'id')
}

method highlightCostume ListBox data accessor {return (itemCostume this data txtClrSelected bgClrSelected 255 accessor)}
method pressedCostume ListBox data accessor {return (itemCostume this data txtClrReady bgClrReady 255 accessor)}

method itemCostume ListBox data foregroundColor backgroundColor alpha accessor {
  // private - return a bitmap representing a list item
  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'Bitmap') {
    bm = (newBitmap (max (+ (* 2 paddingX) (width dta)) (width morph)) (+ (height dta) (* 2 paddingY)) backgroundColor)
    drawBitmap bm dta paddingX paddingY alpha
    return bm
  } (isClass dta 'Morph') {
    return (itemCostume this (fullCostume dta) foregroundColor backgroundColor alpha 'id')
  } (hasField dta 'morph') {
    return (itemCostume this (fullCostume (getField dta 'morph')) foregroundColor backgroundColor alpha 'id')
  } (isAnyClass dta 'Command' 'Reporter') {
    return (itemCostume this (fullCostume (morph (toBlock dta))) foregroundColor backgroundColor alpha 'id')
  } (isClass dta 'String') {
    return (itemCostume this (stringImage dta fontName fontSize foregroundColor) foregroundColor backgroundColor alpha 'id')
  } else {
    return (itemCostume this (toString dta) foregroundColor backgroundColor alpha 'id')
  }
}

// context menu

method handleContextRequest ListBox item {
  raise morph 'handleListContextRequest' (array this item)
}

// serialization

method preSerialize ListBox {
  removeAllParts morph
  setCostume morph nil
}

method postSerialize ListBox {
  updateMorphContents this
  select this selection true
}
