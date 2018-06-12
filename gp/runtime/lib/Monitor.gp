// Monitor - Readout for the value of a variable or expression

// { m = (newMonitor 'Seconds' (action 'second')); addPart page m }

defineClass Monitor morph getAction bgColor style dividerX label readout lastValue

method bgColor Monitor {
  // Fix monitors saved in projects before bgColor was added
  if (isNil bgColor) { bgColor = (gray 200) }
  return bgColor
}

method fieldInfo Monitor fieldName {
  if ('style' == fieldName) {
    info = (dictionary)
    atPut info 'type' 'options'
    atPut info 'options' (array 'labelOnLeft' 'labelOnTop' 'embedded')
    return info
  }
  return nil
}

to newMonitor labelString get bgColor {
  if (isNil bgColor) { bgColor = (gray 200) }
  result = (new 'Monitor' (newMorph) get bgColor 'labelOnLeft')
  setHandler (morph result) result
  setGrabRule (morph result) 'handle'
  setFPS (morph result) 10
  setClipping (morph result) true
  buildUI result labelString
  return result
}

method buildUI Monitor labelString {
  fontSize = (13 * (global 'scale'))
  label = (newText labelString 'Arial Bold' fontSize (gray 255))
  readout = (newText (toString lastValue) 'Arial' fontSize (gray 0))
  setPinToTopLeft (morph label)
  setPinToTopLeft (morph readout)
  removeAllParts morph
  addPart morph (morph label)
  addPart morph (morph readout)
  fixLayout this
}

method morph Monitor { return morph }
method style Monitor { return style }
method labelWidth Monitor { return (width (morph label)) }

method label Monitor { return label }
method readout Monitor { return readout }
method getAction Monitor { return getAction }

method value Monitor {
  if (isNil getAction) { return lastValue }
  return (call getAction)
}

method setStyle Monitor newStyle {
  if (isOneOf newStyle 'labelOnLeft' 'labelOnTop' 'embedded' 'varPane') {
    style = newStyle
    fixLayout this
  }
}

method setDividerX Monitor x {
  dividerX = x
  fixLayout this
}

method step Monitor {
  digitsAfterDecimal = 2
  if (isNil getAction) { return }
  newValue = (call getAction)
  if (newValue === lastValue) { return } // no change
  lastValue = newValue

  if (and (isAnyClass newValue 'Array' 'List') ((count newValue) > 20)) { // long Arrays/Lists
	s = (join '<' (className (classOf newValue)) '> (' (count newValue) ' items)')
  } (isAnyClass newValue 'Dictionary' 'Table') {
	s = (join '<' (className (classOf newValue)) '> (' (count newValue) ' items)')
  } (isClass newValue 'BinaryData') {
	s = (join '<' (className (classOf newValue)) '> (' (byteCount newValue) ' bytes)')
  } (isClass newValue 'String') {
	if ((count newValue) > 100) {
		s = (join (substring newValue 1 100) '...')
	} else {
		s = newValue
	}
  } else { // this case includes short Arrays and Lists
	if (implements lastValue 'copy') { // used to detect changes to arrays/lists
	  lastValue = (copy lastValue)
	}
	s = (toString newValue)
	if (and (isClass newValue 'Float') ((abs newValue) >= 0.01)) {
	  decimalIndex = (indexOf (letters s) '.')
	  if (decimalIndex > 0) {
		s = (substring s 1 (min (decimalIndex + digitsAfterDecimal) (count s)))
	  }
	}
  }
  if (s == (text readout)) { return }
  setText readout s
  redraw readout
  fixLayout this true
}

method fixLayout Monitor keepBitmap {
  scale = (global 'scale')
  oldScale = (scale morph)
  setScale morph 1
  labelW = (normalWidth (morph label))
  readoutW = (normalWidth (morph readout))
  borderColor = (gray 110)
  radius = (2 * scale)
  border = (2 * scale)

  if ('labelOnLeft' == style) {
    setInsetInOwner (morph label) (6 * scale) (4 * scale)
	readoutX = (labelW + (15 * scale))
    setInsetInOwner (morph readout) readoutX (4 * scale)
    bgWidth = ((labelW + readoutW) + (25 * scale))
    bgHeight = ((normalHeight (morph label)) + (8 * scale))
  } ('embedded' == style) {
    radius = 1
	border = 1
    setInsetInOwner (morph label) (6 * scale) (4 * scale)
	readoutX = (labelW + (20 * scale))
    setInsetInOwner (morph readout) readoutX (4 * scale)
//  bgWidth = (width (owner morph))
    bgWidth = 400
    bgHeight = ((normalHeight (morph label)) + (8 * scale))
  } ('varPane' == style) {
	hide (morph label)
	border = (1 * scale)
	readoutX = 0
    setInsetInOwner (morph readout) (6 * scale) (3 * scale)
    bgWidth = (110 * scale)
    bgHeight = (20 * scale)
  }

  bm = (costumeData morph)
  if (true != keepBitmap) { bm = nil } // always rebuild bitmap if not called
  if (or (isNil bm) (bgWidth >= (width bm)) (bgHeight >= (height bm))) {
    bm = (newBitmap bgWidth bgHeight)
	fillRoundedRect (newShapeMaker bm) (rect 0 0 bgWidth bgHeight) radius bgColor border borderColor borderColor
	if (notNil dividerX) {
      fillRect bm borderColor dividerX 0 1 bgHeight
	} else {
	  frameX = (readoutX - (4 * scale))
	  if ('varPane' == style) { frameX = border }
	  fillRect bm (gray 240) frameX border (bgWidth - (frameX + border)) (bgHeight - (2 * border))
	}
    setCostume morph bm
  }
  setPinToTopLeft morph
  setScale morph oldScale
}
