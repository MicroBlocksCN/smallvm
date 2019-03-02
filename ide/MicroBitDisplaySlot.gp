defineClass MicroBitDisplaySlot morph display paintMode inset stride ledWidth ledHeight

to newMicroBitDisplaySlot anInteger {
	return (initialize (new 'MicroBitDisplaySlot') contents)
}

method initialize MicroBitDisplaySlot anInteger {
	morph = (newMorph this)
	setHandler morph this
	setGrabRule morph 'defer'
	setTransparentTouch morph true
	display = (newArray 25 false)
	inset = 5
	stride = 15
	ledWidth = 8
	ledHeight = 12
	if (notNil anInteger) { setContents this anInteger }
	redraw this
	return this
}

method contents MicroBitDisplaySlot {
	result = 0
	shift = 0
	for y 5 {
		for x 5 {
			index = ((5 * (y - 1)) + x)
			if (at display index) {
				result = (result | (1 << shift))
			}
			shift += 1
		}
	}
	return result
}

method setContents MicroBitDisplaySlot anInteger {
	fillArray display 0
	shift = 0
	for y 5 {
		for x 5 {
			val = ((anInteger & (1 << shift)) != 0)
			index = ((5 * (y - 1)) + x)
			atPut display index val
			shift += 1
		}
	}
	redraw this
	raise morph 'inputChanged' this
}

method redraw MicroBitDisplaySlot {
	scale = (global 'scale')
	bgColor = (colorHSV 235 0.62 0.80)
	offColor = (colorHSV 235 0.62 0.40)
	onColor = (colorHSV 0 1.0 0.9)
	bm = (costumeData morph)
	if (isNil bm) { bm = (newBitmap (76 * scale) (82 * scale) bgColor) }
	for y 5 {
		for x 5 {
			index = ((5 * (y - 1)) + x)
			c = offColor
			if (at display index) { c = onColor }
			left = (inset + ((x - 1) * stride))
			top = (inset + ((y - 1) * stride))
			fillRect bm c (left * scale) (top * scale) (ledWidth * scale) (ledHeight * scale)
		}
	}
	setCostume morph bm
}

// events

method handDownOn MicroBitDisplaySlot aHand {
	// Start drawing on the LED display.

	focusOn aHand this
	paintMode = true
	index = (ledIndex this aHand)
	if (notNil index) {
		paintMode = (not (at display index))
	}
	handMoveFocus this aHand
	return true
}

method handMoveFocus MicroBitDisplaySlot aHand {
	// Draw on the LED display as the mouse moves.

	index = (ledIndex this aHand)
	if (notNil index) {
		atPut display index paintMode
		redraw this
		raise morph 'inputChanged' this
		// xxx update underlying block
	}
	return true
}

method ledIndex MicroBitDisplaySlot aHand {
	// Return an array with the x,y pair of the LED under the hand.
	// Return nil if hand is not over any LED.

	scale = (global 'scale')
	normalizedX = ((((x aHand) - (left morph)) / scale) - inset)
	normalizedY = ((((y aHand) - (top morph)) / scale) - inset)
	if (or (normalizedX < 0) (normalizedY < 0)) { return nil }
	if ((normalizedX % stride) >= ledWidth) { return nil }
	if ((normalizedY % stride) >= ledHeight) { return nil }

	col = (truncate (normalizedX / stride))
	row = (truncate (normalizedY / stride))
	if (or (col > 4) (row > 4)) { return nil }

	return (((row * 5) + col) + 1)
}
