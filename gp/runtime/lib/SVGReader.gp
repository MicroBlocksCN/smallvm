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

defineClass SVGReader scaleFactor overridenColor backgroundColor svgData pen bitmap

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
		fillColor = (readStringAttribute this 'fill' pathTag)
		drawPath this (readStringAttribute this 'd' pathTag)
		if (notNil fillColor) {
			fill pen (parseColor this fillColor)
		}
		i = (findSubstring '<path' svgData (i + (count pathTag)))
	}
	return bitmap
}

method createBitmap SVGReader {
	w = (readNumberAttribute this 'width' svgData)
	h = (readNumberAttribute this 'height' svgData)
	if (or (isNil w) (isNil h)) {
		s = (readStringAttribute this 'viewBox' svgData)
		if (isNil s) {
			print 'SVGReader: No width, height, or viewBox attributes found'
			// use default dimensions
			w = 100
			h = 100
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

method readNumberAttribute SVGReader attrName aString {
	pattern = (join ' ' attrName '="')
	i = (findSubstring pattern aString startIndex)
	if (isNil i) { return nil } // not found
	i += (count pattern)
	end = i
	while (isDigit (at aString end)) { end += 1 }
	return (toInteger (substring aString i (end - 1)))
}

method readStringAttribute SVGReader attrName aString {
	pattern = (join ' ' attrName '="')
	i = (findSubstring pattern aString startIndex)
	if (isNil i) { return nil } // not found
	i += (count pattern)
	end = i
	while ('"' != (at aString end)) { end += 1 }
	return (trim (substring aString i (end - 1)))
}

method extractPathTag SVGReader startIndex {
	// Return the "<path .../>" tag tag starting at the given index.

	start = (startIndex + 5)
	end = (findSubstring '/>' svgData start)
	if (isNil end) { return '' } // no terminator; truncated file?
	return (substring svgData start (end - 1))
}

method drawPath SVGReader pathString {
	i = 1
	while (i < (count pathString)) {
		currentChar = (toUpperCase (at pathString i))
		paramList = (getPathParams this pathString (i + 1))
		params = (at paramList 1)
		if (currentChar == 'M') { // move to absolute point
			beginPath pen (at params 1) (at params 2)
		} (currentChar == 'L') { // draw line to absolute point
			lineTo pen (at params 1) (at params 2)
		} (currentChar == 'V') { // draw vertical line to absolute y
			vLine pen (at params 1)
		} (currentChar == 'H') { // draw horizontal line to absolute x
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

	for item (splitWith (trim paramString) ' ') {
		add params ((toNumber item) * scaleFactor)
	}
	return (list params i)
}

method isPathCommand SVGReader ch {
	return (and (isLetter ch) ('E' != ch) ('e' != ch))
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
