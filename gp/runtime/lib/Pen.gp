// Pen
// graphics primitives for canvasses (bitmaps or textures)

defineClass Pen canvas color size xPos yPos heading isDown

to newPen canvas {
  return (new 'Pen' canvas (color) 1 0 0 0.0 false)
}
method canvas Pen {return canvas}
method setCanvas Pen aBitmapOrTexture {canvas = aBitmapOrTexture}

// pen color and thickness

method alpha Pen {return (alpha color)}
method color Pen {return color}
method lineWidth Pen {return size}

method setAlpha Pen a {setAlpha color a}
method setColor Pen aColor {color = aColor}
method setLineWidth Pen aNumber {size = (max 1 (round aNumber))}

// pen up/down

method isDown Pen {return isDown}
method down Pen {isDown = true}
method up Pen {isDown = false}

// position and motion

method x Pen {return xPos}
method y Pen {return yPos}
method setX Pen num {xPos = num}
method setY Pen num {yPos = num}

method goto Pen newX newY {
  if isDown {
	drawLine this xPos yPos newX newY
  }
  xPos = newX
  yPos = newY
}

method move Pen n {
  newX = (xPos + (n * (cos heading)))
  newY = (yPos + (n * (sin heading)))
  goto this newX newY
}

// direction

method direction Pen {return heading}
method setDirection Pen num {heading = (num % 360)}
method turn Pen degrees {setDirection this (heading + degrees)}

method turnTo Pen x y {
  deltaX = ((toFloat x) - (toFloat xPos))
  deltaY = ((toFloat y) - (toFloat yPos))
  setDirection this (atan deltaY deltaX)
}

// line drawing

method drawLine Pen x0 y0 x1 y1 {
  usePrimitive = (and (1 == size) (255 == (alpha color)) (isClass canvas 'Bitmap'))
  if usePrimitive {
    drawLineOnBitmap canvas x0 y0 x1 y1 color size false
    return
  }
  x0 = (truncate x0)
  y0 = (truncate y0)
  x1 = (truncate x1)
  y1 = (truncate y1)

  // check for vertical and horizontal layout
  if (and (size == 1) (or (x0 == x1) (y0 == y1))) {
    lx = (min x0 x1)
    rx = (max x0 x1)
    ty = (min y0 y1)
    by = (max y0 y1)
    fillRect this lx ty (max 1 (rx - lx)) (max 1 (by - ty))
    return
  }

  // Bresenham's algorithm
  dx = (abs (x1 - x0))
  dy = (abs (y1 - y0))
  if (x0 < x1) {sx = 1} else {sx = -1}
  if (y0 < y1) {sy = 1} else {sy = -1}
  err = (dx - dy)
  while true {
    plot this x0 y0
    if (and (x0 == x1) (y0 == y1)) {return}
    e2 = (2 * err)
    if (e2 > (0 - dy)) {
      err = (err - dy)
      x0 = (x0 + sx)
    }
    if (and (x0 == x1) (y0 == y1)) {
      plot this x0 y0
      return
    }
    if (e2 < dx) {
      err = (err + dx)
      y0 = (y0 + sy)
    }
  }
}

method plot Pen x y {
  if (size > 1) {
    s2 = (size / 2)
    x = (x - s2)
    y = (y - s2)
  }
  fillRect canvas color x y size size
}

// arrow support for showing links

method drawArrow Pen startX startY endX endY arrowColor noArrowHead {
  oldColor = color
  if (notNil arrowColor) { color = arrowColor } else { color = (gray 0) }
  scale = (global 'scale')
  headAngle = 25
  headLength = (10 * scale)
  if (noArrowHead == true) { headLength = 0 }

  if (notNil canvas) {
	drawVectorArrow this startX startY endX endY headAngle headLength
  } else {
	// draw a dotted line directly onto the display buffer
	drawDottedArrow this startX startY endX endY headAngle headLength
  }
  color = oldColor
}

method drawVectorArrow Pen startX startY endX endY headAngle headLength {
  scale = (global 'scale')
  vecPen = (newVectorPen canvas)
  beginPath vecPen startX startY
  goto vecPen endX endY
  if (headLength > 0) {
	angle = (atan (startY - endY) (startX - endX))
	turn vecPen (angle + headAngle)
	forward vecPen headLength
	forward vecPen (0 - headLength)
	turn vecPen (-2 * headAngle)
	forward vecPen headLength
  }
  stroke vecPen (gray 255) (2 * scale) 1 1 // thick white arrow
  stroke vecPen (gray 0) (0.5 * scale) 1 1 // thinner black arrow inside it
}

method drawDottedArrow Pen startX startY endX endY headAngle headLength {
  size = (global 'scale') // pen width
  drawDottedLine this startX startY endX endY
  if (headLength > 0) {
	a0 = (atan (startY - endY) (startX - endX))
	a1 = (a0 - headAngle)
	a2 = (a0 + headAngle)
	drawDottedLine this endX endY (endX + (headLength * (cos a1))) (endY + (headLength * (sin a1)))
	drawDottedLine this endX endY (endX + (headLength * (cos a2))) (endY + (headLength * (sin a2)))
  }
}

method drawDottedLine Pen x0 y0 x1 y1 {
  x0 = (truncate x0)
  y0 = (truncate y0)
  x1 = (truncate x1)
  y1 = (truncate y1)

  white = (gray 255)
  c = color

  // Bresenham's algorithm
  dx = (abs (x1 - x0))
  dy = (abs (y1 - y0))
  if (x0 < x1) {sx = 1} else {sx = -1}
  if (y0 < y1) {sy = 1} else {sy = -1}
  err = (dx - dy)
  while true {
	fillRect canvas c x0 y0 size size
    if (and (x0 == x1) (y0 == y1)) {return}
    e2 = (2 * err)
    if (e2 > (0 - dy)) {
      err = (err - dy)
      x0 = (x0 + sx)
    }
    if (and (x0 == x1) (y0 == y1)) {
	  fillRect canvas c x0 y0 size size
      return
    }
    if (e2 < dx) {
      err = (err + dx)
      y0 = (y0 + sy)
    }
    if (c == white) { c = color } else { c = white }
  }
}

// circles

method drawCircle Pen centerX centerY radius fillColor border borderColor {
  if (notNil fillColor) {
	fillCircle this centerX centerY radius fillColor
  }
  if (notNil borderColor) {
	oldSize = size
	oldColor = color
	size = (max 1 (round border))
	color = borderColor
	strokeCircle this centerX centerY radius
	size = oldSize
	color = oldColor
  }
}

method strokeCircle Pen x0 y0 radius {
  f = (1 - radius)
  ddf_x = 1
  ddf_y = (-2 * radius)
  x = 0
  y = radius
  plot this x0 (y0 - radius) // top
  plot this x0 (y0 + radius) // bottom
  plot this (x0 - radius) y0 // left
  plot this (x0 + radius) y0 // right
  while (x < y) {
    if (f >= 0) {
      y += -1
      ddf_y += 2
      f += ddf_y
    }
    x += 1
    ddf_x += 2
    f += ddf_x
    plot this (x0 - x) (y0 - y) // upper top left
    plot this (x0 + x) (y0 - y) // upper top right
    plot this (x0 - y) (y0 - x) // lower top left
    plot this (x0 + y) (y0 - x) // lower top right
    plot this (x0 - y) (y0 + x) // upper bottom left
    plot this (x0 + y) (y0 + x) // upper bottom right
    plot this (x0 - x) (y0 + y) // lower bottom left
    plot this (x0 + x) (y0 + y) // lower bottom right
  }
}

method fillCircle Pen x0 y0 radius fillColor {
  f = (1 - radius)
  ddf_x = 1
  ddf_y = (-2 * radius)
  x = 0
  y = radius
  fillRect canvas fillColor x0 (y0 - radius) 1 1 // top
  fillRect canvas fillColor x0 (y0 + radius) 1 1 // bottom
  fillRect canvas fillColor (x0 - radius) y0 ((2 * radius) + 1) 1 // middle line
  while (x < y) {
    if (f >= 0) {
      y += -1
      ddf_y += 2
      f += ddf_y
    }
    x += 1
    ddf_x += 2
    f += ddf_x
    w = ((2 * x) + 1)
	fillRect canvas fillColor (x0 - x) (y0 - y) w 1
	fillRect canvas fillColor (x0 - x) (y0 + y) w 1
    w = ((2 * y) + 1)
	fillRect canvas fillColor (x0 - y) (y0 - x) w 1
	fillRect canvas fillColor (x0 - y) (y0 + x) w 1
  }
}
