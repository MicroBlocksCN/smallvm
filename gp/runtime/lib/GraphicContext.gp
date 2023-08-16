// GraphicContext -- drawing state for Morphs
//
//	surface - a bitmap or nil; if nil, draw directly to the screen
//	clipRect - the current clipping rectangle
//	fontName, fontSize - current font settings
//	offsetX, offsetY - offset from the top-left of surface (in global coordinates)
//	savedState - a stack of clipping rectangles
//
// Offsets are absolute, not relative to the current offset.
// Clipping is additive. Each call to setClip intersects the new rectangle
// with the existing clipping rectangle.
//
// John Maloney, February 2021

defineClass GraphicContext surface fontName fontSize clipRect offsetX offsetY shapeMaker savedState

to newGraphicContextOnScreen clipRect {
	ctx = (newGraphicContextOn nil)
	if (notNil clipRect) { setClip ctx clipRect }
	return ctx
}

to newGraphicContextOn aBitmapOrNil {
	return (initialize (new 'GraphicContext') aBitmapOrNil)
}

method initialize GraphicContext aBitmapOrNil {
	surface = aBitmapOrNil
	fontName = 'Arial'
	fontSize = 36
	clipRect = (rect 0 0 (width this) (height this))
	offsetX = 0
	offsetY = 0
	shapeMaker = (newShapeMaker surface)
	savedState = (list)
	return this
}

method surface GraphicContext { return surface }

method width GraphicContext {
	if (notNil surface) { return (width surface) }
	return (at (windowSize) 3)
}

method height GraphicContext {
	if (notNil surface) { return (height surface) }
	return (at (windowSize) 4)
}

method intersectsClip GraphicContext aRect {
	// Return true if the given rectangle intersects the current clipping rectangle.

	if (or (offsetX != 0) (offsetY != 0)) {
		return (intersects aRect (translatedBy clipRect (- offsetX) (- offsetY)))
	}
	return (intersects aRect clipRect)
}

method setClip GraphicContext aRect {
	// Make the new clipping rectangle be the intersection of the current
	// clipping rectangle and the given rectangle. The new clipping rectangle
	// will always be within the current one.

	if (or (0 != offsetX) (0 != offsetY)) {
		aRect = (translatedBy aRect offsetX offsetY)
	}
	clipRect = (roundToIntegers (intersection clipRect aRect))
}

method setFont GraphicContext fName fSize {
	// Set the font name, font size, or both. Nil arguments are ignored,
	// so you can change just one of these without changing the other.

	if (notNil fName) { fontName = fName }
	if (notNil fSize) { fontSize = fSize }
	setFont fontName fontSize
}

method setOffset GraphicContext x y {
	// Set the offset (from the top-left of the surface) used for drawing operations.

	offsetX = x
	offsetY = y
}

method saveState GraphicContext {
	// Push the current drawing state.

	addFirst savedState (list clipRect offsetX offsetY)
}

method restoreState GraphicContext {
	// Restore the previous drawing state.

	if (notEmpty savedState) {
		oldState = (removeFirst savedState)
		clipRect = (at oldState 1)
		offsetX = (at oldState 2)
		offsetY = (at oldState 3)
	}
}

method getShapeMaker GraphicContext {
	// Get a ShapeMaker for vector drawing.

	pen = (pen shapeMaker)
	setOffset pen offsetX offsetY
	setClipRect pen clipRect
	return shapeMaker
}

// graphics operations

method clear GraphicContext aColor {
	if (isNil aColor) { aColor = (gray 255) }
	fillRect surface aColor 0 0 (width this) (height this)
}

method drawBitmap GraphicContext aBitmap x y {
	if (isNil x) { x = 0 }
	if (isNil y) { y = 0 }
	alpha = 255
	blendMode = 1 // alpha blending
	drawBitmap surface aBitmap (x + offsetX) (y + offsetY) alpha blendMode clipRect
}

method warpBitmap GraphicContext aBitmap x y scaleX scaleY {
	if (isNil x) { x = 0 }
	if (isNil y) { y = 0 }
	centerX = (+ x offsetX (half (scaleX * (width aBitmap))))
	centerY = (+ y offsetY (half (scaleY * (height aBitmap))))
	alpha = 255
	blendMode = 1 // alpha blending
	warpBitmap surface aBitmap centerX centerY scaleX scaleY 0 clipRect
}

method fillRect GraphicContext color x y w h blendMode {
	if (isNil blendMode) {
		if ((alpha color) < 255) { blendMode = 1 } else { blendMode = 0 }
	}
	if (and (1 == blendMode) (0 == (alpha color))) { return } // fully transparent
	r = (intersection clipRect (rect (x + offsetX) (y + offsetY) w h))
	if (and ((width r) > 0) ((height r) > 0)) {
		fillRect surface color (left r) (top r) (width r) (height r) blendMode
	}
}

method drawString GraphicContext aString aColor x y {
	if (isNil aColor) { aColor = (gray 0) }
	if (isNil x) { x = 0 }
	if (isNil y) { y = 0 }
	setFont fontName fontSize
	drawString surface aString aColor (x + offsetX) (y + offsetY) clipRect
}

method drawTexture GraphicContext aTexture x y {
	if (isNil x) { x = 0 }
	if (isNil y) { y = 0 }
	alpha = 255
	degrees = 0
	flip = 0
	blendMode = 1 // alpha blending

	showTexture surface aTexture (x + offsetX) (y + offsetY) alpha 1 1 degrees flip blendMode clipRect
}

method show GraphicContext {
	// For debugging. Display my surface, if any, on the screen and flip screen buffer.

	if (notNil surface) { clearBuffer (gray 255) } // clear screen before displaying surface
	if (isClass surface 'Bitmap') {
		drawBitmap nil surface
	} (isClass surface 'Texture') {
		showTexture nil surface
	}
	flipBuffer
}

// cached path drawing

method drawCachedPaths GraphicContext pathList x y {
	// Draw cached paths to the screen.

	if (notNil surface) { return } // do nothing if not screen

	for p pathList {
		op = (at p 1)
		path = (at p 2)
		vectorSetPathOffset x y
		if ('stroke' == op) {
			vectorStrokePath nil path (at p 3) (at p 4) (at p 5) (at p 6) clipRect
		} ('fill' == op) {
			vectorFillPath nil path (at p 3) clipRect
		} ('fillAndStroke' == op) {
			vectorFillPath nil (copy path) (at p 3) clipRect
			vectorSetPathOffset x y
			vectorStrokePath nil (copy path) (at p 4) (at p 5) 0 0 clipRect
		}
	}
}
