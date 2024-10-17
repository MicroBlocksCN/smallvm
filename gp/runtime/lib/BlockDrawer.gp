defineClass BlockDrawer morph target orientation

to newBlockDrawer aBlock horizontalOrVertical {
  return (initialize (new 'BlockDrawer') aBlock horizontalOrVertical)
}

method initialize BlockDrawer aBlock horizontalOrVertical {
  morph = (newMorph this)
  target = aBlock
  orientation = horizontalOrVertical
  if (isNil orientation) { orientation = 'horizontal' }
  setTransparentTouch morph true // allow clicks anywhere in bounds rectangle
  fixLayout this
  return this
}

method fixLayout BlockDrawer {
  if (notNil target) {
    hasMore = (canExpand target)
    hasLess = (canCollapse target)
  } else {
    hasMore = true
    hasLess = true
  }
  size = (18 * (blockScale))
  unit = (half size)
  extra = unit
  if (orientation == 'horizontal') {
	if (and hasMore hasLess) { extra += (unit + (floor (size / 3))) }
	setExtent morph (+ unit extra) size
  } else {
	if (and hasMore hasLess) { extra += (unit + (floor (size / 5))) }
	setExtent morph size (+ unit extra)
  }
}

method drawOn BlockDrawer ctx {
  if (notNil target) {
    hasMore = (canExpand target)
    hasLess = (canCollapse target)
  } else {
    hasMore = true
    hasLess = true
  }

  scale = (blockScale)
  size = (height morph)
  if (orientation == 'vertical') { size = (width morph) }
  unit = (half size)
  padding = (half unit)
  clr = (gray 255 220)

  pen = (getShapeMaker ctx)
  x = (left morph)
  y = ((top morph) + (1 * scale))
  h = (size - (2 * scale))
  offset = 0
  if hasLess { // draw left or up arrow
	if (orientation == 'horizontal') {
	  fillArrow pen (rect (+ x padding) y unit h) 'left' clr
	  offset = (unit + (floor (size / 3)))
	} else {
	  fillArrow pen (rect x (+ y padding) size unit) 'up' clr
	  offset = (unit + (floor (size / 5)))
	}
  }
  if hasMore { // draw right or down arrow
	if (orientation == 'horizontal') {
	  fillArrow pen (rect (+ x padding offset) y unit h) 'right' clr
	} else {
	  fillArrow pen (rect x (+ y padding offset) size unit) 'down' clr
	}
  }
  // uncomment following line to see bounds rectangle
  // outlineRectangle pen (bounds morph) 1 (gray 180)
}

method handEnter BlockDrawer aHand {
  setCursor 'pointer'
}

method handLeave BlockDrawer aHand {
  setCursor 'default'
  // handEnter happens before handLeave, so cursor wouldn't go back to finger
  // when you move between two buttons without any space in between. A temporary
  // solution is to re-trigger handEnter on the new morph under the hand.
  handEnter (objectAt aHand) aHand
}

method clicked BlockDrawer aHand {
  if (isNil target) {return false}
  hasMore = (canExpand target)
  hasLess = (canCollapse target)
  if (and hasMore hasLess) {
    if (orientation == 'horizontal') {
      if ((x aHand) > (hCenter (bounds morph))) {
        expand target
      } else {
        collapse target
      }
    } else { // 'vertical'
      if ((y aHand) > (vCenter (bounds morph))) {
        expand target
      } else {
        collapse target
      }
    }
  } else { // single arrow
    if hasLess {
      collapse target
    } else {
      expand target
    }
  }
  return true
}

// keyboard accessibility hooks

method trigger BlockDrawer {
  if (isNil target) {return}
  if (canExpand target) {
    expand target
  } (canCollapse target) {
    collapse target
  }
}

method collapse BlockDrawer {
  if (isNil target) {return}
  if (canCollapse target) {collapse target}
}
