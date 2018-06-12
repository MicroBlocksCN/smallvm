// Rectangle

defineClass Rectangle left top width height

to rect x y w h {
  if (isNil x) {x = 0}
  if (isNil y) {y = 0}
  if (isNil w) {w = 0}
  if (isNil h) {h = 0}
  return (new 'Rectangle' x y w h)
}

// accessing

method left Rectangle {return left}
method setLeft Rectangle aNumber {left = aNumber}
method top Rectangle {return top}
method setTop Rectangle aNumber {top = aNumber}
method width Rectangle {return width}
method setWidth Rectangle aNumber {width = aNumber}
method right Rectangle {return (left + width)}
method setRight Rectangle aNumber {width = (aNumber - left)}
method height Rectangle {return height}
method setHeight Rectangle aNumber {height = aNumber}
method bottom Rectangle {return (top + height)}
method setBottom Rectangle aNumber {height = (aNumber - top)}
method hCenter Rectangle {return (+ left (width / 2))}
method vCenter Rectangle {return (+ top (height / 2))}
method copy Rectangle {return (rect left top width height)}

// converting

method toString Rectangle {
  return (join '(rect ' left ' ' top ' ' width ' ' height ')')
}

// equality

method '==' Rectangle other {
  if (this === other) { return true }
  if (not (isClass other 'Rectangle')) {return false}
  if (left != (left other)) {return false}
  if (top != (top other)) {return false}
  if (width != (width other)) {return false}
  if (height != (height other)) {return false}
  return true
}

// functions

method insetBy Rectangle x y {
  // y is optional
  if (isNil y) {y = x}
  return (rect
    (left + x)
    (top + y)
    (width - (x * 2))
    (height - (y * 2)))
}

method expandBy Rectangle x y {
  // y is optional
  if (isNil y) {y = x}
  return (insetBy this (0 - x) (0 - y))
}

method intersect Rectangle another {
  // (command version) - mutates the receiver
  newR = (min (right this) (right another))
  newB = (min (bottom this) (bottom another))
  left = (max left (left another))
  top = (max top (top another))
  setRight this newR
  setBottom this newB
}

method intersection Rectangle another {
  // (reporter version) - answer a new rectangle
  result = (rect (max left (left another)) (max top (top another)))
  setRight result (min (right this) (right another))
  setBottom result (min (bottom this) (bottom another))
  return result
}

method merge Rectangle another {
  // (command version) - mutates the receiver
  newR = (max (right this) (right another))
  newB = (max (bottom this) (bottom another))
  left = (min left (left another))
  top = (min top (top another))
  setRight this newR
  setBottom this newB
}

method mergedWith Rectangle another {
  // (reporter version) - answer a new rectangle
  result = (rect (min left (left another)) (min top (top another)))
  setRight result (max (right this) (right another))
  setBottom result (max (bottom this) (bottom another))
  return result
}

// intersecting line segments

method intersectionsWithLineSegment Rectangle x1 y1 x2 y2 {
  line = (array x1 y1 x2 y2)
  right = (right this)
  bottom = (bottom this)
  result = (list)
  lines = (array
    (array left top right top)
    (array left top left bottom)
    (array left bottom right bottom)
    (array right top right bottom)
  )
  for side lines {
    collision = (callWith 'intersectionOfLines' (join side line))
    if (notNil collision) {
      add result collision
      if (== 2 (count result)) {return result}
    }
  }
  return result
}

to intersectionOfLines p0x p0y p1x p1y p2x p2y p3x p3y {
  // return an array containing the x and y coordinates where two line segments
  // intersect, nil if they don't'
  // adapted from http://stackoverflow.com/a/14795484
  s10x = (p1x - p0x)
  s10y = (p1y - p0y)
  s32x = (p3x - p2x)
  s32y = (p3y - p2y)

  denom = ((s10x * s32y) - (s32x * s10y))
  if (denom == 0) {return nil} // collinear
  denomPositive = (denom > 0)

  s02x = (p0x - p2x)
  s02y = (p0y - p2y)
  sNumber = ((s10x * s02y) - (s10y * s02x))
  if ((sNumber < 0) == denomPositive) {return nil} // no collision

  tNumber = ((s32x * s02y) - (s32y * s02x))
  if ((tNumber < 0) == denomPositive) {return nil} // no collision

  if (or (== denomPositive (sNumber > denom)) (== denomPositive (tNumber > denom))) {return nil} // no collision

  // collision detected
  t = ((toFloat tNumber) / (toFloat denom))
  return (array (p0x + (toInteger (t * (toFloat s10x)))) (p0y + (toInteger (t * (toFloat s10y)))))
}

// testing

method containsPoint Rectangle x y {
  if (x <= left) {return false}
  if (x > (right this)) {return false}
  if (y <= top) {return false}
  return (y <= (bottom this))
}

method containsRectangle Rectangle another {
  return (and
    (containsPoint this (left another) (top another))
    (containsPoint this (right another) (bottom another))
  )
}

method intersects Rectangle another {
  if ((right another) < left) {return false}
  if ((bottom another) < top) {return false}
  if ((left another) > (right this)) {return false}
  return ((top another) <= (bottom this))
}

// transforming

method translateBy Rectangle factor yFactor {
  // modify me inline, yFactor is optional
  if (isNil yFactor) {yFactor = factor}
  left += factor
  top += yFactor
}

method translatedBy Rectangle factor yFactor {
  // answer a new rectangle, yFactor is optional
  if (isNil yFactor) {yFactor = factor}
  return (rect (left + factor) (top + yFactor) width height)
}

method scaledBy Rectangle factor {
  return (rect (left * factor) (top * factor) (width * factor) (height * factor))
}

method scaledAndRotatedBoundingBox Rectangle xFactor yFactor degrees centerX centerY {
  // answer new absolute boundingBox
  if (isNil yFactor) {yFactor = xFactor}
  if (isNil degrees) {degrees = 0}
  if (isNil centerX) {centerX = (hCenter this)}
  if (isNil centerY) {centerY = (vCenter this)}
  p1 = (scaleAndRotateAround left top degrees centerX centerY xFactor yFactor)
  p2 = (scaleAndRotateAround (right this) top degrees centerX centerY xFactor yFactor)
  p3 = (scaleAndRotateAround (right this) (bottom this) degrees centerX centerY xFactor yFactor)
  p4 = (scaleAndRotateAround left (bottom this) degrees centerX centerY xFactor yFactor)
  box = (rect
    (min (first p1) (first p2) (first p3) (first p4))
    (min (last p1) (last p2) (last p3) (last p4))
  )
  setRight box (max (first p1) (first p2) (first p3) (first p4))
  setBottom box  (max (last p1) (last p2) (last p3) (last p4))
  return box
}

to scaleAndRotateAround x y degrees centerX centerY scaleX scaleY {
  // scale first, then rotate
  if (isNil centerX) {centerX = 0}
  if (isNil centerY) {centerY = 0}
  if (isNil scaleX) {scaleX = 1}
  if (isNil scaleY) {scaleY = scaleX}
  xd = (scaleX * (x - centerX))
  yd = (scaleY * (y - centerY))
  if (degrees == 0) {
	return (array (centerX + xd) (centerY + yd))
  }
  dist = (sqrt (+ (* xd xd) (* yd yd)))
  dir = ((atan yd xd) - degrees)
  return (array (centerX + (dist * (cos dir))) (centerY + (dist * (sin dir))))
}
