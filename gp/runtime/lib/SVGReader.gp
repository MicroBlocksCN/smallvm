to testSVG fileName optionalScale useOriginalColor {
	scale = 2
	if (notNil optionalScale) { scale = optionalScale }
	fgColor = (gray 100)
	bgColor = (gray 220)
	if (true == useOriginalColor) { fgColor = nil }
	filePath = (join '../img/' fileName '.svg')

	ctx = (newGraphicContextOnScreen)
	clear ctx bgColor

	fgColor = nil // show original colors
	reader = (initialize (new 'SVGReader') scale fgColor bgColor)
	bm = (readFrom reader (readFile filePath))
	drawBitmap ctx bm 0 0
	show ctx
	return bm
}

to readIcon iconName fgColor bgColor {
	// returns a bitmap costume
	scale = (global 'scale')
	print 'reading icon' iconName
	return (readSVG (readEmbeddedFile (join 'img/' iconName '.svg')) scale fgColor bgColor)
}

to readSVG data scale fgColor bgColor {
	if (isNil scale) { scale = (global 'scale') }
	reader = (initialize (new 'SVGReader') scale fgColor bgColor)
	return (readFrom reader data)
}

defineClass SVGReader scaleFactor overridenColor backgroundColor svgData lastX lastY lastCX lastCY pen bitmap

method initialize SVGReader scale fgColor bgColor {
	if (notNil scale) {
		scaleFactor = scale
	} else {
		scaleFactor = 1
	}
	overridenColor = fgColor // if nil, uses original color
	backgroundColor = bgColor // if nil, does not handle holes
	return this
}

method readFrom SVGReader data {
	svgData = data
	createBitmap this
	i = (findSubstring '<path' svgData startIndex)
	while (notNil i) {
		pathTag = (extractPathTag this i)
		drawPath this (readStringAttribute this 'd' pathTag)

		fillColor = (readColor this 'fill' pathTag)
		if (notNil fillColor) {
			fill pen fillColor
		}

		strokeColor = (readColor this 'stroke' pathTag)
		if (notNil strokeColor) {
			strokeWidth = (readNumberWithUnits this 'stroke-width' pathTag)
			if (isNil strokeWidth) { strokeWidth = 1 }
			stroke pen strokeColor (scaleFactor * strokeWidth)
		}
		i = (findSubstring '<path' svgData (i + (count pathTag)))
	}
	return bitmap
}

method createBitmap SVGReader {
	w = (ceiling (readNumberWithUnits this 'width' svgData))
	h = (ceiling (readNumberWithUnits this 'height' svgData))
	if (or (isNil w) (isNil h)) {
		s = (readStringAttribute this 'viewBox' svgData)
		if (isNil s) {
			print 'SVGReader: No width, height, or viewBox attributes found'
			// use default dimensions
			w = 33
			h = 32
		} else {
			viewBox = (words s)
			w = (toInteger (at viewBox 3))
			h = (toInteger (at viewBox 4))
		}
	}
	w = (w * scaleFactor)
	h = (h * scaleFactor)
	bitmap = (newBitmap w h fillColor)
	pen = (newVectorPen bitmap)
	setClipRect pen 0 0 w h
}

method readNumberWithUnits SVGReader attrName srcString {
	pattern = (join ' ' attrName '="')
	i = (findSubstring pattern srcString startIndex)
	if (isNil i) { return nil } // not found
	i += (count pattern)
	end = i
	if (or ('.' == (at srcString end)) ('.' == (at srcString end))) { end += 1 } // leading '-' or '.'
	while (isDigit (at srcString end)) { end += 1 }
	n = (toNumber (substring srcString i (end - 1)))
	if (isLetter (at srcString end)) {
		units = (substring srcString end (end + 1))
		if ('pt' == units) { n = (n * 1.25)
		} ('pc' == units) { n = (n * 15)
		} ('mm' == units) { n = (n * 3.543307)
		} ('cm' == units) { n = (n * 35.43307)
		} ('in' == units) { n = (n * 90)
		}
	}
	return n
}

method readStringAttribute SVGReader attrName srcString {
	pattern = (join ' ' attrName '="')
	i = (findSubstring pattern srcString startIndex)
	if (isNil i) { return nil } // not found
	i += (count pattern)
	end = i
	while ('"' != (at srcString end)) { end += 1 }
	return (trim (substring srcString i (end - 1)))
}

method extractPathTag SVGReader startIndex {
	// Return the "<path .../>" tag tag starting at the given index.

	start = (startIndex + 5)
	end = (findSubstring '/>' svgData start)
	if (isNil end) { return '' } // no terminator; truncated file?
	return (substring svgData start (end - 1))
}

method drawPathOLD SVGReader pathString {
	i = 1
	while (i < (count pathString)) {
		currentChar = (toUpperCase (at pathString i))
		paramList = (getPathParams this pathString (i + 1))
		params = (at paramList 1)
		if (currentChar == 'M') { // move to point
			beginPath pen (at params 1) (at params 2)
		} (currentChar == 'L') { // draw line
			lineTo pen (at params 1) (at params 2)
		} (currentChar == 'V') { // draw vertical line
			vLine pen (at params 1)
		} (currentChar == 'H') { // draw horizontal line
			hLine pen (at params 1)
		} (currentChar == 'C') { // cubic Bézier
			(cubicCurveTo
				pen
				(at params 1)
				(at params 2)
				(at params 3)
				(at params 4)
				(at params 5)
				(at params 6)
			)
		} (currentChar == 'S') { // smooth curve
			(curveTo
				pen
				(at params 1)
				(at params 2)
				(at params 3)
				(at params 4)
			)
		} (currentChar == 'Z') { // close path
		} else {
			print 'missing path command' currentChar 'in SVG parser'
		}
		i = (at paramList 2)
	}
}

method drawPath SVGReader pathString {
	lastX = 0
	lastY = 0
	lastCX = 0
	lastCY = 0
	i = 1
	while (i < (count pathString)) {
		isAbsolute = (isUpperCase (at pathString i))
		paramsAndNextIndex = (getPathParams this pathString (i + 1))
		params = (at paramsAndNextIndex 1)
// xxx print '  ' (at pathString i) (count params) params
		cmd = (toUpperCase (at pathString i))
		if ('M' == cmd) { // move
			moveCmd this params isAbsolute
		} ('L' == cmd) { // line
			lineCmd this params isAbsolute
		} ('V' == cmd) { // vertical line
			vLineCmd this params isAbsolute
		} ('H' == cmd) { // horizontal line
			hLineCmd this params isAbsolute
		} ('C' == cmd) { // dcubic Bézier
			cubicCmd this params isAbsolute
		} (currentChar == 'S') { // smooth curve
			smoothCurveCmd this params isAbsolute
		} (currentChar == 'Z') { // close path
		} else {
			print 'missing path command' currentChar 'in SVG parser'
		}
		i = (at paramsAndNextIndex 2)
	}
}

method moveCmd SVGReader params isAbsolute {
	paramCount = (count params)
 	i = 1
oldX = lastX
oldY = lastY
	while (i < paramCount) {
		if isAbsolute { // absolute position; clear lastX & lastY
			lastX = 0
			lastY = 0
		}
		lastX += (at params i)
		lastY += (at params (i + 1))
		if (i == 1) {
print 'move' oldX oldY lastX lastY
			beginPath pen lastX lastY
		} else {
print 'move(lineto)' oldX oldY lastX lastY
			lineTo pen lastX lastY
		}
		i += 2
	}
}

method lineCmd SVGReader params isAbsolute {
	if isAbsolute { // absolute position; clear lastX & lastY
		lastX = 0
		lastY = 0
	}
	lastX += (at params 1)
	lastY += (at params 2)
	lineTo pen lastX lastY
}

method hLineCmd SVGReader params isAbsolute {
	if isAbsolute { // absolute position; clear lastX
		lastX = 0
	}
oldX = lastX
	lastX += (at params 1)
print 'hLine' oldX lastY lastX lastY
	lineTo pen lastX lastY
}

method vLineCmd SVGReader params isAbsolute {
	if isAbsolute { // absolute position; clear lastY
		lastY = 0
	}
oldY = lastY
	lastY += (at params 1)
print 'vLine' lastX oldY lastX lastY
	lineTo pen lastX lastY
}

method cubicCmd SVGReader params isAbsolute {
	if isAbsolute {
		c1X = (at params 1)
		c1Y = (at params 2)
		lastCX = (at params 3)
		lastCY = (at params 4)
		lastX = (at params 5)
		lastY = (at params 6)
	} else {
		c1X = (lastX + (at params 1))
		c1Y = (lastY + (at params 2))
		lastCX = (lastX + (at params 3))
		lastCY = (lastY + (at params 4))
		lastX = (lastX + (at params 5))
		lastY = (lastY + (at params 6))
	}
	cubicCurveTo pen c1X c1Y lastCX lastCY lastX lastY
}

method smoothCurveCmd SVGReader params isAbsolute {
	if isAbsolute { // absolute position; clear lastX & lastY
		lastX = 0
		lastY = 0
	}
	lastX += (at params 1)
	lastY += (at params 2)
	curveTo pen lastX lastY
}

method getPathParams SVGReader pathString startIndex {
	length = (count pathString)
	i = startIndex
	if (i >= length) { return (list (list) length) }
	params = (list)
	paramString = ''
	while (and (i <= length) (not (isPathCommand this (at pathString i)))) {
		paramString = (join paramString (at pathString i))
		i = (i + 1)
	}

	// some SVGs separate param groups by commas ¯\_(ツ)_/¯
	paramString = (copyReplacing paramString ',' ' ')

	// optimized .SVG's don't use space before negative parameters
	paramString = (copyReplacing paramString '-' ' -')

	for item (splitWith (trim paramString) ' ') {
		add params ((toNumber item) * scaleFactor)
	}
	return (list params i)
}

method isPathCommand SVGReader ch {
	return (and (isLetter ch) ('E' != ch) ('e' != ch))
}

method readColor SVGReader attrName srcString {
	colorString = (readStringAttribute this attrName srcString)
	if (or (isNil colorString) ('none' == colorString)) { return nil }
	return (parseColor this colorString)
}

method parseColor SVGReader colorString {
	if ('none' == colorString) {
		if (notNil backgroundColor) { return backgroundColor }
		return (color 255 0 255) // magenta, so missing background color will be noticeable
	}
	if (notNil overridenColor) { return overridenColor }

	if (colorString == 'black') {
		return (gray 0)
	} (colorString == 'white') {
		return (gray 255)
	} (beginsWith colorString '#') {
		return (colorHex (substring colorString 2))
	} else {
		print 'missing color' colorString 'in SVG parser'
	}
}
