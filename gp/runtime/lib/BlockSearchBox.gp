// BlockSearchBox - A widget for finding blocks

defineClass BlockSearchBox morph searchText menu

method morph BlockSearchBox { return morph }

to newBlockSearchBox w h {
  return (initialize (new 'BlockSearchBox') w h)
}

method initialize BlockSearchBox w h {
  scale = (global 'scale')
  morph = (newMorph this)

  bm = (newBitmap (w * scale) (h * scale) (gray 240))
  setCostume morph bm
  outlineRectangle (newShapeMaker bm) (bounds morph) (1 * scale) (gray 150)
  drawBitmap bm (searchIcon this) (2 * scale) (2 * scale) 130
  costumeChanged morph

  searchText = (newText)
  setFont searchText nil (13 * scale)
  setColor searchText (gray 30)
  setEditRule searchText 'editable' // 'line' does not work; shift key is inserted as character
  setGrabRule (morph searchText) 'ignore'
  setPosition (morph searchText) (20 * scale) (2 * scale)
  addPart morph (morph searchText)

  return this
}

method handDownOn BlockSearchBox hand {
  edit searchText hand
  return true
}

method textEdited BlockSearchBox {
  s = (text searchText)
  if ('' == s) {
	closeUnclickedMenu (global 'page') this
	return
  }
  if (endsWith s (newline)) { // workaround because 'line' editRule does not work
	setText searchText (substring s 1 ((count s) - 1))
  }
  showMenu this (findMatchingSpecs this (text searchText))
  return true
}

method findMatchingSpecs BlockSearchBox prefix {
  maxMatches = 10
  result = (list)
  entries = (dictionary)
  authoringSpecs = (authoringSpecs)
  for entry (allSpecs authoringSpecs) {
    fType = (at entry 1)
    if (or (isNil types) (contains types fType)) {
      fName = (at entry 2)
      spec = (at entry 3)
      if (beginsWith fName prefix) {
        if (not (contains entries fName)) {
          add entries fName
          add result (specForEntry authoringSpecs entry)
        }
      } else {
        specWords = (copyWithout (words spec) '_')
        s = (joinStringArray specWords ' ')
        if (or (beginsWith s prefix) (allWordsMatch this (words prefix) specWords)) {
          if (not (contains entries fName)) {
            add entries fName
            add result (specForEntry authoringSpecs entry)
          }
        }
      }
      if ((count result) >= maxMatches) {return result}
    }
  }
  return result
}

method allWordsMatch BlockSearchBox soughtWords specWords {
  // Return true if every sought word is a prefix of some word in specWords.
  for sought soughtWords {
    match = false
    for w specWords {
      if (beginsWith w sought) { match = true }
    }
    if (not match) { return false }
  }
  return true
}

// block selection menu

method showMenu BlockSearchBox specList {
  if (notNil menu) { destroy (morph menu) }
  menu = (menu nil this)
  setField menu 'returnFocus' searchText
  for spec specList {
	aBlock = (blockForSpec spec)
	addItem menu (fullCostume (morph aBlock)) (action 'grabBlock' this aBlock)
  }
  popUp menu (page morph) (left morph) (bottom morph) true // suppress focus
}

method grabBlock BlockSearchBox aBlock {
  op = (primName (expression aBlock))
  showBlockCategory (categoryFor (authoringSpecs) op)
  grab (hand (global 'page')) aBlock
  setText searchText ''
}

method step BlockSearchBox {
  // Clear the search text when the menu goes away.
  if ('' != (text searchText)) {
	if (or (isNil menu) (isNil (owner (morph menu)))) {
	  setText searchText ''
	  menu = nil
	}
  }
}

// magnifying glass icon

method searchIcon BlockSearchBox {
  icon = (newBitmap 30 30)
  p = (newVectorPen icon)
  beginPath p 12 3
  turn p 360 9
  stroke p (gray 150) 3
  beginPath p 19 18
  setHeading p 45
  forward p 13
  stroke p (gray 150) 3
  if (2 != (global 'scale')) {
	icon = (scaleAndRotate icon ((global 'scale') / 2))
  }
  return icon
}
