to readIcon iconName color {
	// returns a bitmap costume
	scale = (global 'scale')
	print 'reading icon' iconName
	return (readSVG (readEmbeddedFile (join 'img/' iconName '.svg')) 0 0 scale color)
}

to readSVG data x y scale color {
	if (isNil scale) { scale = (global 'scale') }
	reader = (initialize (new 'SVGReader') x y scale color)
	readFrom reader data
	return (bitmap reader)
}

defineClass SVGReader pen index svgData originX originY scaleFactor bitmap overridenColor

method initialize SVGReader x y scale color {
	index = 1

	originX = x
	originY = y
	if (notNil scale) {
		scaleFactor = scale
	} else {
		scaleFactor = 1
	}
	if (notNil color) { overridenColor = color }

	return this
}

method bitmap SVGReader { return bitmap }

method readFrom SVGReader data {
	svgData = data
	nextTag = (nextTag this)
	while (notNil nextTag) {
		processTag this nextTag (nextAttributes this)
		nextTag = (nextTag this)
	}
}

method nextTag SVGReader {
	startIndex = (findSubstring '<' svgData index)
	endIndex = (findAnyOf svgData (list ' ' '>') startIndex)
	if (or (isNil startIndex) (isNil endIndex)) {
		index = (count svgData)
		return nil
	}
	tagName = (substring svgData (startIndex + 1) (endIndex - 1))
	index = endIndex
	return (toLowerCase tagName)
}

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

	bitmap = (newBitmap w h)
	pen = (newVectorPen bitmap)
	setOffset pen originX originY
	setClipRect pen originX originY w h
}

method processPath SVGReader attributes {
	for attr attributes {
		name = (first attr)
		value = (at attr 2)
		if (name == 'd') {
			drawPath this value
		} (name == 'fill') {
			fill pen (parseColor this value)
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
