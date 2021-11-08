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
	if (isNil aTip) {
		return
	}
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
	dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAABwAAAAkCAYAAACaJFpUAAAACXBIWXMAACRyAAAkcgG1MFKpAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAkhJREFUSInt17trFFEUx/HPLj6jaBJFRcUH
2NpYSFARBB8YiKIIEsTSRyHiX+ALW7EQxRAUIWgK0UL9C6ysRAW1EJOgJIKPqImaKDFrMWfJZPPYzZKx
8gcDe8/9nfOdO3P3XCZnci3BXjRhHVZgQYmnD914jQe4jw9l6o7RIlzCLxRS1w904E1cHRFLewZxEfWV
wrbiYyT34Qq2j7OytBZgB66iP3I/YEs5WHNqVa1YWuldprQMN4ys9uBExk0B+40jFRRuQwvOYidmlcwf
i1qDaChNXoieuKujFcDgu9Hv7hNOYWbKczzmupW8kgsxcbNC2HjA4vUIi1O+toifLwbqIvknlk8DsICn
mBe+lVG7X/IkHQpTyxRg5YAFXE95WyPWDO0xaJxm4B+sD29TxG7B8xhM9j+rBljA5fAujPEzkt3VN0VY
pcCOlL9ftLxhdGUEHMbs8HdhOI9cTGahnOQAEIxcPiNQWvkJBxloQNJl/hmwHUOlwQI6qyhWbtM8FJ0l
1InCjCpARR3GePnDeIWXEyVWu8KpqhOFf7FLR+k/8D9wysrhS/yuy5j1DUN5Sa+rRU2GsPmSA74nb6Qj
bMsQWKz9Ag5Ius2dDIF3g7Ef5uJdBHZlANsdtd9iTjHYGMEv2DyNsI34HLX3lE6ei4mfOCNZebWqiXoD
UfP0RMaTASygF9ewD6sqgKwOb4vkSRVv/kS5xLWSk3rQ2EO119gP0t5xfIO4jTWlxXOTgOslu6oBGyTf
fbXGPuoBfMV7PMFj3DPSUEbpLyCd4FksPh5fAAAAAElFTkSuQmCC'
	data = '
iVBORw0KGgoAAAANSUhEUgAAAA4AAAASCAYAAABrXO8xAAAACXBIWXMAABI5AAASOQEodzeCAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAQBJREFUOI2l07EuBFEUxvGfmdVSoeAlSBD2
Hai1REJJKd6EByCh8AYkhEhQUNlCqdmwG0RjjGLu2DXZzc7El9zk5nznf+45uffS0TA2cYEWXsJq4Rwb
IeePJnCNA8wi7vJizOEQVxjPjRousVWshjucYgURtkNHMazhqAcEX0jxjhMM4RircIaFAWCKN6xjMXSh
WZipH5jiOYzWjAKU9AGLGgtgHJUEcn3L5lQbkJjiI+xj2ZV8lgHn8xNkj+Gp23wt32mHqTrjr/4FJhUL
xEgiPKBeAazjHpZxg5ES0ChusZQHdtGQvcXJHsBU8BrYKZoz2Mcj2jofuR1ie5jOk38AxyA7mTaRsDIA
AAAASUVORK5CYII='
	return (readFrom (new 'PNGReader') (base64Decode data))
}

method leftClickLogo MicroBlocksTipBar {
	dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAABwAAAAkCAYAAACaJFpUAAAACXBIWXMAACRyAAAkcgG1MFKpAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAkVJREFUSInt18uLTnEcx/HXM0lmiEEuRS5l
w0ZZSChZaHLPpSRbkZKFP0DIVlYjkxTJLUmS/8DCSpNihXFpKJdxNy7Dsfh9h+M8z8w8M+ZYzbdOPb/v
9/v7vH+X73N+51fRv03FRqzHPMzA+ELOO3TiPq7jGl4OoFtlk3EMX5Hlnk94iAfxPAxfPucLjmJSvbAV
McIM79GKVTVmlrfxkXMcH6LvCywfCLY9N6uTmFbvKHM2Haf8me22vhKXBuwbdhZio9GCg2jD2TrAu/E9
oEuKwWY8j1HtKoD245W/9+ljHUDYE/mdCltyJAJncr4puFkADRZIWo0Mh3sdE0Pgs1T2MBbtfcAGC5wZ
2h8wAXaESFsu6XQ/sMECSQWYSUXpQjTWRHAhfgwzcF30Owd3otG7qa0DwIYCnBD92kkV+D4XfFwCkLSH
L+AnHoVzTLTLAD7CzwZUQoT0V6gMQawey1BpKDiL7WG3IqAT3f8T2INLZQJJa9uRazfjhuEvmg5ko2oE
3mItFmC+2vvaMwTgbyvOsCzrQFZ6VRZtBDgCHLRV8CZ+TyyZ9Q49DdL7sxlNJcLGSQf8swbcC+fKEoG9
2ndhq/S2uVwi8EowtkAjnoajpQTY6tB+In1RIH2xZVIBLRtG2GK8Du0NxeChCHyW7hCN/wBqCr3u0DzQ
V+K+AGbowglswqw6ILMjt01aqd7B7x2o41xclG49xYO3S/WFtKtG3hecx5yieH9faJOwWbpqLZLufc2q
l7pbOrSf4zZu4WoMpMp+AZVe3/Vj4nt+AAAAAElFTkSuQmCC'
	data = '
iVBORw0KGgoAAAANSUhEUgAAAA4AAAASCAYAAABrXO8xAAAACXBIWXMAABI5AAASOQEodzeCAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAQVJREFUOI2l008rRFEYx/GPe4clsWDByjug
KOY9sLZFYicbJe+EF0DKyh7lX4oNK16BmsxMiMVM1+Ke21zTNWbyq+d0zvP8vs+p53RoqR8buEQNryFq
uMB68PzQGG5xgBnEuVqMWRziBqNZoYRrbCLCEk5x394dW7gKjBUchc4neEOCRgEIx1iGc8xhG+8B6gTO
4wwq4baXHNQJLKESBWgAI78Y29VAHOUSSZcg0inCp/QpvvARomOjPlQxHM6TuX2i+EkEJl16VDX621Os
f4HNHhvEaEZ4RLkHsIwHWMQdBruAhqSTXsgSu3jGKsYLgAmsBc9Oe3Ea+3hCXesj10NuD1OZ+Rsiaz99
cgtWngAAAABJRU5ErkJggg=='
	if (2 == (global 'scale')) { data = dataRetina }
	return (readFrom (new 'PNGReader') (base64Decode data))
}
