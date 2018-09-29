defineClass Alignment morph rule padding itemAreaSelector sortingOrder vPadding framePaddingX framePaddingY

to newAlignment rule padding itemAreaSelector sortFunction {
  align = (new 'Alignment')
  initialize align nil rule padding itemAreaSelector sortFunction
  return align
}

// info

method fieldInfo Alignment fieldName {
  if ('rule' == fieldName) {
    info = (dictionary)
    atPut info 'type' 'options'
    atPut info 'options' (array 'none' 'column' 'line' 'centered-line' 'multi-column' 'multi-line')
    return info
  }
  return nil
}

method initialize Alignment aMorph aRule aPadding aSelector aFunction {
  if (isNil aRule) {aRule = 'multi-column'}
  if (isNil aPadding) {
    scale = (global 'scale')
    aPadding = (scale * 5)
  }
  if (isNil aSelector) {aSelector = 'fullBounds'}
  morph = aMorph
  rule = aRule
  padding = aPadding
  vPadding = padding
  framePaddingX = padding
  framePaddingY = padding
  itemAreaSelector = aSelector
  sortingOrder = aFunction
}

method rule Alignment {return rule}
method padding Alignment {return padding}
method setPadding Alignment num {padding = num}
method vPadding Alignment {return vPadding}
method setVPadding Alignment num {vPadding = num}
method setItemAreaSelector Alignment aString {itemAreaSelector = aString}
method setSortingOrder Alignment aFunctionOrNil {sortingOrder = aFunctionOrNil}
method framePaddingX Alignment {return framePaddingX}
method framePaddingY Alignment {return framePaddingY}

method setFramePadding Alignment x y {
  framePaddingX = x
  if (notNil y) {framePaddingY = y}
}

method setRule Alignment aString {
  // 'none'
  // 'column'
  // 'line'
  // 'centered-line'
  // 'multi-column'
  // 'multi-line'
  rule = aString
}

method items Alignment {
  items = (list)
  for each (parts morph) {
    if (isVisible each) {
      add items each
    }
  }
  if (isNil sortingOrder) {
    return items
  }
  return (sorted (toArray items) sortingOrder)
}

// layout

method fixLayout Alignment {
  if (rule == 'none') {
    // client did their own layout so just recompute size
    ia = (itemsArea this)
    if (notNil ia) {
      setWidth (bounds morph) ((width ia) + (framePaddingX * 2))
      setHeight (bounds morph) ((height ia) + (framePaddingY * 2))
    }
  } (rule == 'column') {
    arrangeSingleColumn this
  } (rule == 'line') {
    arrangeSingleLine this
  } ( rule == 'centered-line') {
    arrangeCenteredLine this
  } (rule == 'multi-column') {
    arrangeMultiColumn this
  } (rule == 'multi-line') {
    arrangeMultiLine this
  } else {
    error 'unsupported layout rule' rule
  }
  if (notNil (owner morph)) {
    parent = (handler (owner morph))
    if (isClass parent 'ScrollFrame') {
      setPosition morph (left (morph parent)) (top (morph parent))
      updateSliders parent
    }
  }
}

method arrangeMultiColumn Alignment {
  maxBottom = (bottom morph)
  if (and (notNil (owner morph)) (isClass (handler (owner morph)) 'ScrollFrame')) {
    maxBottom = ((bottom (clientArea (handler (owner morph)))) - framePaddingY)
  }
  x = ((left morph) + framePaddingX)
  y = ((top morph) + framePaddingY)
  w = 0
  for item (items this) {
    area = (call itemAreaSelector item)
    newBottom = (+ y (height area))
    if (newBottom > maxBottom) {
      x += (w + padding)
      w = 0
      y = ((top morph) + framePaddingY)
    }
    setPosition item x y
    y += ((height area) + vPadding)
    w = (max w (width area))
  }
  ia = (itemsArea this)
  if (notNil ia) {
    setWidth (bounds morph) ((width ia) + (framePaddingX * 2))
    setHeight (bounds morph) ((height ia) + (framePaddingY * 2))
  }
}

method arrangeMultiLine Alignment {
  maxRight = (right morph)
  if (and (notNil (owner morph)) (isClass (handler (owner morph)) 'ScrollFrame')) {
    maxRight = (right (clientArea (handler (owner morph))))
  }
  x = ((left morph) + framePaddingX)
  y = ((top morph) + framePaddingY)
  h = 0
  for item (items this) {
    area = (call itemAreaSelector item)
    newRight = (+ x (width area))
    if (newRight > maxRight) {
      y += (h + vPadding)
      h = 0
      x = ((left morph) + framePaddingX)
    }
    setPosition item x y
    x += ((width area) + padding)
    h = (max h (height area))
  }
  ia = (itemsArea this)
  if (notNil ia) {
    setWidth (bounds morph) ((width ia) + (framePaddingX * 2))
    setHeight (bounds morph) ((height ia) + (framePaddingY * 2))
  }
}

method arrangeSingleColumn Alignment {
  x = ((left morph) + framePaddingX)
  y = ((top morph) + framePaddingY)
  w = 0
  for item (items this) {
    setPosition item x y
    area = (call itemAreaSelector item)
    y = ((bottom area) + vPadding)
    w = (max w (width area))
  }
  setWidth (bounds morph) (w + (framePaddingX * 2))
  setHeight (bounds morph) (((y - vPadding) - (top morph)) + framePaddingY)
}

method arrangeSingleLine Alignment {
  x = ((left morph) + framePaddingX)
  y = ((top morph) + framePaddingY)
  h = 0
  for item (items this) {
    setPosition item x y
    area = (call itemAreaSelector item)
    x = ((right area) + padding)
    h = (max h (height area))
  }
  setHeight (bounds morph) (h + (framePaddingY * 2))
  setWidth (bounds morph) (((x - padding) - (left morph)) + framePaddingX)
}

method arrangeCenteredLine Alignment {
  // additionally vertically center the elements
  h = 0
  for each (items this) {
    h = (max h (height each))
  }
  setHeight (bounds morph) (h + (framePaddingY * 2))
  x = ((left morph) + framePaddingX)
  y = ((top morph) + framePaddingY)
  for each (items this) {
    setPosition each x (y + ((h - (height each)) / 2))
    area = (call itemAreaSelector each)
    x = ((right area) + padding)
  }
  setWidth (bounds morph) (((x - padding) - (left morph)) + framePaddingX)
}

method adjustSizeToScrollFrame Alignment aScrollFrame {
  if (rule == 'multi-column') {arrangeMultiColumn this}
  if (rule == 'multi-line') {arrangeMultiLine this}
  if (or (isNil aScrollFrame) (isEmpty (parts morph))) {return}
  ca = (clientArea aScrollFrame)
  ia = (expandBy (itemsArea this) padding)
  setWidth (bounds morph) (max (width ia) (width ca))
  setHeight (bounds morph) (max (height ia) (height ca))
}

method itemsArea Alignment {
  // answer the items' bounding box w/o padding
  box = nil
  for item (parts morph) {
    area = (call itemAreaSelector item)
    if (isNil box) {box = (copy area)}
    merge box area
  }
  return box
}
