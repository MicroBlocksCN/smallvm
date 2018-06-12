// Widget to select and grab a bitmap from the screen.

defineClass ScreenGrabber morph mode grabAction

to screenGrab action {
  grabber = (initialize (new 'ScreenGrabber') action)
  setPosition (morph grabber) (handX) (handY)
  addPart (global 'page') (morph grabber)
  focusOn (hand (global 'page')) grabber
}

method initialize ScreenGrabber action {
  mode = 'move'
  grabAction = action
  scale = (global 'scale')
  morph = (newMorph this)
  setExtent morph (14 * scale) (14 * scale)
  setTransparentTouch morph true
  setGrabRule morph 'ignore'
  redraw this
  return this
}

method redraw ScreenGrabber {
  color = (color 200 0 200)
  w = (width morph)
  h = (height morph)
  bm = (newBitmap w h)
  fillRect bm color 0 0 2 h
  fillRect bm color (w - 2) 0 2 h
  fillRect bm color 0 0 w 2
  fillRect bm color 0 (h - 2) w 2
  setCostume morph bm
}

method handDownOn ScreenGrabber hand {
  // Start dragging to resize.
  mode = 'resize'
  focusOn hand this
  return true
}

method handMoveFocus ScreenGrabber hand {
  x = (x hand)
  y = (y hand)
  if ('move' == mode) {
	setPosition morph x y
  } else {
	if (or (x < (left morph)) (y < (top morph))) {
	  setPosition morph x y
	}
	scale = (global 'scale')
	w = (max (14 * scale) (x - (left morph)))
	h = (max (14 * scale) (y - (top morph)))
	setExtent morph w h
  }
  return true
}

method handUpOn ScreenGrabber hand {
  // If resizing, grab the screen area and exit.
  if ('resize' == mode) {
	if (notNil grabAction) {
	  inset = (2 * (global 'scale'))
	  bm = (takeSnapshotWithBounds (morph (global 'page')) (insetBy (bounds morph) inset))
	  call grabAction bm
	}
	removeFromOwner morph
  }
  return true
}
