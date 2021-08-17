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
	setFont this 'Arial Bold' 16
	h = ((count items) * (itemHeight this))
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
	setExtent morph nil ((count items) * (itemHeight this))
}

method drawOn CategorySelector ctx {
	scale = (global 'scale')
	bgColor = (gray 240)
	white = (gray 255)
	black = (gray 0)

	insetX = (20 * scale)
	insetY = (2 * scale)

	itemH = (itemHeight this)
	swatchInsetX = (4 * scale)
	swatchInsetY = (2 * scale)
	swatchW = (10 * scale)
	swatchH = (itemH - (3 * scale))

	x = (left morph)
	y = ((top morph) + scale)
	w = (width morph)
	for i (count items) {
		catColor = (blockColorForCategory (authoringSpecs) (at items i))
		itemC = bgColor
		textC = black
		drawSwatch = true
		if (i == selectedIndex) {
			itemC = catColor
			textC = white
			drawSwatch = false
		} (i == hoverIndex) {
			itemC = (lighter catColor 40)
			textC = white
			drawSwatch = false
		}
		fillRect ctx itemC x (y + scale) w (itemH - scale)
		label = (localized (at items i))
		setFont ctx fontName fontSize
		drawString ctx label textC (x + insetX) (y + insetY)
		if drawSwatch {
			fillRect ctx catColor (x + swatchInsetX) (y + swatchInsetY) swatchW swatchH
		}
		y += itemH
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
	return (fontSize + 10)
}

method handDownOn CategorySelector aHand {
	i = (truncate (((y aHand) - (top morph)) / (itemHeight this)))
	if (and (i >= 0) (i < (count items))) {
		selectedIndex = (i + 1)
		if (notNil selectAction) { call selectAction selection }
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
		i = (truncate ((handY - (top morph)) / (itemHeight this)))
		if (and (i >= 0) (i < (count items))) {
			hoverIndex = (i + 1)
		} else {
			hoverIndex = 0
		}
	}
	if (hoverIndex != oldHoverIndex) { changed morph }
}

// context menu

method rightClicked CategorySelector {
	item = (selection this)
	if (notNil item) {
		raise morph 'handleListContextRequest' (array this item)
	}
	return true
}
