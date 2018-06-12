// morphic toggle handlers, used for radio buttons and list items

defineClass Toggle morph trigger query transitionSelector

method setData Toggle obj {setData trigger obj}
method data Toggle {return (data trigger)}

method refresh Toggle {
  if (call query) {
    highlight trigger
  } else {
    normal trigger
  }
}

method isOn Toggle {return (call query)}

method handDownOn Toggle aHand {
  if (transitionSelector == 'handDownOn') {handDownOn trigger aHand}
  return true
}

method handEnter Toggle aHand {
  if (transitionSelector == 'handEnter') {
    if (and (not (isDown aHand)) (not (isOn this))) {
      handDownOn trigger aHand
      raise morph 'highlightOn' this
    }
  }
  if (notNil (hint trigger)) {
    addSchedule (global 'page') (schedule (action 'showHint' morph (hint trigger)) 300)
  }
}

method handLeave Toggle aHand {
  if (notNil (hint trigger)) {removeHint (page aHand)}
  raise morph 'highlightOff' this
  refresh this
}

method clicked Toggle {
  clicked trigger
  refresh this
  return true
}

method doubleClicked Toggle {return (doubleClicked trigger)}
method setHint Toggle aStringOrNil {setHint trigger aStringOrNil}

method rightClicked Toggle {
  raise morph 'handleContextRequest' this
  return true
}

method replaceCostumes Toggle normalBitmap highlightBitmap pressedBitmap {
  replaceCostumes trigger normalBitmap highlightBitmap pressedBitmap
}

method removeCostume Toggle costumeName {removeCostume trigger costumeName}

to toggleButton action query width height corner border hasFrame flat {
  scale = (global 'scale')
  if (isNil width) {width = (scale * 45)}
  if (isNil height) {height = (scale * 30)}
  if (isNil corner) {corner = (scale * 13)}
  if (isNil border) {border = (max 1 (scale / 2))}
  if (isNil hasFrame) {hasFrame = true}
  if (isNil flat) {flat = (global 'flat')}
  frameSize = 2
  incr = 0
  if (not hasFrame) {
    frameSize = 0
    incr = 2
  }
  btnColor = (color 130 130 130)
  btn = (buttonBitmap nil btnColor (height - frameSize) (height - frameSize) false (corner - frameSize) border nil flat)

  tbm = (buttonBitmap nil (color 100 200 100) width height true (corner + incr) border hasFrame flat)
  drawBitmap tbm btn (width - (height - frameSize)) (frameSize / 2)

  fbm = (buttonBitmap nil (color 180 100 100) width height true (corner + incr) border hasFrame flat)
  drawBitmap fbm btn 0 (frameSize / 2)

  pbm = (buttonBitmap nil (darker btnColor) width height true (corner + incr) border hasFrame flat)
  drawBitmap pbm btn ((width - (height - frameSize)) / 2) (frameSize / 2)

  bt = (new 'Trigger' nil action fbm tbm pbm)
  m = (newMorph)
  setMorph bt m
  setWidth (bounds m) width
  setHeight (bounds m) height
  tg = (new 'Toggle' m bt query) // 'handDownOn')
  setHandler m tg
  refresh tg
  return tg
}
