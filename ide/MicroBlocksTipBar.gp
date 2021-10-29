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

	initContents this

	setClipping morph true
	setHandler morph this

	addPart morph (morph title)
	addPart morph (morph tip)

	return this
}

method setTitle MicroBlocksTipBar aTitle { setText title aTitle }
method setTip MicroBlocksTipBar aTip { setText tip aTip }

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
	className = (className (classOf anElement))
	content = (at contentDict className)
	if (isNil content) { return (array '' '') }
	return content
}

method fixLayout MicroBlocksTipBar {
	page = (global 'page')
	setExtent morph (width page) 30
	redraw box

	setLeft (morph title) ((left morph) + 3)
	setTop (morph title) ((top morph) + 3)

	setLeft (morph tip) ((right (morph title)) + 10)
	setTop (morph tip) ((top morph) + 3)
}
