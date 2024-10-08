// Color

defineClass Color r g b a

method red Color { return r }
method green Color { return g }
method blue Color { return b }
method alpha Color { return a }
method setAlpha Color newAlpha { if (isNil newAlpha) { a = 255 } else { a = newAlpha }}

to color r g b a {
  if (or (isNil r) (r < 0)) { r = 0 }
  if (or (isNil g) (g < 0)) { g = 0 }
  if (or (isNil b) (b < 0)) { b = 0 }
  if (or (isNil a) (a > 255)) { a = 255 }
  r = (toInteger r)
  g = (toInteger g)
  b = (toInteger b)
  a = (toInteger a)
  if (r > 255) { r = 255 }
  if (g > 255) { g = 255 }
  if (b > 255) { b = 255 }
  if (a < 0) { a = 0 }
  return (new 'Color' r g b a)
}

to colorHex s {
  a = 255
  if ((count s) < 6) {
    // one hex digit per channel
    r = ((hex (at s 1)) << 8)
    g = ((hex (at s 2)) << 8)
    b = ((hex (at s 3)) << 8)
    if (4 == (count s)) {
      a = ((hex (at s 4)) << 8)
    }
  } else {
    // two hex digits per channel
    r = (hex (substring s 1 2))
    g = (hex (substring s 3 4))
    b = (hex (substring s 5 6))
    if (8 == (count s)) {
      a = (hex (substring s 7 8))
    }
  }
  return (new 'Color' r g b a)
}

to colorSwatch r g b a { return (color r g b a) }
to colorFromSwatch c { return c }

to gray level alpha {
  return (color level level level alpha)
}

to randomColor {
  return (new 'Color' (rand 0 255) (rand 0 255) (rand 0 255) 255)
}

to colorFrom aValue {
  a = ((aValue >> 24) & 255)
  r = ((aValue >> 16) & 255)
  g = ((aValue >> 8) & 255)
  b = ((aValue >> 0) & 255)
  return (new 'Color' r g b a)
}

to transparent {
  return (color 255 255 255 0)
}

// converting

method toString Color {
  if (a == 255) {
	if (and (g == r) (b == r)) {
	  return (join '(gray ' r ')')
	} else {
	  return (join '(color ' r ' ' g ' ' b ')')
	}
  }
  return (join '(color ' r ' ' g ' ' b ' ' a ')')
}

method pixelValue Color {
  return (| ((toLargeInteger (a & 255)) << 24) ((r & 255) << 16) ((g & 255) << 8) (b & 255))
}

method pixelRGB Color {
  return (+ ((r & 255) << 16) ((g & 255) << 8) (b & 255))
}

method inverted Color {
  // Return the RGB inverse of this color with the same alpha.
  return (color (255 - r) (255 - g) (255 - b) a)
}

// copying

method copy Color { return (new 'Color' r g b a) }
method withAlpha Color alpha { return (new 'Color' r g b (clamp (toInteger alpha)) 0 255) }

// mixing

method mixed Color percent otherColor {
  // Return a copy of this color mixed with another color.
  p2 = (100 - percent)
  return (color
    (((r * percent) + ((red otherColor) * p2)) / 100)
    (((g * percent) + ((green otherColor) * p2)) / 100)
    (((b * percent) + ((blue otherColor) * p2)) / 100)
  )
}

method lighter Color percent {
  // Return an rgb-interpolated lighter copy of this color.
  if (isNil percent) { percent = 20 }
  return (mixedPercentWithGray this percent 255)
}

method darker Color percent {
  // Return an rgb-interpolated lighter copy of this color.
  if (isNil percent) { percent = 30 }
  return (mixedPercentWithGray this percent 0)
}

method mixedPercentWithGray Color percent gray {
  percent = (clamp (round percent) 0 100)
  invPercent = (100 - percent)
  scaledGray = (percent * gray)
  return (new 'Color'
    (round (((r * invPercent) + scaledGray) / 100))
    (round (((g * invPercent) + scaledGray) / 100))
    (round (((b * invPercent) + scaledGray) / 100))
    a)
}

to colorHSV h s v alpha {
  // Return a color with the given hue, saturation, and brightness.

  if (isNil alpha) { alpha = 255 }
  h = (h % 360)
  if (h < 0) { h += 360 }
  s = (toFloat (clamp s 0 1))
  v = (toFloat (clamp v 0 1))

  i = (truncate (h / 60.0))
  f = ((h / 60.0) - i)
  p = (v * (1 - s))
  q = (v * (1 - (s * f)))
  t = (v * (1 - (s * (1 - f))))

  if (i == 0) {
    r = v; g = t; b = p
  } (i == 1) {
    r = q; g = v; b = p
  } (i == 2) {
    r = p; g = v; b = t
  } (i == 3) {
    r = p; g = q; b = v
  } (i == 4) {
    r = t; g = p; b = v
  } (i == 5) {
    r = v; g = p; b = q
  }
  a = (clamp (toInteger alpha) 0 255)
  return (new 'Color' (truncate (255 * r)) (truncate (255 * g)) (truncate (255 * b)) a)
}

method hue Color {
  if (a == 0) { return 0 }
  return (at (hsv this) 1)
}

method saturation Color {
  if (a == 0) { return 0 }
  return (at (hsv this) 2)
}

method brightness Color {
  if (a == 0) { return 0 }
  return (at (hsv this) 3)
}

method hsv Color {
  // Return an array containing the hue, saturation, and brightness for this color.

  min = (min r g b)
  max = (max r g b)
  if (max == min) { return (array 0 0 (max / 255.0)) } // gray; hue arbitrarily reported as zero
  if (r == min) {
    f = (g - b)
	i = 3
  } (g == min) {
    f = (b - r)
	i = 5
  } (b == min) {
    f = (r - g)
	i = 1
  }
  hue = ((60.0 * (i - ((toFloat f) / (max - min)))) % 360)
  sat = 0
  if (max > 0) { sat = ((toFloat (max - min)) / max) }
  bri = (max / 255.0)
  return (array hue sat bri)
}

method shiftHue Color n {
  hsv = (hsv this)
  newHue = ((at hsv 1) + n)
  return (colorHSV newHue (at hsv 2) (at hsv 3))
}

method shiftSaturation Color n {
  hsv = (hsv this)
  newSaturation = ((at hsv 2) + (n / 100.0))
  return (colorHSV (at hsv 1) newSaturation (at hsv 3))
}

method shiftBrightness Color n {
  hsv = (hsv this)
  newBrightness = ((at hsv 3) + (n / 100.0))
  return (colorHSV (at hsv 1) (at hsv 2) newBrightness)
}

// named colors

to microBlocksColor colorName optionalWeight {
  // Return a color from the MicroBlocks UI color palette.
  // The blueGray family takes an optional weight paraemeter (larger numbers are darker).

  palette = (global 'microBlocksPalette')
  if (isNil palette) { palette = (initMicroBlocksUIColors (color)) }
  fullName = colorName
  if (notNil optionalWeight) { fullName = (join '' colorName '-' optionalWeight) }
  return (at palette fullName (gray 100))
}

method initMicroBlocksUIColors Color {
  // Create the MicroBlocks UI color palette.

  palette = (dictionary)
  atPut palette 'red' (colorHex 'E03B3B')
  atPut palette 'green' (colorHex '61D14E')
  atPut palette 'yellow' (colorHex 'FED722')
  atPut palette 'yellowBorder' (colorHex 'B79701')
  atPut palette 'white' (gray 255)
  atPut palette 'black' (colorHex '2A2A2A')

  // gray900 in the style sheet, but it's the only gray we're using
  atPut palette 'gray' (colorHex '383838')

  // blueGrays
  atPut palette 'blueGray-50' (colorHex 'ECEDF1')
  atPut palette 'blueGray-75' (colorHex 'E1E3E8')
  atPut palette 'blueGray-100' (colorHex 'CFD1DC')
  atPut palette 'blueGray-200' (colorHex 'B0B3C5')
  atPut palette 'blueGray-300' (colorHex '9095AE')
  atPut palette 'blueGray-400' (colorHex '787E9C')
  atPut palette 'blueGray-500' (colorHex '60678B')
  atPut palette 'blueGray-600' (colorHex '545A7A')
  atPut palette 'blueGray-700' (colorHex '454A64')
  atPut palette 'blueGray-800' (colorHex '373B4F')
  atPut palette 'blueGray-850' (colorHex '2D3143')
  atPut palette 'blueGray-900' (colorHex '262938')

  setGlobal 'microBlocksPalette' palette
  return palette
}

// equality

method == Color other {
  return (and
	(isClass other 'Color')
    (r == (red other))
    (g == (green other))
    (b == (blue other))
    (a == (alpha other))
  )
}

method thumbnail Color w h {
  // Return a bitmap of the given dimensions and this color (for compatability with Bitmap).
  return (newBitmap w h this)
}
