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

method wantsDropOf BlocksPalette aHandler {
  return (isAnyClass aHandler 'Block' 'Monitor')
}

method justReceivedDrop BlocksPalette aHandler {
  // Delete Blocks or Monitors dropped on the palette.

  wantsToRaise = (and (isClass aHandler 'Block') (isPrototypeHat aHandler))
  if (userDestroy (morph aHandler)) {
    if wantsToRaise { raise morph 'reactToMethodDelete' this }
  } else {
    grab (hand (global 'page')) aHandler
  }
}
