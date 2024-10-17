defineClass Slider morph orientation action floor ceiling value size thickness backgroundColor sliderColor padding

to slider orientation span action thickness floor ceiling value size padding {
	if (isNil span) { span = 100 }
	if (isNil action) { action = 'nop' }
	if (isNil thickness) { thickness = (10 * (global 'scale')) }
	if (isNil floor) { floor = 0 }
	if (isNil ceiling) { ceiling = 100 }
	if (isNil value) { value = 50 }
	if (isNil size) { size = 10 }
	if (isNil padding) { padding = 0 }
	result = (new 'Slider' nil orientation action floor ceiling value size thickness nil nil padding)
	return (initialize result span)
}

method initialize Slider span {
	if (orientation == 'horizontal') {
		w = span
		h = (thickness + (2 * padding))
	} else {
		w = (thickness + (2 * padding))
		h = span
	}
	morph = (newMorph this)
	setExtent morph w h
	backgroundColor = (gray 255 90) // default background color
	sliderColor = (gray 110 180) // default handle color
	return this
}

method setColors Slider bgColor fgColor {
	if (notNil bgColor) { backgroundColor = bgColor }
	if (notNil fgColor) { sliderColor = fgColor }
	changed morph
}

method ceiling Slider { return ceiling }
method floor Slider { return floor }
method value Slider { return value }
// method unit Slider {
// 	span = (height morph)
// 	if (orientation == 'horizontal') { span = (width morph) }
// 	span = (toFloat span)
// 	valueRange = (max 1 (ceiling - floor))
// 	stretch = (max thickness (toInteger ((span / valueRange) * size)))
// 	return ((span - stretch) / valueRange)
// }

method setAction Slider anAction {action = anAction}
method setSize Slider num {update this nil nil nil num}
method setValue Slider num {update this nil nil num}

method update Slider floorNum ceilNum valNum sizeNum {
	if (isNil floorNum) {floorNum = floor}
	if (isNil ceilNum) {ceilNum = ceiling}
	if (isNil valNum) {valNum = value}
	if (isNil sizeNum) {sizeNum = size}
	floor = floorNum
	ceiling = ceilNum
	value = valNum
	size = sizeNum
	call action value
	changed morph
}

method drawOn Slider ctx {
	scale = (global 'scale')

	fillRect ctx backgroundColor (left morph) (top morph) (width morph) (height morph)
	if ((ceiling - floor) == 0) {
		frac = 0
	} else {
		frac = ((value - floor) / (ceiling - floor))
	}
	if (orientation == 'horizontal') {
		sliderSize = (* ((width (bounds morph)) / ceiling) scale 150)
		sliderRange = ((width morph) - sliderSize)
		offset = (toInteger (frac * sliderRange))
		sliderRect = (rect ((left morph) + offset) ((top morph) + padding) sliderSize thickness)
	} (orientation == 'vertical') {
		sliderSize = (* ((height (bounds morph)) / (max ceiling 1)) scale 150)
		sliderRange = ((height morph) - sliderSize)
		offset = (toInteger (frac * sliderRange))
		sliderRect = (rect ((left morph) + padding) ((top morph) + offset) thickness sliderSize)
	}

	sliderCorner = (4 * scale)
	fillRoundedRect (getShapeMaker ctx) sliderRect sliderCorner sliderColor 0
}

// events

method clicked Slider {
	return true
	setCursor 'move'
}

method rightClicked Slider { return true }

method handDownOn Slider aHand {
	setCursor 'move'
	focusOn aHand this
	handMoveFocus this aHand
	return true
}

method handEnter Slider aHand {
	setCursor 'move'
}

method handLeave Slider aHand {
	setCursor 'default'
}

method handMoveFocus Slider aHand {
	setCursor 'move'
	if (orientation == 'horizontal') {
		frac = (((x aHand) - (left morph)) / (width morph))
	} (orientation == 'vertical') {
		frac = (((y aHand) - (top morph)) / (height morph))
	}
	frac = (clamp frac 0 1)
	value = (floor + (frac * (ceiling - floor)))
	value = (clamp value floor ceiling)
	call action value
}
