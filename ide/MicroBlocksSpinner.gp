// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2020 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksSpinner.gp - A modal spinner animation
// Bernat Romagosa, October 2020

defineClass MicroBlocksSpinner morph label sublabel paddle1 rotation labelGetter doneGetter

to newSpinner labelReporter doneReporter {
	return (initialize (new 'MicroBlocksSpinner') labelReporter doneReporter)
}

method initialize MicroBlocksSpinner labelReporter doneReporter {
	labelGetter = labelReporter
	doneGetter = doneReporter

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
	label = (newText (call labelGetter) 'Arial' (24 * scale) (gray 255))
	addPart morph (morph label)

	sublabel = (newText (localized '(press ESC to cancel)') 'Arial' (18 * scale) (gray 255))
	addPart morph (morph sublabel)

	pageM = (morph (global 'page'))
	setExtent morph (width (bounds pageM)) (height (bounds pageM))

	return this
}

method redraw MicroBlocksSpinner {
	pageM = (morph (global 'page'))
	gotoCenterOf morph pageM
	gotoCenterOf (morph paddle1) pageM
	gotoCenterOf (morph label) pageM
	gotoCenterOf (morph sublabel) pageM
	moveBy (morph label) 0 105
	moveBy (morph sublabel) 0 170
}

method destroy MicroBlocksSpinner {
	destroy morph
}

method step MicroBlocksSpinner {
	if (call doneGetter) { destroy this }
	rotation = (rotation - 1)
	rotateAndScale (morph paddle1) rotation
	redraw this
	setText label (call labelGetter)
}
