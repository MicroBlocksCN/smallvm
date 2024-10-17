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
  size = (20 * (blockScale))
  setExtent morph size size
  return this
}

method contents ColorSlot { return contents }

method setContents ColorSlot aColor {
  if (isNil aColor) { aColor = (color 35 190 30) }
  if (isClass aColor 'Integer') {
  	aColor = (color ((aColor >> 16) & 255) ((aColor >> 8) & 255) (aColor & 255))
  } (not (isClass aColor 'Color')) {
	aColor = (color 255 0 255)
  }
  contents = aColor
  changed morph
  raise morph 'inputChanged' this
}

method drawOnSquare ColorSlot ctx {
	borderWidth = (blockScale)
	r = (bounds morph)
	sm = (getShapeMaker ctx)
 	fillRectangle sm r contents
 	outlineRectangle sm r borderWidth (gray 80)
}

method drawOn ColorSlot ctx {
	borderWidth = (blockScale)
	r = (bounds morph)
	radius = (half (width r))
	drawCircle (getShapeMaker ctx) (hCenter r) (vCenter r) radius contents borderWidth (microBlocksColor 'gray')
}

// events

method clicked ColorSlot aHand {
  if (notNil (ownerThatIsA morph 'InputDeclaration')) { return }
  page = (global 'page')
  cp = (newColorPicker (action 'setContents' this) contents)
  setPosition (morph cp) (left morph) ((bottom morph) + (2 * (global 'scale')))
  keepWithin (morph cp) (bounds (morph page))
  addPart page cp
  return true
}

// keyboard accessibility hooks

method trigger ColorSlot {
  clicked this
}
