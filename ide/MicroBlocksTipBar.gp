// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksTipBar.gp - A bar that displays useful information about the
// 						  currently hovered item
// Bernat Romagosa, November 2021

defineClass MicroBlocksTipBar morph box title tip contentDict

method title MicroBlocksTipBar { return title }
method tip MicroBlocksTipBar { return tip }

method initialize MicroBlocksTipBar {
	page = (global 'page')
	fontName = 'Arial'
	titleFontName = 'Arial Bold'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	title = (newText '' titleFontName fontSize (gray 0) 'left' nil 0 0 5 3)
	tip = (newText '' fontName fontSize (gray 0) 'left' nil 0 0 5 3)

	box = (newBox nil (gray 200) 0 1)
	morph = (morph box)
	setFPS morph 5

	initContents this

	setClipping morph true
	setHandler morph this

	addPart morph (morph title)
	addPart morph (morph tip)

	return this
}

method setTitle MicroBlocksTipBar aTitle { setText title aTitle }
method setTip MicroBlocksTipBar aTip { setText tip aTip }

method step MicroBlocksTipBar {
	hand = (hand (global 'page'))
	if (isBusy hand) {
		setTitle this ''
		setTip this ''
	} else {
		updateTip this (objectAt hand)
	}
}

method updateTip MicroBlocksTipBar anElement {
	contents = (contentsFor this anElement)
	setTitle this (at contents 1)
	setTip this (at contents 2)
	fixLayout this
}

method initContents MicroBlocksTipBar {
	contentDict = (dictionary)
	atPut contentDict 'BooleanSlot' (array 'Boolean Input' 'Click on it toggle value, or drop a reporter into it.')
	atPut contentDict 'ColorSlot' (array 'Color Input' 'Click on it to change the color, or drop a reporter into it.')
	atPut contentDict 'InputSlot' (array 'Input' 'Click on it to edit its value, or drop a reporter into it.')
	atPut contentDict 'BlockDrawer' (array 'Block Extension' 'Click the right arrow to show optional inputs or the left arrow to hide them.')

	atPut contentDict 'Command' (array 'Command Block' 'Click on it to run it, or drag attach to other command blocks to build scripts. Right-click for menu.')
	atPut contentDict 'Reporter' (array 'Reporter Block' 'Click on it to see its value, or drop it into an input slot to use the value. Right-click for menu.')
	atPut contentDict 'Script' (array 'Script' 'Click on it to run it.')

	atPut contentDict 'PaneResizer' (array 'Pane Divider' 'Drag to change pane width.')
	atPut contentDict 'Library' (array 'Library' 'Click to show the blocks in this library. Right-click for menu.')
	atPut contentDict 'BlockCategory' (array 'Block Category' 'Click to show the blocks in this category.')
	atPut contentDict 'BlocksPalette' (array 'Palette' 'Drag blocks from here for use in scripts. Drop blocks or scripts here to delete them.')

	atPut contentDict 'ScriptEditor' (array 'Scripts Pane' 'Drag blocks here to build scripts. Right-click for menu.')
}

method contentsFor MicroBlocksTipBar anElement {
	key = (className (classOf anElement))
	if ('Button' == key) {
		return (array 'Button' (hint anElement))
	}
	block = nil
	if ('Block' == key) { block = anElement }
	if ('Text' == key) {
		if (notNil (ownerThatIsA (morph anElement) 'InputSlot')) {
			key = 'InputSlot'
		} (notNil (ownerThatIsA (morph anElement) 'Block')) {
			block = (handler (ownerThatIsA (morph anElement) 'Block'))
		}
	}
	if ('Slider' == key) {
		paneM = (ownerThatIsA (morph anElement) 'ScrollFrame')
		if (notNil paneM) {
			key = (className (classOf (contents (handler paneM))))
		}
	}
	if (notNil block) {
		topBlock = (topBlock block)
		if ('reporter' == (type block)) {
			if (block == topBlock) { // stand-alone reporter
				key = 'Reporter'
			} else { // reporter in a script
				key = 'Script'
			}
		} else {
			if (and (block == topBlock) (isNil (next block))) { // stand-alone command
				key = 'Command'
			} else {
				key = 'Script'
			}
		}
	}
	if (isClass anElement 'CategorySelector') {
		category = (categoryUnderHand anElement)
		items = (collection anElement)
		if (and (notEmpty items) ('Output' == (first items))) {
			key = 'BlockCategory'
		} else {
			key = 'Library'
		}
	}
	content = (at contentDict key)
	if (isNil content) { // no match
		devMode = false
		if devMode { return (array key '') } // show key in tip bar during development
		return (array '' '')
	}
	return content
}

method fixLayout MicroBlocksTipBar {
	scale = (global 'scale')
	page = (global 'page')
	setExtent morph (width page) (20 * scale)
	redraw box

	topInset = (0 * scale)
	hInset = (1 * scale)
	setLeft (morph title) ((left morph) + hInset)
	setTop (morph title) ((top morph) + topInset)

	setLeft (morph tip) ((right (morph title)) + hInset)
	setTop (morph tip) ((top morph) + topInset)
}
