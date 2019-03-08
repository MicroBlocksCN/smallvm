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
	setFPS morph 30
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
}

method drawData MicroBlockDataGraph {
	bgColor = (gray 240)
	clientArea = (clientArea window)
	top = ((top clientArea) - (top morph))
	left = ((left clientArea) - (left morph))
	fillRect (costumeData morph) bgColor left top (width clientArea) (height clientArea)
	colors = (list (color 200 0 0) (color 0 110 0) (color 0 0 200) (gray 30) (color 0 170 170) (color 180 0 180))
	sequences = (extractSequences this)
//start = (msecsSinceStart)
	for i (min (count sequences) (count colors)) {
		graphSequence this (at sequences i) (at colors i)
	}
//print ((msecsSinceStart) - start) 'msecs for' (min (count sequences) (count colors))
}

method extractSequencesXXX MicroBlockDataGraph { // xxx testing
	sequences = (list)
	for incr 1 {
		seq = (list)
		n = 0
		repeat 2000 {
			n += (incr / 10)
			if (n > 100) { n = -100 }
			add seq (toInteger n)
		}
		add sequences seq
	}
	return sequences
}

method extractSequences MicroBlockDataGraph {
	loggedData = (loggedData (smallRuntime))
	maxPoints = (pointCount this)
	if ((count loggedData) > maxPoints) {
		loggedData = (copyFromTo loggedData ((count loggedData) - maxPoints))
	}
	sequences = (list)
	for line loggedData {
		nums = (filter 'representsANumber' (splitWith line ' '))
		while ((count sequences) < (count nums)) {
			add sequences (list)
		}
		for i (count nums) {
			add (at sequences i) (toNumber (at nums i))
		}
	}
	return sequences
}

method pointCount MicroBlockDataGraph {
	// Return the number of data points that will fit the current window size.

	lineW = 2
	return (toInteger ((width (clientArea window)) / lineW))
}

method graphSequence MicroBlockDataGraph seq aColor {
	if (isEmpty seq) { return }
	scale = (global 'scale')
	xScale = scale
	yScale = scale
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
	x = (left graphBnds)
	pointCount = (toInteger ((width graphBnds) / xScale))
	i = (max 1 ((count seq) - pointCount))
	while (i < (count seq)) {
		n = (at seq i)
		y = (yOrigin - (n * yScale))
		if (y < top) { y = top }
		if (y > bottom) { y = bottom }
		goto pen x y
		if (not (isDown pen)) { down pen } // first point
		x += xScale
		if (x > right) { return }
		i += 1
	}
}
