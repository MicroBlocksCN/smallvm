to testSVG fileName optionalScale useOriginalColor {
	scale = 2
	if (notNil optionalScale) { scale = optionalScale }
	fgColor = (gray 100)
	bgColor = (gray 220)
	if (true == useOriginalColor) { fgColor = nil }
	filePath = (join '../img/' fileName '.svg')

	ctx = (newGraphicContextOnScreen)
	clear ctx bgColor

	reader = (initialize (new 'SVGReader') scale fgColor bgColor)
	readFrom reader (readFile filePath)
	bm = (bitmap reader)
	drawBitmap ctx (bitmap reader) 0 0
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
	readFrom reader data
	return (bitmap reader)
}

defineClass SVGReader scaleFactor overridenColor backgroundColor svgData index pen bitmap

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

method bitmap SVGReader { return bitmap }

method readFrom SVGReader data {
	svgData = data
	index = 1
	nextTag = (nextTag this)
	while (notNil nextTag) {
		processTag this nextTag (nextAttributes this)
		nextTag = (nextTag this)
	}
}

method nextTag SVGReader {
	startIndex = (findSubstring '<' svgData index)
	if (notNil startIndex) {
		endIndex = (tagNameEnd this startIndex)
	}
	if (or (isNil startIndex) (isNil endIndex)) {
		index = (count svgData)
		return nil
	}
	tagName = (substring svgData (startIndex + 1) (endIndex - 1))
	index = endIndex
	return (toLowerCase tagName)
}

method tagNameEnd SVGReader startIndex {
	end = (count svgData)
	i = (startIndex + 1)
	while (i < end) {
		ch = (at svgData i)
		if (or ('>' == ch) (isWhiteSpace ch)) { return i }
		i += 1
	}
}

// method findTagEnd SVGReader startIndex {
// 	// Find the closing ">" after startIndex.
// 	// Don't worry delimiters inside strings for now.
//
// 	nestingCount = 1
// 	i = (startIndex + 1)
// 	end = (count svgData)
// 	while (i < end) {
// 		ch = (at svgData i)
// 		if ('>' == ch) {
// 			nestingCount += -1
// 			if (nestingCount <= 0) { return i }
// 		}
// 		if ('<' == ch) {
// 			if (and (i < end) ((at svgData (i + 1)) != '/')) {
// 				nestingCount += 1
// 			}
// 		}
// 		i += 1
// 	}
// 	return nil // hit end without finding the closing ">"
// }

method nextAttributes SVGReader {
	tagEndIndex = (findSubstring '>' svgData index)
	lastAttributeEndIndex = tagEndIndex
	while ((at svgData lastAttributeEndIndex) != '"') { // "
		lastAttributeEndIndex = (lastAttributeEndIndex - 1)
	}
	attributes = (list)
	while (index < lastAttributeEndIndex) {
		nextAttr = (nextAttribute this)
		if (notNil nextAttr) { add attributes nextAttr }
	}
	return attributes
}

method nextAttribute SVGReader {
	tagEndIndex = (findSubstring '>' svgData index)
	equalsIndex = (findSubstring '=' svgData index)

	if (or (equalsIndex > tagEndIndex) (isNil equalsIndex)) { return }

	attrEndIndex = (findSubstring '"' svgData (equalsIndex + 2)) //"

	attrName = ''
	// + 2 and - 1 to get rid of the quotes in attrs
	attrValue = (substring svgData (equalsIndex + 2) (attrEndIndex - 1))

	i = (equalsIndex - 1)
	if (i < tagEndIndex) {
		while (i > index) {
			i = (i - 1)
			if ((at svgData i) == ' ') {
				attrName = (substring svgData (i + 1) (equalsIndex - 1))
				i = index
			}
		}
	}
	index = attrEndIndex
	return (list attrName attrValue)
}

method processTag SVGReader tagName attributes {
	if (tagName == 'svg') {
		processSVGTag this attributes
	} (tagName == 'path') {
		processPath this attributes
	}
}

method processSVGTag SVGReader attributes {
	w = 0
	h = 0
	for attr attributes {
		name = (first attr)
		value = (at attr 2)
		if (name == 'width') {
			w = ((toNumber value) * scaleFactor)
		} (name == 'height') {
			h = ((toNumber value) * scaleFactor)
		} (name == 'viewBox') {
			//TODO parse viewBox here. Or not!
		}
	}

	fillColor = backgroundColor
	if (isNil backgroundColor) { fillColor = (gray 0 0) }
	bitmap = (newBitmap w h fillColor)
	pen = (newVectorPen bitmap)
	setClipRect pen 0 0 w h
}

method processPath SVGReader attributes {
	for attr attributes {
		name = (first attr)
		value = (at attr 2)
		if (name == 'd') {
			drawPath this value
		} (name == 'fill') {
			fill pen (parseColor this value)
		} (name == 'stroke') {
			stroke pen (color 255 0 0) // (parseColor this value)
		} else {
			print 'missing attribute' name 'in SVG parser'
		}
	}
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
	while (and (i <= length) (not (isLetter (at pathString i)))) {
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

method parseColor SVGReader colorString {
	if ('none' == colorString) {
		if (notNil backgroundColor) { return backgroundColor }
		return (color 0 255 255) // magenta, so clear areas will be noticeable
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
