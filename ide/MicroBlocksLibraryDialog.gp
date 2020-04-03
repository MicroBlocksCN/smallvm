// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksLibraryDialog.gp - Provides a dialog to explore, load and export libraries

defineClass MicroBlocksLibraryDialog morph window filePicker descriptionFrame descriptionText depsText depsFrame versionAuthorText versionFrame tagText tagFrame

to pickLibraryToOpen anAction defaultPath {
	page = (global 'page')
	dialog = (initialize (new 'MicroBlocksLibraryDialog') anAction defaultPath false)
	addPart page dialog
	dialogM = (morph dialog)
	setPosition dialogM (half ((width page) - (width dialogM))) (40 * (global 'scale'))
}

method initialize MicroBlocksLibraryDialog anAction defaultPath saveFlag {
	filePicker = (initialize (new 'FilePicker') anAction defaultPath (array '.ubl') saveFlag)
	morph = (morph filePicker)
	window = (window filePicker)
	setHandler morph this

	descriptionText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5)
	if saveFlag { setEditRule descriptionText 'editable' }
	descriptionFrame = (scrollFrame descriptionText (clientColor window))
	addPart (morph descriptionFrame) (morph descriptionText)

	addPart morph (morph descriptionFrame)

	versionAuthorText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5)
	versionFrame = (newBox nil (clientColor window) 0)
	setClipping (morph versionFrame) true
	addPart (morph versionFrame) (morph versionAuthorText)
	addPart morph (morph versionFrame)

	depsText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5 0)
	depsFrame = (scrollFrame depsText (clientColor window))
	addPart morph (morph depsFrame)

	tagText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5 0)
	tagFrame = (scrollFrame tagText (clientColor window))
	addPart morph (morph tagFrame)

	onFileSelect filePicker (action 'updateLibraryInfo' this)

	scale = (global 'scale')
	setMinExtent morph (600 * scale) (466 * scale)
	setExtent morph (600 * scale) (466 * scale)

	redraw this
	fixLayout this
	return this
}

method updateLibraryInfo MicroBlocksLibraryDialog selectedPath {
	libName = (withoutExtension (substring selectedPath ((findLast selectedPath '/') + 1)))
	if (beginsWith selectedPath '//') {
	  data = (readEmbeddedFile (substring selectedPath 3))
	} else {
	  data = (readFile selectedPath)
	}
	cmdList = (parse data)
	library = (newMicroBlocksModule libName)
	loadFromCmds library cmdList
	setText descriptionText (description library)
	if (isEmpty (dependencies library)) {
		setText depsText 'No dependencies'
	} else {
		setText depsText (join 'Depends: ' (joinStrings (dependencyNames library) ', '))
	}
	setText versionAuthorText (join 'v' (toString (at (version library) 1)) '.' (toString (at (version library) 2)) ', by ' (author library))
	setText tagText (joinStrings (tags library) ', ')
	fixLayout this
}

method redraw MicroBlocksLibraryDialog {
	redraw filePicker
	fixLayout this
}

method fixLayout MicroBlocksLibraryDialog {
	scale = (global 'scale')
	fixLayout filePicker
	listPaneM = (morph (listPane filePicker))

	margin = (10 * scale)

	// file list panel should take roughly half the space
	topInset = (55 * scale)
	bottomInset = (40 * scale)
	leftInset = (110 * scale)
	rightInset = ((((width morph) / 2) - 20) * scale)
	setPosition listPaneM ((left morph) + leftInset) ((top morph) + topInset)
	setExtent listPaneM ((width morph) - (leftInset + rightInset)) ((height morph) - (topInset + bottomInset))

	propLeft = ((right listPaneM) + margin)
	propWidth = ((((width morph) - propLeft) + (left morph)) - (margin * 2))

	descriptionHeight = (height listPaneM)

	// tags
	setExtent (morph tagFrame) propWidth (2 * (height (morph versionAuthorText)))
	setLeft (morph tagFrame) propLeft
	setBottom (morph tagFrame) (bottom listPaneM)
	descriptionHeight = ((descriptionHeight - (height (morph tagFrame))) - margin)
	wrapLinesToWidth tagText propWidth

	// dependencies
	setExtent (morph depsFrame) propWidth (height (morph tagFrame))
	setLeft (morph depsFrame) propLeft
	setBottom (morph depsFrame) ((top (morph tagFrame)) - margin)
	descriptionHeight = ((descriptionHeight - (height (morph depsFrame))) - margin)

	// version and author
	setExtent (morph versionFrame) propWidth (height (morph versionAuthorText))
	setLeft (morph versionFrame) propLeft
	setBottom (morph versionFrame) ((top (morph depsFrame)) - margin)
	descriptionHeight = ((descriptionHeight - (height (morph versionFrame))) - margin)

	// description
	setPosition (morph descriptionFrame) propLeft (top listPaneM)
	setExtent (morph descriptionFrame) propWidth descriptionHeight
	wrapLinesToWidth descriptionText propWidth
}
