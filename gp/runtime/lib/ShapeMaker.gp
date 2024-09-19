defineClass ShapeMaker pen recordedPaths

method pen ShapeMaker { return pen }

to newShapeMaker bitmap {
  return (initialize (new 'ShapeMaker') bitmap)
}

to newShapeMakerForPathRecording {
  return (initForRecording (new 'ShapeMaker'))
}

method initialize ShapeMaker aBitmap {
  if (isNil aBitmap) {
    pen = (newVectorPenPrims)
  } else {
    pen = (newVectorPen aBitmap)
  }
  recordedPaths = nil
  return this
}

// path recording

method initForRecording ShapeMaker {
  pen = (newVectorPen aBitmap)
  recordedPaths = (list)
  return this
}

method isRecording ShapeMaker { return (notNil recordedPaths) }
method recordedPaths ShapeMaker { return recordedPaths }

method fill ShapeMaker fillColor {
  if (notNil recordedPaths) {
    add recordedPaths (array 'fill' (copyWith (path pen) 'Z') fillColor)
  } else {
    fill pen fillColor
  }
}

method fillAndStroke ShapeMaker fillColor borderColor borderWidth {
  if (notNil recordedPaths) {
    add recordedPaths (array 'fillAndStroke' (path pen) fillColor borderColor borderWidth)
  } else {
    fillAndStroke pen fillColor borderColor borderWidth
  }
}

method stroke ShapeMaker borderColor borderWidth joint cap {
  if (isNil joint) { joint = 0 }
  if (isNil cap) { cap = 0 }
  if (notNil recordedPaths) {
    add recordedPaths (array 'stroke' (path pen) borderColor borderWidth joint cap)
  } else {
    stroke pen borderColor borderWidth joint cap
  }
}

// shapes

method fillRectangle ShapeMaker rect fillColor {
  beginPath pen (left rect) (bottom rect)
  roundedRectPath this rect 0
  fill this fillColor
}

method outlineRectangle ShapeMaker rect border borderColor {
  if (border <= 0) { return }
  beginPath pen (left rect) (bottom rect)
  roundedRectPath this rect 0
  stroke this borderColor border
}

method outlineRoundedRectangle ShapeMaker rect border borderColor radius {
  if (border <= 0) { return }
  beginPath pen (left rect) ((bottom rect) - radius)
  roundedRectPath this rect radius
  stroke this borderColor border
}

method fillRoundedRect ShapeMaker rect radius color border borderColorTop borderColorBottom {
  if (isNil border) {border = 0}
  if (border > 0) {
    if (isNil borderColorTop) { borderColorTop = (darker color) }
    if (isNil borderColorBottom) { borderColorBottom = borderColorTop }
    rect = (insetBy rect (border / 2))
  }
  if (or ((width rect) <= 0) ((height rect) <= 0)) { return }

  radius = (min radius ((height rect) / 2) ((width rect) / 2))
  beginPath pen (left rect) ((bottom rect) - radius)
  roundedRectPath this rect radius
  fill this color

  if (border > 0) {
    beginPath pen (left rect) ((bottom rect) - radius)
    setHeading pen 270
    roundedRectHalfPath this rect radius
    stroke this borderColorTop border

    beginPath pen (right rect) ((top rect) + radius)
    setHeading pen 90
    roundedRectHalfPath this rect radius
    stroke this borderColorBottom border
  }
}

method roundedRectPath ShapeMaker rect radius {
  setHeading pen 270
  if (0 == radius) {
	w = (width rect)
	h = (height rect)
	repeat 2 {
	  forward pen h
	  turn pen 90
	  forward pen w
	  turn pen 90
	}
  } else {
	repeat 2 {
	  roundedRectHalfPath this rect radius
	}
  }
}

method roundedRectHalfPath ShapeMaker rect radius {
  radius = (min radius ((height rect) / 2) ((width rect) / 2))
  w = ((width rect) - (radius * 2))
  h = ((height rect) - (radius * 2))

  useNew = true
  if useNew {
    forward pen h
    turn pen 90 radius
    forward pen w
    turn pen 90 radius
  } else {
    corner = (sqrt ((radius * radius) * 2))
    forward pen h
    turn pen 45
    forward pen corner 50
    turn pen 45
    forward pen w
    turn pen 45
    forward pen corner 50
    turn pen 45
  }
}

method drawCircle ShapeMaker centerX centerY radius fillColor borderWidth borderColor {
  // Draw a circle with an optional border. If color is nil or transparent,
  // the circle is not filled.

  if (isNil borderWidth) { borderWidth = 0 }
  startY = (centerY - radius)
  beginPath pen centerX startY
  turn pen 360 radius
  fillAndStroke this fillColor borderColor borderWidth
}

method fillArrow ShapeMaker rect orientation fillColor {
  if (isNil fillColor) { fillColor = (gray 0) }
  if (orientation == 'right') {
    baseLength = (height rect)
    ak = (width rect)
    beginPath pen (left rect) (bottom rect)
    setHeading pen 270
  } (orientation == 'left') {
    baseLength = (height rect)
    ak = (width rect)
    beginPath pen (right rect) (top rect)
    setHeading pen 90
  } (orientation == 'up') {
    baseLength = (width rect)
    ak = (height rect)
    beginPath pen (right rect) (bottom rect)
    setHeading pen 180
  } (orientation == 'down') {
    baseLength = (width rect)
    ak = (height rect)
    beginPath pen (left rect) (top rect)
    setHeading pen 0
  } else {
    error (join 'unsupported orientation "' orientation '"')
  }
  gk = (baseLength / 2)
  tipLength = (sqrt ((gk * gk) + (ak * ak)))
  tipAngle = (90 + (atan gk ak))
  forward pen baseLength
  turn pen tipAngle
  forward pen tipLength
  fill this fillColor
}

method drawLine ShapeMaker x0 y0 x1 y1 thickness color joint cap {
  beginPath pen x0 y0
  lineTo pen x1 y1
  stroke this color thickness joint cap
}

// Tab

method drawTab ShapeMaker rect radius border color {
  radius = (min radius ((height rect) / 2) ((width rect) / 4))
  if (isNil border) {border = 0}
  halfBorder = (border / 2)
  rect = (rect ((left rect) + halfBorder) (top rect) ((width rect) - border) ((height rect) - halfBorder))

  // start at bottom right and draw base first (helps filling heuristic when simulating vector primitives)
  beginPath pen (right rect) (bottom rect)
  tabPath this rect radius
  fillAndStroke this color (lighter color) border
}

method tabPath ShapeMaker rect radius {
  w = ((width rect) - (radius * 4))
  h = ((height rect) - (radius * 2))
  corner = (sqrt ((radius * radius) * 2))

  // start at bottom right and draw base first (helps filling heuristic when simulating vector primitives)
  beginPath pen (right rect) (bottom rect)
  setHeading pen 180
  forward pen (width rect)

  setHeading pen 0
  turn pen -45
  forward pen corner -50
  turn pen -45
  forward pen h
  turn pen 45
  forward pen corner 50
  turn pen 45
  forward pen w
  turn pen 45
  forward pen corner 50
  turn pen 45

  setHeading pen 90
  forward pen h
  turn pen -45
  forward pen corner -50
  turn pen -45
}

// Speech bubble

method drawSpeechBubble ShapeMaker rect scale direction fillColor borderColor {
  if (isNil direction) { direction = 'left' }
  if (isNil fillColor) { fillColor = (gray 250) }
  if (isNil borderColor) { borderColor = (gray 140) }

  border = (2 * scale)
  radius = (5 * scale)
  tailH = (8 * scale) // height of tail
  tailW = (4 * scale) // width of tail base
  indent = (8 * scale) // horizontal distance from edge to tail

  r = (insetBy rect border)
  w = ((width r) - (2 * radius))
  h = (((height r) - tailH) - (2 * radius))

  beginPath pen (left r) ((top r) + (h + radius))
  setHeading pen 270
  forward pen h
  turn pen 90 radius
  forward pen w
  turn pen 90 radius
  forward pen h
  turn pen 90 radius
  if ('left' == direction) {
	forward pen (indent - radius)
	lineTo pen (right r) (bottom r)
	lineTo pen ((right r) - (+ indent tailW radius)) ((bottom r) - tailH)
  } ('right' == direction) {
	forward pen (w - (indent + tailW))
	lineTo pen (left r) (bottom r)
	lineTo pen ((left r) + indent) ((bottom r) - tailH)
  }
  lineTo pen ((left r) + radius) ((bottom r) - tailH)
  turn pen 90 radius

  fillAndStroke this fillColor borderColor border
}

// Grips

method circleWithCrosshairs ShapeMaker size circleRadius color {
  center = (size / 2)
  circleBorder = (size / 6)
  drawCircle this center center circleRadius nil circleBorder color
  fillRectangle this (rect 0 (center - 1) size 2) color
  fillRectangle this (rect (center - 1) 0 2 size) color
}

method drawRotationHandle ShapeMaker size circleRadius color {
  center = (size / 2)
  circleBorder = (size / 6)
  drawCircle this center center circleRadius nil circleBorder color
}

method drawResizer ShapeMaker x y width height orientation isInset {
  right = (x + width)
  if ('horizontal' == orientation) { right = x }
  off = 0
  if isInset { off = 2 }
  w = 0.8
  c = (gray 130)
  space = (truncate (width / 3))
  if ('vertical' == orientation) {
	for i (width / space) {
	  baseY = (+ y ((i - 1) * space) off)
	  drawLine this x (baseY + (w * 1)) right (baseY + (w * 1)) w c
	  drawLine this x (baseY + (w * 2)) right (baseY + (w * 2)) w c
	  drawLine this x (baseY + (w * 3)) right (baseY + (w * 3)) w c
	}
  } else { // 'horizontal' or 'free'
	bottom = (y + height)
	for i (width / space) {
	  baseLeft = (+ x ((i - 1) * space) off)
	  baseRight = (+ right ((i - 1) * space) off)
	  drawLine this (baseLeft + (w * 1)) bottom (baseRight + (w * 1)) y w c
	  drawLine this (baseLeft + (w * 2)) bottom (baseRight + (w * 2)) y w c
	  drawLine this (baseLeft + (w * 3)) bottom (baseRight + (w * 3)) y w c
	}
  }
}

// Button

method drawButton ShapeMaker x y width height buttonColor corner border isInset {
  if (isNil isInset) {isInset = false}
  if isInset {
    topColor = (darker buttonColor)
    bottomColor = (lighter buttonColor)
  } else {
    topColor = (lighter buttonColor)
    bottomColor = (darker buttonColor)
  }
  fillRoundedRect this (rect x y width height) corner buttonColor border topColor bottomColor
}

// Blocks

// Block corner radius and reporter end radius
method blockCorner ShapeMaker { return (4 * (blockScale)) }

// Block dent width and inset from edge plus indent for C-shaped blocks.
method dent ShapeMaker { return (6 * (blockScale)) }
method notchWidth ShapeMaker { return (16 * (blockScale)) } // 12
method notchDepth ShapeMaker { return (4 * (blockScale)) } // 3
method inset ShapeMaker { return (8 * (blockScale)) }
method cIndent ShapeMaker { return (8 * (blockScale)) }

// Block border width, inset, and color.
method blockBorder ShapeMaker { return (max 1 (round (global 'scale'))) }
method blockBorderInset ShapeMaker { return ((blockBorder this) / 2) }
method blockBorderColor ShapeMaker blockColor {
  hsv = (hsv blockColor)
  return (colorHSV (at hsv 1) (at hsv 2) (0.8 * (at hsv 3)))
}

method drawReporter ShapeMaker rect blockColor radius {
  fillRoundedRect this rect radius blockColor (blockBorder this) (blockBorderColor this blockColor)
}

method beginBlockPath ShapeMaker rect {
  // Position the pen at the bottom left corner of rect minus the notch and corner height.

  beginPath pen (left rect) ((bottom rect) - ((notchDepth this) + (blockCorner this)))
}

method drawBlock ShapeMaker rect blockColor {
  dent = (dent this)
  inset = (inset this)
  corner = (blockCorner this)
  borderColor = (blockBorderColor this blockColor)
  beginBlockPath this rect
  blockTopPath this rect
  blockBottomPath this rect
  fill this blockColor
  stroke this borderColor (blockBorder this)
}

method drawHatBlock ShapeMaker rect blockColor {
  hatWidth = (80 * (blockScale))
  inset = (inset this)
  corner = (blockCorner this)

  hatHeight = ((hatWidth / (sqrt 2)) - (hatWidth / 2))
  borderColor = (blockBorderColor this blockColor)

  beginBlockPath this rect
  hatBlockTopPath this rect hatWidth
  blockBottomPath this rect
  fillAndStroke this blockColor borderColor (blockBorder this)
//   fill this blockColor
//   stroke this borderColor (blockBorder this)
}

method drawBlockWithCommandSlots ShapeMaker rect commandSlots blockColor {
  scale = (blockScale)
  borderColor = (blockBorderColor this blockColor)
  corner = (blockCorner this)

  // contruct and fill a path including command slots
  beginBlockPath this rect
  blockTopPath this rect
  for cslot commandSlots {
	slotTopPath this cslot rect
	slotBottomPath this cslot rect
  }
  blockBottomPath this rect
  fill this blockColor
  stroke this borderColor (blockBorder this)
}

method slotTopPath ShapeMaker cslot rect {
  scale = (blockScale)
  inset = (inset this)
  corner = (blockCorner this)

  slotTop = ((at cslot 1) - (3 * scale))
  slotH = ((at cslot 2) - (14 * scale))
  upperIndentInset = (42 * scale)

  setHeading pen 90 // down
  lineTo pen (right rect) ((top rect) + slotTop)

  turn pen 90 corner

  // top slot edge to notch
  forward pen ((width rect) - upperIndentInset)

  // top notch
  blockNotch this -1

  // top edge inset
  forward pen (inset - corner)

  // inner left of slot
  turn pen -90 corner
  forward pen slotH
}

method slotBottomPath ShapeMaker cslot rect {
  // bottom edge of slot and corner
  corner = (blockCorner this)
  turn pen -90 corner
  lineTo pen ((right rect) - corner) (y pen)
  turn pen 90 corner
}

method blockTopPath ShapeMaker rect {
  corner = (blockCorner this)
  inset = (inset this)

  // left side vertical
  setHeading pen 270
  forward pen ((height rect) - ((notchDepth this) + (2 * corner)))

  // top left corner
  roundedCorner this corner 1

  // upper inset
  forward pen (inset - corner)

  // upper notch
  blockNotch this 1

  // top edge from notch to right side
  forward pen ((width rect) - (+ inset (notchWidth this) corner))

  // upper right corner
  roundedCorner this corner 1
}

method blockBottomPath ShapeMaker rect {
  inset = (inset this)
  corner = (blockCorner this)

  // right side vertical edge
  setHeading pen 90
  lineTo pen (x pen) ((bottom rect) - (corner + (notchDepth this)))

  // bottom right corner
  roundedCorner this corner 1

  // bottom edge from right side to notch
  forward pen ((width rect) - (+ inset (notchWidth this) corner))

  // bottom notch
  blockNotch this -1

  // bottom inset
  forward pen (inset - corner)

  // bottom left corner
  roundedCorner this corner 1
}

method hatBlockTopPath ShapeMaker rect hatWidth {
  hatHeight = ((hatWidth / (sqrt 2)) - (hatWidth / 2))
  corner = (blockCorner this)

  // left side
  setHeading pen 270
  forward pen ((height rect) - (+ hatHeight (corner * 2)))

  // top hat-curve
  turn pen 90
  forward pen hatWidth 40
  forward pen ((width rect) - (hatWidth + corner))

  // upper right corner
  roundedCorner this corner 1
}

method roundedCorner ShapeMaker radius dir {
  // Turn by 90 degrees with rounding.
  // dir is 1 for a right turn, -1 for a left turn.

  turn pen (dir * 45)
  forward pen (sqrt ((radius * radius) * 2)) (dir * 50)
  turn pen (dir * 45)
}

method blockNotch ShapeMaker dir {
  // Draw a block notch.
  // dir is 1 if notch starts with a right turn, -1 if it starts with left turn.
  // bottomW is notchWidth - (2 * dx)

  scale = (blockScale)
  dx = (3 * scale)
  dy = (notchDepth this)
  bottomW = ((notchWidth this) - (2 * dx))

  moveBy pen (dx * dir) dy
  moveBy pen (bottomW * dir) 0
  moveBy pen (dx * dir) (0 - dy)
}
