defineClass BlockDrawer morph target size orientation

to newBlockDrawer aBlock size orientation {
  if (isNil orientation) {orientation = 'horizontal'}
  bd = (new 'BlockDrawer' nil aBlock size orientation)
  initialize bd
  return bd
}

method initialize BlockDrawer {
  if (isNil size) {
    scale = (global 'scale')
    size = (scale * 10)
  }
  morph = (newMorph this)
  setTransparentTouch morph true // optimization
  redraw this
}

method redraw BlockDrawer {
  if (notNil target) {
    hasMore = (canExpand target)
    hasLess = (canCollapse target)
  } else {
    hasMore = true
    hasLess = true
  }
  unit = (size / 2)
  space = (size / 3)
  if (and hasLess hasMore) {
    w = (+ size space 1)
  } else {
    w = (+ unit 1)
  }
  if (orientation == 'horizontal') {
    bm = (newBitmap w size)
  } else { // 'vertical'
    bm = (newBitmap size w)
  }

  pen = (newShapeMaker bm)
  clr = (gray 0)
  if (global 'stealthBlocks') {
    clr = (gray (stealthLevel 0 180))
  }
  x = 0
  if hasLess { // draw left arrow
	if (orientation == 'horizontal') {
	  fillArrow pen (rect 0 0 unit size) 'left' clr
	} else {
	  fillArrow pen (rect 0 0 size unit) 'up' clr
	}
    x = (unit + space)
  }
  if hasMore { // draw right arrow
	if (orientation == 'horizontal') {
	  fillArrow pen (rect x 0 unit size) 'right' clr
	} else {
	  fillArrow pen (rect 0 x size unit) 'down' clr
	}
  }
  setCostume morph bm
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
  } else {
    if hasLess { // left arrow only
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

