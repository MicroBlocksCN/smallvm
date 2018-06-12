// basic morphic button handlers

defineClass Trigger morph action normalCostume highlightCostume pressedCostume data renderer onDoubleClick hint downX downY

method setAction Trigger aCallableOrArray {action = aCallableOrArray}
method setData Trigger obj {data = obj}
method data Trigger {return data}
method setRenderer Trigger obj {renderer = obj}
method onDoubleClick Trigger anAction {onDoubleClick = anAction}
method setHint Trigger aStringOrNil {hint = aStringOrNil}
method hint Trigger {return hint}

method trigger Trigger anAction {
  if (isNil anAction) {anAction = action}
  if (isClass anAction 'Array') {
    for each anAction {call each}
  } else {
    call anAction
  }
}

method normal Trigger {
  if (isNil normalCostume) {
    if (notNil renderer) {
      normalCostume = (call 'normalCostume' renderer data)
    }
  }
  if (notNil normalCostume) { setCostume morph normalCostume true }
  if (notNil renderer) {
      highlightCostume = nil
      pressedCostume = nil
  }
}

method highlight Trigger {
  if (isNil highlightCostume) {
    if (notNil renderer) {
      highlightCostume = (call 'highlightCostume' renderer data)
    }
  }
  if (notNil highlightCostume) { setCostume morph highlightCostume true }
}

method press Trigger {
  if (isNil pressedCostume) {
    if (notNil renderer) {
      pressedCostume = (call 'pressedCostume' renderer data)
    }
  }
  if (notNil pressedCostume) { setCostume morph pressedCostume true }
}

method handEnter Trigger aHand {
  highlight this
  if (notNil hint) {
	addSchedule (global 'page') (schedule (action 'showHint' morph hint) 300)
  }
}

method handLeave Trigger aHand {
  normal this
  if (notNil hint) {removeHint (page aHand)}
  removeSchedulesFor (global 'page') 'showHint' morph
}

method handDownOn Trigger aHand {
  downX = (x aHand)
  downY = (y aHand)
  press this
  return true
}

method handUpOn Trigger aHand {
  wasDragged = (isNil (getField aHand 'lastTouched'))
  setField aHand 'lastTouched' nil // cancel clicked event
  press this
  if (notNil hint) {removeHint (page aHand)}
  removeSchedulesFor (global 'page') 'showHint' morph
  doOneCycle (page aHand)
  if (and (not wasDragged) (notNil downX) (notNil downY)) {
     x = (downX - (x aHand))
     y = (downY - (y aHand))
     if (((x * x) + (y * y)) < 100) {
       trigger this
       downX = nil
       downY = nil
       return true
     }
   }
  return false
}

method clicked Trigger {
  highlight this
  trigger this
  return true
}

method doubleClicked Trigger {
  trigger this onDoubleClick
  return true
}

method rightClicked Trigger {
  raise morph 'handleContextRequest' this
  return true
}

method replaceCostumes Trigger normalBM highlightBM pressedBM {
  normalCostume = normalBM
  highlightCostume = highlightBM
  pressedCostume = pressedBM
  normal this
}

method removeCostume Trigger costumeName {
  if (costumeName == 'normal') {
    normalCostume = nil
  } (costumeName == 'highlight') {
    highlightCostume = nil
  } (costumeName == 'pressed') {
    pressedCostume = nil
  }
}

method clearCostumes Trigger {
  normalCostume = nil
  highlightCostume = nil
  pressedCostume = nil
  setCostume morph nil
}

to pushButton label color action minWidth minHeight {
  btn = (new 'Trigger' (newMorph) action)
  setHandler (morph btn) btn
  drawLabelCostumes btn label color minWidth minHeight
  return btn
}

to downArrowButton color action {
  btn = (new 'Trigger' (newMorph) action)
  setTransparentTouch (morph btn) true
  setHandler (morph btn) btn
  drawDownArrowCostumes btn color
  return btn
}

method drawDownArrowCostumes Trigger color {
  if (isNil color) {color = (color)}

  scale = (global 'scale')
  size = (scale * 10)
  unit = (size / 2)
  space = (size / 3)

  bm = (newBitmap (+ size space 1) size)
  fillArrow (newShapeMaker bm) (rect 0 unit size unit) 'down' color

  normalCostume = bm
  highlightCostume = bm
  pressedCostume = bm
  setCostume morph normalCostume
}

method drawLabelCostumes Trigger label color minWidth minHeight {
  if (isNil minWidth) {minWidth = 0}
  if (isNil minHeight) {minHeight = 0}
  normalCostume = (buttonBitmap label color minWidth minHeight)
  highlightCostume = (buttonBitmap label (darker color) minWidth minHeight)
  pressedCostume = (buttonBitmap label (darker color) minWidth minHeight true)
  setCostume morph normalCostume
}

to buttonBitmap label color w h isInset corner border hasFrame flat {
  if (isNil flat) {flat = (global 'flat')}
  if (isClass label 'String') {
    scale = (global 'scale')
    off = (max (scale / 2) 1)
    lbm = (stringImage label 'Arial Bold' (scale * 11) (color 255 255 255) 'center' (darker color) (off * -1) nil nil nil nil nil nil flat)
  } else {
    lbm = nil
  }
  return (buttonImage lbm color corner border isInset hasFrame w h flat)
}

to buttonImage labelBitmap color corner border isInset hasFrame width height flat {
  // answer a new bitmap depicting a push button rendered
  // with the specified box settings.
  // the bitmap's width and height are determined by the - optional -
  // labelBitmap's dimensions, width and height are also optional arguments
  // allowing the image to be bigger than the automatic minimum

  scale = (global 'scale')

  if (isNil color) {color = (color 130 130 130)}
  if (isNil corner) {corner = (scale * 6)}
  if (isNil border) {border = (max 1 (scale / 2))}
  if (isNil isInset) {isInset = false}
  if (isNil hasFrame) {hasFrame = true}
  if (isNil width) {width = (+ corner corner border border)}
  if (isNil height) {height = (+ border border)}
  if (isNil flat) {flat = (global 'flat')}

  lblWidth = 0
  if (isClass labelBitmap 'Bitmap') {lblWidth = (width labelBitmap)}
  lblHeight = 0
  if (isClass labelBitmap 'Bitmap') {lblHeight = (height labelBitmap)}

  if flat {border = 0}

  w = (max (+ lblWidth corner corner border border) width)
  h = (max (+ lblHeight border border) height)

  bm = (newBitmap w h)
  drawButton (newShapeMaker bm) 0 0 w h color corner border isInset
  if (isClass labelBitmap 'Bitmap') {
    off = 0
    if isInset {off = (max (border / 2) 1)}
    drawBitmap bm labelBitmap (((w - (width labelBitmap)) / 2) + off) (((h - (height labelBitmap)) / 2) + off)
  }
  return bm
}

// serialization

method preSerialize Trigger {
  if (notNil renderer) { clearCostumes this }
  downX = nil
  downY = nil
}
