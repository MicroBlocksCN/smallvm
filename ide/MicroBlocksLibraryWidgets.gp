// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksLibraryWidgets.gp - Provides morphs dialogs to explore and load libraries

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


// Tag list and editor
// -------------------
// Embeddable morph that shows a list of tags and lets you remove them or add new ones

defineClass MicroBlocksTagViewer morph box library tags editFlag

to newTagViewer lib forEditing {
	return (initialize (new 'MicroBlocksTagViewer') lib forEditing)
}

method initialize MicroBlocksTagViewer lib forEditing {
	box = (newBox nil (transparent) 0)
	morph = (morph box)
	setClipping morph true
	setAlpha morph 0
	editFlag = (or (and (notNil forEditing) forEditing) false)
	if (notNil lib) {
		setLibrary this lib
	}

	fixLayout this

	return this
}

method tags MicroBlocksTagViewer { return (toArray tags) }
method morph MicroBlocksTagViewer { return morph }

method setLibrary MicroBlocksTagViewer lib {
	library = lib
	tags = (copy (tags library))
	buildListView this
}

method queryNewTag MicroBlocksTagViewer {
	newTag = (prompt (global 'page') 'Tag name?')
	if (notEmpty newTag) {
		addTag this newTag
		buildListView this
		fixLayout this
	}
}

method tags MicroBlocksTagViewer { return (copy tags) }
method removeTag MicroBlocksTagViewer tag { tags = (copyWithout tags tag) }
method addTag MicroBlocksTagViewer tag {
	if (not (contains tags tag)) {
		tags = (copyWith tags tag)
	}
}

method buildListView MicroBlocksTagViewer {
	removeAllParts morph
	for tag tags {
		text = (newText tag 'Arial' ((global 'scale') * 10) (gray 0) 'center' nil 0 0 5 3 'static' (gray 200))
		addPart morph (morph text)
	}
	if editFlag {
		addPart morph (morph (pushButton '+' (gray 200) (action 'queryNewTag' this)))
	}
}

method fixLayout MicroBlocksTagViewer {
	scale = (global 'scale')
	margin = (6 * scale)
	left = (left morph)
	height = ((scale * 10) + (margin * 2))
	for tagText (parts morph) {
		setLeft tagText left
		if ((right tagText) > ((left morph) + (width morph))) {
			height = ((height + (height tagText)) + margin)
			left = (left morph)
			setLeft tagText left
		}
		setExtent morph (width morph) height
		setBottom tagText (bottom morph)
		left = ((left + (width tagText)) + margin)
	}
}

// Library properties frame
// ------------------------
// Embeddable frame that displays library information

defineClass MicroBlocksLibraryPropertiesFrame morph library descriptionFrame descriptionText depsText depsFrame versionAuthorText versionFrame tagViewer editFlag

to newLibraryPropertiesFrame lib forEditing {
	return (initialize (new 'MicroBlocksLibraryPropertiesFrame') lib forEditing)
}

method initialize MicroBlocksLibraryPropertiesFrame lib forEditing {

	editFlag = (or (and (notNil forEditing) forEditing) false)

	morph = (morph (newBox nil (transparent) 0))

	descriptionText = (newText '' 'Arial' ((global 'scale') * 12) (gray 0) 'left' nil 0 0 5)
	if editFlag { setEditRule descriptionText 'editable' }
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

	tagViewer = (newTagViewer lib editFlag)
	addPart morph (morph tagViewer)

	if (notNil lib) { setLibrary this lib }

	fixLayout this

	return this
}

method isForEditing MicroBlocksLibraryPropertiesFrame { return editFlag }
method getDescription MicroBlocksLibraryPropertiesFrame { return (contentsWithoutCRs descriptionText) }

method setLibrary MicroBlocksLibraryPropertiesFrame lib {
	library = lib
	updateFields this
	fixLayout this
}

method saveChanges MicroBlocksLibraryPropertiesFrame {
	setDescription library (getDescription this)
	setTags library (tags tagViewer)
}

method updateFields MicroBlocksLibraryPropertiesFrame {
	setText descriptionText (description library)
	if (isEmpty (dependencies library)) {
		setText depsText 'No dependencies'
	} else {
		setText depsText (join 'Depends: ' (joinStrings (dependencyNames library) ', '))
	}
	setText versionAuthorText (join
		'v' (toString (at (version library) 1)) '.' (toString (at (version library) 2))
		', by ' (author library))
	setLibrary tagViewer library
}

method fixLayout MicroBlocksLibraryPropertiesFrame {
	scale = (global 'scale')
	margin = (10 * scale)

	descriptionHeight = (height morph)

	// tags
	setExtent (morph tagViewer) (width morph) 0
	fixLayout tagViewer
	setLeft (morph tagViewer) (left morph)
	setBottom (morph tagViewer) (bottom morph)
	descriptionHeight = ((descriptionHeight - (height (morph tagViewer))) - margin)

	// dependencies
	if (or (isNil library) (isEmpty (tags library))) {
		depsHeight = ((scale * 10) + (margin * 2))
		depsBottom = (bottom morph)
	} else {
		depsHeight = (height (morph tagViewer))
		depsBottom = ((top (morph tagViewer)) - margin)
		descriptionHeight = (descriptionHeight - margin)
	}
	setExtent (morph depsFrame) (width morph) depsHeight
	setLeft (morph depsFrame) (left morph)
	setBottom (morph depsFrame) depsBottom
	descriptionHeight = (descriptionHeight - (height (morph depsFrame)))

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

defineClass MicroBlocksLibraryInfoDialog morph window frame library propertiesFrame editFlag saveButton cancelButton

to showLibraryInfo lib forEditing {
	page = (global 'page')
	dialog = (initialize (new 'MicroBlocksLibraryInfoDialog') lib forEditing)
	addPart page dialog
	dialogM = (morph dialog)
	setPosition dialogM (half ((width page) - (width dialogM))) (40 * (global 'scale'))
}

method initialize MicroBlocksLibraryInfoDialog lib forEditing {
	library = lib
	window = (window (moduleName library))
	morph = (morph window)
	setHandler morph this

	propertiesFrame = (newLibraryPropertiesFrame library forEditing)
	frame = (scrollFrame propertiesFrame (gray 230) true)

	editFlag = (isForEditing propertiesFrame)

	addPart morph (morph frame)

	if editFlag {
		saveButton = (pushButton 'Save' (gray 130) (action 'saveChanges' this))
		addPart morph (morph saveButton)
		cancelButton = (pushButton 'Cancel' (gray 130) (action 'close' this))
		addPart morph (morph cancelButton)
	}

	scale = (global 'scale')
	setMinExtent morph (320 * scale) (240 * scale)
	setExtent morph (480 * scale) (320 * scale)

	return this
}

method saveChanges MicroBlocksLibraryInfoDialog {
	saveChanges propertiesFrame
	close this
}

method close MicroBlocksLibraryInfoDialog {
	destroy morph false
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

	if editFlag {
		// buttons
		setRight (morph saveButton) ((right morph) - (2 * margin))
		setBottom (morph saveButton) ((bottom morph) - (2 * margin))
		setRight (morph cancelButton) ((left (morph saveButton)) - margin)
		setBottom (morph cancelButton) (bottom (morph saveButton))
		bottomInset = ((height (morph saveButton)) + margin)
	} else {
		bottomInset = 0
	}

	setPosition (morph frame) ((left morph) + margin) ((top morph) + topInset)
	setExtent (morph frame) ((width morph) - (2 * margin)) (((height morph) - topInset) - margin)

	setPosition (morph propertiesFrame) ((left (morph frame)) + margin) ((top (morph frame)) + margin)
	setExtent (morph propertiesFrame) ((width (morph frame)) - (2 * margin)) (((height (morph frame)) - (2 * margin)) - bottomInset)

	fixLayout propertiesFrame
}
