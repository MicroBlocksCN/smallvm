// VectorPen.gp -- Turtle-style vector graphics with stroked and/or filled paths.

// VectorPen includes an incomplete simulation of vector graphics for use when the vector
// graphics primitives are not available (e.g. when porting to a new platform). This
// simulation does not handle paths that cross themselves or have holes, anti-aliasing,
// or line cap and joint styles. It may also omit future features of GP vector graphics
// primitives such as gradients.

defineClass VectorPen penX penY heading bitmap owner path usePrimitives pathWidth halfWidth color

method examples VectorPen {
  showImage (drawCircle (newVectorPen))
  showImage (drawBox (newVectorPen))
  showImage (drawFatBox (newVectorPen))
  showImage (drawStar (newVectorPen))
  showImage (drawPentagon (newVectorPen))
  showImage (drawRoundedRect (newVectorPen))

  // simulated:
  showImage (drawCircle (newVectorPen nil nil true))
  showImage (drawBox (newVectorPen nil nil true))
  showImage (drawFatBox (newVectorPen nil nil true))
  showImage (drawStar (newVectorPen nil nil true))
  showImage (drawPentagon (newVectorPen nil nil true))
  showImage (drawRoundedRect (newVectorPen nil nil true))
}

to newVectorPen bitmap owningMorph noPrimitives {
  if (isNil bitmap) {
	bitmap = (newBitmap 200 200)
  }
  return (intialize (new 'VectorPen') bitmap owningMorph noPrimitives)
}

method bitmap VectorPen { return bitmap }
method setColor VectorPen c { noop } // for compatability with pen; ignore
method setHeading VectorPen degrees { heading = degrees }

method intialize VectorPen aBitmap aMorph noPrimitives {
  penX = 100
  penY = 100
  heading = 0
  bitmap = aBitmap
  owner = aMorph
  path = (list)
  usePrimitives = (hasPrimitive 'vectorFillPath')
  if (noPrimitives == true) { usePrimitives = false }
if (true == (global 'fakeVectors')) { usePrimitives = false } // xxx for testing
  return this
}

method beginPath VectorPen x y {
  if (isNil x) { x = 100 }
  if (isNil y) { y = 100 }
  penX = x
  penY = y
  heading = 0
  path = (list 'M' x y)
}

method goto VectorPen dstX dstY {
  // For compatability with Pen
  lineTo this dstX dstY
}

method lineTo VectorPen dstX dstY {
  startX = penX
  startY = penY
  penX = dstX
  penY = dstY
  addSegment this startX startY penX penY
}

method curveTo VectorPen dstX dstY cx cy {
  startX = penX
  startY = penY
  penX = dstX
  penY = dstY
  addAll path (array 'C' dstX dstY cx cy)
}

method cubicCurveTo VectorPen c1X c1Y c2X c2Y dstX dstY {
  // Approximate a cubic Bezier with four quadratic ones.
  // Based on Timothee Groleau's Bezier_lib.as - v1.2, 19/05/02, which
  // uses a simplified version of the midpoint algorithm by Helen Triolo.
  // http://www.timotheegroleau.com/Flash/articles/cubic_bezier_in_flash.htm

  startX = penX
  startY = penY
  penX = dstX
  penY = dstY

  // points used to calculate the control points pc2 and pc3
  paX = (interpolate startX c1X 0.75)
  paY = (interpolate startY c1Y 0.75)
  pbX = (interpolate dstX c2X 0.75)
  pbY = (interpolate dstY c2Y 0.75)

  // 1/16 of the [start, dst] segment
  dx = ((dstX - startX) / 16)
  dy = ((dstY - startY) / 16)

  // control point 1
  pc1X = (interpolate startX c1X 0.375)
  pc1Y = (interpolate startY c1Y 0.375)

  // control point 2
  pc2X = ((interpolate paX pbX 0.375) - dx)
  pc2Y = ((interpolate paY pbY 0.375) - dy)

  // control point 3
  pc3X = ((interpolate pbX paX 0.375) + dx)
  pc3Y = ((interpolate pbY paY 0.375) + dy)

  // control point 4
  pc4X = (interpolate dstX c2X 0.375)
  pc4Y = (interpolate dstY c2Y 0.375)

  // three intermediate anchor points
  pa1X = (interpolate pc1X pc2X 0.5)
  pa1Y = (interpolate pc1Y pc2Y 0.5)

  pa2X = (interpolate paX pbX 0.5)
  pa2Y = (interpolate paY pbY 0.5)

  pa3X = (interpolate pc3X pc4X 0.5)
  pa3Y = (interpolate pc3Y pc4Y 0.5)

  // draw the four quadratic subsegments
  addAll path (array 'C' pa1X pa1Y pc1X pc1Y)
  addAll path (array 'C' pa2X pa2Y pc2X pc2Y)
  addAll path (array 'C' pa3X pa3Y pc3X pc3Y)
  addAll path (array 'C' dstX dstY pc4X pc4Y)
}

method forward VectorPen dist curvature {
  startX = penX
  startY = penY
  penX += (dist * (cos heading))
  penY += (dist * (sin heading))

  // make almost vertical or horizontal exact (compenstates for tiny floating point errors)
  if ((abs (penX - startX)) < 0.000001) { penX = startX }
  if ((abs (penY - startY)) < 0.000001) { penY = startY }

  addSegment this startX startY penX penY curvature
}

method turn VectorPen degrees radius {
  // If radius is nil or zero, turn in place. If radius > 0, move the given number of
  // degrees along an approximately circular arc. To ensure minimal error, the arc is
  // approximated by a sequence of short, quadratic Bezier arc segments.

  if (degrees == 0) { return } // no turn

  if (or (isNil radius) (radius == 0)) { // turn in place
	heading = ((heading + degrees) % 360)
	return
  }

  if (degrees > 0) { // right turn (clockwise)
	centerX = (penX - (radius * (sin heading)))
	centerY = (penY + (radius * (cos heading)))
	angle = (heading - 90) // bearing from center point to pen
  } else { // left turn (counter-clockwise)
	centerX = (penX + (radius * (sin heading)))
	centerY = (penY - (radius * (cos heading)))
	angle = (heading + 90) // bearing from center point to pen
  }
  maxDegreesPerStep = 45
  steps = ((truncate ((abs degrees) / maxDegreesPerStep)) + 1)
  degreesPerStep = (degrees / steps)
  repeat steps {
	midAngle = (angle + (degreesPerStep / 2))
	endAngle = (angle + degreesPerStep)
	cx = ((((-0.5 * ((cos angle) + (cos endAngle))) + (2 * (cos midAngle))) * radius) + centerX)
	cy = ((((-0.5 * ((sin angle) + (sin endAngle))) + (2 * (sin midAngle))) * radius) + centerY)

	penX = (centerX + (radius * (cos endAngle)))
	penY = (centerY + (radius * (sin endAngle)))
	addAll path (array 'C' penX penY cx cy)
	angle = endAngle
  }
  heading = ((heading + degrees) % 360)
}

method stroke VectorPen borderColor width joint cap {
  if (isNil borderColor) { borderColor = (gray 0) }
  if (isNil width) { width = 1 }
  if (isNil joint) { joint = 0 }
  if (isNil cap) { cap = 0 }

  if usePrimitives {
	vectorStrokePath bitmap (toArray path) borderColor width joint cap
  } else {
	// Simulate vector primitives. Cap and joint are ignored.
	color = borderColor
	drawPath this (max 1 (round width))
  }
  if (notNil owner) { costumeChanged owner }
}

method fill VectorPen fillColor {
  if (isNil fillColor) { fillColor = (gray 0) }
  if usePrimitives {
	closedPath = (copy path)
	add closedPath 'Z'
	vectorFillPath bitmap (toArray closedPath) fillColor
  } else {
	if (fillColor == (gray 0)) { fillColor = (gray 1) } // avoid black/transparent confusion
	oldPath = path
	path = (closedPath this)
	color = fillColor
	drawPath this 1
	fillPath this
	path = oldPath
  }
  if (notNil owner) { costumeChanged owner }
}

method fillRoundedRect VectorPen rect radius fillColor border borderColor {
  // Draw a rounded rectangle. If fillColor is nil, just draw the border.
  // If border is nil or 0, just draw the fill. borderColor defaults to black.

  if (isNil radius) { radius = 4 }
  if (isNil border) { border = 0 }
  adjustedW = ((width rect) - ((2 * radius) + border))
  adjustedH = ((height rect) - ((2 * radius) + border))

  beginPath this (+ (left rect) (half border) radius) (+ (top rect) (half border))
  setHeading this 0
  repeat 2 {
	forward this adjustedW
	turn this 90 radius
	forward this adjustedH
	turn this 90 radius
  }
  if (notNil fillColor) {
	fill this fillColor
  }
  if (border > 0) {
	if (isNil borderColor) { borderColor = (gray 0) }
	stroke this borderColor border
  }
}

// internal method

method addSegment VectorPen x1 y1 x2 y2 curvature {
  if (isNil curvature) { curvature = 0 }
  if (curvature == 0) {
	addAll path (array 'L' x2 y2)
  } else {
	// control point is on a line perpendicular to the segment
	// at it's midpoint, scaled by (curvature / 100)
	curvature = (curvature / 100)
	midpointX = ((x1 + x2) / 2)
	midpointY = ((y1 + y2) / 2)
	cx = (midpointX + (curvature * (y2 - y1)))
	cy = (midpointY + (curvature * (x1 - x2)))
	addAll path (array 'C' x2 y2 cx cy)
  }
}

method closedPath VectorPen {
  if ((count path) < 4) { return path }
  firstX = (at path 2)
  firstY = (at path 3)
  if (and ((round penX) == (round firstX)) ((round penY) == (round firstY))) {
	return path
  }
  result = (copy path)
  addAll result (array 'L' firstX firstY)
  return result
}

method drawPath VectorPen width {
  pathWidth = width
  halfWidth = (half pathWidth)
  startX = 0
  startY = 0
  i = 1
  while (i <= (count path)) {
	cmd = (at path i)
	if ('M' == cmd) {
	  startX = (at path (i + 1))
	  startY = (at path (i + 2))
	  i += 3
	} ('L' == cmd) {
	  endX = (at path (i + 1))
	  endY = (at path (i + 2))
	  drawLine this startX startY endX endY
	  startX = endX
	  startY = endY
	  i += 3
	} ('C' == cmd) {
	  endX = (at path (i + 1))
	  endY = (at path (i + 2))
	  cx = (at path (i + 3))
	  cy = (at path (i + 4))
	  quadBezier this startX startY endX endY cx cy
	  startX = endX
	  startY = endY
	  i += 5
	}
  }
}

method quadBezier VectorPen x0 y0 x1 y1 cx cy {
  stepCount = 20
  x = x0
  y = y0
  for i stepCount {
	p = (quadaticBezier x0 y0 x1 y1 cx cy i stepCount)
	nextX = (first p)
	nextY = (last p)
	drawLine this x y nextX nextY
	x = nextX
	y = nextY
  }
}

method quadBezierNoPrimitive VectorPen x0 y0 x1 y1 cx cy {
  // This version computes the Bezier points in GP instead of using a primitive.
  stepCount = 10
  x = x0
  y = y0
  for i stepCount {
	t = (i / stepCount)
	invT = (1 - t)
	a = (invT * invT)
	b = (2 * (t * invT))
	c = (t * t)
	nextX = (+ (a * x0) (b * cx) (c * x1))
	nextY = (+ (a * y0) (b * cy) (c * y1))
	drawLine this x y nextX nextY
	x = nextX
	y = nextY
  }
}

method drawLine VectorPen x0 y0 x1 y1 {
  x0 = (truncate x0)
  y0 = (truncate y0)
  x1 = (truncate x1)
  y1 = (truncate y1)

  // use line drawing primitive:
  drawLineOnBitmap bitmap x0 y0 x1 y1 color pathWidth
  return

  if (x0 == x1) { // vertical line
	top = (min y0 y1)
	h = (abs (y1 - y0))
	if (pathWidth <= 1) {
	  fillRect bitmap color x0 top 1 (h + 1)
	} else {
	  fillRect bitmap color (x0 - halfWidth) (top - halfWidth) pathWidth (h + pathWidth)
	}
	return
  } (y0 == y1) { // horizontal line
	left = (min x0 x1)
	w = (abs (x1 - x0))
	if (pathWidth <= 1) {
	  fillRect bitmap color left y0 (w + 1) 1
	} else {
	  fillRect bitmap color (left - halfWidth) (y0 - halfWidth) (w + pathWidth) pathWidth
	}
	return
  }

  // Bresenham's algorithm
  dx = (abs (x1 - x0))
  dy = (abs (y1 - y0))
  if (x0 < x1) {sx = 1} else {sx = -1}
  if (y0 < y1) {sy = 1} else {sy = -1}
  err = (dx - dy)
  while true {
	fillRect bitmap color (x0 - halfWidth) (y0 - halfWidth) pathWidth pathWidth
	if (and (x0 == x1) (y0 == y1)) {return}
	  e2 = (2 * err)
	if (e2 > (0 - dy)) {
	  err = (err - dy)
	  x0 = (x0 + sx)
	}
	if (and (x0 == x1) (y0 == y1)) {
	  fillRect bitmap color (x0 - halfWidth) (y0 - halfWidth) pathWidth pathWidth
	  return
	}
	if (e2 < dx) {
	  err = (err + dx)
	  y0 = (y0 + sy)
	}
  }
}

method fillPath VectorPen {
  // Use flood fill to fill a closed path, using a point on the right side of the first
  // segment as the seed. Does not work for paths that cross themselves, for donuts, etc.

  if ((count path) < 6) { return }
  n = 1
  firstX = (at path 2)
  firstY = (at path 3)
  if (not (isClass (at path 4) 'String')) { print 'first cmd:' (at path 1); return }
  dx = ((at path 5) - firstX)
  dy = ((at path 6) - firstY)
  len = (sqrt (+ (dx * dx) (dy * dy)))
  if (len > 0) {
	centerX = (firstX + (dx / 2))
	centerY = (firstY + (dy / 2))
	seedX = (round (centerX - ((2 * dy) / len)))
	seedY = (round (centerY + ((2 * dx) / len)))
  } else {
	pathCenter = (pathCenter this)
	seedX = (round (first pathCenter))
	seedY = (round (last pathCenter))
  }
  if (or (seedX < 0) (seedY < 0)) {
	print 'bad seed' seedX seedY
	return
  }
  floodFill bitmap seedX seedY color
  if false { fillRect bitmap (color 0 255 255) seedX seedY 2 2 } // show fill point (debugging)
}

method pathCenter VectorPen {
  // Return an array containing the center of this path.

  if ((count path) < 3) { return (array 0 0) } // shouldn't happen
  firstX = (at path 2)
  firstY = (at path 3)
  sumX = firstX
  sumY = firstY
  n = 1
  i = 4
  while (i <= (count path)) {
	cmd = (at path i)
	if ('M' == cmd) {
	  sumX += (at path (i + 1))
	  sumY += (at path (i + 2))
	  i += 3
	} ('L' == cmd) {
	  sumX += (at path (i + 1))
	  sumY += (at path (i + 2))
	  i += 3
	} ('C' == cmd) {
	  sumX += (at path (i + 1))
	  sumY += (at path (i + 2))
	  i += 5
	}
	n += 1
  }
  return (array (sumX / n) (sumY / n))
}

// examples

method drawCircle VectorPen {
  beginPath this 100 10
  setHeading this 0
  turn this 360 80
  fill this (randomColor)
  stroke this (gray 0) 1
  return (bitmap this)
}

method drawBox VectorPen {
  beginPath this 80 10
  setHeading this 0
  repeat 4 {
	forward this 100
	turn this 90
  }
  fill this (randomColor)
  stroke this (color 0 0 200) 8
  return (bitmap this)
}

method drawFatBox VectorPen {
  beginPath this 20 20
  setHeading this 0
  repeat 4 {
	forward this 100 10
	turn this 90
  }
  fill this (randomColor)
  stroke this (gray 0) 3
  return (bitmap this)
}

method drawStar VectorPen {
  beginPath this 30 80
  repeat 6 {
	// go one extra stroke to ensure a good miter at the starting point
	forward this 150
	turn this 144
  }
  jointStyle = 0 // 0 - sharp (mitered), 1 - rounded, 2 - beveled
  fill this (randomColor)
  stroke this (gray 0) 10 jointStyle
  return (bitmap this)
}

method drawPentagon VectorPen {
  beginPath this 50 20
  setHeading this 5
  repeat 5 {
	forward this 100
	turn this 72
  }
  fill this (randomColor)
  stroke this (gray 0) 3
  return (bitmap this)
}

method drawRoundedRect VectorPen {
  radius = 10
  borderThickness = 3
  fillRoundedRect this (rect 10 10 100 100) radius (randomColor) borderThickness (gray 0)
  return (bitmap this)
}
