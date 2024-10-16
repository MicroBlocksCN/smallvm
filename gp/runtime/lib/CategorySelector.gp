defineClass CategorySelector morph fontName fontSize selectAction items selectedIndex hoverIndex

to newCategorySelector aList anAction {
	// Create a new block category or library selector.
	// Optional anAction is called when a selection is made.

	if (isNil aList) { aList = (list) }
	return (initialize (new 'CategorySelector') aList anAction)
}

method initialize CategorySelector aList anAction {
	morph = (newMorph this)
	setTransparentTouch morph true
	setClipping morph true
	setFPS morph 10
	selectAction = anAction
	items = aList
	selectedIndex = 0
	setFont this 'Arial Bold' 12
	h = ((count items) * ((itemHeight this) + (5 * (global 'scale'))))
	setExtent morph 300 (clamp h 100 500)
	return this
}

method updateMorphContents CategorySelector {
	// For compatability with ListBox. Ignored.
}

method setFont CategorySelector fName fSize {
  if (notNil fName) { fontName = fName }
  if (notNil fSize) { fontSize = ((global 'scale') * fSize) }
  changed morph
}

method collection CategorySelector { return items }

method setCollection CategorySelector itemNames {
	oldSelection = (selection this)
	items = itemNames
	select this oldSelection
	setExtent morph nil ((count items) * ((itemHeight this) + (5 * (global 'scale'))))
}

method heightForItems CategorySelector {
  return ((count items) * ((itemHeight this) + (5 * (global 'scale'))))
}

method drawOn CategorySelector ctx {
	pe = (findProjectEditor)
	scale = (global 'scale')
	white = (gray 255)
	black = (gray 0)

	insetX = (20 * scale)
	insetY = (4 * scale)
	if ('Linux' == (platform)) { insetY = (3 * scale) }

	itemH = (itemHeight this)

	x = ((left morph) + (12 * scale))
	y = ((top morph) + scale)
	w = (width morph)
	for i (count items) {
		catColor = (blockColorForCategory (authoringSpecs) (at items i))
		label = (localized (at items i))
		setFont ctx fontName fontSize
		if (or (i == hoverIndex) (i == selectedIndex)) {
			fillRoundedRect (getShapeMaker ctx) (rect x (y + scale) w (itemH - scale)) (itemH / 2) catColor
			if (w > 75) {
				drawString ctx label white ((x + insetX) - (12 * scale)) (y + insetY)
			}
		} else {
			fillRoundedRect (getShapeMaker ctx) (rect (x + (12 * scale)) (y + scale) (w - (12 * scale)) (itemH - scale)) (itemH / 2) catColor
			if (w > 75) {
				drawString ctx label white (x + insetX) (y + insetY)
			}
		}
		y += (itemH + (5 * scale))
	}
}

method selection CategorySelector {
	if (or (selectedIndex < 1) (selectedIndex > (count items))) {
		return nil
	}
	return (at items selectedIndex)
}

method select CategorySelector itemName {
	for i (count items) {
		if (itemName == (at items i)) {
			selectedIndex = i
			changed morph
			if (notNil selectAction) { call selectAction selection }
			return
		}
	}
	selectedIndex = 0
	changed morph
}

method itemHeight CategorySelector {
	return (24 * (global 'scale'))
}

method handEnter CategorySelector aHand { setCursor 'pointer' }
method handLeave CategorySelector aHand { setCursor 'default' }

method handDownOn CategorySelector aHand {
	i = (truncate (((y aHand) - (top morph)) / ((itemHeight this) + ((global 'scale') * 5))))
	if (and (i >= 0) (i < (count items))) {
		selectedIndex = (i + 1)
		if (notNil selectAction) { call selectAction selection }
		hoverIndex = 0
		changed morph
	}
	return true
}

method step CategorySelector {
	hand = (hand (global 'page'))
	if (isBusy hand) { return }
	handX = (x hand)
	handY = (y hand)
	oldHoverIndex = hoverIndex
	if (not (containsPoint (bounds morph) handX handY)) {
		hoverIndex = 0
	} else {
		i = (truncate ((handY - (top morph)) / ((itemHeight this) + ((global 'scale') * 5))))
		if (and (i >= 0) (i < (count items))) {
			hoverIndex = (i + 1)
		} else {
			hoverIndex = 0
		}
	}
	if (hoverIndex != oldHoverIndex) { changed morph }
}

method categoryUnderHand CategorySelector {
	hand = (hand (global 'page'))
	if (isBusy hand) { return nil }
	handX = (x hand)
	handY = (y hand)
	if (containsPoint (bounds morph) handX handY) {
		i = (truncate ((handY - (top morph)) / ((itemHeight this) + ((global 'scale') * 5))))
		if (and (i >= 0) (i < (count items))) { return (at items (i + 1)) }
	}
	return nil
}

// context menu

method rightClicked CategorySelector {
	handDownOn this (hand (global 'page'))
	item = (selection this)
	if (notNil item) {
		raise morph 'handleListContextRequest' (array this item)
	}
	return true
}

// dropping

method wantsDropOf CategorySelector aHandler {
	if (not (isMicroBlocks)) { return false } // this is a MicroBlocks specific feature
	// only accept definition hat blocks
	scripter = (scripter (findProjectEditor))
	return (and
		(isClass aHandler 'Block')
		(isNil (blockSpec aHandler))
		((type aHandler) == 'hat')
	)
}

method justReceivedDrop CategorySelector aHandler {
	// Add blocks to libraries by dropping their definition into the library selector
	pe = (findProjectEditor)
	scripter = (scripter pe)
	mainModule = (main (project pe))
	intoLibrary = (and
		((getField scripter 'libSelector') == this)
		(notNil (categoryUnderHand this)))
	intoMyBlocks = (and
		((getField scripter 'categorySelector') == this)
		((categoryUnderHand this) == 'My Blocks'))

	// accept it if dropping onto the library list or onto the category list,
	// but only if it's onto My Blocks
	if (or intoLibrary intoMyBlocks){
		block = (handler (at (parts (morph aHandler)) 2))
		function = (function block)
		for lib (values (libraries (project scripter))) {
			if (contains (functions lib) function) {
				// Block already in a library, let's remove it from there first
				removeFunction lib function
				remove (blockList lib) (functionName function)
				remove (blockSpecs lib) (blockSpecFor function)
			}
		}
		if intoLibrary {
			library = (at (libraries (project scripter)) (categoryUnderHand this))
		} else {
			library = mainModule
		}
		if (not (contains (functions library) function)) {
			globalsUsed = (globalVarsUsed function)
			if (contains (functions mainModule) function) {
				// Block is in My Blocks, let's remove it from there first
				removeFunction mainModule function
				remove (blockList mainModule) (functionName function)
				remove (blockSpecs mainModule) (blockSpecFor function)
				for var globalsUsed {
					deleteVariable mainModule var
				}
			}
			addFunction library function
			add (blockList library) (functionName function)
			add (blockSpecs library) (blockSpecFor function)
			for var globalsUsed {
				addVariable library var
			}
		}
		select this (categoryUnderHand this)
	}
	animateBackToOldOwner (hand (global 'page')) (morph aHandler) (action 'languageChanged' scripter)
}

