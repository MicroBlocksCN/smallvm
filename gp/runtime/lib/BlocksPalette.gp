defineClass BlocksPalette morph alignment

method alignment BlocksPalette { return alignment }

to newBlocksPalette {
  return (initialize (new 'BlocksPalette'))
}

method initialize BlocksPalette {
  order = (function b1 b2 {
    return ((primName (expression (handler b1))) < (primName (expression  (handler b2))))
  })
  morph = (newMorph this)
  setTransparentTouch morph true // optimization
  alignment = (newAlignment 'multi-column' nil 'bounds' order)
  setMorph alignment morph
  return this
}

method adjustSizeToScrollFrame BlocksPalette aScrollFrame {
  adjustSizeToScrollFrame alignment aScrollFrame
}

method cleanUp BlocksPalette {
  fixLayout alignment
}

method layoutChanged BlocksPalette {
  changed morph
}

method wantsDropOf BlocksPalette aHandler {
  return (isAnyClass aHandler 'Block' 'Monitor' 'MicroBlocksSelectionContents')
}

method justReceivedDrop BlocksPalette aHandler {
  // Hide a block definition when it is is dropped on the palette.
  if (not (isMicroBlocks)) {
    gpJustReceivedDrop this aHandler
    return
  }
  pe = (findProjectEditor)
  if (isClass aHandler 'Block') { stopRunningBlock (smallRuntime) aHandler }
  if (and (isClass aHandler 'Block') (isPrototypeHat aHandler)) {
	proto = (editedPrototype aHandler)
	if (and (notNil pe) (notNil proto) (notNil (function proto))) {
		hideDefinition (scripter pe) op
		removeFromOwner (morph aHandler)
		return
	}
  }
  if (and (isClass aHandler 'Block') (notNil pe)) {
	recordDrop (scriptEditor (scripter pe)) aHandler
	deleteChunkFor (smallRuntime) aHandler
  }
  if (isClass aHandler 'MicroBlocksSelectionContents') {
	for part (parts (morph aHandler)) {
		justReceivedDrop this (handler part)
	}
  }
  removeFromOwner (morph aHandler)
}

method gpJustReceivedDrop BlocksPalette aHandler {
  // Delete Blocks or Monitors dropped on the palette.

  wantsToRaise = (and (isClass aHandler 'Block') (isPrototypeHat aHandler))
  if (userDestroy (morph aHandler)) {
    if wantsToRaise { raise morph 'reactToMethodDelete' this }
  } else {
    grab (hand (global 'page')) aHandler
  }
}
