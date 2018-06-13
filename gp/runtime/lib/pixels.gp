// Bitmap pixel access as single list of pixels
// Mark Guzdial, August 2015
// Subset of Mark's original version integrated into GP by John Maloney

to self_getPixels bm {
  m = (morph (implicitReceiver))
  if (isNil bm) {
	bm = (costumeData m)
  } else {
	if (isClass bm 'String') {
	  bm = (imageNamed bm m)
	}
	if (not (isClass bm 'Bitmap')) { return (array) }
	m = nil // don't update morph when setting pixels
  }
  allpixels = (list)
  pixels = (pixelData bm)
  for i (count pixels) {
	add allpixels (new 'Pixel' pixels i m)
  }
  return allpixels
}

to self_getPixelXY x y bm {
  // Return the pixel at x,y in the given bitmap or the current costume.
  m = (morph (implicitReceiver))
  if (isNil bm) {
	bm = (costumeData m)
  } else {
	if (isClass bm 'String') {
	  bm = (imageNamed bm m)
	}
	if (not (isClass bm 'Bitmap')) { error 'No image with that name' }
	m = nil // don't update morph when setting pixels
  }
  pixels = (pixelData bm)
  x = (round x)
  y = (round y)
  if (or (x < 1) (x > (width bm))) { error (join 'x must be between 1 and ' (width bm)) }
  if (or (y < 1) (y > (height bm))) { error (join 'y must be between 1 and ' (height bm)) }
  i = (((y - 1) * (width bm)) + x)
  return (new 'Pixel' pixels i m)
}

to self_copycostume name {
  m = (morph (implicitReceiver))
  self_setCostume name
  setCostume m (copy (costumeData m))
  costumeChanged m
}

// Let pixel getters work with both pixels and color objects:

to getRed obj { return (red obj) }
to getGreen obj { return (green obj) }
to getBlue obj { return (blue obj) }

// Pixel Class

defineClass Pixel pixels index targetMorph

method red Pixel { return (((getPixelRGB pixels index) >> 16) & 255) }
method green Pixel { return (((getPixelRGB pixels index) >> 8) & 255) }
method blue Pixel { return ((getPixelRGB pixels index) & 255) }

method setRed Pixel newRed {
  alpha = (getPixelAlpha pixels index)
  rgb = (getPixelRGB pixels index)
  red = (clamp (round newRed) 0 255)
  green = ((rgb >> 8) & 255)
  blue = (rgb & 255)
  setPixelRGBA pixels index red green blue alpha
  if (notNil targetMorph) { costumeChanged targetMorph }
}

method setGreen Pixel newGreen {
  alpha = (getPixelAlpha pixels index)
  rgb = (getPixelRGB pixels index)
  red = ((rgb >> 16) & 255)
  green = (clamp (round newGreen) 0 255)
  blue = (rgb & 255)
  setPixelRGBA pixels index red green blue alpha
  if (notNil targetMorph) { costumeChanged targetMorph }
}

method setBlue Pixel newBlue {
  alpha = (getPixelAlpha pixels index)
  rgb = (getPixelRGB pixels index)
  red = ((rgb >> 16) & 255)
  green = ((rgb >> 8) & 255)
  blue = (clamp (round newBlue) 0 255)
  setPixelRGBA pixels index red green blue alpha
  if (notNil targetMorph) { costumeChanged targetMorph }
}

method setColor Pixel color {
  alpha = (getPixelAlpha pixels index)
  setPixelRGBA pixels index (red color) (green color) (blue color) alpha
  if (notNil targetMorph) { costumeChanged targetMorph }
}

method getColor Pixel {
  alpha = (getPixelAlpha pixels index)
  rgb = (getPixelRGB pixels index)
  red = ((rgb >> 16) & 255)
  green = ((rgb >> 8) & 255)
  blue = (rgb & 255)
  return (color red green blue alpha)
}

method setGray Pixel grayLevel {
  alpha = (getPixelAlpha pixels index)
  rgb = (getPixelRGB pixels index)
  gray = (clamp (round grayLevel) 0 255)
  setPixelRGBA pixels index gray gray gray alpha
  if (notNil targetMorph) { costumeChanged targetMorph }
}

method getX Pixel {
  bm = (costumeData targetMorph)
  if (index < 1) { return 1 }
  i = (toInteger ((index - 1) % (width bm)))
  return (i + 1)
}

method getY Pixel {
  bm = (costumeData targetMorph)
  i = (toInteger ((index - 1) / (width bm)))
  if (i >= (height bm)) { return (height bm) }
  return (i + 1)
}
