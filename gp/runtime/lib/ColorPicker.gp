defineClass ColorPicker morph action paletteBM lastColor grayPalette colorPalette slider swatch inputs

to newColorPicker action initialColor withTransparentButton {
  // If there is already a ColorPicker on the screen, return it.
  // Otherwise, create and return a new one.

  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'ColorPicker') {
      picker = (handler m)
	  setAction picker action
	  if (notNil initialColor) {
	    setField picker 'lastColor' initialColor
	    selectColor picker initialColor true
	  }
	  changed (morph picker)
	  return picker
	}
  }
  return (initialize (new 'ColorPicker') action initialColor withTransparentButton)
}

method setAction ColorPicker anAction { action = anAction }

method initialize ColorPicker anAction initialColor withTransparentButton {
  morph = (newMorph this)
  setGrabRule morph 'ignore'
  setCostume morph (drawFrame this 285 166)
  addGrayPalette this 10 18 200 10
  addColorPalette this 10 32 200 128
  addSlider this 214 32 10 128
  addSwatch this 228 32 52 52
  if (isNil withTransparentButton) { withTransparentButton = false }
  if withTransparentButton { addTransparentButton this 244 141 }
  addCloseButton this 256 8
  addReadouts this 250 82
  action = anAction
  if (notNil initialColor) {
	lastColor = initialColor
	selectColor this initialColor true
  }
  return this
}

method drawOn ColorPicker ctx {
  r = (bounds morph)
  drawBitmap ctx (costumeData morph) (left r) (top r) // frame

  r = (bounds colorPalette)
  drawBitmap ctx (costumeData colorPalette) (left r) (top r)

  r = (bounds grayPalette)
  drawBitmap ctx (costumeData grayPalette) (left r) (top r)
}

method drawFrame ColorPicker w h {
  scale = (global 'scale')
  w = (w * scale)
  h = (h * scale)
  cornerRadius = (4 * scale)
  fillColor = (microBlocksColor 'blueGray' 850)
  border = (2 * scale)
  frameColor = (transparent)
  bm = (newBitmap (w + (2 * border)) (h + (2 * border)))
  fillRoundedRect (newShapeMaker bm) (rect 0 0 (width bm) (height bm)) cornerRadius fillColor border frameColor frameColor
  return bm
}

method addGrayPalette ColorPicker x y w h {
  scale = (global 'scale')
  x = (x * scale)
  y = (y * scale)
  w = (w * scale)
  h = (h * scale)

  grayPalette = (newMorph this)
  bm = (newBitmap w h)
  for i w {
	// grayscale ramp with a few extra full black/full white pixels at the ends
    xOffset = (i - 10)
    c = (gray ((255 * xOffset) / (w - 20)))
    fillRect bm c (i - 1) 0 1 h
  }
  setCostume grayPalette bm
  setPosition grayPalette x y
  addPart morph grayPalette
}

method addColorPalette ColorPicker x y w h {
  scale = (global 'scale')
  x = (x * scale)
  y = (y * scale)
  w = (w * scale)
  h = (h * scale)

  paletteBM = (newBitmap w h) // cache of color palette at full brightness
  drawColorPalette this paletteBM 1

  colorPalette = (newMorph this)
  bm = (newBitmap w h)
  setCostume colorPalette bm
  setPosition colorPalette x y
  addPart morph colorPalette
}

method addSlider ColorPicker x y w h {
  scale = (global 'scale')
  x = (x * scale)
  y = (y * scale)
  w = (w * scale)
  h = (h * scale)

  slider = (slider 'vertical' h (action 'setBrightness' this) w 0 100 50)
  setColors slider (microBlocksColor 'blueGray' 100) (microBlocksColor 'blueGray' 200)
  setPosition (morph slider) x y
  addPart morph (morph slider)
  slider changed
}

method addSwatch ColorPicker x y w h {
  scale = (global 'scale')
  x = (x * scale)
  y = (y * scale)
  w = (w * scale)
  h = (h * scale)

  swatch = (newMorph)
  setExtent swatch w h
  setPosition swatch x y
  setCostume swatch (gray 255)
  addPart morph swatch
}

method addTransparentButton ColorPicker x y {
  scale = (global 'scale')
  b = (pushButton 'Trans.' (action 'setTransparent' this))
  setPosition (morph b) (x * scale) (y * scale)
  addPart morph (morph b)
}

method setTransparent ColorPicker {
  if (notNil action) { call action (transparent) }
}

method addCloseButton ColorPicker x y {
  scale = (global 'scale')
  x = (x * scale)
  y = (y * scale)

  buttonW = (20 * scale)
  buttonH  = (15 * scale)
  closeBtn = (pushButton 'X' (action 'destroy' (morph this)) buttonW buttonH)
  setPosition (morph closeBtn) x y
  addPart morph (morph closeBtn)
}

method addReadouts ColorPicker x y {
  scale = (global 'scale')
  x = (left swatch)
  y = ((bottom swatch) + (9 * scale))
  fontSize = (13 * scale)
  inputs = (list)
  color = (microBlocksColor 'blueGray' 200)
  for component (array 'R' 'G' 'B') {
	text = (newText component 'Courier Bold' fontSize color)
	setPosition (morph text) x (y + (2 * scale))
	addPart morph (morph text)

	input = (newInput this 0)
	add inputs input
	setPosition (morph input) ((right (morph text)) + (6 * scale)) y
	addPart morph (morph input)

	y += (26 * scale)
  }
}

method newInput ColorPicker value {
  scale = (global 'scale')
  input = (newText (toString value) 'Courier Bold' (13 * scale) (microBlocksColor 'blueGray' 900))
  setBorders input (3 * scale) (2 * scale) true
  setEditRule input 'numerical'
  setGrabRule (morph input) 'ignore'
  inputFrame = (newBox nil (gray 255) 1 nil false false)
  addPart (morph inputFrame) (morph input)
  setExtent (morph inputFrame) (36 * scale) (15 * scale)
  return inputFrame
}

method setBrightness ColorPicker n {
  n = (clamp (n / 100.0) 0 1)
  n = (1.0 - (n * n)) // use a quadratic function that spread out brighter end of range
  bm = (costumeData colorPalette)
  fill bm (gray 0)
  alpha = (clamp (toInteger (255 * n)) 0 255)
  drawBitmap bm paletteBM 0 0 alpha
  setCostume colorPalette bm
  if (notNil lastColor) {
	c = (colorHSV (hue lastColor) (saturation lastColor) (alpha / 255))
	selectColor this c false
  }
}

method handDownOn ColorPicker aHand {
  x = (x aHand)
  y = (y aHand)
  if (or (containsPoint (bounds grayPalette) x y)
		 (containsPoint (bounds colorPalette) x y)) {
	focusOn aHand this
	handMoveFocus this aHand
	setCursor 'crosshair'
  } else {
	grab aHand this
  }
  return true
}

method handUpOn ColorPicker aHand {
  setCursor 'default'
  return true
}

method handMoveFocus ColorPicker aHand {
  bm = (takeSnapshotWithBounds (morph (global 'page')) (rect (handX) (handY) 1 1))
  lastColor = (getPixel bm 0 0)
  selectColor this lastColor true
}

method selectColor ColorPicker c updateSlider {
  setCostume swatch c
  updateRGBReadouts this c
  if updateSlider { setValue slider (100.0 * (sqrt (1.0 - (brightness c)))) }
  if (notNil action) { call action c }
  changed morph
}

method textEdited ColorPicker input {
  // is raised while being edited
  text = (text input)
  if ((count text) > 3) {
    setText input (substring text 1 3)
  }
}

method textChanged ColorPicker input {
  // is raised while finished editing
  setText input (leftPadded (text input) 3 '0')
  updateComponents this
}

method updateComponents ColorPicker {
  c = (array 0 0 0)
  for i 3 {
    input = (handler (at (parts (morph (at inputs i))) 1))
	atPut c i (toNumber (text input))
  }
  if (or
	((at c 1) != (red lastColor))
	((at c 2) != (green lastColor))
	((at c 3) != (blue lastColor))
  ) {
	  selectColor this (color (at c 1) (at c 2) (at c 3))
  }
}

method updateRGBReadouts ColorPicker c {
  for i 3 {
    input = (handler (at (parts (morph (at inputs i))) 1))
	setText input (leftPadded (toString (getField c (at (array 'r' 'g' 'b') i))) 3 '0')
  }
}

method drawColorPalette ColorPicker bm brightness {
  w = (width bm)
  h = (height bm)
  pixels = (getField bm 'pixelData')
  for x w {
    for y h {
	  hue = ((toFloat (360 * x)) / w)
	  sat = ((toFloat y) / h)
	  setBitmapHSV this pixels ((w * (y - 1)) + x) hue sat brightness
	}
  }
}

method setBitmapHSV ColorPicker pixelData pixelIndex h s v {
  // Optimized version of colorHSV for building a color palette (2x faster).
  // Assumes h, s, v are floats in ranges 0..360 (h) and 0..1 (s and v).

  h = (h % 360.0)
  i = (truncate (h / 60.0)) // integer 0..5
  f = ((h / 60.0) - i) // fractional part
  p = (v * (1 - s))
  q = (v * (1 - (s * f)))
  t = (v * (1 - (s * (1 - f))))

  if (i == 0) {
    r = v; g = t; b = p
  } (i == 1) {
    r = q; g = v; b = p
  } (i == 2) {
    r = p; g = v; b = t
  } (i == 3) {
    r = p; g = q; b = v
  } (i == 4) {
    r = t; g = p; b = v
  } (i == 5) {
    r = v; g = p; b = q
  }
  setPixelRGBA pixelData pixelIndex (truncate (255 * r)) (truncate (255 * g)) (truncate (255 * b)) 255
}
