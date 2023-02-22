// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksSelection.gp - Selection rectangle, to deal with several scripts
//							 at the same time

// Bernat Romagosa, February, 2023

// a few minor additions to Hand
method oldX Hand { return oldX }
method oldY Hand { return oldY }
method savePosition Hand {
	oldX = x
	oldY = y
}

// a few minor additions to Block
method select Block {
	if (isNil originalColor) {
		originalColor = color
		color = (mixed color 50 (color 0 255 0))
		pathCache = nil
		changed morph
		if (notNil (next this)) {
			select (next this)
		}
		for i (inputs this) {
			if (isClass i 'Block') {
				select i
			} (and
				(isClass i 'CommandSlot')
				(notNil (nested i))
			) {
				select (nested i)
			}
		}
	}
}

method unselect Block {
	if (notNil originalColor) {
		color = originalColor
		originalColor = nil
		pathCache = nil
		changed morph
	}
}

// MicroBlocksSelection

to startSelecting aScripter aHand {
	(initialize (new 'MicroBlocksSelection' aScripter (rect (x aHand) (y aHand))))
	savePosition aHand
}

to cancelSelection {
	scripter = (scripter (findMicroBlocksEditor))
	for p (allMorphs (morph (scriptEditor scripter))) {
		if (isClass (handler p) 'Block') { unselect (handler p) }
	}
	for p (parts (morph scripter)) {
		if (isClass (handler p) 'MicroBlocksSelection') { destroy (handler p) }
	}
}

defineClass MicroBlocksSelection scripter rectangle morph blocks

method initialize MicroBlocksSelection {
	cancelSelection
	setSelection scripter this

	blocks = (list)
	morph = (newMorph this)
	
	addPart (morph scripter) morph
	return this
}

method destroy MicroBlocksSelection {
	setSelection scripter nil
	destroy morph
}

// selecting

method updateSelection MicroBlocksSelection aHand {
	setLeft rectangle (min (oldX aHand) (x aHand))
	setTop rectangle (min (oldY aHand) (y aHand))
	setWidth rectangle (abs ((x aHand) - (oldX aHand)))
	setHeight rectangle (abs ((y aHand) - (oldY aHand)))	
	fixLayout this
}

method endSelection MicroBlocksSelection {
	if ((area rectangle) > 1) {
		for p (allMorphs (morph (scriptEditor scripter))) {
			if (isClass (handler p) 'Block') {
				if (intersects rectangle (bounds p)) {
					add blocks (topBlock (handler p))
					select (topBlock (handler p))
				}
			}
		}
	}
	destroy this
}


// debugging

method toString MicroBlocksSelection {
	return (join 'selection: ' (toString rectangle))
}

// drawing

method fixLayout MicroBlocksSelection {
	setExtent morph (width rectangle) (height rectangle)
	setPosition morph (left rectangle) (top rectangle)
}

method drawOn MicroBlocksSelection ctx {
	fillRect ctx (color 0 128 0 50) (left rectangle) (top rectangle) (width rectangle) (height rectangle) 1
}

// events

method handUpOn MicroBlocksSelection aHand {
	endSelection this
	return true
}
