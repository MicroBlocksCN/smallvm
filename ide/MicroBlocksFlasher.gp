// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFlasher.gp - An interface to internal ESPTool to flash Espressif boards
// Bernat Romagosa, September 2019

defineClass MicroBlocksFlasher morph label sublabel paddle1 rotation boardName portName eraseFlag downloadFlag espTool espTask

to newFlasher board serialPortName eraseFlashFlag downloadLatestFlag {
	return (initialize (new 'MicroBlocksFlasher') board serialPortName eraseFlashFlag downloadLatestFlag)
}

method initialize MicroBlocksFlasher board serialPortName eraseFlashFlag downloadLatestFlag {
	boardName = board
	portName = serialPortName
	eraseFlag = eraseFlashFlag
	downloadFlag = downloadLatestFlag

	morph = (newMorph this)
	setCostume morph (gray 0 80)

	paddle1 = (newBox nil (gray 255) 10)
	paddle2 = (newBox nil (gray 255) 10)
	setExtent (morph paddle1) 100 20
	setExtent (morph paddle2) 20 100
	addPart (morph paddle1) (morph paddle2)
	gotoCenterOf (morph paddle2) (morph paddle1)
	addPart morph (morph paddle1)
	rotation = 0

	scale = (global 'scale')
	label = (newText '' 'Arial' (24 * scale) (gray 255))
	addPart morph (morph label)

	sublabel = (newText (localized '(press ESC to cancel)') 'Arial' (18 * scale) (gray 255))
	addPart morph (morph sublabel)

	pageM = (morph (global 'page'))
	setExtent morph (width (bounds pageM)) (height (bounds pageM))
	return this
}

method redraw MicroBlocksFlasher {
	pageM = (morph (global 'page'))
	gotoCenterOf morph pageM
	gotoCenterOf (morph paddle1) pageM
	gotoCenterOf (morph label) pageM
	gotoCenterOf (morph sublabel) pageM
	moveBy (morph label) 0 105
	moveBy (morph sublabel) 0 170
}

method step MicroBlocksFlasher {
	rotation = (rotation - 1)
	rotateAndScale (morph paddle1) rotation
	redraw this
	if (notNil espTool) { setText label (status espTool) }
	if (or (isNil espTask) (isTerminated espTask)) { destroy this }
}

method destroy MicroBlocksFlasher {
	destroy morph
	if (notNil espTask) {
		stopTask espTask
		espTask = nil
	}
	enableAutoConnect (smallRuntime)
}

method startFlasher MicroBlocksFlasher {
	espTool = (newESPTool)
	ok = (openPort espTool portName boardName)
	if (not ok) {
		destroy this
		inform 'Could not open serial port'
		return
	}
	espTask = (launch
		(global 'page')
		(action 'installFirmware' espTool boardName eraseFlag downloadFlag))
}
