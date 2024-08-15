// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksTipBar.gp - A bar that displays useful information about the item under the mouse
// Bernat Romagosa, November 2021

defineClass MicroBlocksTipBar morph title tipMorph tip contentDict iconsDict help tipColor titleColor bgColor

method initialize MicroBlocksTipBar editor {
	titleColor = (microBlocksColor 'blueGray' 50)
	tipColor = (microBlocksColor 'blueGray' 300)
	bgColor = (microBlocksColor 'blueGray' 850)
	morph = (newMorph this)
	setClipping morph true
	setFPS morph 5

	initContents this
	initIcons this
	help = (initialize (new 'MicroBlocksHelp'))

	titleFontName = 'Arial Bold'
	titleFontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { titleFontSize = (12 * (global 'scale')) }
	title = (newText '' titleFontName titleFontSize titleColor 'left' nil 0 0 5 3)
	addPart morph (morph title)

	tip = (newAlignment 'centered-line' 0 'bounds')
	tipMorph = (newMorph tip)
	setMorph tip tipMorph
	addPart morph tipMorph
	return this
}

method helpEntry MicroBlocksTipBar primName { return (entryForOp help primName) }
method title MicroBlocksTipBar { return title }
method setTitle MicroBlocksTipBar aTitle { setText title (localized aTitle) }
method tip MicroBlocksTipBar { return tip }

method setTip MicroBlocksTipBar aTip {
	// Tips can contain icon placeholders, like so:
	// [l] run this block [r] open context menu

	fontName = 'Arial'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	removeAllParts tipMorph
	text = ' '
	if (isNil aTip) {
		return
	}
	for word (words (localized aTip)) {
		if (contains (keys iconsDict) word) {
			if ((count text) > 0) {
				addPart tipMorph (morph (newText text fontName fontSize tipColor 'left' nil 0 0 5 3))
				text = ' '
			}
			icon = (newMorph)
			setCostume icon (at iconsDict word)
			setPosition icon 0 0
			addPart tipMorph icon
		} else {
			text = (join text word ' ')
		}
	}
	if ((count text) > 0) {
		addPart tipMorph (morph (newText text fontName fontSize tipColor 'left' nil 0 0 5 3))
	}
	fixLayout tip
}

// drawing

method drawOn MicroBlocksTipBar ctx {
	fillRectangle (getShapeMaker ctx) (bounds morph) bgColor
}

// stepping

method step MicroBlocksTipBar {
	hand = (hand (global 'page'))
	if (and (isClass (grabbedObject hand) 'Block') (isClass (objectAt hand) 'BlocksPalette')) {
		updateTip this (objectAt hand)
	} (isBusy hand) {
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

method fixLayout MicroBlocksTipBar {
	scale = (global 'scale')
	page = (global 'page')
	setExtent morph (width page) (22 * scale)

	setRight tipMorph ((right (morph page)) - (2 * scale))
	setRight (morph title) ((left tipMorph) + (2 * scale))

	top = (top morph)
	if ('Linux' != (platform)) { top += (2 * scale) }
	setTop (morph title) top
	setTop tipMorph top
}

// tip Contents

method initContents MicroBlocksTipBar {
	contentDict = (dictionary)
	atPut contentDict 'BooleanSlot' (array 'Boolean Input' '[l] toggle value, or drop a reporter into it.')
	atPut contentDict 'ColorSlot' (array 'Color Input' '[l] change the color, or drop a reporter into it.')
	atPut contentDict 'InputSlot' (array 'Input' '[l] edit its value, or drop a reporter into it.')
	atPut contentDict 'BlockDrawer' (array 'Block Extension' '[l] right arrow to show optional inputs, left arrow to hide.')

	atPut contentDict 'Command' (array 'Command Block' '[l] to run, or drag to build scripts. [r] menu.')
	atPut contentDict 'Hat' (array 'Hat Block' '[l] to run, or drag to build scripts. [r] menu.')
	atPut contentDict 'Reporter' (array 'Reporter Block' '[l] to see value, or drop into an input slot. [r] menu.')
	atPut contentDict 'Script' (array 'Script' '[l] to run. [r] menu.')

	atPut contentDict 'PaneResizer' (array 'Pane Divider' 'Drag to change pane width.')
	atPut contentDict 'Library' (array 'Library' '[l] to show the blocks in this library. [r] menu.')
	atPut contentDict 'BlockCategory' (array 'Block Category' '[l] to show the blocks in this category.')
	atPut contentDict 'BlocksPalette' (array 'Palette' 'Drag blocks from here to build scripts. Drop scripts here to delete them.')

	atPut contentDict 'ScriptEditor' (array 'Scripts Pane' 'Drag blocks here to build scripts. [r] menu.')
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
		if (and ('hat' == (type block)) (isNil (next block))) {
			key = 'Hat'
		} ('reporter' == (type block)) {
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
	if (isOneOf key 'Reporter' 'Command' 'Hat') {
 		helpEntry = (helpEntry this (primName (expression block)))
 		if (notNil helpEntry) {
 			if (devMode) {
 				// just show the help string
 				fullDescription = (at helpEntry 3)
 			} else {
 				// show help string and gesture hints
				fullDescription = (join (localized (at helpEntry 3)) '    ' (localized (at content 2)))
 			}
 			content = (copy content)
 			atPut content 2 fullDescription
 		}
 	}
	return content
}

// icons

method initIcons MicroBlocksTipBar {
	iconsDict = (dictionary)
	atPut iconsDict '[l]' (readSVGIcon 'mouse-left-button')
	atPut iconsDict '[r]' (readSVGIcon 'mouse-right-button')
	atPut iconsDict '(-o)' (readSVGIcon 'bool_true')
	atPut iconsDict '(o-)' (readSVGIcon 'bool_false')
}
