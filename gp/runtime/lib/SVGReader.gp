to readSVG data x y {
	reader = (initialize (new 'SVGReader') x y)
	readFrom reader data
	return (bitmap reader)
}

defineClass SVGReader pen index svgData originX originY

method initialize SVGReader x y {
	index = 1

	//bm = (newBitmap 100 100) // just in case SVG tag doesn't have any dimensions
	pen = (newVectorPenOnScreen)

	setOffset pen x y
	originX = x
	originY = y

	return this
}

method bitmap SVGReader { return bm }

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
			w = (toNumber value)
		} (name == 'height') {
			h = (toNumber value)
		} (name == 'viewBox') {
			//TODO parse viewBox here
		}
	}

	setClipRect pen originX originY w h
	//bm = (newBitmap (w + 5) (h + 5)) // add a bit for line width
	//pen = (newVectorPen bm)
}

method processPath SVGReader attributes {
	for attr attributes {
		name = (first attr)
		value = (at attr 2)
		if (name == 'd') {
			drawPath this value
		} (name == 'fill') {
			fill pen (parseColor this value)
		}
	}
}

method drawPath SVGReader pathString {
	i = 1
	while (i < (count pathString)) {
		currentChar = (at pathString i)
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
		} (currentChar == 'Z') { // close path
		}
		i = (at paramList 2)
	}
}

method getPathParams SVGReader pathString startIndex {
	i = startIndex
	if (i >= (count pathString)) { return (list (list) (count pathString)) }
	params = (list)
	paramString = ''
	while (not (isLetter (at pathString i))) {
		paramString = (join paramString (at pathString i))
		i = (i + 1)
	}
	for item (splitWith (trim paramString) ' ') { add params (toNumber item) }
	return (list params i)
}

method parseColor SVGReader colorString {
	if (colorString == 'black') { return (gray 0) }
}
