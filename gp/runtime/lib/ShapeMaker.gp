defineClass ShapeMaker pen

method pen ShapeMaker { return pen }

to newShapeMaker bitmap {
  return (initialize (new 'ShapeMaker') bitmap)
}

method initialize ShapeMaker aBitmap {
  pen = (newVectorPen aBitmap)
  return this
}

// shapes

method fillRectangle ShapeMaker rect fillColor {
  bitmap = (bitmap pen)
  fillRect bitmap fillColor (left rect) (top rect) (width rect) (height rect)
}

method outlineRectangle ShapeMaker rect border borderColor {
  x = (left rect)
  y = (top rect)
  w = (width rect)
  h = (height rect)
  bitmap = (bitmap pen)
  fillRect bitmap borderColor x y w border
  fillRect bitmap borderColor x y border h
  fillRect bitmap borderColor ((x + w) - border) y border h
  fillRect bitmap borderColor x ((y + h) - border) w border
}

method fillRoundedRect ShapeMaker rect radius color border borderColorTop borderColorBottom {
  if (isNil border) {border = 0}
  if (border > 0) {
    if (isNil borderColorTop) {borderColorTop = (color 0 0 0 255)}
    if (isNil borderColorBottom) {borderBolorBottom = borderColorTop}
    rect = (insetBy rect (border / 2))
  }
  if (or ((width rect) <= 0) ((height rect) <= 0)) { return }

  radius = (min radius ((height rect) / 2) ((width rect) / 2))
  beginPath pen (left rect) ((bottom rect) - radius)
  roundedRectPath this rect radius
  fill pen color

  if (border > 0) {
    beginPath pen (left rect) ((bottom rect) - radius)
    setHeading pen 270
    roundedRectHalfPath this rect radius
    stroke pen borderColorTop border

    beginPath pen (right rect) ((top rect) + radius)
    setHeading pen 90
    roundedRectHalfPath this rect radius
    stroke pen borderColorBottom border
  }
  unmultiplyAlpha (bitmap pen)
}

method drawCircle ShapeMaker centerX centerY radius color border borderColor {
  // Draw a circle with an optional border. If color is nil or transparent,
  // the circle is not filled.

  if (isNil border) {border = 0}
  startY = (centerY - radius)
  beginPath pen centerX startY
  turn pen 360 radius
  if (and (notNil color) ((alpha color) > 0)) {
    fill pen color
  }
  if (border > 0) {
    if (isNil borderColor) {borderColor = (gray 0)}
    stroke pen borderColor border
  }
  unmultiplyAlpha (bitmap pen)
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
  fill pen fillColor 1
  unmultiplyAlpha (bitmap pen)
}

method drawLine ShapeMaker x0 y0 x1 y1 thickness color joint cap {
  beginPath pen x0 y0
  lineTo pen x1 y1
  stroke pen color thickness joint cap
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
  fill pen color
  if (border > 0) {
    stroke pen (lighter color) border
  }
  unmultiplyAlpha (bitmap pen)
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

  fill pen fillColor
  stroke pen borderColor border
  unmultiplyAlpha (bitmap pen)
}

// Grips

method circleWithCrosshairs ShapeMaker size circleRadius color {
  center = (size / 2)
  circleBorder = (size / 6)
  drawCircle this center center circleRadius nil circleBorder color
  unmultiplyAlpha (bitmap pen)
  fillRectangle this (rect 0 (center - 1) size 2) color
  fillRectangle this (rect (center - 1) 0 2 size) color
}

method drawRotationHandle ShapeMaker size circleRadius color {
  center = (size / 2)
  circleBorder = (size / 6)
  drawCircle this center center circleRadius nil circleBorder color
  unmultiplyAlpha (bitmap pen)
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

// Blocks

method drawBlock ShapeMaker x y width height blockColor radius dent inset border {
  rect = (insetBy (rect x y width height) (border / 2))
  beginPath pen (left rect) ((bottom rect) - (radius * 2))

  blockPath this rect radius dent inset
  fill pen blockColor

  if (and (not (global 'flatBlocks')) (border > 0)) {
    beginPath pen (left rect) ((bottom rect) - (radius * 2))
    blockTopPath this rect radius dent inset
    stroke pen (lighter blockColor) border

    beginPath pen (right rect) ((top rect) + radius)
    blockBottomPath this rect radius dent inset
    stroke pen (darker blockColor) border
  }
  unmultiplyAlpha (bitmap pen)
}

method drawHatBlock ShapeMaker x y width height hatWidth blockColor radius dent inset border {
  hatHeight = ((hatWidth / (sqrt 2)) - (hatWidth / 2))
  rect = (insetBy (rect x y width height) (border / 2))

  beginPath pen (left rect) ((bottom rect) - (radius * 2))
  hatBlockPath this rect radius dent inset hatWidth
  fill pen blockColor

  if (and (not (global 'flatBlocks')) (border > 0)) {
    beginPath pen (left rect) ((bottom rect) - (radius * 2))
    hatBlockTopPath this rect radius dent inset hatWidth
    stroke pen (lighter blockColor) border

    beginPath pen (right rect) (+ (top rect) hatHeight radius)
    setHeading pen 90
    hatBlockBottomPath this rect radius dent inset hatWidth
    stroke pen (darker blockColor) border
  }
  unmultiplyAlpha (bitmap pen)
}

method drawCSlot ShapeMaker x y width height blockColor radius dent inset border {
  halfBorder = (border / 2)

  rect = (rect x y width (height + border))
  beginPath pen x (y - halfBorder)
  cSlotPath this rect radius dent inset border
  fill pen blockColor

  if (and (not (global 'flatBlocks')) (border > 0)) {
    corner = (sqrt ((radius * radius) * 2))

    beginPath pen ((right rect) - halfBorder) ((top rect) - halfBorder)
    cSlotTopPath this rect radius dent inset border
    stroke pen (darker blockColor) border

    beginPath pen (((left rect) + inset) - (border * 2.5)) ((bottom rect) - (+ halfBorder (radius * 2)))
    setHeading pen 90
    cSlotBottomPath this rect radius dent inset border
    stroke pen (lighter blockColor) border
  }
  unmultiplyAlpha (bitmap pen)
}

method drawReporter ShapeMaker x y width height blockColor rounding border {
  if (global 'flatBlocks') {border = 0}
  drawButton this x y width height blockColor rounding border
}

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

// paths

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

method blockPath ShapeMaker rect radius dent inset {
  blockTopPath this rect radius dent inset
  blockBottomPath this rect radius dent inset
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

method blockTopPath ShapeMaker rect radius dent inset {
  corner = (sqrt ((radius * radius) * 2))

  // left side
  setHeading pen 270
  forward pen ((height rect) - (radius * 3))

  // top left corner
  turn pen 45
  forward pen corner 50
  turn pen 45

  // upper inset
  forward pen (inset - radius)

  // upper notch
  turn pen 45
  forward pen corner
  turn pen -45
  forward pen dent
  turn pen -45
  forward pen corner
  turn pen 45

  forward pen ((width rect) - (+ inset dent (radius * 3)))

  // upper right corner
  turn pen 45
  forward pen corner 50
}

method blockBottomPath ShapeMaker rect radius dent inset {
  corner = (sqrt ((radius * radius) * 2))

  setHeading pen 90

  // right side
  forward pen ((height rect) - (radius * 3))

  // bottom right corner
  turn pen 45
  forward pen corner 50
  turn pen 45

  forward pen ((width rect) - (+ inset dent (radius * 3)))

  // bottom notch
  turn pen -45
  forward pen corner
  turn pen 45
  forward pen dent
  turn pen 45
  forward pen corner
  turn pen -45

  // bottom inset
  forward pen (inset - radius)

  // bottom left corner
  turn pen 45
  forward pen corner 50
  turn pen 45
}

method hatBlockPath ShapeMaker rect radius dent inset hatWidth {
  hatBlockTopPath this rect radius dent inset hatWidth
  hatBlockBottomPath this rect radius dent inset hatWidth
}

method hatBlockTopPath ShapeMaker rect radius dent inset hatWidth {
  corner = (sqrt ((radius * radius) * 2))
  hatHeight = ((hatWidth / (sqrt 2)) - (hatWidth / 2))

  // left side
  setHeading pen 270
  forward pen ((height rect) - (+ hatHeight (radius * 2)))

  // top hat-curve
  turn pen 90
  forward pen hatWidth 40
  forward pen ((width rect) - (+ hatWidth radius))

  // upper right corner
  turn pen 45
  forward pen corner 50
  turn pen 45
}

method hatBlockBottomPath ShapeMaker rect radius dent inset hatWidth {
  corner = (sqrt ((radius * radius) * 2))
  hatHeight = ((hatWidth / (sqrt 2)) - (hatWidth / 2))

  // right side
  forward pen ((height rect) - (+ hatHeight (radius * 3)))

  // bottom right corner
  turn pen 45
  forward pen corner 50
  turn pen 45

  forward pen ((width rect) - (+ inset dent (radius * 3)))

  // bottom notch
  turn pen -45
  forward pen corner
  turn pen 45
  forward pen dent
  turn pen 45
  forward pen corner
  turn pen -45

  // bottom inset
  forward pen (inset - radius)

  // bottom left corner
  turn pen 45
  forward pen corner 50
  turn pen 45
}

method cSlotPath ShapeMaker rect radius dent inset border {
  corner = (sqrt ((radius * radius) * 2))
  b = (border / 2)

  // top
  forward pen ((width rect) - b)

  cSlotTopPath this rect radius dent inset border
  cSlotBottomPath this rect radius dent inset border

  // bottom
  turn pen 135
  forward pen ((width rect) - b)
}

method cSlotTopPath ShapeMaker rect radius dent inset border {
  corner = (sqrt ((radius * radius) * 2))

  // top right corner
  turn pen 135
  forward pen corner 50
  turn pen 45

  // upper inner slot
  forward pen ((width rect) - (+ (radius * 4) inset dent border))

  // upper notch
  turn pen -45
  forward pen corner
  turn pen 45
  forward pen dent
  turn pen 45
  forward pen corner
  turn pen -45
  forward pen (+ border (inset - radius))

  // upper left inner corner
  turn pen -45
  forward pen corner -50
  turn pen -45

  // right (inner) side
  forward pen ((height rect) - (radius * 4))
}

method cSlotBottomPath ShapeMaker rect radius dent inset border {
  corner = (sqrt ((radius * radius) * 2))

  // lower left inner corner
  turn pen -45
  forward pen corner -50
  turn pen -45

  // lower inner slot
  forward pen ((width rect) - (radius * 3))

  // bottom right corner
  turn pen 45
  forward pen corner 50
}
