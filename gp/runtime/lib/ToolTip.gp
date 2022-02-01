// Tooltip for buttons and menu items.

defineClass ToolTip morph contents

to newToolTip aString tipWidth {
  return (initialize (new 'ToolTip') aString tipWidth)
}

method morph ToolTip { return morph }

method initialize ToolTip aString tipWidth {
	scale = (global 'scale')

	if (isNil aString) { aString = 'Tooltip!' }
	if (isNil tipWidth) { tipWidth = (200 * scale) }

	font = 'Arial'
	fontSize = (18 * scale)
	if ('Linux' == (platform)) { fontSize = (13 * scale) }

	setFont font fontSize
	aString = (toString aString)
	lines = (toList (wordWrapped aString tipWidth))
	maxLines = 10
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

method layoutChanged ToolTip { fixLayout this }

method fixLayout ToolTip {
	scale = (global 'scale')
	fontSize = (18 * scale)
	if ('Linux' == (platform)) { fontSize = (13 * scale) }
	hInset = (11 * scale)
	vInset = (7 * scale)
	setPosition (morph contents) ((left morph) + hInset) ((top morph) + vInset)
	w = ((width (morph contents)) + (2 * hInset))
	h = (+ (height (morph contents)) (2 * vInset))
	setExtent morph w h
}

method drawOn ToolTip ctx {
	border = (1 * (global 'scale'))
	corner = (3 * (global 'scale'))
	fillColor = (color 255 255 230)
	fillRoundedRect (getShapeMaker ctx) (bounds morph) corner fillColor border (gray 140) (gray 140)
}
