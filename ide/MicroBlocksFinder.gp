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

	count = ((count (functions finder)) + (count (scripts finder)))
	if (count == 0) {
		inform (global 'page') 'This block is not being used in this project'
		return
	}

	menu = (menu (join 'Users of ' (primName (expression aBlock))) finder)
	for entry (functions finder) {
		b = (blockForFunction entry)
		fixLayout b
		addItem menu (fullCostume (morph b)) (action 'jumpTo' finder entry)
	}
	if (notNil (functions finder)) { addLine menu }
	for entry (scripts finder) {
		// entries are 2-item arrays with topBlock and actual found block
		addItem menu (fullCostume (at entry 1) 600 200) (action 'jumpTo' finder (at entry 2))
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
	for script (parts (morph (scriptEditor (scripter (smallRuntime))))) {
		// script is a 3 item array where the first two are its coordinates
		if (isClass (handler script) 'Block') {
			instance = (findInScript this script)
			if (notNil instance) {
				add scripts (array script instance)
			}
		}
	}
}

method findInScript BlockFinder script {
	for child (allMorphs script) {
		if (and
			(isClass (handler child) 'Block')
			((primName (expression (handler child))) == (primName (expression block)))
		) {
			return child
		}
	}
	return nil
}

method jumpTo BlockFinder entry {
	scripter = (scripter (findProjectEditor))
	if (isClass entry 'Function') {
		showDefinition scripter (functionName entry)
		m = (findDefinitionOf scripter (functionName entry))
		entry = (findInScript this m)
	}
	scrollIntoView (scriptsFrame scripter) (fullBounds entry) true
	repeat 6 { flash (handler entry) }
}
