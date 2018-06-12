// C-shaped block slots

defineClass CommandSlot morph corner dent inset border color scale isAlternative

to newCommandSlot color nestedBlock {
  cs = (new 'CommandSlot')
  initialize cs color nestedBlock
  fixLayout cs
  return cs
}

method initialize CommandSlot blockColor nestedBlock {
  scale = (global 'scale')
  corner = 3
  dent = 2 // 6
  inset = 4 // 12
  border = 1
  color = blockColor
  morph = (newMorph this)
  if (isNil nestedBlock) {return}
  addPart morph (morph nestedBlock)
}

method fixLayout CommandSlot silently {
  if (global 'stealthBlocks') {
    corner = (stealthLevel 3 0)
    border = (stealthLevel 1 0)
  }

  if (isNil (owner morph)) {
    block = nil
  } else {
    block = (handler (owner morph))
  }
  if (isClass block 'Block') {
    w = ((width (morph block)) - (scale * (border + corner)))
  } else {
    setExtent morph (scale * 25) // for debugging
  }
  nested = (nested this)
  if (isNil nested) {
    if (global 'stealthBlocks') {
      h = (stealthLevel (scale * 16) 0)
    } else {
      h = (scale * 16)
    }
  } else {
    h = (+ (scale * corner) (height (fullBounds (morph nested))))
    setPosition (morph nested) ((left morph) + (scale * corner)) ((top morph) + (scale * corner))
  }
  setExtent morph w h
  if (silently == true) {return}
  raise morph 'layoutChanged' this
  raise morph 'scriptChanged' this
  raise morph 'inputChanged' this
}

method redraw CommandSlot {
  clr = (copy color)
  if (getAlternative this) {color = (lighter clr 20)}
  if (global 'stealthBlocks') {setAlpha clr (stealthLevel 255 0)}
  bm = (newBitmap (width morph) (height morph))
  drawCSlot (newShapeMaker bm) 0 0 (width bm) (height bm) color (scale * corner) (scale * dent) (scale * inset) ((max 1 (scale / 2)) * border)
  setCostume morph bm
  color = clr
}

// accessing

method scaledCorner CommandSlot {return (scale * corner)}

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
  if (notNil aBlock) {fixBlockColor aBlock}
  fixLayout this
  raise morph 'blockStackChanged' this
}

method topBlock CommandSlot {
  t = (handler (owner morph))
  if (not (isClass t 'Block')) {return this}
  return (topBlock t)
}

method stackList CommandSlot {
  nested = (nested this)
  if (isNil nested) {return (list)}
  return (stackList nested)
}

// events

method scriptChanged CommandSlot aBlock {fixLayout this}

method expressionChanged CommandSlot changedBlock {
  parent = (handler (owner morph))
  if (and (changedBlock == (nested this)) (isClass parent 'Block')) {
    setArg (expression parent)  (inputIndex parent this) (expression changedBlock)
    return
  }
  raise morph 'expressionChanged' changedBlock
}

// zebra-coloring

method color CommandSlot {return color}

method getAlternative CommandSlot {
  if (isNil isAlternative) {isAlternative = false}
  return isAlternative
}

method fixBlockColor CommandSlot {
  if (notNil (owner morph)) {
    parent = (handler (owner morph))
    if (and (isClass parent 'Block')
        ((color parent) == color)
        ((getAlternative parent) != (getAlternative this))) {
      isAlternative = (not isAlternative)
      redraw this
      fixPartColors this
    }
  }
}

method fixPartColors CommandSlot {
  for i (count (parts morph)) {
    each = (handler (at (parts morph) i))
    if (isClass each 'Block') {
      fixBlockColor each
    }
  }
}
