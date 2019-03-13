// interactively eval GP code in a morphic window

defineClass MicroBlockDataGraph morph window lastDataCount lastDataItem

to openMicroBlockDataGraph {
	page = (global 'page')
	result = (new 'MicroBlockDataGraph')
	initialize result
	setPosition (morph result) (x (hand page)) (y (hand page))
	addPart page result
	return result
}

method initialize MicroBlockDataGraph {
	scale = (global 'scale')
	window = (window 'Data Graph')
	morph = (morph window)
	setHandler morph this
	setMinExtent morph (scale * 140) (scale * 50)
	setExtent morph (scale * 200) (scale * 120)
	lastDataCount = 0
	lastDataItem = nil
	setFPS morph 60
}

method step MicroBlockDataGraph {
	if (not (newDataAvailable this)) { return }
	redraw this
	loggedData = (loggedData (smallRuntime))
	lastDataCount = (count loggedData)
	lastDataItem = nil
	if (lastDataCount > 0) {
		lastDataItem = (last loggedData)
	}
}

method newDataAvailable MicroBlockDataGraph {
	loggedData = (loggedData (smallRuntime))
	if (lastDataCount != (count loggedData)) { return true }
	if (and ((count loggedData) > 0) ((last loggedData) != lastDataItem)) { return true }
	return false
}

method redraw MicroBlockDataGraph {
	fixLayout window
	redraw window
	drawData this
	costumeChanged morph
}

method drawData MicroBlockDataGraph {
	bgColor = (gray 240)

	yScale = (1 * (global 'scale'))
	clientArea = (clientArea window)
	top = ((top clientArea) - (top morph))
	left = ((left clientArea) - (left morph))
	fillRect (costumeData morph) bgColor left top (width clientArea) (height clientArea)
	drawGrid this yScale
	colors = (list (color 200 0 0) (color 0 110 0) (color 0 0 200) (gray 30) (color 0 170 170) (color 180 0 180))
	sequences = (extractSequences this)
	for i (min (count sequences) (count colors)) {
		graphSequence this (at sequences i) (at colors i) yScale
	}
}

method extractSequences MicroBlockDataGraph {
	loggedData = (loggedData (smallRuntime) (pointCount this))
	sequences = (list)
	for line loggedData {
		items = (splitWith line ' ')
		while ((count sequences) < (count items)) {
			add sequences (list)
		}
		for i (count items) {
			add (at sequences i) (toNumber (at items i))
		}
	}
	return sequences
}

method pointCount MicroBlockDataGraph {
	// Return the number of data points that will fit the current window size.

	scale = (global 'scale')
	leftInset = (40 * scale)
	lineW = scale
	return (toInteger (((width (clientArea window)) - leftInset) / lineW))
}

method graphSequence MicroBlockDataGraph seq aColor yScale {
	if (isEmpty seq) { return }
	scale = (global 'scale')
	lineW = (2 * scale)

	graphBnds = (translatedBy (clientArea window) (- (left morph)) (- (top morph)))
	graphBnds = (insetBy graphBnds (half lineW))
	right = (right graphBnds)
	top = (top graphBnds)
	bottom = (bottom graphBnds)
	yOrigin = (top + (half (height graphBnds)))

	pen = (newPen (costumeData morph))
	setLineWidth pen lineW
	setColor pen aColor
	x = ((left graphBnds) + (38 * scale))
	pointCount = (pointCount this)
	i = (max 1 ((count seq) - pointCount))
	while (i < (count seq)) {
		n = (at seq i)
		y = (yOrigin - (n * yScale))
		if (y < top) { y = top }
		if (y > bottom) { y = bottom }
		goto pen x y
		if (not (isDown pen)) { down pen } // first point
		x += scale
		if (x > right) { return }
		i += 1
	}
}

method drawGrid MicroBlockDataGraph yScale {
	scale = (global 'scale')
	lineW = scale

	graphBnds = (translatedBy (clientArea window) (- (left morph)) (- (top morph)))
	graphBnds = (insetBy graphBnds (half lineW))
	left = ((left graphBnds) + (38 * scale))
	right = (right graphBnds)
	yOrigin = ((top graphBnds) + (half (height graphBnds)))

	bm = (costumeData morph)
	max = (((half (height graphBnds)) - 10) / yScale)
	for offset (range 0 max 25) {
		c = (gray 220)
		if ((offset % 100) == 0) { c = (gray 190) } // darker lines for multiples of 100
		y = (yOrigin - (offset * yScale))
		fillRect bm c left y (right - left) lineW
		drawLabel this bm (toString offset) left y
		y = (yOrigin + (offset * yScale))
		fillRect bm c left y (right - left) lineW
		drawLabel this bm (toString (- offset)) left y
	}
}

method drawLabel MicroBlockDataGraph bm label left y {
	scale = (global 'scale')
	fontName = 'Arial'
	fontSize = (13 * scale)

	label = (stringImage label fontName fontSize (gray 100))
	x = (left - ((width label) + (7 * scale)))
	drawBitmap bm label x (y - (half (fontSize + scale)))
}
