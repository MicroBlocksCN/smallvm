// Morphic TabBar handler

defineClass TabBar morph listBox alignment tabCorner

to tabBar aCollection getEntry onSelect bgColor fontSize onDoubleClick {
  if (isNil getEntry) {getEntry = 'id'}
  if (isNil onSelect) {onSelect = 'nop'}
  lb = (new 'ListBox' nil aCollection onSelect getEntry nil bgColor)
  onDoubleClick lb onDoubleClick
  tb = (new 'TabBar' nil lb)
  initialize tb 'line' fontSize
  buildMorph tb
  return tb
}

method initialize TabBar alignRule fontPixelSize {
  if (isNil fontPixelSize) {fontPixelSize = 11}
  scale = (global 'scale')
  setField listBox 'fontName' 'Arial Bold'
  fontSize = (scale * fontPixelSize)
  setField listBox 'fontSize' fontSize
  tabCorner = ((fontSize / 2) + (scale + 0))
  setField listBox 'txtClrNormal' (color 230 230 230)
  setField listBox 'txtClrReady' (color 255 255 255)
  setField listBox 'txtClrSelected' (color)
  bgClrSelected = (color 200 200 200)
  setField listBox 'bgClrSelected' bgClrSelected
  setField listBox 'bgClrNormal' (darker bgClrSelected 50)
  setField listBox 'bgClrReady' (darker bgClrSelected 30)
  alignment = (newAlignment alignRule (0 - (fontSize + (scale * 2))))
  setVPadding alignment 0
  setFramePadding alignment 0 0
}

method setBGColors TabBar selectedColor normalColor readyColor {
  if (notNil selectedColor) { setField listBox 'bgClrSelected' selectedColor }
  if (notNil normalColor) { setField listBox 'bgClrNormal' normalColor }
  if (notNil readyColor) { setField listBox 'bgClrReady' readyColor }
  buildMorph this
}

method alignment TabBar {return alignment}
method collection TabBar { return (collection listBox)}
method selection TabBar {return (selection listBox)}
method onSelect TabBar anAction {onSelect listBox anAction}
method onDoubleClick TabBar anAction {onDoubleClick listBox anAction}

method buildMorph TabBar {
  if (notNil morph) {destroy morph}
  morph = (newMorph this)
  setMorph alignment morph
  setMorph listBox morph
  setTransparentTouch morph true
  updateMorphContents this
}

method select TabBar aListItem silently {
  select listBox aListItem silently
  addPart morph (selectedMorph listBox) // bring to front
}

method setCollection TabBar aCollection {
  setField listBox 'collection' aCollection
  updateMorphContents this
}

method updateMorphContents TabBar {
  // remove all existing list items, if any
  repeat (count (parts morph)) {destroy (at (parts morph) 1)}

  // create items
  for item (collection this) {
    lbl = (normalCostume this item)
    li = (newTab this item)
    setHeight (bounds (morph li)) (height lbl)
    setWidth (bounds (morph li)) (width lbl)
    addPart morph (morph li)
  }
  fixLayout alignment

  // create a new background bitmap/texture
  bg = (newBitmap (max 1 (width morph)) (max 1 (height morph)) (getField listBox 'bgColor'))
  setCostume morph bg

  // refresh every item
  for i (count (parts morph)) {
    item = (handler (at (parts morph) i))
    refresh item
  }

  // update sliders, if any
  owner = (owner morph)
  if (and (notNil owner) (isClass (handler owner) 'ScrollFrame'))  {updateSliders (handler owner)}
}

method newTab TabBar item {
  tab = (listItem listBox item)
  tr = (getField tab 'trigger')
  setAction tr (action 'select' this item)
  setRenderer tr this
  return tab
}

// tabs rendering

method normalCostume TabBar data {
  return (tabBitmap
    this
    (toString (call (getField listBox 'getEntry') data))
    (getField listBox 'txtClrNormal')
    (getField listBox 'bgClrNormal')
    false
    (getField listBox 'bgClrSelected')
  )
}

method highlightCostume TabBar data {
  return (tabBitmap
    this
    (toString (call (getField listBox 'getEntry') data))
    (getField listBox 'txtClrSelected')
    (getField listBox 'bgClrSelected')
    true
    (getField listBox 'bgClrSelected')
  )
}

method pressedCostume TabBar data {
  return (tabBitmap
    this
    (toString (call (getField listBox 'getEntry') data))
    (getField listBox 'txtClrReady')
    (getField listBox 'bgClrReady')
    false
    (getField listBox 'bgClrSelected')
  )
}

method tabBitmap TabBar label color bodyColor isInFront frontColor {
  if (isNil color) {color = (color 255 255 255)}
  if (isNil bodyColor) {bodyColor = (color 130 130 130)}
  if (isNil isInFront) {isInFront = false}
  scale = (global 'scale')
  if (isClass label 'String') {
    off = (max (scale / 2) 1)
    shadowColor = (darker bodyColor)
    shift = -1
    if (and ((red color) == 0) ((green color) == 0) ((blue color) == 0)) {
      shadowColor = (color 255 255 255)
      shift = 1
    }
    lbm = (stringImage
      label
      (getField listBox 'fontName')
      (getField listBox 'fontSize')
      color
      'center'
      shadowColor
      (off * shift)
    )
  } else {
    lbm = nil
  }
  tabBorder = (max 1 (scale / 2))
  if (global 'flat') {tabBorder = 0}

  w = (+ (width lbm) (tabCorner * 4) (tabBorder * 2))
  h = (+ (height lbm) (tabBorder * 2))
  bm = (newBitmap w h)
  if isInFront {
	clr = (gray 220)
  } else {
	clr = (gray 120)
  }
  drawTab (newShapeMaker bm) (rect 0 0 w h) tabCorner tabBorder clr
  drawBitmap bm lbm ((w - (width lbm)) / 2) ((h - (height lbm)) / 2)
  return bm
}

// serialization

method preSerialize TabBar {
  removeAllParts (morph listBox)
  setCostume (morph listBox) nil
  setCostume morph nil
}

method postSerialize TabBar {
  updateMorphContents this
}
