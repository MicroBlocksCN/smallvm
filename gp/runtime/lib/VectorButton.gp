// VectorButton.gp - Simple button that uses SVG vector costumes.

defineClass VectorButton morph clickAction hint isOn hoverOver offPaths onPaths

to newVectorButton action hint {
  return (initialize (new 'VectorButton') action hint)
}

method initialize VectorButton action hintString {
  if (isNil action) { action = (action 'toggle' this) }
  if (isNil hintString) { hintString = '' }
  morph = (newMorph this)
  setGrabRule morph 'ignore'
  setExtent morph (24 * (global 'scale')) (24 * (global 'scale'))
  setDefaultPaths this
  clickAction = action
  hint = hintString
  isOn = false
  hoverOver = false
  return this
}

method setHint VectorButton aStringOrNil { hint = aStringOrNil }
method hint VectorButton { return hint }

method toggle VectorButton { setOn this (not isOn) }
method isOn VectorButton { return isOn }

method setOn VectorButton bool {
  isOn = (true == bool)
  changed morph
}

method setDefaultPaths VectorButton {
  scale = (global 'scale')
  r = (rect 0 0 (width morph) (height morph))
  corner = (5 * scale)

  sm = (newShapeMakerForPathRecording)
  fillRoundedRect sm r corner (gray 100) scale
  offPaths = (recordedPaths sm)

  sm = (newShapeMakerForPathRecording)
  fillRoundedRect sm r corner (color 255 255 0) scale
  onPaths = (recordedPaths sm)
}

method setSVGPaths VectorButton offPathList onPathList {
  // Set the off and on paths. If onPathList is omitted offPathList will be used.

  offPaths = offPathList
  onPaths = onPathList
  if (isNil onPaths) { onPaths = offPaths }
  changed morph
}

// drawing

method drawOn VectorButton ctx {
  if (or isOn hoverOver) {
    drawCachedPaths ctx onPaths (left morph) (top morph)
  } else {
    drawCachedPaths ctx offPaths (left morph) (top morph)
  }
}

// events

method handDownOn VectorButton hand {
  if (notNil clickAction) { call clickAction this }
  return true
}

method handEnter VectorButton aHand {
  hoverOver = (containsPoint (bounds morph) (x aHand) (y aHand))
  if hoverOver { setCursor 'pointer' }
  changed morph
}

method handLeave VectorButton aHand {
  setCursor 'default'
  // handEnter happens before handLeave, so cursor wouldn't go back to pointer
  // when moving between two buttons without any space in between. A temporary
  // solution is to re-trigger handEnter on the new morph under the hand.
  handEnter (objectAt aHand) aHand
  hoverOver = false
  changed morph
}
