// Palette of GP blocks by class

to openSystemPalette defaultClassOrNil {
  page = (global 'page')
  pal = (newSystemPalette)
  if (notNil defaultClassOrNil) { browse pal defaultClassOrNil }
  setPosition (morph pal) (x (hand page)) (y (hand page))
  addPart page pal
  return pal
}

defineClass SystemPalette morph window classListFrame blocksPane blocksFrame

to newSystemPalette {
  return (initialize (new 'SystemPalette'))
}

method initialize SystemPalette {
  scale = (global 'scale')
  window = (window 'System Palette')
  clr = (clientColor window)
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 300) (scale * 200)

  classList = (listBox (sortedClasses this) nil (action 'selectClass' this) clr (action 'openClassBrowser' this nil))
  classListFrame = (scrollFrame classList clr)
  addPart morph (morph classListFrame)

  blocksPane = (newBlocksPalette)
  blocksFrame = (scrollFrame blocksPane (gray 220))
  addPart morph (morph blocksFrame)

  setExtent morph (scale * 400) (scale * 200)
  return this
}

method sortedClasses SystemPalette {
  classList = (list)
  for c (classes) {
    if ((count (methods c)) > 0) { add classList (className c) }
  }
  result = (sorted classList)
  addFirst result '<Global Blocks>'
  return result
}

method browse SystemPalette aClass {
  select (contents classListFrame) aClass
  m = (selectedMorph (contents classListFrame))
  if (notNil m) { scrollIntoView classListFrame (bounds m) }
}

method selectClass SystemPalette className {
  removeAllParts (morph blocksPane)
  fList = (list)
  if ('<Global Blocks>' == className) {
	for f (functions (topLevelModule)) {
	  if (isNil (specForOp (authoringSpecs) (primName f))) { add fList f }
	}
  } else {
    aClass = (class className)
    if (notNil aClass) { fList = (methods aClass) }
  }
  fList = (sorted fList (function f1 f2 { return ((functionName f1) < (functionName f2)) }))
  for f fList {
    b = (morph (blockForSpec (blockSpecFor f)))
    setGrabRule b 'template'
    addPart (morph blocksPane) b
  }
  cleanUp blocksPane
}

// item menu

method handleListContextRequest SystemPalette anArray {
  classList = (contents classListFrame)
  item = (data (last anArray))
  if (classList == (first anArray)) {
    menu = (menu nil this)
    if ('<Global Blocks>' == item) {
      addItem menu 'browse global blocks...' (action 'browseClass'item)
    } else {
      addItem menu 'browse class...' (action 'browseClass'item)
    }
    popUpAtHand menu (global 'page')
  }
}

// top bar menu

method rightClicked SystemPalette aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method contextMenu SystemPalette {
  menu = (menu nil this)
  addItem menu 'find system block matching...' (action 'findBlock' this)
  addItem menu 'find primitives matching...' (action 'findPrimitive' this)
  return menu
}

method findBlock SystemPalette {
  searchString = (toLowerCase (prompt (global 'page') 'Block name?'))
  if ('' == searchString) { return }
  selectors = (dictionary)
  for f (allInstances 'Function') { add selectors (functionName f) }
  addAll selectors (primitives)
  startMatches = (list)
  otherMatches = (list)
  for sel (sorted (keys selectors)) {
	lowercaseSel = (toLowerCase sel)
    if (beginsWith lowercaseSel searchString) {
      add startMatches sel
    } ((containsSubString lowercaseSel searchString) > 0) {
      add otherMatches sel
    }
  }
  totalMatches = ((count startMatches) + (count otherMatches))
  if (0 == totalMatches) { return } // no matches
  if (1 == totalMatches) {
	browseImplementors this (first (join startMatches otherMatches))
	return
  }
  if (totalMatches > 30) {
	n = (30 - (count startMatches))
	otherMatches = (copyFromTo otherMatches 1 n)
  }

  menu = (menu 'Implementors of:' (action 'browseImplementors' this) true) // reverse call
  for sel startMatches { addItem menu sel }
  addLine menu
  for sel otherMatches { addItem menu sel }
  popUpAtHand menu (global 'page')
}

method browseImplementors SystemPalette selector {
  implementors = (implementors selector)
  if (0 == (count implementors)) { return }
  if (1 == (count implementors)) {
    openClassBrowser this selector (first implementors)
    return
  }
  menu = (menu (join 'implementations of' (newline) selector) (action 'openClassBrowser' this selector) true) // reverse call
  for each implementors {
    addItem menu (join each '...') each
  }
  popUpAtHand menu (global 'page')
}

method showPrimitive SystemPalette primName {
  inform (global 'page') (join primName ' is a primitive' (newline) (primitiveHelpString primName))
}

method openClassBrowser SystemPalette methodName className {
  if ('<primitive>' == className) {
    showPrimitive this methodName
    return
  }
  page = (global 'page')
  brs = (newClassBrowser)
  setPosition (morph brs) (x (hand page)) (y (hand page))
  addPart page brs
  aClass = (class className)
  if (notNil aClass) {
    browse brs aClass methodName
  } else {
    if ('<generic>' == className) {
      className = (globalBlocksName brs)
    }
    browse brs className (functionNamed methodName)
  }
}

method findPrimitive SystemPalette {
  searchString = (toLowerCase (prompt (global 'page') 'Primitive name?'))
  if ('' == searchString) { return }
  result = (dictionary)
  for p (sorted (primitives)) {
	lowercaseSel = (toLowerCase p)
    if ((containsSubString (toLowerCase p) searchString) > 0) {
      atPut result p (primitiveHelpString p)
    }
  }
  if ((count result) > 0) {
    openExplorer result
  }
}

// layout

method redraw SystemPalette {
  fixLayout window
  redraw window
  fixLayout this
}

method fixLayout SystemPalette {
  classesWidth = (action 'spaceBoundedBy' window (action 'allWidth' (contents classListFrame)) 25)
  packer = (newPanePacker (clientArea window))
  packPanesH packer classListFrame classesWidth blocksFrame 'rest'
  packPanesV packer classListFrame 'rest'
  packPanesV packer blocksFrame 'rest'
  finishPacking packer
}
