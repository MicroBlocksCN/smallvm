// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFinder.gp - Finds and helps graphically locate users of a
// particular block in a project, be it functions that call it or scripts that
// include it.

// Bernat Romagosa, July, 2022

to findBlockUsers aProject aBlock {
	finder = (initialize (new 'BlockFinder') aProject aBlock)
	find finder 'users'
	showResults finder 'users'
}

to findVarAccessors aProject aBlock {
	finder = (initialize (new 'BlockFinder') aProject aBlock)
	find finder 'accessors'
	showResults finder 'accessors'
}

to findVarModifiers aProject aBlock {
	finder = (initialize (new 'BlockFinder') aProject aBlock)
	find finder 'modifiers'
	showResults finder 'modifiers'
}

defineClass BlockFinder morph window frame project block functions scripts noEntriesTexts

method initialize BlockFinder aProject aBlock {
	project = aProject
	block = aBlock
	functions = (list)
	scripts = (list)

	noEntriesTexts = (dictionary)
	atPut noEntriesTexts 'users' 'This block is not being used in this project'
	atPut noEntriesTexts 'accessors' 'This variable is not being read anywhere in this project'
	atPut noEntriesTexts 'modifiers' 'This variable is not being modified anywhere in this project'

	return this
}

method functions BlockFinder { return functions }
method scripts BlockFinder { return scripts }

method varName BlockFinder { return (first (argList (expression block))) }

method allEntries BlockFinder {
	return (join functions scripts)
}

method find BlockFinder purpose {
	// look in block definitions
	for function (allFunctions project) {
		if (usedInFunction this function purpose) { add functions function }
	}
	// look in scripts
	for script (parts (morph (scriptEditor (scripter (smallRuntime))))) {
		// script is a 3 item array where the first two are its coordinates
		if (isClass (handler script) 'Block') {
			instance = (findInScript this script purpose)
			if (notNil instance) {
				add scripts (array script instance)
			}
		}
	}
}

method usedInFunction BlockFinder function purpose {
	if (purpose == 'users') {
		return (contains (allCalls function) (primName (expression block)))
	} (purpose == 'accessors') {
		for expression (allBlocks (cmdList function)) {
			if (and
				((primName expression) == 'v')
				((varName this) == (first (argList expression)))
			) {
				return true
			}
		}
		return false
	} (purpose == 'modifiers') {
		for expression (allBlocks (cmdList function)) {
			if (and
				(contains (array '=' '+=') (primName expression))
				((varName this) == (first (argList expression)))
			) {
				return true
			}
			
		}
		return false
	}
}

method findInScript BlockFinder script purpose {
	for child (allMorphs script) {
		if (isClass (handler child) 'Block') {
			if (or 
				(and (purpose == 'users')
					((primName (expression (handler child))) == (primName (expression block)))
				)
				(and (purpose == 'accessors')
					((primName (expression (handler child))) == 'v')
					((first (argList (expression (handler child)))) == (varName this))
				)
				(and (purpose == 'modifiers')
					(contains (array '=' '+=') (primName (expression (handler child))))
					((first (argList (expression (handler child)))) == (varName this))
				)
			) {
				return child
			}
		}
	}
	return nil
}

method menuTitleFor BlockFinder purpose {
	if (purpose == 'users') {
		return (join (localized 'Users of ') (primName (expression block)))
	} (purpose == 'accessors') {
		return (join (localized 'Accessors of ') (varName this))
	} (purpose == 'modifiers') {
		return (join (localized 'Modifiers of ') (varName this))
	}
}

method showResults BlockFinder purpose {
	page = (global 'page')
	count = ((count functions) + (count scripts))
	if (count == 0) {
		inform page (at noEntriesTexts purpose)
		return
	}

	menu = (menu (menuTitleFor this purpose) this)
	for entry functions {
		b = (blockForFunction entry)
		fixLayout b
		addItem menu (fullCostume (morph b)) (action 'jumpTo' this entry purpose)
	}
	if (notNil functions) { addLine menu }
	for entry scripts {
		// entries are 2-item arrays with topBlock and actual found block
		addItem menu (fullCostume (at entry 1) 600 200) (action 'jumpTo' this (at entry 2))
	}
	popUp menu page
}

method jumpTo BlockFinder entry purpose {
	scripter = (scripter (findProjectEditor))
	if (isClass entry 'Function') {
		showDefinition scripter (functionName entry)
		m = (findDefinitionOf scripter (functionName entry))
		entry = (findInScript this m purpose)
	}
	scrollIntoView (scriptsFrame scripter) (fullBounds entry) true
	repeat 6 { flash (handler entry) }
}
