// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2020 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksSpinner.gp - A modal spinner animation
// Bernat Romagosa, October 2020

defineClass MicroBlocksSpinner morph label sublabel rotation labelGetter doneGetter task stopAction

to newSpinner labelReporter doneReporter {
	return (initialize (new 'MicroBlocksSpinner') labelReporter doneReporter)
}

method initialize MicroBlocksSpinner labelReporter doneReporter {
	labelGetter = labelReporter
	doneGetter = doneReporter

	morph = (newMorph this)
	setCostume morph (gray 0 80)
	rotation = 0

	scale = (global 'scale')
	label = (newText (localized (call labelGetter)) 'Arial' (24 * scale) (gray 255))
	addPart morph (morph label)

	sublabel = (newText (localized '(press ESC to cancel)') 'Arial' (18 * scale) (gray 255))
	addPart morph (morph sublabel)

	pageM = (morph (global 'page'))
	setExtent morph (width (bounds pageM)) (height (bounds pageM))

	setFPS morph 4
	fixLayout this
	return this
}

method fixLayout MicroBlocksSpinner {
	pageM = (morph (global 'page'))
	setExtent morph (width (bounds pageM)) (height (bounds pageM))
	gotoCenterOf morph pageM
	gotoCenterOf (morph label) pageM
	gotoCenterOf (morph sublabel) pageM
	moveBy (morph label) 0 105
	moveBy (morph sublabel) 0 170
}

method drawOn MicroBlocksSpinner ctx {
	r = (bounds morph)
	fillRect ctx (costumeData morph) (left r) (top r) (width r) (height r) 1
	pen = (pen (getShapeMaker ctx))
	beginPath pen (hCenter r) (vCenter r)
	setHeading pen rotation
	repeat 2 {
		forward pen 50
		turn pen 180
		forward pen 100
		forward pen -50
		turn pen 90
	}
	stroke pen (gray 230) 25
}

method spinnerChanged MicroBlocksSpinner {
	// Must increase bounding rectangle by half the pen width due to rounded ends.

	bnds = (bounds morph)
	left = ((hCenter bnds) - 65)
	top = ((vCenter bnds) - 65)
	reportDamage (owner morph) (rect left top 130 130)
}

method task MicroBlocksSpinner { return task }
method setTask MicroBlocksSpinner aTask { task = aTask }

method setStopAction MicroBlocksSpinner anAction { stopAction = anAction }

method destroy MicroBlocksSpinner {
	setCursor 'default'
	if (notNil stopAction) {
		call stopAction
	}
	if (notNil task) {
		terminate task
	}
	destroy morph
}

method step MicroBlocksSpinner {
	if (call doneGetter) {
		setCursor 'default'
		destroy this
		return
	}

	setCursor 'wait'
	rotation = ((rotation + 30) % 360)
	spinnerChanged this
	setText label (localized (call labelGetter))
	setXCenter (morph label) (hCenter (bounds morph))
}
