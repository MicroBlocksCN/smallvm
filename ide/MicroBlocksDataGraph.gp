// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright 2021 John Maloney, Bernat Romagosa, and Jens Mönig
//
// Display graph data

defineClass MicroBlocksDataGraph morph window lastDataIndex zeroAtBottom

to newMicroBlocksDataGraph { return (initialize (new 'MicroBlocksDataGraph')) }

method initialize MicroBlocksDataGraph {
	scale = (global 'scale')
	window = (window 'Data Graph')
	morph = (morph window)
	setHandler morph this
	setMinExtent morph (scale * 140) (scale * 50)
	setExtent morph (scale * 200) (scale * 120)
	lastDataIndex = 0
	zeroAtBottom = false;
	setFPS morph 20
	return this
}

method step MicroBlocksDataGraph {
	if ((lastDataIndex (smallRuntime)) == lastDataIndex) { return }
	lastDataIndex = (lastDataIndex (smallRuntime))
	changed morph
}

method graphArea MicroBlocksDataGraph {
	scale = (global 'scale')
	inset = (5 * scale)
	topInset = (24 * scale)
	left = ((left morph) + inset)
	top = ((top morph) + topInset)
	w = ((width morph) - (2 * inset))
	h = ((height morph) - (topInset + inset))
	return (rect left top w h)
}

method drawOn MicroBlocksDataGraph ctx {
  scale = (global 'scale')
  radius = (4 * scale)

  // draw window frame
  fillRoundedRect (getShapeMaker ctx) (bounds morph) radius (gray 80)

  // clear graph area
  bgColor = (gray 240)
  fillRoundedRect (getShapeMaker ctx) (graphArea this) radius bgColor

  // draw the data
  drawData this ctx
}

method redraw MicroBlocksDataGraph {
	fixLayout window
	changed morph
}

method drawData MicroBlocksDataGraph ctx {
	yScale = (1 * (global 'scale'))
	drawGrid this ctx yScale
	colors = (list (color 200 0 0) (color 0 110 0) (color 0 0 200) (gray 30) (color 0 170 170) (color 180 0 180))
	sequences = (extractSequences this)
	for i (min (count sequences) (count colors)) {
		graphSequence this ctx (at sequences i) (at colors i) yScale
	}
}

method extractSequences MicroBlocksDataGraph {
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

method pointCount MicroBlocksDataGraph {
	// Return the number of data points that will fit the current window size.

	scale = (global 'scale')
	leftInset = (40 * scale)
	lineW = scale
	return (toInteger (((width (graphArea this)) - leftInset) / lineW))
}

method graphSequence MicroBlocksDataGraph ctx seq aColor yScale {
	if (isEmpty seq) { return }
	scale = (global 'scale')
	lineW = (2 * scale)

	graphBnds = (graphArea this)
	graphBnds = (insetBy graphBnds (half lineW))
	right = (right graphBnds)
	top = (top graphBnds)
	bottom = (bottom graphBnds)
	if zeroAtBottom {
		yOrigin = (((top graphBnds) + (height graphBnds)) - (9 * scale))
	} else {
		yOrigin = ((top + (half (height graphBnds))) + 1)
	}

	lineW = scale
	pen = (pen (getShapeMaker ctx))
	x = ((left graphBnds) + (38 * scale))
	pointCount = (pointCount this)
	i = (max 1 ((count seq) - pointCount))
	isFirstPoint = true
	while (i < (count seq)) {
		n = (at seq i)
		y = (yOrigin - (n * yScale))
		if (y < top) { y = top }
		if (y > bottom) { y = bottom }
		if isFirstPoint {
			beginPath pen x y
			isFirstPoint = false
		} else {
			goto pen x y
		}
		x += scale
		if (x > right) { return }
		i += 1
	}
	stroke pen aColor lineW
}

method drawGrid MicroBlocksDataGraph ctx yScale {
	scale = (global 'scale')
	lineW = scale

	graphBnds = (graphArea this)
	graphBnds = (insetBy graphBnds (half lineW))
	left = ((left graphBnds) + (38 * scale))
	right = (right graphBnds)

	if zeroAtBottom {
		yOrigin = (((top graphBnds) + (height graphBnds)) - (10 * scale))
		max = (((height graphBnds) - (16 * scale)) / yScale)
		for offset (range 0 max 25) {
			c = (gray 220)
			if ((offset % 100) == 0) { c = (gray 190) } // darker lines for multiples of 100
			y = (yOrigin - (offset * yScale))
			fillRect ctx c left y (right - left) lineW
			drawLabel this ctx (toString offset) left y
		}
	} else {
		yOrigin = ((top graphBnds) + (half (height graphBnds)))
		max = (((half (height graphBnds)) - 10) / yScale)
		for offset (range 0 max 25) {
			c = (gray 220)
			if ((offset % 100) == 0) { c = (gray 190) } // darker lines for multiples of 100
			y = (yOrigin - (offset * yScale))
			fillRect ctx c left y (right - left) lineW
			drawLabel this ctx (toString offset) left y
			y = (yOrigin + (offset * yScale))
			fillRect ctx c left y (right - left) lineW
			drawLabel this ctx (toString (- offset)) left y
		}
	}
}

method drawLabel MicroBlocksDataGraph ctx label left y {
	scale = (global 'scale')
	fontName = 'Arial'
	fontSize = (13 * scale)

	x = (left - ((stringWidth label) + (7 * scale)))
	setFont ctx fontName fontSize
	drawString ctx label (gray 100) x (y - (half (fontSize + scale)))
}

// context menu

method rightClicked MicroBlocksDataGraph aHand {
	popUpAtHand (contextMenu this) (global 'page')
	return true
}

method contextMenu MicroBlocksDataGraph {
	menu = (menu 'Graph' this)
	addItem menu 'clear graph' 'clearGraph'
	addLine menu
	if zeroAtBottom {
		addItem menu 'zero in middle' 'toggleZeroAtBottom'
	} else {
		addItem menu 'zero at bottom' 'toggleZeroAtBottom'
	}
	addLine menu
	addItem menu 'export data to CSV file' 'exportData'
	addItem menu 'import data from CSV file' 'importData'
	if (devMode) {
		addItem menu 'copy graph data to clipboard' 'copyDataToClipboard'
		addLine menu
		addItem menu 'set serial delay' (action 'serialDelayMenu' (smallRuntime))
	}
	return menu
}

method clearGraph MicroBlocksDataGraph {
	clearLoggedData (smallRuntime)
}

method toggleZeroAtBottom MicroBlocksDataGraph {
	zeroAtBottom = (not zeroAtBottom)
	redraw this
}

method exportData MicroBlocksDataGraph {
	// collect data as .csv entries
	result = (list)
	for entry (loggedData (smallRuntime)) {
		csvLine = (list)
		items = (splitWith entry ' ')
		for i (count items) {
			val = (at items i)
			if ('false' == val) {
				add csvLine '0' // map false to 0 (useful for graphing digital pins)
			} ('true' == val) {
				add csvLine '100' // map true to 100 (useful for graphing digital pins)
			} (representsANumber val) {
				add csvLine (toString (toNumber val))
			} else {
				add csvLine val
			}
			if (i < (count items)) { add csvLine ', ' }
		}
		add result (joinStrings csvLine)
	}
	data = (joinStrings result (newline))

	if ('Browser' == (platform)) {
		browserWriteFile data 'data.csv' 'graphData'
		return
	}

	fileName = (fileToWrite 'data')
	if (isEmpty fileName) { return }
	if (not (endsWith fileName '.csv' )) { fileName = (join fileName '.csv') }
	writeFile fileName data
}

method importData MicroBlocksDataGraph {
	pickFileToOpen (action 'importDataFromCSVFile' this) (gpFolder) (array '.csv' '.txt')
}

method importDataFromCSVFile MicroBlocksDataGraph fileName {
	data = (readFile fileName)
	if (isNil data) { return } // could not read file
	data = (joinStrings (splitWith data ',')) // remove commas
	clearLoggedData (smallRuntime)
	for entry (lines data) { addLoggedData (smallRuntime) entry }
}

method copyDataToClipboard MicroBlocksDataGraph {
  data = (loggedData (smallRuntime))
  setClipboard (joinStrings data (newline))
}

method showRecentData MicroBlocksDataGraph {
  data = (loggedData (smallRuntime) 100) // get the most recent 100 entries
  ws = (openWorkspace (global 'page') (joinStrings data (newline)))
  setTitle ws 'Recent Data'
  setFont ws 'Arial' (16 * (global 'scale'))
}
