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
	atPut contentDict 'InputSlot' (array 'Input slot' 'Click on it to edit its value, or drop a reporter into it.')
	atPut contentDict 'Block' (array 'Block' 'Click on it to run it, or drag it into the scripting area to build scripts.')
}

method contentsFor MicroBlocksTipBar anElement {
	key = (className (classOf anElement))
	if ('Text' == key) {
		if (notNil (ownerThatIsA (morph anElement) 'InputSlot')) {
			key = 'InputSlot'
		} (notNil (ownerThatIsA (morph anElement) 'Block')) {
			key = 'Block'
		}
	}
	if (isClass anElement 'CategorySelector') {
		category = (categoryUnderHand anElement)
		items = (collection anElement)
		if (and (notEmpty items) ('Output' == (first items))) {
			key = (join 'Category: ' category)
		} else {
			key = (join 'Library: ' category)
		}
	}
	content = (at contentDict key)
	if (isNil content) { return (array key '') } // show key in tip bar during development
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
