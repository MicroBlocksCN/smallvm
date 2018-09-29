// ScaledImage - Scaled image for presentations

defineClass ScaledImage morph image imgScale centerOnPage resizeStartY originalHeight

method morph ScaledImage { return morph }

to showImage aBitmap {
  // Example: showImage (newBitmap 100 100 (randomColor)

  result = (newScaledImage aBitmap)
  addPart (global 'page') result
  return result
}

to newScaledImage fileNameOrBitmap {
  result = (new 'ScaledImage' (newMorph) nil 1 false)
  setHandler (morph result) result
  setGrabRule (morph result) 'ignore'
  if (isClass fileNameOrBitmap 'String') {
	readFile result fileNameOrBitmap
  } (isClass fileNameOrBitmap 'Bitmap') {
	setImage result fileNameOrBitmap
  } else {
	setImage result (newBitmap 100 160 (randomColor))
  }
  setPosition (morph result) 100 100
  return result
}

method setImage ScaledImage bm {
  image = bm
  imgScale = 1
  redraw this
  return this
}

method setScale ScaledImage newScale {
  imgW = (max 1 (width image))
  imgH = (max 1 (height image))
  minScale = (min 1 (5 / (min imgW imgH)))
  maxScale = (max 1 (4000 / (max imgW imgH)))
  centerP = (rotationCenter morph)
  imgScale = (clamp newScale minScale maxScale)
  redraw this
  placeRotationCenter morph (first centerP) (last centerP)
  fixCentering this
}

// menu

method contextMenu ScaledImage {
  menu = (menu nil (action 'menuSelection' this) true)
  addItem menu 'bigger'
  addItem menu 'smaller'
  addItem menu 'normal size'
  addLine menu
  addItem menu 'center on page'
  addItem menu 'don''t center'
  addLine menu
  addItem menu 'read file'
  return menu
}

method menuSelection ScaledImage sel {
  factor = 2
  if ('bigger' == sel) { setScale this (factor * imgScale) }
  if ('smaller' == sel) { setScale this ((1.0 / factor) * imgScale) }
  if ('normal size' == sel) { setScale this 1.0 }
  if ('center on page' == sel) {
	centerOnPage = true
	fixCentering this
  }
  if ('don''t center' == sel) { centerOnPage = false }
  if ('read file' == sel) {
	fileName = (pickFileToOpen nil '' (array 'png' 'jpg'))
	if ('' != fileName) {
		readFile this fileName
		setScale this 1
	}
  }
}

method readFile ScaledImage fileName {
  data = (readFile fileName true)
  if (notNil data) {
	if (isPNG data) {
	  setImage this  (readFrom (new 'PNGReader') data)
	} (isJPEG data) {
	  setImage this  (jpegDecode data)
	} else {
	  error 'Unrecognized image format'
	}
  }
}

method fixCentering ScaledImage {
  if (true == centerOnPage) {
  	presentationWidth = (width (morph (global 'page')))
  	setLeft morph ((presentationWidth - (width morph)) / 2)
  }
}

method redraw ScaledImage {
  if (isNil imgScale) { imgScale = 1 }
  setCostume morph (scaleAndRotate image (imgScale * (global 'scale')))
}

// events

method rightClicked ScaledImage aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method handDownOn ScaledImage hand {
  if (shiftKeyDown (keyboard (page hand))) {
	resizeStartY = (y hand)
	originalHeight = (height (bounds morph))
	focusOn hand this
  } else {
	grab hand this
  }
  return true
}

method handMoveFocus ScaledImage hand {
  imgH = (max 1 (height image))
  minScale = (min 1 (5 / imgH))
  maxScale = (max 1 (4000 / imgH))
  newScale = ((originalHeight + (resizeStartY - (y hand))) / imgH)
  newScale = (clamp newScale minScale maxScale)
  setScale this newScale
}

method pageResized ScaledImage {
  fixCentering this
}
