// MorphRefIcon - Display an arrow pointing to the target morph while pressed.
// The target is retrieved by evaluating an action.

defineClass MorphRefIcon morph isActive getTarget

method isActive MorphRefIcon { return isActive }

method targetMorph MorphRefIcon {
  if (isNil getTarget) { return nil }
  result = (call getTarget)
  if (hasField result 'morph') {
	result = (getField result 'morph')
  }
  if (not (isClass result 'Morph')) { return nil }
  return result
}

method initialize MorphRefIcon varName targetObj targetModule {
  morph = (newMorph this)
  setCostume morph (makeIcon this)
  setScale morph ((global 'scale') / 2)
  setTransparentTouch morph true
  setFPS morph 5
  hide morph // initially hidden; step will make it visible if it is a morph
  isActive = false
  if (notNil varName) {
	if (isNil targetObj) {
	  getTarget = (action 'shared' varName targetModule)
	} else {
	  if ('this' == varName) {
		getTarget = (action 'id' targetObj)
	  } else {
		getTarget = (action 'getField' targetObj varName)
	  }
	}
  }
  return this
}

method makeIcon MorphRefIcon {
  bm = (newBitmap 34 20)
  pen = (newVectorPen bm)

  beginPath pen 1 10
  setHeading pen 0
  forward pen 32 57
  setHeading pen 180
  forward pen 32 57
  stroke pen (gray 50) 2

  beginPath pen 10 10
  setHeading pen 270
  turn pen 360 7
  fill pen (gray 50)
  return bm
}

method step MorphRefIcon {
  // Show only when the target is a morph.
  if (isClass (targetMorph this) 'Morph') {
	show morph
  } else {
	hide morph
  }
}

method handDownOn MorphRefIcon hand {
  handLeave this hand // cancel the hint
  focusOn hand this
  isActive = true
  return true
}

method handUpOn MorphRefIcon hand {
  isActive = false
  return true
}

// hint

method handEnter MorphRefIcon aHand {
  hint = 'Press and hold to show an arrow pointing to the object referred to by this variable.
To make this variable refer to a different object, drop that object onto the readout.'

  hint = 'Press and hold to point to the object in this variable.
To refer to a different object, drop it onto the readout.'
  addSchedule (global 'page') (schedule (action 'showHint' morph hint) 800)
}

method handLeave MorphRefIcon aHand {
  removeSchedulesFor (global 'page') 'showHint' morph
  removeHint (page aHand)
}
