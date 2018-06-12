// morphic grip handlers, used for sliders and resizing handles

defineClass Grip morph trigger orientation gripInset within offsetX offsetY

method setGripInset Grip n { gripInset = n }

method fieldInfo Grip fieldName {
  if ('orientation' == fieldName) {
    info = (dictionary)
    atPut info 'type' 'options'
    atPut info 'options' (array 'horizontal' 'vertical')
    return info
  }
  return nil
}

to newGrip orientation width height {
  if (isNil width) {width = 20}
  if (isNil height) {height = 20}
  bt = (new 'Trigger' nil 'nop')
  m = (newMorph)
  setGrabRule m 'ignore'
  setMorph bt m
  setWidth (bounds m) width
  setHeight (bounds m) height
  grip = (new 'Grip' m bt orientation 0)
  setHandler m grip
  setRenderer bt grip
  redraw grip
  return grip
}

method handEnter Grip aHand {handEnter trigger aHand}
method handLeave Grip aHand {handLeave trigger aHand}
method clicked Grip {return true}
method rightClicked Grip {return true}

method stayWithin Grip aConstraint {
  // aConstraint can be either a Morph, a Rectangle, a two-number array or
  // anything that is callable, such as a string (selector) a function or an action,
  // and that will answer either a Morph, Rectangle or two-number array.
  // Two-number arrays are taken to represent the minimum coordinates, e.g. for
  // resizing handles
  within = aConstraint
}

method handDownOn Grip aHand {
  focusOn aHand this
  offsetX = ((x aHand) - (left morph))
  offsetY = ((y aHand) - (top morph))
  return (handDownOn trigger aHand)
}

method handMoveFocus Grip aHand {
  newX = (((x aHand) - offsetX) + gripInset)
  newY = (((y aHand) - offsetY) + gripInset)
  if (orientation == 'horizontal') {
    setLeft morph newX
  } (orientation == 'vertical') {
    setTop morph newY
  } else {
    setPosition morph newX newY
  }
  trigger this
}

method constrainTo Grip anArea {
  // private
  if (isNil anArea) {return}
  if (isClass anArea 'Morph') {
    keepWithin morph (bounds anArea)
  } (isClass anArea 'Rectangle') {
    keepWithin morph anArea
  } (isClass anArea 'Array') {
    stayRightBelow morph (at anArea 1) (at anArea 2)
  } else {
    constrainTo this (call anArea)
  }
}

method trigger Grip {
  constrainTo this within
  trigger trigger
}

method redraw Grip {
  // adjust to a change of bounds
  // by creating a new set of canvasses
  replaceCostumes this
}

method replaceCostumes Grip normalCostume highlightCostume pressedCostume {
  replaceCostumes trigger normalCostume highlightCostume pressedCostume
}

method clearCostumes Grip { clearCostumes trigger }
method removeCostume Grip costumeName {removeCostume trigger costumeName}
method normalCostume Grip {return (newBitmap (width morph) (height morph) (color 200 200 255))}
method highlightCostume Grip {return (newBitmap (width morph) (height morph) (color 200 255 200))}
method pressedCostume Grip {return (newBitmap (width morph) (height morph) (color 255 200 200))}

to resizeHandle target orientation {
  if (isNil orientation) {orientation = 'free'}
  m = (newMorph)
  setGrabRule m 'ignore'
  setTransparentTouch m true

  bt = (new 'Trigger')
  setMorph bt m
  grip = (new 'Grip' m bt orientation 0)
  drawResizeCostumes grip
  setHandler m grip
  stayWithin grip (action 'resizingConstraint' (morph target) (width m) (height m))

  if (orientation == 'vertical') {
    action = (action 'setHeightToBottom' (morph target) m)
    setBottom m (bottom (morph target))
    setXCenter m (hCenter (bounds (morph target)))
  } (orientation == 'horizontal') {
    action = (action 'setWidthToRight' (morph target) m)
    setRight m (right (morph target))
    setYCenter m (vCenter (bounds (morph target)))
  } else {
    action = (action 'setExtentToRightBottom' (morph target) m)
    if (isClass target 'Window') {
      setGripInset grip (border target)
    }
    setRight m (right (morph target))
    setBottom m (bottom (morph target))
  }
  setAction bt action

  addPart (morph target) m
  return grip
}

to moveHandle target {
  m = (newMorph)
  setGrabRule m 'ignore'
  setTransparentTouch m true
  bt = (new 'Trigger')
  setMorph bt m
  grip = (new 'Grip' m bt 'horizontal' 0)
  drawResizeCostumes grip
  setField grip 'orientation' 'free'
  gotoCenterOf m (morph target)
  setHandler m grip
  setAction bt (action 'gotoCenterOf' (morph target) m)
  page = (global 'page')
  closeUnclickedMenu page grip
  addPart page grip
  setField page 'activeMenu' grip
  return grip
}

to pinHandle target {
  m = (newMorph)
  setGrabRule m 'ignore'
  setTransparentTouch m true
  bt = (new 'Trigger')
  setMorph bt m
  grip = (new 'Grip' m bt 'free' 0)
  drawCrosshairsCostumes grip
  rp = (rotationCenter (morph target))
  setCenter m (first rp) (last rp)
  setHandler m grip
  setAction bt (action 'setRotationCenterTo' (morph target) m)
  page = (global 'page')
  closeUnclickedMenu page grip
  addPart page grip
  setField page 'activeMenu' grip
  return grip
}

to scalingHandle target {
  m = (newMorph)
  setGrabRule m 'ignore'
  setTransparentTouch m true
  bt = (new 'Trigger')
  setMorph bt m
  grip = (new 'Grip' m bt 'free' 0)
  drawSquareHotSpotCostumes grip
  rp = (rotationCenter (morph target))
  setCenter m (first rp) (last rp)
  dist = ((width (morph target)) / 2)
  rot = (rotation (morph target))
  moveBy m (dist * (cos rot)) (-1 * (dist * (sin rot)))
  setHandler m grip
  setAction bt (action 'scaleTo' (morph target) m)
  page = (global 'page')
  closeUnclickedMenu page grip
  addPart page grip
  setField page 'activeMenu' grip
  return grip
}

to rotationHandle target {
  m = (newMorph)
  setGrabRule m 'ignore'
  setTransparentTouch m true
  bt = (new 'Trigger')
  setMorph bt m
  grip = (new 'Grip' m bt 'free' 0)
  drawRoundHotSpotCostumes grip
  rp = (rotationCenter (morph target))
  setCenter m (first rp) (last rp)
  dist = ((width (morph target)) / 2)
  rot = (rotation (morph target))
  moveBy m (dist * (cos rot)) (-1 * (dist * (sin rot)))
  setHandler m grip
  setAction bt (action 'pointTo' (morph target) m)
  page = (global 'page')
  closeUnclickedMenu page grip
  addPart page grip
  setField page 'activeMenu' grip
  return grip
}

method drawResizeCostumes Grip {
  scale = (global 'scale')
  size = (scale * 15)
  nbm = (newBitmap size size)
  hbm = (newBitmap size size)
  drawResizer (newShapeMaker nbm) 0 0 size size orientation false
  drawResizer (newShapeMaker hbm) 0 0 size size orientation true
  replaceCostumes trigger nbm hbm hbm
  setWidth (bounds morph) (width nbm)
  setHeight (bounds morph) (height nbm)
}

method drawCrosshairsCostumes Grip {
  scale = (global 'scale')
  size = (30 * scale)
  bigCircle = (12 * scale)
  smallCircle = (10 * scale)
  color = (gray 0 180)
  nbm = (newBitmap size size)
  hbm = (newBitmap size size)
  circleWithCrosshairs (newShapeMaker nbm) size bigCircle color
  circleWithCrosshairs (newShapeMaker hbm) size smallCircle color
  replaceCostumes trigger nbm hbm hbm
  setWidth (bounds morph) (width nbm)
  setHeight (bounds morph) (height nbm)
}

method drawRoundHotSpotCostumes Grip {
  scale = (global 'scale')
  size = (24 * scale)
  center = (size / 2)
  bigCircle = (10 * scale)
  smallCircle = (8 * scale)
  color = (gray 0)
  nbm = (newBitmap size size)
  hbm = (newBitmap size size)
  drawCircle (newShapeMaker nbm) center center bigCircle nil (size / 6) color
  drawCircle (newShapeMaker hbm) center center smallCircle nil (size / 6) color
  replaceCostumes trigger nbm hbm hbm
  setWidth (bounds morph) (width nbm)
  setHeight (bounds morph) (height nbm)
}

method drawSquareHotSpotCostumes Grip {
  scale = (global 'scale')
  size = (20 * scale)
  inset = (2 * scale)
  smaller = (size - (2 * inset))
  rect = (rect 0 0 size size)
  color = (gray 0)
  nbm = (newBitmap size size)
  hbm = (newBitmap size size)
  outlineRectangle (newShapeMaker nbm) (rect 0 0 size size) (size / 6) color
  outlineRectangle (newShapeMaker hbm) (rect inset inset smaller smaller) (size / 6) color
  replaceCostumes trigger nbm hbm hbm
  setWidth (bounds morph) (width nbm)
  setHeight (bounds morph) (height nbm)
}

method drawPaneResizingCostumes Grip {
  w = (width morph)
  h = (height morph)
  hc = (color 180 180 255 150)
  nbm = (newBitmap w h)
  hbm = (newBitmap w h hc)
  replaceCostumes trigger nbm hbm
  if (== this (focus (hand (global 'page')))) {
    highlight trigger
  }
}

// serialization

method preSerialize Grip {
  preSerialize trigger
}

method postSerialize Grip {
  postSerialize trigger
}
