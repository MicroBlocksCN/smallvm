// Button.gp - Simple button
// addPart (global 'page') (morph (newButton)) xxx

defineClass Button morph clickAction offCostume onCostume isOn

to newButton label action {
  return (initialize (new 'Button') label action)
}

method initialize Button label action {
  if (isNil label) { label = 'Button' }
  if (isNil action) { action = (action 'toggle' this) }
  morph = (newMorph this)
  setLabel this label
  clickAction = action
  isOn = false
  return this
}

method toggle Button { setOn this (not isOn) }
method isOn Button { return isOn }

method setOn Button bool {
  isOn = (true == bool)
  if (and isOn (notNil onCostume)) {
	setCostume morph onCostume
  } else {
	setCostume morph offCostume
  }
}

method setLabel Button label offColor onColor minWidth minHeight fontName fontSize fontColor {
  if (isNil offColor) { offColor = (gray 120) }
  if (isNil onColor) { onColor = (lighter offColor 50) }
  offBM = (makeCostume this label offColor minWidth minHeight fontName fontSize fontColor)
  onBM = (makeCostume this label onColor minWidth minHeight fontName fontSize fontColor)
  setCostumes this offBM onBM
}

method setCostumes Button offBM onBM {
  offCostume = offBM
  onCostume = onBM
  setCostume morph offCostume
}

// button costumes

method makeCostume Button label color minWidth minHeight fontName fontSize fontColor {
  // Draw a button with the given label and color. The label can be a String or a Bitmap.
  scale = (global 'scale')
  if (isNil label) { label = 'Click!' }
  if (isNil color) { color = (gray 120) }
  if (isNil minWidth) { minWidth = 10 }
  if (isNil minHeight) { minHeight = 10 }
  if (isNil fontName) { fontName = 'Arial Bold' }
  if (isNil fontSize) { fontSize = (scale * 11) }
  if (isNil fontColor) { fontColor = (gray 255) }

  borderColor = (gray 80)
  borderW = scale
  cornerRadius = (5 * scale)
  hPadding = (14 * scale)
  vPadding = (10 * scale)

  if (isClass label 'String') {
	setFont fontName fontSize
	labelBitmap = (newBitmap (stringWidth label) (fontHeight))
	drawString labelBitmap label fontColor
  } else {
	labelBitmap = label
  }

  w = (max minWidth ((width labelBitmap) + hPadding))
  h = (max minHeight ((height labelBitmap) + vPadding))

  bm = (newBitmap w h)
  fillRoundedRect (newVectorPen bm) (rect 0 0 w h) cornerRadius color borderW borderColor
  drawBitmap bm labelBitmap (half (w - (width labelBitmap))) (half (h - (height labelBitmap)))
  return bm
}

// events

method handDownOn Button hand {
  if (notNil clickAction) {
	call clickAction this
  }
  return true
}

method handEnter Button aHand {
  if (notNil onCostume) {
	setCostume morph onCostume
  }
}

method handLeave Button aHand {
  setOn this isOn
}
