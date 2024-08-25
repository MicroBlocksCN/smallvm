to readSVGIcon iconName fgColor bgColor iconScale strokeOverideFlag {
	// Returns a bitmap for the given icon at the given scale.
	// All parameters except iconName are optional.

	fileName = (join 'img/' iconName '.svg')
	data = (readEmbeddedFile fileName)
	if (isNil data) { print 'File not found:' fileName }
	return (renderSVG data fgColor bgColor iconScale strokeOverideFlag)
}

to renderSVG data fgColor bgColor iconScale strokeOverideFlag {
	// Convert the given SVG data into a bitmap at the scale.
	// If fgColor is not nil, stroke and fill colors will be mapped to that color.
	// bgColor is optional but can be provided to avoid antialiasing fringes.

	svgReader = (initialize (new 'SVGReader') fgColor bgColor iconScale strokeOverideFlag)
	return (readFrom svgReader data)
}

to testSVG fileName optionalScale optionalFGColor {
	// Used for testing rendering from GP command line.

	bgColor = (gray 240)
	fileName = (join '../img/' fileName '.svg')
	data = (readFile fileName)
	if (isNil data) { print 'File not found:' fileName }

	bm = (renderSVG data optionalFGColor bgColor optionalScale false)
	ctx = (newGraphicContextOnScreen)
	clear ctx bgColor
	drawBitmap ctx bm 0 0
	show ctx
	return bm
}

to newSVGImage iconName fgColor bgColor iconScale strokeOverideFlag {
	return (initialize (new 'SVGImage') iconName fgColor bgColor iconScale strokeOverideFlag)
}

defineClass SVGImage morph

method initialize SVGImage iconName fgColor bgColor iconScale strokeOverideFlag {
	bitmap = (readSVGIcon iconName fgColor bgColor iconScale strokeOverideFlag)
	morph = (newMorph)
	setCostume morph bitmap
	return this
}

method morph SVGImage { return morph }

defineClass SVGReader scaleFactor overridenColor overrideStrokes backgroundColor svgData startX startY lastX lastY lastCX lastCY pen bitmap

method initialize SVGReader fgColor bgColor iconScale strokeOverideFlag {
	if (notNil iconScale) {
		scaleFactor = iconScale
	} else {
		scaleFactor = (global 'scale')
	}
	overridenColor = fgColor // if nil, uses original color
	backgroundColor = bgColor // provide this to avoid anti-aliasing fringes
	if (and (isNil bgColor) (notNil fgColor)) {
		backgroundColor = fgColor
	}

	if (isNil strokeOverideFlag) { strokeOverideFlag = true }
	overrideStrokes = strokeOverideFlag
	return this
}

method readFrom SVGReader data {
	if (isNil data) { return (newBitmap (10 * scaleFactor) (10 * scaleFactor) (gray 100)) } // no data
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
	fillColor = (gray 100 0)
	if (notNil backgroundColor) { fillColor = (withAlpha backgroundColor 0) }
	bitmap = (newBitmap w h fillColor)
	pen = (newVectorPen bitmap)
	setClipRect pen 0 0 w h
}

method readNumberWithUnits SVGReader attrName srcString {
	// Note: Handles positive and negative decimal numbers without exponents.

	pattern = (join ' ' attrName '="')
	i = (findSubstring pattern srcString startIndex)
	if (isNil i) { return nil } // not found
	i += (count pattern)
	end = i
	if ('-' == (at srcString end)) { end += 1 } // leading '-'
	while (or (isDigit (at srcString end)) ('.' == (at srcString end))) { end += 1 }
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

method drawPath SVGReader pathString {
	lastX = 0
	lastY = 0
	lastCX = 0
	lastCY = 0
	i = 1
	isFirst = true
	while (i <= (count pathString)) {
		isAbsolute = (isUpperCase (at pathString i))
		cmd = (toUpperCase (at pathString i))
		paramsAndNextIndex = (getPathParams this pathString (i + 1))
		params = (at paramsAndNextIndex 1)
		argsNeeded = (argsNeededForCmd this cmd)
		while ((count params) >= argsNeeded) {
			if ('M' == cmd) { // move
				moveCmd this params isAbsolute isFirst
			} ('L' == cmd) { // line
				lineCmd this params isAbsolute
			} ('V' == cmd) { // vertical line
				vLineCmd this params isAbsolute
			} ('H' == cmd) { // horizontal line
				hLineCmd this params isAbsolute
			} ('C' == cmd) { // cubic Bézier
				cubicCmd this params isAbsolute
			} ('S' == cmd) { // smooth curve
				smoothCurveCmd this params isAbsolute
			} ('A' == cmd) { // arc command - not supported
				print 'SVG arc (A) path command is not supported; convert to Bezier curve' params
			} ('Z' == cmd) { // close path
				closePath pen
				argsNeeded = 10000 // force loop exit (since Z has zero paramters)
			} else {
				print 'missing path command' cmd 'in SVG parser'
			}
			params = (copyFromTo params (argsNeeded + 1))
			isFirst = false
		}
		i = (at paramsAndNextIndex 2)
	}
}

method argsNeededForCmd SVGReader cmd {
	pathCmd = (toUpperCase cmd)
	if ('A' == cmd) { return 7
	} ('C' == cmd) { return 6
	} ('H' == cmd) { return 1
	} ('L' == cmd) { return 2
	} ('M' == cmd) { return 2
	} ('Q' == cmd) { return 4
	} ('S' == cmd) { return 4
	} ('T' == cmd) { return 2
	} ('V' == cmd) { return 1
	} ('Z' == cmd) { return 0
	}
	return 0
}

method moveCmd SVGReader params isAbsolute isFirst {
	if isAbsolute { // absolute position; clear lastX & lastY
		lastX = 0
		lastY = 0
	}
	lastX += (at params 1)
	lastY += (at params 2)
	if isFirst {
		beginPath pen lastX lastY
		startX = lastX
		startY = lastY
	} else {
		lineTo pen lastX lastY
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
	lastX += (at params 1)
	lineTo pen lastX lastY
}

method vLineCmd SVGReader params isAbsolute {
	if isAbsolute { // absolute position; clear lastY
		lastY = 0
	}
	lastY += (at params 1)
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
	c1X = (lastX + (lastX - lastCX))
	c1Y = (lastY + (lastY - lastCY))
	if isAbsolute {
		lastCX = (at params 1)
		lastCY = (at params 2)
		lastX = (at params 3)
		lastY = (at params 4)
	} else {
		lastCX = (lastX + (at params 1))
		lastCY = (lastY + (at params 2))
		lastX = (lastX + (at params 3))
		lastY = (lastY + (at params 4))
	}
	cubicCurveTo pen c1X c1Y lastCX lastCY lastX lastY
}

method getPathParams SVGReader pathString startIndex {
	len = (count pathString)
	i = startIndex
	while (and (i <= len) (not (isPathCommand this (at pathString i)))) {
		i = (i + 1)
	}
	paramString = (substring pathString startIndex (i - 1))
	return (list (splitParameterString this paramString) i)
}

method isPathCommand SVGReader ch {
	// "E" is not a path command. Don't be confused by exponential notation such as 1.0e-6.

	return (and (isLetter ch) ('E' != ch) ('e' != ch))
}

method splitParameterString SVGReader paramString {
	// Split the path parameter string into a list of numbers.
	// The separator rules are tricky!

	result = (list)
	digitSeen = false
	start = 1
	for i (count paramString) {
		ch = (at paramString i)
		if (and (isOneOf ch ',' ' ') digitSeen) {
			// some SVGs separate x-y pairs with a comma and other parameters with spaces
			add result (scaledNumber this (substring paramString start (i - 1)))
			digitSeen = false
			start = (i + 1)
		} (and ('-' == ch) digitSeen) {
			// optimized .SVG's may omit separator before negative parameters! (i.e. 1-2 means 1, -2)
			if (not (isOneOf (at paramString (i - 1)) 'E' 'e')) {
				add result (scaledNumber this (substring paramString start (i - 1)))
				digitSeen = false
				start = i
			}
		} (isDigit ch) {
			digitSeen = true
		}
	}
	if (start <= (count paramString)) {
		add result (scaledNumber this (substring paramString start))
	}
	return result
}

method scaledNumber SVGReader numberString {
	return (scaleFactor * (toNumber numberString))
}

method readColor SVGReader attrName srcString {
	colorString = (readStringAttribute this attrName srcString)
	if (or (isNil colorString) ('none' == colorString)) { return nil }
	if (notNil overridenColor) {
		if ('fill' == attrName) { return overridenColor }
		if (and overrideStrokes ('stroke' == attrName)) { return overridenColor }

	}
	return (parseColor this colorString)
}

method parseColor SVGReader colorString {
	if (colorString == 'black') {
		return (gray 0)
	} (colorString == 'white') {
		return (gray 255)
	} (beginsWith colorString '#') {
		return (colorHex (substring colorString 2))
	} else {
		print 'missing color' colorString 'in SVG parser'
	}
	return (gray 100) // missing color
}
