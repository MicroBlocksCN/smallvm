defineClass ColorPicker morph action paletteBM lastColor grayPalette colorPalette slider swatch rText gText bText

to newColorPicker action initialColor {
  return (initialize (new 'ColorPicker') action initialColor)
}

method initialize ColorPicker anAction initialColor {
  morph = (newMorph this)
  setGrabRule morph 'ignore'
  setCostume morph (drawFrame this 297 158)
  addGrayPalette this 10 10 200 10
  addColorPalette this 10 25 200 128
  addSlider this 220 25 10 128
  addSwatch this 240 25 50 50
  addTransparentButton this 244 141
  addCloseButton this 273 5
  addReadouts this 250 85
  action = anAction
  if (notNil initialColor) {
	lastColor = initialColor
	selectColor this initialColor true
  }
  return this
}

method drawFrame ColorPicker w h {
  scale = (global 'scale')
  w = (w * scale)
  h = (h * scale)
  cornerRadius = (4 * scale)
  fillColor = (gray 200)
  border = (2 * scale)
  frameColor = (gray 100)
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
  setPosition (morph slider) x y
  addPart morph (morph slider)
}

method addSwatch ColorPicker x y w h {
  scale = (global 'scale')
  x = (x * scale)
  y = (y * scale)
  w = (w * scale)
  h = (h * scale)

  swatch = (newMorph)
  bm = (newBitmap w h (color 200 0 0))
  setCostume swatch bm
  setPosition swatch x y
  addPart morph swatch
}

method addTransparentButton ColorPicker x y {
  scale = (global 'scale')
  b = (pushButton 'Trans.' (gray 100) (action 'setTransparent' this))
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

  closeBtn = (pushButton 'X' (color 140 100 100) (action 'destroy' (morph this)))
  setPosition (morph closeBtn) x y
  addPart morph (morph closeBtn)
}

method addReadouts ColorPicker x y {
  scale = (global 'scale')
  x = ((left swatch) + (4 * scale))
  y = ((bottom swatch) + (10 * scale))
  fontSize = (13 * scale)
  rText = (newText 'R   0' 'Courier Bold' fontSize)
  gText = (newText 'G   0' 'Courier Bold' fontSize)
  bText = (newText 'B   0' 'Courier Bold' fontSize)
  setPosition (morph rText) x y
  setPosition (morph gText) x (y + (13 * scale))
  setPosition (morph bText) x (y + (26 * scale))
  addPart morph (morph rText)
  addPart morph (morph gText)
  addPart morph (morph bText)
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
  } else {
	grab aHand this
  }
  return true
}

method handMoveFocus ColorPicker aHand {
  bm = (takeSnapshotWithBounds (morph (global 'page')) (rect (handX) (handY) 1 1))
  lastColor = (getPixel bm 0 0)
  selectColor this lastColor true
}

method selectColor ColorPicker c updateSlider {
  fill (costumeData swatch) c
  costumeChanged swatch
  updateRGBReadouts this c
  if updateSlider { setValue slider (100.0 * (sqrt (1.0 - (brightness c)))) }
  if (notNil action) { call action c }
}

method updateRGBReadouts ColorPicker c {
  setText rText (join 'R ' (leftPadded (toString (red c)) 3 '0'))
  setText gText (join 'G ' (leftPadded (toString (green c)) 3 '0'))
  setText bText (join 'B ' (leftPadded (toString (blue c)) 3 '0'))
}

method drawColorPalette ColorPicker bm brightness {
  w = (width bm)
  h = (height bm)
  pixels = (getField bm 'pixelData')
  for x w {
    gcIfNeeded // this method generates a LOT of float objects, so may need to GC
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
