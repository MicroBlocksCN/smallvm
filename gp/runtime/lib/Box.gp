// morphic box handler, used as mixin in a variety of morphs

defineClass Box morph color corner border isInset hasFrame isFlat borderColor

to newBox morph color corner border isInset hasFrame isFlat borderColor {
  result = (initialize (new 'Box'))
  if (notNil morph) {
  	setField result 'morph' morph
  	setHandler morph result
  }
  if (notNil color) {
	setField result 'color' color
	setField result 'borderColor' (darker color)
  }
  if (notNil corner) { setField result 'corner' corner }
  if (notNil border) { setField result 'border' border }
  if (notNil isInset) { setField result 'isInset' isInset }
  if (notNil hasFrame) { setField result 'hasFrame' hasFrame }
  if (notNil isFlat) { setField result 'isFlat' isFlat }
  if (notNil borderColor) { setField result 'borderColor' borderColor }
  return result
}

method initialize Box {
  scale = (global 'scale')
  morph = (newMorph this)
  color = (color 70 160 180)
  corner = (scale * 4)
  border = 0
  isInset = true
  hasFrame = false
  isFlat = false
  setExtent morph (60 * scale) (40 * scale)
  return this
}

method color Box {return color}
method setColor Box aColor {color = aColor}
method corner Box {return corner}
method setCorner Box num {corner = num}
method border Box {return border}
method setBorder Box num {border = num}
method setBorderColor Box aColor {borderColor = aColor}
method isInset Box {return isInset}
method setInset Box bool {isInset = bool}
method setFrame Box bool {hasFrame = bool}
method setFlat Box bool {isFlat = bool}

method drawOn Box aContext {
  if (0 == (alpha color)) { return }
  shapeMaker = (getShapeMaker aContext)
  if isFlat {
	fillRoundedRect shapeMaker (bounds morph) corner color border borderColor borderColor
  } else {
	drawButton shapeMaker (left morph) (top morph) (width morph) (height morph) color corner border isInset
  }
}

method redraw Box {
  bm = (newBitmap (width morph) (height morph))
  if (0 == (alpha color)) {return}
  if isFlat {
	fillRoundedRect (newShapeMaker bm) (rect 0 0 (width morph) (height morph)) corner color border borderColor borderColor
  } else {
	drawButton (newShapeMaker bm) 0 0 (width morph) (height morph) color corner border isInset
  }
  setCostume morph bm
}
