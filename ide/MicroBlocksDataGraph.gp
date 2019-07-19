// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// interactively eval GP code in a morphic window

defineClass MicroBlockDataGraph morph window lastDataIndex

to newMicroBlockDataGraph { return (initialize (new 'MicroBlockDataGraph')) }

method initialize MicroBlockDataGraph {
	scale = (global 'scale')
	window = (window 'Data Graph')
	morph = (morph window)
	setHandler morph this
	setMinExtent morph (scale * 140) (scale * 50)
	setExtent morph (scale * 200) (scale * 120)
	lastDataIndex = 0
	setFPS morph 60
	return this
}

method step MicroBlockDataGraph {
	if ((lastDataIndex (smallRuntime)) == lastDataIndex) { return }
	redraw this
	lastDataIndex = (lastDataIndex (smallRuntime))
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
			val = (at items i)
			if ('true' == val) {
				add (at sequences i) 100 // map true to 100 (useful for graphing digital pins)
			} else {
				add (at sequences i) (toNumber val)
			}
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

// context menu

method rightClicked MicroBlockDataGraph aHand {
	popUpAtHand (contextMenu this) (global 'page')
	return true
}

method contextMenu MicroBlockDataGraph {
	menu = (menu 'Graph' this)
	addItem menu 'clear graph' 'clearGraph'
	addItem menu 'export data to CSV file' 'exportData'
	addItem menu 'import data from CSV file' 'importData'
	if (devMode) {
		addItem menu 'copy graph data to clipboard' 'copyDataToClipboard'
	}
	return menu
}

method clearGraph MicroBlockDataGraph {
	clearLoggedData (smallRuntime)
}

method exportData MicroBlockDataGraph {
	fileName = (fileToWrite 'data')
	if (isEmpty fileName) { return }
	if (not (endsWith fileName '.csv' )) { fileName = (join fileName '.csv') }

	// collect data as .csv entries
	result = (list)
	for entry (loggedData (smallRuntime)) {
		csvLine = (list)
		items = (splitWith entry ' ')
		for i (count items) {
			val = (at items i)
			if ('false' == val) {
				add csvLine 0 // map false to 0 (useful for graphing digital pins)
			} ('true' == val) {
				add csvLine 100 // map true to 100 (useful for graphing digital pins)
			} (representsANumber val) {
				add csvLine (toString (toNumber val))
			} else {
				add csvLine val
			}
			if (i < (count items)) { add csvLine ', ' }
		}
		add result (joinStrings csvLine)
	}
	writeFile fileName (joinStrings result (newline))
}

method importData MicroBlockDataGraph {
	pickFileToOpen (action 'importDataFromCSVFile' this) (gpFolder) (array '.csv' '.txt')
}

method importDataFromCSVFile MicroBlockDataGraph fileName {
	data = (readFile fileName)
	if (isNil data) { return } // could not read file
	data = (joinStrings (splitWith data ',')) // remove commas
	clearLoggedData (smallRuntime)
	for entry (lines data) { addLoggedData (smallRuntime) entry }
}

method copyDataToClipboard MicroBlockDataGraph {
  data = (loggedData (smallRuntime))
  setClipboard (joinStrings data (newline))
}

method showRecentData MicroBlockDataGraph {
  data = (loggedData (smallRuntime) 100) // get the most recent 100 entries
  ws = (openWorkspace (global 'page') (joinStrings data (newline)))
  setTitle ws 'Recent Data'
  setFont ws 'Arial' (16 * (global 'scale'))
}
