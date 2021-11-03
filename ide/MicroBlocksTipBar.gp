// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksTipBar.gp - A bar that displays useful information about the
// 						  currently hovered item
// Bernat Romagosa, November 2021

defineClass MicroBlocksTipBar morph box title tipMorph tip contentDict iconsDict

method title MicroBlocksTipBar { return title }
method tip MicroBlocksTipBar { return tip }

method initialize MicroBlocksTipBar {
	page = (global 'page')
	fontName = 'Arial'
	titleFontName = 'Arial Bold'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	title = (newText '' titleFontName fontSize (gray 0) 'left' nil 0 0 5 3)

	tip = (newAlignment 'centered-line' 0 'bounds')
	tipMorph = (newMorph tip)
	setMorph tip tipMorph

	box = (newBox nil (gray 200) 0 1)
	morph = (morph box)
	setFPS morph 5

	initContents this
	initIcons this

	setClipping morph true
	setHandler morph this

	addPart morph (morph title)
	addPart morph tipMorph

	return this
}

method initIcons MicroBlocksTipBar {
	iconsDict = (dictionary)
	atPut iconsDict '[l]' (leftClickLogo this)
	atPut iconsDict '[r]' (rightClickLogo this)
}

method setTitle MicroBlocksTipBar aTitle { setText title aTitle }
method setTip MicroBlocksTipBar aTip {
	// Tips can contain icon placeholders, like so:
	// [l] run this block [r] open context menu
	removeAllParts tipMorph
	text = ''
	for word (words aTip) {
		if (contains (keys iconsDict) word) {
			if ((count text) > 0) {
				addPart tipMorph (morph (newText text titleFontName fontSize (gray 0) 'left' nil 0 0 5 3))
				text = ''
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
		addPart tipMorph (morph (newText text titleFontName fontSize (gray 0) 'left' nil 0 0 5 3))
	}
	fixLayout tip
}

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
	atPut contentDict 'BooleanSlot' (array 'Boolean Input' '[l] toggle value, or drop a reporter into it.')
	atPut contentDict 'ColorSlot' (array 'Color Input' '[l] change the color, or drop a reporter into it.')
	atPut contentDict 'InputSlot' (array 'Input' '[l] edit its value, or drop a reporter into it.')
	atPut contentDict 'BlockDrawer' (array 'Block Extension' '[l] right arrow to show optional inputs. [l] left arrow to hide them.')

	atPut contentDict 'Command' (array 'Command Block' '[l] run it, or drag attach to other command blocks to build scripts. [r] menu.')
	atPut contentDict 'Reporter' (array 'Reporter Block' '[l] see its value, or drop it into an input slot to use the value. [r] menu.')
	atPut contentDict 'Script' (array 'Script' '[l] run it. [r] menu.')

	atPut contentDict 'PaneResizer' (array 'Pane Divider' 'Drag to change pane width.')
	atPut contentDict 'Library' (array 'Library' '[l] show the blocks in this library. [r] menu.')
	atPut contentDict 'BlockCategory' (array 'Block Category' '[l] show the blocks in this category.')
	atPut contentDict 'BlocksPalette' (array 'Palette' 'Drag blocks from here for use in scripts. Drop blocks or scripts here to delete them.')

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
	setExtent morph (width page) (24 * scale)
	redraw box

	topInset = (0 * scale)
	hInset = (1 * scale)
	setLeft (morph title) ((left morph) + hInset)
	setTop (morph title) ((top morph) + topInset)

	setLeft tipMorph ((right (morph title)) + hInset)
	setTop tipMorph ((top morph) + topInset)
}

method rightClickLogo MicroBlocksTipBar {
	data = '
iVBORw0KGgoAAAANSUhEUgAAAAsAAAAPCAYAAAAyPTUwAAAACXBIWXMAAAUTAAAFEwFaO8pPAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAQJJREFUKJHN0qFKQ3EYhvHfzubckZ22MFgS
nVjEYZElm2CZXoFJ1OAtiHdgEYNWi0mMg92CA5tBMGgSi9vAicP9LUcmsmH1SS8vT3g/+DJGbGMPU4gw
xAfOcAHZVDxBGU1kcFQoFOZDCNchhBVsoJnFFuYwixks4aZUKh1Wq9WNTqcTDQaDF2Qj7OIBtzjAIyRJ
8t5oNJJarbYcx/ET9iPksYZTY6jX60k+n9/EdISQ7n0eJxeLRcPhsIyQQQttrOAVq9iJ4/iqUqkM+v1+
6PV6l91ud+FbXsdieiDco5rmN9yhlUuLkBY/af+eFI3bOYl/JMdGPzKJLOIcznGDzz/k4y9pHkHLpi92
fAAAAABJRU5ErkJggg=='
	return (readFrom (new 'PNGReader') (base64Decode data))
}

method leftClickLogo MicroBlocksTipBar {
	data = '
iVBORw0KGgoAAAANSUhEUgAAAAsAAAAPCAYAAAAyPTUwAAAACXBIWXMAAAUTAAAFEwFaO8pPAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAQZJREFUKJHN0rFKQgEUxvGf92rem16hJaql
IYpASBAanNqCFomgxtoq6Al6iZZoKNp6hYLCJ4hqamioKZBeQDLStOWCEUpr/+nw8eecbzgZA7axhxwC
9PCJU1xAmIrHmArD8CaKomK32z3ENC5RxRquQ6xjrlgsVsvl8k6n01lotVpX2EQWs2ghDLAbRVGzUqks
1ev1JEmSj/TaKw7wiGfsBxjL5/PrtVotMZwTrCAfoN/r9SYLhcII1xtm0M+gUSqVXpIk2YrjONNsNnPt
dnsD57jFBO6wnEEDq1jEeLrtGfPp/I4nNLJp0E+Dnzz87hOMKjqMfyTHBj8yihBxFme4x9cf8tE3ewE5
yrBvnpwAAAAASUVORK5CYII='
	return (readFrom (new 'PNGReader') (base64Decode data))
}
