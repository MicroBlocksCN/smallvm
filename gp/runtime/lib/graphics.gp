defineClass Bitmap width height pixelData name

method width Bitmap { return width }
method height Bitmap { return height }
method pixelData Bitmap { return pixelData }
method name Bitmap { return name }
method setName Bitmap s { name = s }

to newBitmap width height color {
  gcIfNeededFor (width * height)
  width = (max 0 (ceiling width))
  height = (max 0 (ceiling height))
  pixelData = (newBinaryData (4 * (width * height)))
  bm = (new 'Bitmap' width height pixelData)
  if (notNil color) { fill bm color }
  setField bm 'name' ''
  return bm
}

to gcIfNeededFor words {
  buffer = 1000000
  stats = (memStats)
  bytesFree = ((at stats 2) - (at stats 1))
  if (((words + buffer) * 4) > bytesFree) {
	print 'gc needed to allocate bitmap;' (gc) 'freed'
  }
}

method fill Bitmap color {
  comment '
	Fill this bitmap with the given color (including alpha).'

  fillPixelsRGBA pixelData (red color) (green color) (blue color) (alpha color)
}

method fillAlpha Bitmap alpha {
  comment '
	Fill the alpha channel of this bitmap without changing the RGB channel.'

  if (isNil alpha) { alpha = 255 }
  for i (count pixelData) {
    rgb = (getPixelRGB pixelData i)
	setPixelRGBA pixelData i ((rgb >> 16) & 255) ((rgb >> 8) & 255) (rgb & 255) alpha
  }
}

method copy Bitmap {
  dup = (newBitmap width height)
  drawBitmap dup this
  if (notNil name) {
	if (endsWith name ' copy') {
	  setName dup name
	} else {
	  setName dup (join '' name ' copy')
	}
  }
  return dup
}

method getPixel Bitmap x y {
  comment '
	Return the color of the given pixel. x and y are zero-based offsets from the top-left corner.'

  if (or (x < 0) (x >= width) (y < 0) (y >= height)) { error 'bad pixel coordinate' }
  i = (toInteger (((y * width) + x) + 1))
  alpha = (getPixelAlpha pixelData i)
  rgb = (getPixelRGB pixelData i)
  return (color ((rgb >> 16) & 255) ((rgb >> 8) & 255) (rgb & 255) alpha)
}

method setPixel Bitmap x y color {
  comment '
	Set the color of the given pixel. x and y are zero-based offsets from the top-left corner.'

  if (or (x < 0) (x >= width) (y < 0) (y >= height)) { error 'bad pixel coordinate' }
  i = (toInteger (((y * width) + x) + 1))
  setPixelRGBA pixelData i (red color) (green color) (blue color) (alpha color)
}

method setRGBA Bitmap x y r g b a {
  comment '
	Set the color of the given pixel. x and y are zero-based offsets from the top-left corner.'

  setPixelRGBA pixelData (toInteger (((y * width) + x) + 1)) r g b a
}

// transformations

method thumbnail Bitmap w h {
  // Create a thumbnail of this bitmap with given width and height.
  w = (floor w)
  h = (floor h)
  if (or (width == 0) (height == 0)) {
	return (newBitmap w h)
  }
  scale = (min ((toFloat w) / width) ((toFloat h) / height))
  xOffset = (floor ((w - (scale * width)) / 2))
  yOffset = (floor ((h - (scale * height)) / 2))
  t = (newTexture w h)
  showTexture t (toTexture this) xOffset yOffset 255 scale scale
  return (toBitmap t)
}

method scaleAndRotate Bitmap xScale yScale rotationDegrees dstBitmap {
  // Return a copy of this bitmap scaled and rotated.
  // Rotation goes counter-clockwise as the angle increases.
  // If dstBitmap is provide and is the right size, recycle it.

  if (isNil yScale) { yScale = xScale }
  if (isNil rotationDegrees) { rotationDegrees = 0 }
  if (or (xScale <= 0) (yScale <= 0)) { error 'Scale must be greater than zero' }
  xOffset = 0
  yOffset = 0
  newW = (xScale * width)
  newH = (yScale * height)
  if (rotationDegrees != 0) {
	diagonal = (sqrt ((newW * newW) + (newH * newH)))
	xOffset = (half (diagonal - newW))
	yOffset = (half (diagonal - newH))
	newW = diagonal
	newH = diagonal
  }
  srcTexture = (toTexture this)
  t = (newTexture (max 1 (ceiling newW)) (max 1 (ceiling newH)))
  showTexture t srcTexture xOffset yOffset 255 xScale yScale rotationDegrees false 0
  if (and (notNil dstBitmap) ((width dstBitmap) == (width t)) ((height dstBitmap) == (height t))) {
	result = dstBitmap
	readTexture result t
  } else {
	result = (toBitmap t)
  }
  destroyTexture t
  destroyTexture srcTexture
  return result
}

method guessTransparentColor Bitmap {
  r = (width - 1)
  b = (height - 1)
  c = (getPixel this 0 0)
  if ((alpha c) == 0) { return c }
  c = (getPixel this r 0)
  if ((alpha c) == 0) { return c }
  c = (getPixel this 0 b)
  if ((alpha c) == 0) { return c }
  c = (getPixel this r b)
  if ((alpha c) == 0) { return c }
  setAlpha c 0
  return c
}

method cropTransparent Bitmap {
  // Return a bitmap cropped to remove any transparent borders around the image,
  // or the original bitmap if it can't be cropped any more.

  top = nil
  bottom = nil
  left = nil
  right = nil

  y = 0
  while (isNil top) {
    i = ((y * width) + 1)
	repeat width {
	  if ((getPixelAlpha pixelData i) > 0) { top = y }
	  i += 1
    }
	y += 1
	if (y >= height) { return (newBitmap 0 0) } // all pixels are transparent
  }

  y = (height - 1)
  while (isNil bottom) {
    i = ((y * width) + 1)
	repeat width {
	  if ((getPixelAlpha pixelData i) > 0) { bottom = y }
	  i += 1
    }
	y += -1
  }

  x = 0
  while (isNil left) {
	y = top
	while (y <= bottom) {
	  i = (((y * width) + x) + 1)
	  if ((getPixelAlpha pixelData i) > 0) { left = x }
	  y += 1
    }
	x += 1
  }

  x = (width - 1)
  while (isNil right) {
	y = top
	while (y <= bottom) {
	  i = (((y * width) + x) + 1)
	  if ((getPixelAlpha pixelData i) > 0) { right = x }
	  y += 1
    }
	x += -1
  }

  result = (newBitmap ((right - left) + 1) ((bottom - top) + 1))
  drawBitmap result this (0 - left) (0 - top) 255 0 // copy mode
  return result
}

method floodFillAt Bitmap startX startY newColor threshold {
  startX = (round startX)
  startY = (round startY)
  if (isNil threshold) { threshold = 0 }
  threshold = (clamp (truncate threshold) 0 7)
  mask = ((255 << threshold) & 255)
  mask = (((mask << 16) | (mask << 8)) | mask)

  w = (width this)
  h = (height this)
  pixels = pixelData
  seedIndex = (toInteger (((startY * w) + startX) + 1))
  if (or (seedIndex < 1) (seedIndex > (count pixels))) { return }
  unprocessed = (newArray (count pixels) true)
  matchRGB = (getPixelRGB pixels seedIndex)
  matchRGB = (matchRGB & mask)

  newR = (red newColor)
  newG = (green newColor)
  newB = (blue newColor)
  newA = (alpha newColor)

  todo = (list (array startX startY))
  while (notEmpty todo) {
    p = (removeLast todo)
	y = (at p 2)
	lineStart = ((w * y) + 1)
	lineEnd = ((lineStart + w) - 1)
	left = (lineStart + (at p 1))
	right = left
	while (and (left > lineStart) (((getPixelRGB pixels (left - 1)) & mask) == matchRGB)) { left += -1 }
	while (and (right < lineEnd) (((getPixelRGB pixels (right + 1)) & mask) == matchRGB)) { right += 1 }
	i = left
	while (i <= right) {
	  setPixelRGBA pixels i newR newG newB newA
	  atPut unprocessed i false
	  i += 1
	}

	// propagate fill to matching pixels in adjacent lines
	for offset (array -1 1) {
	  adjacentY = (y + offset)
	  if (and (adjacentY >= 0) (adjacentY < h)) { // if adjacentY is in range
		lineStart = ((w * adjacentY) + 1)
		run = false
		for i (range (left + (w * offset)) (right + (w * offset))) {
		  if (and (at unprocessed i) (((getPixelRGB pixels i) & mask) == matchRGB)) {
			if (not run) {
			  // only add one todo list entry for each run
			  x = (i - lineStart)
			  add todo (array x adjacentY)
			  run = true
			}
		  } else {
			run = false
		  }
		  atPut unprocessed i false
		}
	  }
	}
  }
}

// alpha channel masking

method extractAlphaChannel Bitmap {
  // Return the alpha channel data for this bitmap.

  result = (newBinaryData (width * height))
  for i (byteCount result) {
	byteAtPut result i (getPixelAlpha pixelData i)
  }
  return result
}

method applyAlphaChannel Bitmap alphaChannel color {
  // Fill this bitmap with the given color masked by
  // the given alpha channel.

  if (isNil color) { color = (color) }
  r = (red color)
  g = (green color)
  b = (blue color)
  fillPixelsRGBA pixelData 0 0 0 0
  count = (min (byteCount alphaChannel) (width * height))
  for i count {
	a = (byteAt alphaChannel i)
	if (a > 0) {
	  setPixelRGBA pixelData i r g b a
	}
  }
  return this
}

// converting

method toTexture Bitmap {
  comment '
	Return a new texture with the contents of this bitmap.'

  if (or (width < 1) (height < 1)) { return (newTexture 1 1) }
  result = (newTexture width height)
  updateTexture result this
  return result
}

method toString Bitmap {
  return (join '<Bitmap ' width 'x' height '>')
}

defineClass Texture width height ref

method width Texture { return width }
method height Texture { return height }

to newTexture width height color {
  ref = (createTexture width height color)
  return (new 'Texture' width height ref)
}

method fill Texture color {
  comment '
	Fill this texture with the given color (including alpha).'

	fillRect this color 0 0 width height 0
}

method copyTexture Texture {
  result = (newTexture width height)
  showTexture result this 0 0 255 1 1 0 false 0
  return result
}

method destroyTexture Texture {
  comment '
	Destroy this texture. This frees the texture memory on the GPU.'

  destroyTexture ref
  ref = nil
}

method toBitmap Texture {
  result = (newBitmap width height)
  readTexture result this
  return result
}

method toString Texture {
  return (join '<Texture ' width 'x' height '>')
}

to fontHeight {
  return ((fontAscent) + (fontDescent))
}
