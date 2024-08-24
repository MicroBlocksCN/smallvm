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
  setCursor 'pointer'
  highlight this
  if (notNil hint) {
	addSchedule (global 'page') (schedule (action 'showTooltip' morph hint) 300)
  }
}

method handLeave Trigger aHand {
  setCursor 'default'
  // handEnter happens before handLeave, so cursor wouldn't go back to finger
  // when you move between two buttons without any space in between. A temporary
  // solution is to re-trigger handEnter on the new morph under the hand.
  handEnter (objectAt aHand) aHand
  normal this
  if (notNil hint) {removeTooltip (page aHand)}
  removeSchedulesFor (global 'page') 'showTooltip' morph
}

method handDownOn Trigger aHand {
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
//  if (not wasDragged) {
       trigger this
       return true
//  } else { print 'TriggerUpMoved' }
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

method normalCostume Trigger { return normalCostume }

method replaceCostumes Trigger normalBM highlightBM pressedBM {
  if (notNil normalBM) {
	setExtent morph (width normalBM) (height normalBM)
  }
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

to pushButton label color action minWidth minHeight makeDefault {
  btn = (new 'Trigger' (newMorph) action)
  setHandler (morph btn) btn
  setGrabRule (morph btn) 'ignore'
  drawLabelCostumes btn label color minWidth minHeight makeDefault
  return btn
}

method drawLabelCostumes Trigger label color minWidth minHeight makeDefault {
  scale = (global 'scale')
  if (isNil minWidth) { minWidth = (30 * scale) }
  if (isNil minHeight) { minHeight = (20 * scale) }
  if makeDefault {
	normalCostume = (buttonBitmap label (gray 0) minWidth minHeight)
  } ('X' == label) {
    // special case for Window close button
	normalCostume = (buttonBitmap label (microBlocksColor 'blueGray' 400) minWidth minHeight)
  } else {
	normalCostume = (buttonBitmap label (transparent) minWidth minHeight)
  }
  highlightCostume = (buttonBitmap label (microBlocksColor 'yellow') minWidth minHeight)
  pressedCostume = (buttonBitmap label (microBlocksColor 'yellow') minWidth minHeight true)
  setCostume morph normalCostume
}

to buttonBitmap label color w h isInset corner border hasFrame flat {
  if (isNil flat) {flat = true}
  if (isClass label 'String') {
    scale = (global 'scale')
    off = (max (scale / 2) 1)
    fontName = 'Arial Bold'
    fontSize = (11 * scale)
    textColor = (gray 0)
    if (color == (gray 0)) { textColor = (gray 255) }
    lbm = (stringImage (localized label) fontName fontSize textColor 'center' (darker color) (off * -1) nil nil nil nil nil nil flat)
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
  if (isNil corner) {corner = (half (max width height))}
  if (isNil border) {border = (max 1 (scale / 2))}
  if (isNil isInset) {isInset = false}
  if (isNil hasFrame) {hasFrame = true}
  if (isNil width) {width = (+ corner corner border border)}
  if (isNil height) {height = (+ border border)}
  if (isNil flat) {flat = false}

  lblWidth = 0
  if (isClass labelBitmap 'Bitmap') {lblWidth = (width labelBitmap)}
  lblHeight = 0
  if (isClass labelBitmap 'Bitmap') {lblHeight = (height labelBitmap)}

  if flat {border = 0}

  w = (max (+ lblWidth corner corner (-5 * scale)) width)
  h = (max (+ lblHeight border border) height)

  bm = (newBitmap w h)
  fillRoundedRect (newShapeMaker bm) (rect 0 0 w h) corner color 1 (gray 0)

  if (isClass labelBitmap 'Bitmap') {
    off = 0
    if isInset {off = (max (border / 2) 1)}
    drawBitmap bm labelBitmap (((w - (width labelBitmap)) / 2) + off) (((h - (height labelBitmap)) / 2) + off)
  }
  if ('Browser' != (platform)) { unmultiplyAlpha bm }
  return bm
}

// serialization

method preSerialize Trigger {
  if (notNil renderer) { clearCostumes this }
}
