// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksLibraryWidgets.gp - Provides morphs and dialogs to explore and load libraries

// Library Import Dialog
// ---------------------
// Explore and load libraries.
// Shows all library fields: name, author, version, dependencies, source, and description.

defineClass MicroBlocksLibraryImportDialog morph window filePicker propertiesFrame

to pickLibraryToOpen anAction defaultPath {
	page = (global 'page')
	dialog = (initialize (new 'MicroBlocksLibraryImportDialog') anAction defaultPath false)
	addPart page dialog
	dialogM = (morph dialog)
	setPosition dialogM (half ((width page) - (width dialogM))) (40 * (global 'scale'))
}

method initialize MicroBlocksLibraryImportDialog anAction defaultPath {
	filePicker = (initialize (new 'MicroBlocksFilePicker') anAction defaultPath (array '.ubl'))
	onSelectCloud filePicker (action 'promptLibUrl' this)

	morph = (morph filePicker)
	window = (window filePicker)
	setHandler morph this

	propertiesFrame = (newLibraryPropertiesFrame nil false window)
	addPart morph (morph propertiesFrame)

	onFileSelect filePicker (action 'updateLibraryInfo' this)
	onFolderSelect filePicker (action 'clearLibraryInfo' this)

	scale = (global 'scale')
	setMinExtent morph (600 * scale) (466 * scale)
	setExtent morph (600 * scale) (466 * scale)

	redraw this
	fixLayout this
	return this
}

method okay MicroBlocksLibraryImportDialog {
	okay filePicker
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

method clearLibraryInfo MicroBlocksLibraryImportDialog {
	clearFields propertiesFrame
}

method promptLibUrl MicroBlocksLibraryImportDialog {
	page = (global 'page')
	url = (prompt page 'Library URL?' 'http://')
	if (and (notEmpty url) (endsWith url '.ubl') ((findLast url '/') > 10)) {
		result = (importLibraryFromUrl (scripter (smallRuntime)) url)
	} (notEmpty url) {
		inform page 'Invalid URL'
	}
	if result { destroy morph }
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
	topInset = (60 * scale)
	bottomInset = (40 * scale)
	leftInset = (110 * scale)
	rightInset = (((width morph) / 2) - (20 * scale))
	setPosition listPaneM ((left morph) + leftInset) ((top morph) + topInset)
	setExtent listPaneM ((width morph) - (leftInset + rightInset)) ((height morph) - (topInset + bottomInset))

	propLeft = ((right listPaneM) + margin)
	propWidth = ((((width morph) - propLeft) + (left morph)) - (margin * 2))

	setPosition (morph propertiesFrame) propLeft (top listPaneM)
	setExtent (morph propertiesFrame) propWidth (height listPaneM)

	fixLayout propertiesFrame
}

// Library Info Dialog
// -------------------
// Inspect and edit libraries.
// Shows all library fields: name, author, version, dependencies, source, and description.

defineClass MicroBlocksLibraryInfoDialog morph window frame library propertiesFrame editFlag saveButton cancelButton

to showLibraryInfo lib forEditing {
	page = (global 'page')
	dialog = (initialize (new 'MicroBlocksLibraryInfoDialog') lib forEditing)
	addPart page dialog
	dialogM = (morph dialog)
	setPosition dialogM (half ((width page) - (width dialogM))) (40 * (global 'scale'))
}

method initialize MicroBlocksLibraryInfoDialog lib forEditing {
	scale = (global 'scale')

	library = lib
	window = (window (moduleName library))
	morph = (morph window)
	setHandler morph this

	propertiesFrame = (newLibraryPropertiesFrame library forEditing window)
	frame = (scrollFrame propertiesFrame (gray 230) true)

	editFlag = (isForEditing propertiesFrame)

	addPart morph (morph frame)

	if editFlag {
		saveButton = (pushButton 'Save' (action 'saveChanges' this) nil (26 * scale))
		addPart morph (morph saveButton)
		cancelButton = (pushButton 'Cancel' (action 'close' this) nil (26 * scale))
		addPart morph (morph cancelButton)
		setLibsDraggable (scripter (smallRuntime)) true
	}

	setMinExtent morph (320 * scale) (240 * scale)
	setExtent morph (420 * scale) (315 * scale)

	return this
}

method saveChanges MicroBlocksLibraryInfoDialog {
	saveChanges propertiesFrame
	close this
}

method close MicroBlocksLibraryInfoDialog {
	scripter = (scripter (smallRuntime))
	setLibsDraggable scripter false
	selectLibrary scripter (moduleName library)
	destroy morph false
}

method wantsDropOf MicroBlocksLibraryInfoDialog aHandler { return true }

method justReceivedDrop MicroBlocksLibraryInfoDialog aHandler {
	if (isClass aHandler 'Toggle') {
		libName = (data aHandler)
		dep = (libraryNamed (project (scripter (smallRuntime))) libName)
		if (and (notNil dep) (libName != (moduleName library))) {
			addDependency propertiesFrame dep
			fixLayout this
		}
	} (or (isAnyClass aHandler 'ColorPicker' 'Monitor') (hasField aHandler 'window')) {
		addPart (morph (global 'page')) (morph aHandler)
		return
	}
	animateBackToOldOwner (hand (global 'page')) (morph aHandler)
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


// Horizontal list item viewer and editor
// --------------------------------------
// Embeddable morph that shows a list of items and lets you remove them or add
// new ones.
// When editable, remove an item by dragging it out of the container window.
// When used for libraries, drag and drop a library from the palette to the
// window to add it as a dependency, or click on the [ + ] button to add it by
// its explicit path (can be a URL).

defineClass MicroBlocksListItemViewer morph box contents newItemQueryString newItemQueryHint editFlag window itemRenderer label

to newItemViewer aList forEditing win {
	return (initialize (new 'MicroBlocksListItemViewer') aList forEditing win)
}

method initialize MicroBlocksListItemViewer aList forEditing win {
	box = (newBox nil (transparent) 0)
	morph = (morph box)
	window = win
	setClipping morph true
	editFlag = (and (notNil forEditing) forEditing)
	setContents this aList
	fixLayout this
	return this
}

method setLabel MicroBlocksListItemViewer aLabel { label = aLabel }

method contents MicroBlocksListItemViewer { return contents }
method setContents MicroBlocksListItemViewer aList {
	contents = (copy (toArray aList))
	buildListView this
}

method setItemRenderer MicroBlocksListItemViewer anAction {
	itemRenderer = anAction
}

method setNewItemQueryString MicroBlocksListItemViewer aString { newItemQueryString = aString }
method setNewItemQueryHint MicroBlocksListItemViewer aString { newItemQueryHint = aString }

method queryNewItem MicroBlocksListItemViewer {
	newItem = (prompt (global 'page') newItemQueryString '' 'line' nil newItemQueryHint)
	if (notEmpty newItem) {
		addItem this newItem
	}
}

method removeItem MicroBlocksListItemViewer itemName {
	for item contents {
		if ((renderedItemName this item) == itemName) {
			contents = (copyWithout contents item)
		}
	}
}

method addItem MicroBlocksListItemViewer item {
	if (not (contains contents (renderedItemName this item))) {
		contents = (copyWith contents item)
		buildListView this
		fixLayout this
	}
}

method itemDropped MicroBlocksListItemViewer itemMorph aHand {
	// If item is dropped outside owner window, we remove it
	if (or
		((handX) < (left (morph window)))
		((handX) > (right (morph window)))
		((handY) < (top (morph window)))
		((handY) > (bottom (morph window)))) {
		removeItem this (itemName itemMorph)
		removePart morph (morph itemMorph)
		destroy (morph itemMorph)
		buildListView this
		fixLayout this
	} else {
		animateBackToOldOwner aHand (morph itemMorph)
	}
}

method renderedItemName MicroBlocksListItemViewer item {
	if (notNil itemRenderer) {
		return (call itemRenderer item)
	} else {
		return item
	}
}

method buildListView MicroBlocksListItemViewer {
	fontName = 'Arial'
	labelFontName = 'Arial Bold'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	removeAllParts morph
	if (or (and (notNil label) (notEmpty contents)) editFlag) {
		addPart morph (morph (newText label labelFontName fontSize (gray 0) 'center' nil 0 0 5 3))
	}
	for item contents {
		addPart morph (morph (newLibraryItem (renderedItemName this item) this editFlag))
	}
	if editFlag {
		addPart morph (morph (newLibraryItem '+' this false (action 'queryNewItem' this)))
	}
}

method fixLayout MicroBlocksListItemViewer {
	scale = (global 'scale')
	margin = (6 * scale)
	left = ((left morph) - (4 * scale))
	height = ((scale * 10) + (margin * 2))
	for text (parts morph) {
		setLeft text left
		if ((right text) > ((left morph) + (width morph))) {
			height = ((height + (height text)) + margin)
			left = (left morph)
			setLeft text left
		}
		setExtent morph (width morph) height
		setBottom text (bottom morph)
		left = ((left + (width text)) + margin)
	}
}

// LibraryItemMorph
// ----------------
// Represents a library or anything else that you want to be able to click and drag around.

defineClass MicroBlocksLibraryItemMorph text morph itemName itemViewer editFlag onClick

to newLibraryItem aName anItemViewer forEditing clickAction {
	return (initialize (new 'MicroBlocksLibraryItemMorph') aName anItemViewer forEditing clickAction)
}

method initialize MicroBlocksLibraryItemMorph aName anItemViewer forEditing clickAction {
	morph = (newMorph this)
	fontName = 'Arial'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	itemName = aName
	itemViewer = anItemViewer
	editFlag = forEditing
	onClick = clickAction

	bm = (stringImage itemName fontName fontSize (gray 0) 'center' nil 0 0 5 3 (gray 200))
	setCostume morph bm
	if editFlag { setGrabRule morph 'handle' }
	return this
}

method itemName MicroBlocksLibraryItemMorph { return itemName }

method clicked MicroBlocksLibraryItemMorph { if (notNil onClick) { call onClick } }
method justDropped MicroBlocksLibraryItemMorph aHand { itemDropped itemViewer this aHand }

method handEnter MicroBlocksLibraryItemMorph aHand {
	if (notNil onClick) {
		setCostumeColor this (gray 180)
	}
}

method handLeave MicroBlocksLibraryItemMorph aHand {
	if (notNil onClick) {
		setCostumeColor this (gray 200)
	}
}

method setCostumeColor MicroBlocksLibraryItemMorph color {
	fontName = 'Arial'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	bm = (stringImage itemName fontName fontSize (gray 0) 'center' nil 0 0 5 3 color)
	setCostume morph bm
}

// Library category picker
// -----------------------
// Simple colored box that lets you pick a category when clicked

defineClass MicroBlocksLibraryCategoryPicker morph box category

method initialize MicroBlocksLibraryCategoryPicker aCategory {
	box = (newBox)
	morph = (morph box)
	updateColor this
	setHandler morph this
	redraw this
	return this
}

method category MicroBlocksLibraryCategoryPicker { return category }

method setCategory MicroBlocksLibraryCategoryPicker aCategory {
	category = aCategory
	updateColor this
}

method pickCategory MicroBlocksLibraryCategoryPicker {
	scripter = (scripter (smallRuntime))
	menu = (menu)
	for cat (categories scripter) {
		addItem menu (localized cat) (action 'setCategory' this cat) '' (fullCostume (morph (newBox nil (blockColorForCategory (authoringSpecs) cat))))
	}
	addItem menu (localized 'Generic') (action 'setCategory' this 'Library') '' (fullCostume (morph (newBox nil (blockColorForCategory (authoringSpecs) 'Library'))))
	popUp menu (global 'page') (left morph) (bottom morph)
}

method clicked MicroBlocksLibraryCategoryPicker aCategory {
	pickCategory this
}

method updateColor MicroBlocksLibraryCategoryPicker {
	if (notNil category) {
		setColor box (blockColorForCategory (authoringSpecs) category)
		redraw this
	}
}

method redraw MicroBlocksLibraryCategoryPicker {
	redraw box
}

// Library properties frame
// ------------------------
// Embeddable frame that displays library information

defineClass MicroBlocksLibraryPropertiesFrame morph window library descriptionFrame descriptionText categoryPicker sourceFrame sourceText depsViewer versionText versionFrame authorText authorFrame editFlag

to newLibraryPropertiesFrame lib forEditing win {
	return (initialize (new 'MicroBlocksLibraryPropertiesFrame') lib forEditing win)
}

method initialize MicroBlocksLibraryPropertiesFrame lib forEditing win {
	fontName = 'Arial'
	fontSize = (16 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	editFlag = (and (notNil forEditing) forEditing)
	morph = (morph (newBox nil (transparent) 0))
	window = win

	descriptionText = (newText '' fontName fontSize (gray 0) 'left' nil 0 0 5)
	if editFlag { setEditRule descriptionText 'editable' }
	descriptionFrame = (scrollFrame descriptionText (gray 255))
	addPart (morph descriptionFrame) (morph descriptionText)

	// make info text always editable and selectable to allow copy-paste of URLs
	setEditRule descriptionText 'editable'
	setGrabRule (morph descriptionText) 'ignore'
	setGrabRule (morph descriptionFrame) 'ignore'

	addPart morph (morph descriptionFrame)

	categoryPicker = (initialize (new 'MicroBlocksLibraryCategoryPicker'))
	addPart morph (morph categoryPicker)

	sourceText = (newText '' fontName fontSize (gray 0) 'left' nil 0 0 5)
	sourceFrame = (newBox nil (gray 255) 0)
	addPart (morph sourceFrame) (morph sourceText)
	addPart morph (morph sourceFrame)

	versionText = (newText '' fontName fontSize (gray 0) 'left' nil 0 0 5)
	if editFlag { setEditRule versionText 'editable' }
	versionFrame = (newBox nil (gray 255) 0)
	addPart (morph versionFrame) (morph versionText)
	addPart morph (morph versionFrame)

	authorText = (newText '' fontName fontSize (gray 0) 'left' nil 0 0 5)
	if editFlag { setEditRule authorText 'editable' }
	authorFrame = (newBox nil (gray 255) 0)
	setClipping (morph authorFrame) true
	addPart (morph authorFrame) (morph authorText)
	addPart morph (morph authorFrame)

	depsViewer = (newItemViewer (array) editFlag window)
	setNewItemQueryString depsViewer 'Dependency path, name or URL?'
	setNewItemQueryHint depsViewer (libraryImportHint this)
	addPart morph (morph depsViewer)

	if (notNil lib) { setLibrary this lib }

	fixLayout this

	return this
}

method libraryImportHint MicroBlocksLibraryPropertiesFrame {
	return (join
			(localized 'If you are adding a library that''s built into MicroBlocks, you can just enter its name.')
			(newline)
			(localized 'If your library is in the Libraries folder in your local MicroBlocks project folder, you need to prefix it with a slash (/).')
			(newline)
			(localized 'If the library is hosted online, please input its full URL.')
		)
}

method isForEditing MicroBlocksLibraryPropertiesFrame { return editFlag }
method getDescription MicroBlocksLibraryPropertiesFrame { return (contentsWithoutCRs descriptionText) }
method getVersion MicroBlocksLibraryPropertiesFrame {
	// Returns an array with the major and minor version parsed out of the string
	versionString = ''
	for c (letters (contentsWithoutCRs versionText)) {
		if (or (representsAnInteger c) (c == '.')) {
			versionString = (join versionString c)
		}
	}
	major = (toInteger (at (splitWith versionString '.') 1))
	minor = (toInteger (at (splitWith versionString '.') 2))
	return (array major minor)
}
method getAuthor MicroBlocksLibraryPropertiesFrame {
	// Returns the sanitized author name, without the trailing "by"
	return (trim (last (splitWithString (contentsWithoutCRs authorText) (join (localized 'by') ' '))))
}

method addDependency MicroBlocksLibraryPropertiesFrame dep {
	addItem depsViewer (path dep)
}

method setLibrary MicroBlocksLibraryPropertiesFrame lib {
	library = lib
	updateFields this
	fixLayout this
}

method saveChanges MicroBlocksLibraryPropertiesFrame {
	setDescription library (getDescription this)
	setDependencies library (contents depsViewer)
	setCategory library (category categoryPicker)
	setVersion library (getVersion this)
	setAuthor library (getAuthor this)
}

method clearFields MicroBlocksLibraryPropertiesFrame {
	setText descriptionText ''
	setText sourceText ''
	setContents depsViewer (array)
	setText versionText ''
	setText authorText ''
}

method updateFields MicroBlocksLibraryPropertiesFrame {
	setText descriptionText (description library)

	path = (path library)
	if (and editFlag (notNil path)) {
		if (beginsWith path '/') {
			setText sourceText (join (gpFolder) '/Libraries' path '.ubl')
		} (beginsWith path 'http://') {
			setText sourceText path
		} else {
			setText sourceText (localized 'built-in library')
		}
	} else {
		setText sourceText (localized 'user library')
	}

	setCategory categoryPicker (moduleCategory library)

	setItemRenderer depsViewer (action 'dependencyName' library)
	setLabel depsViewer (localized 'Depends:')
	setContents depsViewer (dependencies library)
	setText versionText (join
		'v' (toString (at (version library) 1)) '.' (toString (at (version library) 2)))
	setText authorText (join (localized 'by') ' ' (author library))
}

method fixLayout MicroBlocksLibraryPropertiesFrame {
	scale = (global 'scale')
	margin = (10 * scale)

	descriptionHeight = (height morph)
	depsBottom = (bottom morph)
	versionBottom = (bottom morph)

	setExtent (morph depsViewer) (width morph) 0
	fixLayout depsViewer
	setLeft (morph depsViewer) (left morph)
	setBottom (morph depsViewer) depsBottom

	if (or editFlag (and (notNil library) (notEmpty (dependencies library)))) {
		descriptionHeight = ((descriptionHeight - (height (morph depsViewer))) - margin)
		versionBottom = ((top (morph depsViewer)) - margin)
	}

	// version and author
	setExtent (morph versionFrame) ((width (morph versionText)) + margin) (height (morph versionText))
	setLeft (morph versionFrame) (left morph)
	setBottom (morph versionFrame) versionBottom
	setExtent (morph authorFrame) (((width morph) - (width (morph versionFrame))) - margin) (height (morph versionText))
	setLeft (morph authorFrame) ((right (morph versionFrame)) + margin)
	setBottom (morph authorFrame) (bottom (morph versionFrame))
	descriptionHeight = ((descriptionHeight - (height (morph versionFrame))) - margin)

	if editFlag {
		// category color
		setExtent (morph categoryPicker) ((width morph) / 6) (height (morph versionFrame))
		setLeft (morph categoryPicker) (left morph)
		setBottom (morph categoryPicker) ((top (morph versionFrame)) - margin)
		show (morph categoryPicker)

		// source
		setExtent (morph sourceFrame) (((width morph) - (width (morph categoryPicker))) - margin) (height (morph sourceText))
		setLeft (morph sourceFrame) ((right (morph categoryPicker)) + margin)
		setBottom (morph sourceFrame) ((top (morph versionFrame)) - margin)
		descriptionHeight = ((descriptionHeight - (height (morph sourceFrame))) - margin)
		show (morph sourceFrame)
	} else {
		hide (morph categoryPicker)
		hide (morph sourceFrame)
	}

	// description
	setPosition (morph descriptionFrame) (left morph) (top morph)
	setExtent (morph descriptionFrame) (width morph) descriptionHeight
	wrapLinesToWidth descriptionText ((width morph) - (18 * scale))
}
