// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFinder.gp - Finds and helps graphically locate users of a
// particular block in a project, be it functions that call it or scripts that
// include it.

// Bernat Romagosa, July, 2022

to findBlockUsers aProject aBlock {
	page = (global 'page')
	finder = (initialize (new 'BlockFinder') aProject aBlock)
	menu = (menu nil finder)
	for entry (functions finder) {
		b = (blockForFunction entry)
		fixLayout b
		addItem menu (fullCostume (morph b)) (action 'jumpTo' finder entry)
	}
	if (notNil (functions finder)) { addLine menu }
	for entry (scripts finder) {
		b = (blockForFunction (at entry 3))
		fixLayout b
		addItem menu (fullCostume (morph b)) (action 'jumpTo' finder entry)
	}
	popUp menu (global 'page')
}

defineClass BlockFinder morph window frame project block functions scripts

method initialize BlockFinder aProject aBlock {
	project = aProject
	block = aBlock
	functions = (list)
	scripts = (list)

	findAllUsers this

	return this
}

method functions BlockFinder { return functions }
method scripts BlockFinder { return scripts }

method allEntries BlockFinder {
	return (join functions scripts)
}

method findAllUsers BlockFinder {
	// look in block definitions
	for function (allFunctions project) {
		if (contains (allCalls function) (primName (expression block))) {
			add functions function
		}
	}
	// look in scripts
	for script (scripts (main project)) {
		// script is a 3 item array where the first two are its coordinates
		for expression (allBlocks (at script 3)) {
			if ((primName expression) == (primName (expression block))) {
				add scripts script
			}
		}
	}
}

method jumpTo BlockFinder entry {
	scripter = (scripter (findProjectEditor))
	if (isClass entry 'Array') {
		// script entries have their coordinates as their first two elements
		scrollToXY scripter (at entry 1) (at entry 2)
	} else {
		showDefinition scripter (functionName entry)
	}
}

method explore BlockFinder {
	// for now, just explore the result
	explore (hand (global 'page')) (allEntries this)
}
