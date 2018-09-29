// SlideText - Text items for presentations

defineClass SlideText morph text centering

method morph SlideText { return morph }
method text SlideText { return text }
method centering SlideText  { return centering }

to newSlideText string fontSize centering {
  if (isNil string) { string = 'Slide Text'}
  if (isNil fontSize) { fontSize = (46 * (global 'scale')) }
  txt = (newText string 'Arial' fontSize)
  acceptEvents (morph txt) false
  setEditRule txt 'editable'
  result = (new 'SlideText' (newMorph) txt)
  setHandler (morph result) result
  setGrabRule (morph result) 'handle'
  setField result 'centering' centering
  addPart (morph result) (morph txt)
  setPosition (morph result) 100 100
  return result
}

// mouse events

method rightClicked SlideText aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method clicked SlideText {return (clicked text)}
method doubleClicked SlideText hand {return (doubleClicked text hand)}
method handDownOn SlideText hand {return (handDownOn text hand)}
// ignore handMoveOver, so the SlideText can be dragged without trying to select portions of the embedded text

// menu

method contextMenu SlideText {
  menu = (menu nil (action 'menuSelection' this) true)
  addItem menu 'title' 56
  addItem menu 'big' 46
  addItem menu 'medium' 38
  addItem menu 'small' 32
  addItem menu 'tiny' 28
  addLine menu
  addItem menu 'center'
  addItem menu 'left'
  addItem menu 'indent 1'
  addItem menu 'indent 2'
  addLine menu
  addItem menu 'center align text'
  addItem menu 'left align text'
  addLine menu
  addItem menu 'duplicate'
  addItem menu 'edit...'
  return menu
}

method menuSelection SlideText sel {
  if (isNumber sel) {
	newSize = (sel * (global 'scale'))
	setFont text 'Arial' newSize
	return
  }
  if ('duplicate' == sel) {
	dup = (newSlideText (text text) (fontSize text) centering)
	hand = (hand (handler (root morph)))
	setPosition (morph dup) ((x hand) - 10) ((y hand) - 10)
	grab hand dup
  }
  pageAlignments = (array 'center' 'left' 'indent 1' 'indent 2')
  if (contains pageAlignments sel) {
	centering = sel
	fixCentering this
  }
  if ('center align text' == sel) {
	align text 'center'
  } ('left align text' == sel) {
	align text 'left'
  } ('edit...' == sel) {
    popUpAtHand (contextMenu text) (global 'page')
  }
}

method justDropped SlideText { fixCentering this }
method pageResized SlideText { fixCentering this }

method fixCentering SlideText {
  if (isNil centering) { return }
  scale = (global 'scale')
//  presentationWidth = (1024 * scale)
  presentationWidth = (width (morph (global 'page')))
  x = (left morph)
  y = (top morph)
  if ('center' == centering) {
	x = ((presentationWidth - (width (morph text))) / 2)
  } ('left' == centering) {
	x = (80 * scale)
  } ('indent 1' == centering) {
	x = (160 * scale)
  } ('indent 2' == centering) {
	x = (240 * scale)
  }
  setPosition morph x y
}

method adjustToScaleBy SlideText factor {
  // Used to switch from retina to normal mode if necessary
  setPosition morph (truncate (factor * (left morph))) (truncate (factor * (top morph)))
  setFont text nil (truncate (factor * (fontSize text)))
}

to addSlideText s { addPart (global 'page') (newSlideText s) }

// serialization

method postSerialize SlideText {
  acceptEvents (morph text) false
}

