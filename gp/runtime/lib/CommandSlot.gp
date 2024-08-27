// C-shaped block slots

defineClass CommandSlot morph corner color wrapHeight

to newCommandSlot color nestedBlock {
  result = (new 'CommandSlot')
  initialize result color nestedBlock
  fixLayout result
  return result
}

method wrapHeight CommandSlot { return wrapHeight }

method setWrapHeight CommandSlot h {
  wrapHeight = h
  if (isNil h) { h = (16 * (blockScale)) }
  setHeight (bounds morph) h
  layoutChanged this
}

method initialize CommandSlot blockColor nestedBlock {
  corner = 3
  color = blockColor
  morph = (newMorph this)
  setTransparentTouch morph false
  if (isNil nestedBlock) { return }
  addPart morph (morph nestedBlock)
}

method drawOn CommandSlot ctx { } // do nothing

method fixLayout CommandSlot {
  scale = (blockScale)

  nested = (nested this)
  if (isNil nested) {
	h = (scale * 16)
  } else {
	insetX = (+ (left morph) (scale * 5) 0)
	if (scale < 3) { insetX += 1 }
	insetY = (+ (top morph) scale 0)
    fixLayout nested // fix layout of nested blocks before computing height
    h = (+ (scale * corner) (height (fullBounds (morph nested))))
    setPosition (morph nested) (floor insetX) (floor insetY)
  }
  w = (30 * scale)
  setExtent morph w h
  layoutChanged this
}

// accessing

method scaledCorner CommandSlot {
  return (corner * (blockScale))
}

method contents CommandSlot {
  nst = (nested this)
  if (notNil nst) {return (expression nst)}
  return nil
}

method setContents CommandSlot obj {nop} // only used for 'command' type input slot declarations

// stacking

method nested CommandSlot {
  if ((count (parts morph)) == 0) {return nil}
  return (handler (at (parts morph) 1))
}

method setNested CommandSlot aBlock {
  if (notNil aBlock) {removeHighlight (morph aBlock)}
  n = (nested this)
  if (notNil n) {remove (parts morph) (morph n)}
  if (notNil aBlock) {
    addPart morph (morph aBlock)
    if (notNil n) {setNext (bottomBlock aBlock) n}
  }
  fixLayout this
  raise morph 'inputChanged' this
  raise morph 'blockStackChanged' this
}

method topBlock CommandSlot {
  t = (handler (owner morph))
  if (not (isClass t 'Block')) { return this }
  return (topBlock t)
}

method stackList CommandSlot {
  nested = (nested this)
  if (isNil nested) {return (list)}
  return (stackList nested)
}

// events

method scriptChanged CommandSlot aBlock {
  layoutChanged this
  if (isClass (handler (owner morph)) 'Block') {
	scriptChanged (handler (owner morph))
  }
}

method layoutChanged CommandSlot {
  if (notNil (owner morph)) {
	owningBlock = (handler (owner morph))
	if (isClass owningBlock 'Block') { layoutChanged owningBlock }
  }
}

method expressionChanged CommandSlot changedBlock {
  parent = (handler (owner morph))
  if (and (changedBlock == (nested this)) (isClass parent 'Block')) {
    setArg (expression parent) (inputIndex parent this) (expression changedBlock)
    return
  }
  raise morph 'expressionChanged' changedBlock
}
