// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksLibraryDialogs.gp - Provides dialogs to explore and load libraries

// Library Import Dialog
// ---------------------
// Explore and load libraries. Shows all library fields: name, author, version,
// dependencies, tags, and description.

defineClass MicroBlocksLibraryImportDialog morph window filePicker propertiesFrame

to pickLibraryToOpen anAction defaultPath {
	page = (global 'page')
	dialog = (initialize (new 'MicroBlocksLibraryImportDialog') anAction defaultPath false)
	addPart page dialog
	dialogM = (morph dialog)
	setPosition dialogM (half ((width page) - (width dialogM))) (40 * (global 'scale'))
}

method initialize MicroBlocksLibraryImportDialog anAction defaultPath {
	filePicker = (initialize (new 'FilePicker') anAction defaultPath (array '.ubl'))
	morph = (morph filePicker)
	window = (window filePicker)
	setHandler morph this

	propertiesFrame = (newLibraryPropertiesFrame)
	addPart morph (morph propertiesFrame)

	onFileSelect filePicker (action 'updateLibraryInfo' this)

	scale = (global 'scale')
	setMinExtent morph (600 * scale) (466 * scale)
	setExtent morph (600 * scale) (466 * scale)

	redraw this
	fixLayout this
	return this
}

method updateLibraryInfo MicroBlocksLibraryImportDialog selectedPath {
	libName = (withoutExtension (substring selectedPath ((findLast selectedPath '/') + 1)))
	if (beginsWith selectedPath '//') {
	  data = (readEmbeddedFile (substring selectedPath 3))
	} else {
	  data = (readFile selectedPath)
	}
	cmdList = (parse data)
	library = (newMicroBlocksModule libName)
	loadFromCmds library cmdList

	setLibrary propertiesFrame library
}

method redraw MicroBlocksLibraryImportDialog {
	redraw filePicker
	fixLayout this
}

method fixLayout MicroBlocksLibraryImportDialog {
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

	setPosition (morph propertiesFrame) propLeft (top listPaneM)
	setExtent (morph propertiesFrame) propWidth (height listPaneM)

	fixLayout propertiesFrame 
}


// Library properties frame
// ------------------------
// Embeddable frame that displays library information

defineClass MicroBlocksLibraryPropertiesFrame morph library descriptionFrame descriptionText depsText depsFrame versionAuthorText versionFrame tagText tagFrame

to newLibraryPropertiesFrame lib {
	return (initialize (new 'MicroBlocksLibraryPropertiesFrame') lib)
}

method initialize MicroBlocksLibraryPropertiesFrame lib {
	morph = (morph (newBox nil (transparent) 0))

	descriptionText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5)
	descriptionFrame = (scrollFrame descriptionText (gray 255))
	addPart (morph descriptionFrame) (morph descriptionText)

	addPart morph (morph descriptionFrame)

	versionAuthorText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5)
	versionFrame = (newBox nil (gray 255) 0)
	setClipping (morph versionFrame) true
	addPart (morph versionFrame) (morph versionAuthorText)
	addPart morph (morph versionFrame)

	depsText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5 0)
	depsFrame = (scrollFrame depsText (gray 255))
	addPart morph (morph depsFrame)

	tagText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5 0)
	tagFrame = (scrollFrame tagText (gray 255))
	addPart morph (morph tagFrame)

	if (notNil lib) { setLibrary this lib }

	return this
}

method setLibrary MicroBlocksLibraryPropertiesFrame lib {
	library = lib
	updateFields this
	fixLayout this
}

method updateFields MicroBlocksLibraryPropertiesFrame {
	setText descriptionText (description library)
	if (isEmpty (dependencies library)) {
		setText depsText 'No dependencies'
	} else {
		setText depsText (join 'Depends: ' (joinStrings (dependencyNames library) ', '))
	}
	setText versionAuthorText (join 'v' (toString (at (version library) 1)) '.' (toString (at (version library) 2)) ', by ' (author library))
	setText tagText (joinStrings (tags library) ', ')
}

method fixLayout MicroBlocksLibraryPropertiesFrame {
	scale = (global 'scale')
	margin = (10 * scale)

	descriptionHeight = (height morph)

	// tags
	setExtent (morph tagFrame) (width morph) (2 * (height (morph versionAuthorText)))
	setLeft (morph tagFrame) (left morph)
	setBottom (morph tagFrame) (bottom morph)
	descriptionHeight = ((descriptionHeight - (height (morph tagFrame))) - margin)
	wrapLinesToWidth tagText (width morph)

	// dependencies
	setExtent (morph depsFrame) (width morph) (height (morph tagFrame))
	setLeft (morph depsFrame) (left morph)
	setBottom (morph depsFrame) ((top (morph tagFrame)) - margin)
	descriptionHeight = ((descriptionHeight - (height (morph depsFrame))) - margin)

	// version and author
	setExtent (morph versionFrame) (width morph) (height (morph versionAuthorText))
	setLeft (morph versionFrame) (left morph)
	setBottom (morph versionFrame) ((top (morph depsFrame)) - margin)
	descriptionHeight = ((descriptionHeight - (height (morph versionFrame))) - margin)

	// description
	setPosition (morph descriptionFrame) (left morph) (top morph)
	setExtent (morph descriptionFrame) (width morph) descriptionHeight
	wrapLinesToWidth descriptionText (width morph)
}


// Library Info Dialog

defineClass MicroBlocksLibraryInfoDialog morph window frame propertiesFrame

to showLibraryInfo library {
	page = (global 'page')
	dialog = (initialize (new 'MicroBlocksLibraryInfoDialog') library)
	addPart page dialog
	dialogM = (morph dialog)
	setPosition dialogM (half ((width page) - (width dialogM))) (40 * (global 'scale'))
}

method initialize MicroBlocksLibraryInfoDialog library {
	window = (window (moduleName library))
	morph = (morph window)
	setHandler morph this

	propertiesFrame = (newLibraryPropertiesFrame library)
	frame = (scrollFrame propertiesFrame (gray 230) true)

	addPart morph (morph frame)

	scale = (global 'scale')
	setMinExtent morph (320 * scale) (240 * scale)
	setExtent morph (480 * scale) (320 * scale)

	return this
}

method redraw MicroBlocksLibraryInfoDialog {
	fixLayout this
	redraw window
	costumeChanged morph
}

method fixLayout MicroBlocksLibraryInfoDialog {
	scale = (global 'scale')

	fixLayout window

	topInset = (30 * scale)
	margin = (6 * scale)

	setPosition (morph frame) ((left morph) + margin) ((top morph) + topInset)
	setExtent (morph frame) ((width morph) - (2 * margin)) (((height morph) - topInset) - margin)

	setPosition (morph propertiesFrame) ((left (morph frame)) + margin) ((top (morph frame)) + margin)
	setExtent (morph propertiesFrame) ((width (morph frame)) - (2 * margin)) ((height (morph frame)) - (2 * margin))

	fixLayout propertiesFrame
}
