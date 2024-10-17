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
    for each anAction {
      if (notNil each) {call each}
	}
  } (notNil anAction) {
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
method highlightCostume Trigger { return highlightCostume }
method pressedCostume Trigger { return pressedCostume }

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

to pushButton label action minWidth minHeight isActive onDark {
  btn = (new 'Trigger' (newMorph) action)
  setHandler (morph btn) btn
  setGrabRule (morph btn) 'ignore'
  drawLabelCostumes btn label minWidth minHeight isActive onDark
  return btn
}

method drawLabelCostumes Trigger label minWidth minHeight isActive onDark {
  scale = (global 'scale')
  if (isNil minWidth) { minWidth = (30 * scale) }
  if (isNil minHeight) { minHeight = (20 * scale) }

  // default colors on light bg
  labelColor = (microBlocksColor 'blueGray' 900)
  borderColor = (microBlocksColor 'blueGray' 200)
  bgColor = (transparent)

  if isActive {
    labelColor = (microBlocksColor 'blueGray' 50)
	bgColor = (microBlocksColor 'blueGray' 900)
	borderColor = bgColor
  } onDark {
    labelColor = (microBlocksColor 'blueGray' 200)
	borderColor = (microBlocksColor 'blueGray' 700)
  } ('X' == label) {
    // special case for Window close button
	bitmap = (readSVGIcon 'icon-close' (microBlocksColor 'blueGray' 100))
	hlBitmap = (readSVGIcon 'icon-close' (microBlocksColor 'yellow'))
	normalCostume = (buttonImage bitmap (transparent) 0 0 false false 12 12 true (transparent))
	highlightCostume = (buttonImage hlBitmap (transparent) 0 0 false false 12 12 true (transparent))
	pressedCostume = (buttonImage hlBitmap (transparent) 0 0 true false 12 12 true (transparent))
	setCostume morph normalCostume
	return
  }

  highlightCostume = (buttonBitmap label (array (microBlocksColor 'blueGray' 900) (transparent) (microBlocksColor 'yellow')) minWidth minHeight)
  pressedCostume = (buttonBitmap label (array (microBlocksColor 'blueGray' 900) (transparent) (microBlocksColor 'yellow')) minWidth minHeight true)
  normalCostume = (buttonBitmap label (array labelColor borderColor bgColor) minWidth minHeight true)
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
	if (isClass color 'Array') {
	  textColor = (at color 1)
	  borderColor = (at color 2)
	  bgColor = (at color 3)
	  shadowColor = (darker (at color 1))
	} else {
	  shadowColor = (darker color)
	}
    lbm = (stringImage (localized label) fontName fontSize textColor 'center' shadowColor (off * -1) nil nil nil nil nil nil flat)
  } else {
    lbm = nil
  }
  return (buttonImage lbm bgColor corner border isInset hasFrame w h flat borderColor)
}

to buttonImage labelBitmap color corner border isInset hasFrame width height flat borderColor {
  // answer a new bitmap depicting a push button rendered
  // with the specified box settings.
  // the bitmap's width and height are determined by the - optional -
  // labelBitmap's dimensions, width and height are also optional arguments
  // allowing the image to be bigger than the automatic minimum

  scale = (global 'scale')

  if (isNil color) {color = (color 130 130 130)}
  if (isNil borderColor) {borderColor = (gray 0)}
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
  fillRoundedRect (newShapeMaker bm) (rect 0 0 w h) corner color 1 borderColor

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
