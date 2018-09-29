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
  if (isNil percent) { percent = 30 }
  return (mixed this (100 - percent) (color 255 255 255))
}

method darker Color percent {
  // Return an rgb-interpolated lighter copy of this color.
  if (isNil percent) { percent = 30 }
  return (mixed this (100 - percent) (color))
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
