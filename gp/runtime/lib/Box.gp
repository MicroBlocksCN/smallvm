// morphic box handler, used as mixin in a variety of morphs

defineClass Box morph color corner border isInset hasFrame

to newBox morph color corner border isInset hasFrame {
  result = (initialize (new 'Box'))
  if (notNil morph) { setField result 'morph' morph }
  if (notNil color) { setField result 'color' color }
  if (notNil corner) { setField result 'corner' corner }
  if (notNil border) { setField result 'border' border }
  if (notNil isInset) { setField result 'isInset' isInset }
  if (notNil hasFrame) { setField result 'hasFrame' hasFrame }
  return result
}

method initialize Box {
  scale = (global 'scale')
  morph = (newMorph this)
  color = (color 200 200 130)
  corner = (scale * 4)
  border = (max 1 (scale / 2))
  isInset = true
  hasFrame = false
  setExtent morph 40 30
  return this
}

method color Box {return color}
method setColor Box aColor {color = aColor}
method corner Box {return corner}
method setCorner Box num {corner = num}
method border Box {return border}
method setBorder Box num {border = num}
method isInset Box {return isInset}
method setInset Box bool {isInset = bool}
method setFrame Box bool {hasFrame = bool}

method redraw Box {
  bm = (newBitmap (width morph) (height morph))
  if (0 == (alpha color)) {return}
  if (global 'flat') {border = 0}
  drawButton (newShapeMaker bm) 0 0 (width morph) (height morph) color corner border isInset
  setCostume morph bm
}
