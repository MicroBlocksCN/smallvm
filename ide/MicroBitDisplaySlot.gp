// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

defineClass MicroBitDisplaySlot morph display paintMode inset stride ledWidth ledHeight

to newMicroBitDisplaySlot anInteger {
	return (initialize (new 'MicroBitDisplaySlot') anInteger)
}

method initialize MicroBitDisplaySlot anInteger {
	morph = (newMorph this)
	setHandler morph this
	setGrabRule morph 'defer'
	setTransparentTouch morph true
	display = (newArray 25 false)
	inset = 0
	stride = 15
	ledWidth = 9
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
	scale = (blockScale)
	bgColor = (transparent)
	offColor = (colorHSV 235 0.62 0.40)
	onColor = (colorHSV 0 1.0 0.9)
	bm = (costumeData morph)
	if (isNil bm) { bm = (newBitmap (69 * scale) (72 * scale) bgColor) }
	for y 5 {
		for x 5 {
			index = ((5 * (y - 1)) + x)
			c = offColor
			if (at display index) { c = onColor }
			left = (inset + ((x - 1) * stride))
			top = (inset + ((y - 1) * (stride - 1)))
			fillRect bm c (left * scale) (top * scale) (ledWidth * scale) (ledHeight * scale)
		}
	}
	setCostume morph bm
}

// events

method handEnter MicroBitDisplaySlot aHand { setCursor 'crosshair' }
method handLeave MicroBitDisplaySlot aHand { setCursor 'default' }

method handDownOn MicroBitDisplaySlot aHand {
	// Start drawing on the LED display.

	setCursor 'crosshair'
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

	scale = (blockScale)
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
