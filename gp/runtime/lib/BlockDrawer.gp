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
  size = (13 * (blockScale))
  unit = (half size)
  extra = 0
  if (orientation == 'horizontal') {
	if (and hasMore hasLess) { extra = (unit + (floor (size / 3))) }
	setExtent morph (+ unit extra) size
  } else {
	if (and hasMore hasLess) { extra = (unit + (floor (size / 5))) }
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
  size = (13 * (blockScale))
  unit = (half size)
  clr = (gray 255 220)

  pen = (getShapeMaker ctx)
  x = (left morph)
  y = (top morph)
  offset = 0
  if hasLess { // draw left arrow
	if (orientation == 'horizontal') {
	  fillArrow pen (rect x y unit size) 'left' clr
	  offset = (unit + (floor (size / 3)))
	} else {
	  fillArrow pen (rect x y size unit) 'up' clr
	  offset = (unit + (floor (size / 5)))
	}
  }
  if hasMore { // draw right arrow
	if (orientation == 'horizontal') {
	  fillArrow pen (rect (x + offset) y unit size) 'right' clr
	} else {
	  fillArrow pen (rect x (y + offset) size unit) 'down' clr
	}
  }
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
