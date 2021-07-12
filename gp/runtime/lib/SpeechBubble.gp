// morphic speech bubble handlers, used for hints, errors, and tool tips

defineClass SpeechBubble morph contents direction isError isTooltip clientMorph lastClientVis

to newBubble aString bubbleWidth direction isError isTooltip {
  return (initialize (new 'SpeechBubble') aString bubbleWidth direction isError isTooltip)
}

method initialize SpeechBubble someData bubbleWidth dir isErrorFlag isTooltipFlag {
  if (isNil someData) {someData = 'hint!'}
  if (isNil bubbleWidth) {bubbleWidth = (175 * (global 'scale')) }
  if (isNil dir) {dir = 'right'}
  direction = dir
  isError = false
  isTooltip = false
  if (true == isErrorFlag) { isError = true }
  if (true == isTooltipFlag) { isTooltip = true }

  scale = (blockScale)
  if isTooltip { scale = (global 'scale') }
  font = 'Arial'
  fontSize = (18 * scale)
  if ('Linux' == (platform)) { fontSize = (13 * scale) }
  maxLines = 30

  setFont font fontSize
  if (isClass someData 'Boolean') {
    contents = (newBooleanSlot someData)
  } else {
    someData = (toString someData)
    lines = (toList (wordWrapped someData bubbleWidth))
    if ((count lines) > maxLines) {
      lines = (copyFromTo lines 1 maxLines)
      add lines '...'
    }
    contents = (newText (joinStrings lines (newline)) font fontSize (gray 0) 'center')
  }

  morph = (newMorph this)
  addPart morph (morph contents)
  fixLayout this
  return this
}

method layoutChanged SpeechBubble {fixLayout this}

method fixLayout SpeechBubble {
  scale = (blockScale)
  if isTooltip { scale = (global 'scale') }
  fontSize = (18 * scale)
  if ('Linux' == (platform)) { fontSize = (13 * scale) }
  hInset = (10 * scale)
  if ('Browser' == (platform)) { hInset = (5 * scale) }
  vInset = (8 * scale)
  tailH = (7 * scale) // height of bubble tail
  if isTooltip { tailH = 0 }
  setPosition (morph contents) ((left morph) + hInset) ((top morph) + vInset)
  w = ((width (morph contents)) + (2 * hInset))
  h = (+ (height (morph contents)) (2 * vInset) tailH)
  setExtent morph w h
}

method drawOn SpeechBubble ctx {
  if isTooltip {
    // used for button tooltips
    border = (1 * (global 'scale'))
    corner = (3 * (global 'scale'))
    fillColor = (color 255 255 230)
    fillRoundedRect (getShapeMaker ctx) (bounds morph) corner fillColor border (gray 140) (gray 140)
    return
  }

  border = (blockScale)
  r = (insetBy (bounds morph) (2 * border))
  if isError {
    fillColor = (colorHSV 0 0.05 1.0)
    borderColor = (colorHSV 0 1.0 0.7)
    drawSpeechBubble (getShapeMaker ctx) r border direction fillColor borderColor
  } else {
    drawSpeechBubble (getShapeMaker ctx) r border direction
  }
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
  vis = (visibleBounds clientMorph)
  if (lastClientVis == vis) { return }
  overlap = (5 * (blockScale)) // xxx
  rightSpace = ((right (owner morph)) - (right vis))
  setBottom morph (vCenter vis)
  if (rightSpace > (width morph)) {
	setDirection this 'right'
    setLeft morph ((right vis) - overlap)
  } else {
	setDirection this 'left'
    setRight morph ((left vis) + overlap)
  }
  keepWithin morph (insetBy (bounds (owner morph)) (3 * (global 'scale')))
  lastClientVis = vis
}

method setDirection SpeechBubble newDir {
  if (newDir == direction) { return }
  direction = newDir
  fixLayout this
}
