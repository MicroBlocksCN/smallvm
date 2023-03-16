// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksSelection.gp - Selection rectangle, to deal with several scripts
//							 at the same time

// Bernat Romagosa, February, 2023

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
	setSelection scripter nil
}

defineClass MicroBlocksSelection scripter rectangle morph blocks selecting

method initialize MicroBlocksSelection {
	cancelSelection
	setSelection scripter this
	selecting = true

	blocks = (list)
	morph = (newMorph this)

	addPart (morph scripter) morph
	return this
}

method destroy MicroBlocksSelection {
	selecting = false
	destroy morph
}

// selecting

method updateSelection MicroBlocksSelection aHand {
	if selecting {
		setLeft rectangle (min (oldX aHand) (x aHand))
		setTop rectangle (min (oldY aHand) (y aHand))
		setWidth rectangle (abs ((x aHand) - (oldX aHand)))
		setHeight rectangle (abs ((y aHand) - (oldY aHand)))
	}
	fixLayout this
}

method endSelection MicroBlocksSelection {
	if ((area rectangle) > 1) {
		for p (allMorphs (morph (scriptEditor scripter))) {
			if (isClass (handler p) 'Block') {
				if (intersects rectangle (bounds p)) {
					tb = (topBlock (handler p))
					if (not (contains blocks tb)) {
						add blocks tb
						select tb
					}
				}
			}
		}
	}
	selecting = false
	destroy this
}


// debugging

method toString MicroBlocksSelection {
	return (join 'selection: ' (toString blocks))
}

// drawing

method fixLayout MicroBlocksSelection {
	setExtent morph (width rectangle) (height rectangle)
	setPosition morph (left rectangle) (top rectangle)
}

method drawOn MicroBlocksSelection ctx {
	fillRect ctx (color 0 128 0 50) (left rectangle) (top rectangle) (width rectangle) (height rectangle) 1
}

// testing

method notEmpty MicroBlocksSelection { return (notEmpty blocks) }

method contains MicroBlocksSelection aBlock {
	return (contains blocks (topBlock aBlock))
}

// events

method handUpOn MicroBlocksSelection aHand {
	endSelection this
	return true
}

method handMoveOver MicroBlocksSelection aHand {
	updateSelection this aHand
}

// actions

method contextMenu MicroBlocksSelection {
	menu = (menu nil this)
	addItem menu 'duplicate selection' 'duplicateBlocks'
	addItem menu 'drag selection' 'dragBlocks'
	addLine menu
	addItem menu 'delete selection' 'deleteBlocks'
	return menu
}

method deleteBlocks MicroBlocksSelection {
	for block blocks {
		removeFromOwner (morph block)
		destroy (morph block)
	}
	cancelSelection
}

method duplicateBlocks MicroBlocksSelection {
	cancelSelection
	showTrashcan (findMicroBlocksEditor)
	contents = (initialize (new 'MicroBlocksSelectionContents') blocks true scripter)
	grab (hand (global 'page')) contents
}

method dragBlocks MicroBlocksSelection {
	cancelSelection
	showTrashcan (findMicroBlocksEditor)
	contents = (initialize (new 'MicroBlocksSelectionContents') blocks false scripter)
	grab (hand (global 'page')) contents
}

defineClass MicroBlocksSelectionContents morph

method initialize MicroBlocksSelectionContents someBlocks duplicating aScripter {
	morph = (newMorph this)
	for block someBlocks {
		if duplicating {
			addPart morph (morph (duplicate block))
		} else {
			addPart morph (morph block)
		}
	}
	addPart (morph (scriptEditor aScripter)) morph // just so it can be animated back to its owner
	return this
}

method justDropped MicroBlocksSelectionContents aHand {
	droppedInto = (owner morph)
	if (isClass droppedInto 'ScriptEditor') {
		for blockMorph (parts morph) {
			addPart droppedInto blockMorph
		}
		removeFromOwner morph
		updateSliders (handler (owner droppedInto))
	}
	hideTrashcan (findMicroBlocksEditor)
}

method destroy MicroBlocksSelectionContents {
	removeFromOwner morph
	destroy morph
}
