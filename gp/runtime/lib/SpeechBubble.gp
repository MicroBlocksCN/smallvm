// morphic speech bubble handlers, used for hints and tool tips

defineClass SpeechBubble morph contents direction shadowOffset clientMorph lastClientVis

to newBubble aString bubbleWidth direction {
  return (initialize (new 'SpeechBubble') aString bubbleWidth direction)
}

method initialize SpeechBubble aString bubbleWidth dir {
  scale = (global 'scale')
  font = 'Arial'
  fontSize = (14 * scale)
  maxLines = 30
  shadowOffset = 3 // optional; if nil, no shadow is drawn

  if (isNil aString) {aString = 'hint!'}
  if (isNil bubbleWidth) {bubbleWidth = 200}
  if (isNil dir) {dir = 'right'}
  direction = dir

  setFont font fontSize
  lines = (toList (wordWrapped aString bubbleWidth))
  if ((count lines) > maxLines) {
	lines = (copyFromTo lines 1 maxLines)
	add lines '...'
  }
  contents = (newText (joinStrings lines (newline)) font fontSize (gray 0) 'center')

  morph = (newMorph this)
  addPart morph (morph contents)
  fixLayout this
  return this
}

method fixLayout SpeechBubble {
  scale = (global 'scale')
  tailH = 8 // height of bubble tail
  hInset = (9 * scale)
  vInset = (5 * scale)
  if ((width (morph contents)) > 100) {
	// use more generous padding for wider text
	hInset = (13 * scale)
	vInset = (9 * scale)
  }
  removeShadowPart morph
  setPosition (morph contents) ((left morph) + hInset) ((top morph) + vInset)
  w = ((width (morph contents)) + (2 * hInset))
  h = (+ (height (morph contents)) (2 * vInset) (tailH * scale))
  setExtent morph w h
  if (notNil shadowOffset) {
    addPart morph (shadowPart morph 100 (shadowOffset * scale))
  }
}

method layoutChanged SpeechBubble {fixLayout this}

method redraw SpeechBubble {
  scale = (global 'scale')
  bm = (newBitmap (width morph) (height morph))
  drawSpeechBubble (newShapeMaker bm) (rect 0 0 (width bm) (height bm)) scale direction
  setCostume morph bm
}

// talk bubble support

method clientMorph SpeechBubble { return clientMorph }
method setClientMorph SpeechBubble m { clientMorph = m }

method step SpeechBubble {
  // Make bubble follow a moving clientMorph.

  if (isNil clientMorph) { return }
  if (isNil (owner clientMorph)) { // client was deleted
	removePart (owner morph) morph
	return
  }
  scale = (global 'scale')
  vis = (visibleBounds clientMorph)
  if (lastClientVis == vis) { return }
  overlap = (7 * scale)
  rightSpace = ((right (owner morph)) - (right vis))
  setBottom morph (vCenter vis)
  if (rightSpace > (width morph)) {
	setDirection this 'right'
    setLeft morph (- (right vis) overlap)
  } else {
	setDirection this 'left'
    setRight morph ((left vis) + overlap)
  }
  lastClientVis = vis
}

method setDirection SpeechBubble newDir {
  if (newDir == direction) { return }
  direction = newDir
  fixLayout this
}
