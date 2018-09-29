// editable color slot for blocks

defineClass ColorSlot morph contents

to newColorSlot {
  return (initialize (new 'ColorSlot'))
}

method initialize ColorSlot {
  morph = (newMorph this)
  setHandler morph this
  setGrabRule morph 'defer'
  setTransparentTouch morph true
  contents = (color 35 190 30)
  redraw this
  return this
}

method contents ColorSlot { return contents }

method setContents ColorSlot aColor {
  if (isNil aColor) { aColor = (color 35 190 30) }
  contents = aColor
  redraw this
  raise morph 'inputChanged' this
}

method redraw ColorSlot {
  scale = (global 'scale')
  border = (1 * scale)
  size = (13 * scale)
  bm = (costume morph)
  bm = nil
  if (isNil bm) { bm = (newBitmap size size (gray 80)) }
  fillRect bm contents border border (size - (2 * border)) (size - (2 * border))
  setCostume morph bm
}

// events

method clicked ColorSlot aHand {
  if (notNil (ownerThatIsA morph 'InputDeclaration')) { return }
  scale = (global 'scale')
  page = (global 'page')
  cp = (newColorPicker (action 'setContents' this) contents)
  setPosition (morph cp) (left morph) ((bottom morph) + (2 * scale))
  keepWithin (morph cp) (bounds (morph page))
  addPart page cp
  return true
}

// keyboard accessibility hooks

method trigger ColorSlot {
  clicked this
}
