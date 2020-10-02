// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFlasher.gp - An interface to internal ESPTool to flash Espressif boards
// Bernat Romagosa, September 2019

defineClass MicroBlocksFlasher spinner boardName portName eraseFlag downloadFlag espTool

to newFlasher board serialPortName eraseFlashFlag downloadLatestFlag {
	return (initialize (new 'MicroBlocksFlasher') board serialPortName eraseFlashFlag downloadLatestFlag)
}

method initialize MicroBlocksFlasher board serialPortName eraseFlashFlag downloadLatestFlag {
	boardName = board
	portName = serialPortName
	eraseFlag = eraseFlashFlag
	downloadFlag = downloadLatestFlag

	spinner = (newSpinner (action 'fetchStatus' this) (action 'isDone' this))

	return this
}

method spinner MicroBlocksFlasher {
	return spinner
}

method fetchStatus MicroBlocksFlasher {
	if (notNil espTool) { return (status espTool) }
}

method isDone MicroBlocksFlasher {
	return (or (isNil (task spinner)) (isTerminated (task spinner)))
}

method destroy MicroBlocksFlasher {
	destroy spinner
    enableAutoConnect (smallRuntime)
}

method startFlasher MicroBlocksFlasher serialPortID {
	espTool = (newESPTool)
	if (notNil serialPortID) {
		setPort espTool serialPortID
		ok = true
	} else {
		ok = (openPort espTool portName boardName)
	}
	if (not ok) {
		destroy this
		inform 'Could not open serial port'
		return
	}
	setTask spinner (launch
		(global 'page')
		(action 'installFirmware' espTool boardName eraseFlag downloadFlag))
}
