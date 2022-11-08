// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksPatches.gp - This file patches/replaces methods in GP's normal class library
// with versions that support MicroBlocks (possibly making them no longer work correctly in
// the normal GP IDE.
//
// This file must be processed *after* the normal GP library has been read with a command like:
//
//	./gp runtime/lib/* microBlocks/GP-IDE/* -
//
// John Maloney, January, 2018

method allVarsMenu InputSlot {
  menu = (menu)

  // shared vars
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  pe = (findProjectEditor)
  if (notNil scripter) {
	varNames = (allVariableNames (project (handler scripter)))
	for varName varNames {
          // hide vars that start with underscore, used for libraries
          if (or ((at varName 1) != '_') (showHiddenBlocksEnabled pe)) {
            addItemNonlocalized menu varName (action 'setContents' this varName)
          }
	}
	if ((count varNames) > 0) { addLine menu }
  }

  // local vars
  myBlock = (handler (ownerThatIsA morph 'Block'))
  localVars = (collectLocals (expression (topBlock myBlock)))

  // if inside function, add the function arg names
  topExpr = (expression (topBlock myBlock))
  if (and ('to' == (primName topExpr)) (notNil scripter)) {
    fName = (first (argList topExpr))
    func = (functionNamed (project (handler scripter)) fName)
    if (notNil func) {
      for argName (argNames func) {
        if (not (contains localVars argName)) { add localVars argName }
      }
    }
  }

  remove localVars ''
  for v varNames { remove localVars v }
  if (notEmpty localVars) {
	localVars = (sorted (keys localVars))
	for varName localVars {
	  addItemNonlocalized menu varName (action 'setContents' this varName)
	}
	addLine menu
  }

  addItem menu (localized 'Add a variable') (action 'createVariable' (handler scripter) this)
  scripter = (scripter (findProjectEditor))
  return menu
}

// Input slot menu options

method clicked InputSlot aHand {
  if (notNil menuSelector) {
    if (or ((x aHand) >= ((right morph) - (fontSize text))) isStatic) {
	  if (contains (methodNames (class 'InputSlot')) menuSelector) {
		menu = (call menuSelector this)
		if (notNil menu) {
		  popUpAtHand menu (page aHand)
		}
	  } else {
		project = (project (findProjectEditor))
		choices = (choicesFor project menuSelector)
		if (notNil choices) {
		  menu = (menu nil (action 'setContents' this) true)
		  for choice choices {
		    labelAndValue = (splitWith choice ':')
		    if ((count labelAndValue) == 2) {
		      if (representsAnInteger (at labelAndValue 2)) {
		        atPut labelAndValue 2 (toNumber (at labelAndValue 2))
		      }
		      addItem menu (at labelAndValue 1) (at labelAndValue 2)
		    } else {
			  addItem menu choice
			}
		  }
		  popUpAtHand menu (page aHand)
		}
	  }
    }
	return true
  }
  return false
}

method typesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'boolean'
  addItem menu 'number'
  addItem menu 'string'
  addItem menu 'list'
  addItem menu 'byte array'
  return menu
}

method buttonMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'A'
  addItem menu 'B'
  addItem menu 'A+B'
  return menu
}

method AtoDMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'A'
  addItem menu 'B'
  addItem menu 'C'
  addItem menu 'D'
  return menu
}

// Pull resistor Menu

method pullMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'none'
  addItem menu 'up'
  addItem menu 'down'
  return menu
}

// List Menus

method itemOfMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 1
  addItem menu 'last'
  addItem menu 'random'
  return menu
}

method replaceItemMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 1
  addItem menu 'last'
  addItem menu 'all'
  return menu
}

method functionNameMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  scripterM = (ownerThatIsA morph 'MicroBlocksScripter')
  if (notNil scripterM) {
    project = (project (handler scripterM))
    specs = (blockSpecs project)
    for func (functions (main project)) {
	  addItem menu (functionName func)
    }
  }
  return menu
}

// Disallow reporter blocks in hat block input slots
// (does apply to BooleanSlots in "when <boolean>" hat blocks)

method isReplaceableByReporter InputSlot {
	owner = (handler (owner morph))
	if (and (isClass owner 'Block') ('hat' == (type owner))) {
		// Don't allow dropping reporters into hat block input slots.
		return false
	}
	return (not isStatic)
}

method confirmToQuit Page {
	confirm this nil (join 'Quit MicroBlocks?') nil nil 'exit'
}

to findProjectEditor {
  m = (findMorph 'MicroBlocksEditor')
  if (notNil m) { return (handler m) }
  return nil
}

to gpFolder {
  if ('iOS' == (platform)) { return '.' }
  path = (userHomePath)

  hidden = (global 'hideFolderShortcuts')
  if (and (notNil hidden) (contains hidden 'Projects')) { return '/' } // if GP hidden, use computer

  // Look for <home>/Documents
  if (contains (listDirectories path) 'Documents') {
	path = (join path '/Documents')
  }
  if (not (contains (listDirectories path) 'MicroBlocks')) {
	if (contains (listDirectories path) 'MicroBlocks Projects') {
		// if it exists, rename old 'MicroBlocks Projects' folder to 'MicroBlocks'
		renameFile (join path '/MicroBlocks Projects') (join path '/MicroBlocks')
	} else {
		// create the MicroBlocks folder if it does not already exist
		makeDirectory (join path '/MicroBlocks')
	}
  }
  if (contains (listDirectories path) 'MicroBlocks') {
    // create the Libraries subfolder, if it does not already exist
	if (not (contains (listDirectories (join path '/MicroBlocks') 'Libraries'))) {
		makeDirectory (join path '/MicroBlocks/Libraries')
	}
	path = (join path '/MicroBlocks')
  }
  return path
}

// Broadcast menu

method broadcastMenu InputSlot {
  menu = (menu)

  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (notNil scripter) {
    saveScripts (handler scripter)
    msgList = (allBroadcasts (project (handler scripter)))

    // special case for default broadcast string
    defaultBroadcast = 'go!'
    remove msgList defaultBroadcast
    addItemNonlocalized menu (localized defaultBroadcast) (action 'setContents' this defaultBroadcast)
    addLine menu

	for s msgList {
      addItemNonlocalized menu s (action 'setContents' this s)
	}
  }
  return menu
}

// Block additions

method clicked Block hand {
  cancelSelection
  if (and (contains (array 'template' 'defer') (grabRule morph)) (isRenamableVar this)) {
    userRenameVariable this
    return
  } (isPrototype this) {
    def = (blockDefinition this)
    if (notNil def) {
      return (clicked def hand)
    }
    return true
  } (isPrototypeHat this) {
    prot = (editedPrototype this)
    if (notNil prot) {
      return (clicked prot hand)
    }
  } (isClass (handler (owner morph)) 'BlockOp') {
    return
  }

  topBlock = (topBlock this)
  if (isPrototypeHat topBlock) { return }
  runtime = (smallRuntime)
  if (isRunning runtime topBlock) {
	stopRunningChunk runtime (lookupChunkID runtime topBlock)
  } else {
	evalOnBoard runtime topBlock
  }
}

method aboutToBeGrabbed Block {
  if (isNil (owner morph)) {return}
  tb = (topBlock this)
  se = (ownerThatIsA (morph tb) 'ScriptEditor')
  if (notNil se) {
    stopEditing (handler se)
  }
  removeSignalPart (morph tb)
  removeStackPart (morph tb)
  removeHighlight (morph tb)


  // show trashcan icon
  if (isPrototypeHat this) {
	  showTrashcan (findMicroBlocksEditor) 'hide'
  } else {
	  showTrashcan (findMicroBlocksEditor) 'delete'
  }

  if (or
		(commandKeyDown (keyboard (global 'page')))
		(controlKeyDown (keyboard (global 'page')))
  ) {
	// duplicate all with control + grab
	dup = (duplicate this)
	owner = (handler (owner morph))
	if (shiftKeyDown (keyboard (global 'page'))) {
		// duplicate block with control + shift + grab
		if (notNil (next dup)) {setNext dup nil}
	}
	if (notNil owner) {
		if (isClass owner 'CommandSlot') {
			setNested owner dup
		} (isClass owner 'Block') {
			if ((type dup) == 'reporter') {
				replaceInput owner this dup
			} else {
				setNext owner dup
			}
		} (isClass owner 'ScriptEditor') {
			addPart (morph owner) (morph dup)
		}
	}
  }

  // extract block with shift + grab
  if (and
		(shiftKeyDown (keyboard (global 'page')))
		(notNil (next this))
  ) {
    extractBlock this true
	return
  }

  parent = (handler (owner morph))
  if (isClass parent 'Block') {
    if (type == 'reporter') {
      revertToDefaultInput parent this
    } else {
      setNext parent nil
    }
  } (isClass parent 'CommandSlot') {
    setNested parent nil
  }

}

method justDropped Block hand {
  cancelSelection
  snap this (x hand) (y hand)
  hideTrashcan (findMicroBlocksEditor)
}

method alternateOperators Block {
  if (contains (array 'v' '=' '+=') (primName expression)) {
	// if it's a variable, return a group with all existing variables
	return (array '')
  } else {
	opGroups = (array
		(array 'analogReadOp' 'digitalReadOp')
		(array 'analogWriteOp' 'digitalWriteOp')
		(array 'analogPins' 'digitalPins')
		(array 'and' 'or')
		(array '+' '-' '*' '/' '%')
		(array 'buttonA' 'buttonB')
		(array '<' '<=' '==' '!=' '>=' '>')
		(array 'maximum' 'minimum')
		(array 'millisOp' 'microsOp')
		(array '=' '+=')
		(array '&' '|' '^' '<<' '>>')
	)
	op = (primName expression)
	for group opGroups {
		if (contains group op) { return group }
	}
  }
  return nil
}

method changeOperator Block newOp {
  cancelSelection
  setField expression 'primName' newOp
  scripter = (scripter (findProjectEditor))
  updateScriptAfterOperatorChange scripter this
}

method changeVar Block varName {
  cancelSelection
  newVarReporter = (newReporter 'v' varName)
  blockOwner = (handler (owner morph))
  if (isClass blockOwner 'Block') {
    owningExpr = (expression blockOwner)
    args = (argList owningExpr)
    for i (count args) {
      if ((at args i) == (expression this)) {
        setArg owningExpr i newVarReporter
      }
    }
  } else { // top level var reporter
    expression = newVarReporter
  }
  scripter = (scripter (findProjectEditor))
  updateScriptAfterOperatorChange scripter this
}

method contextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
  pe = (findProjectEditor)
  scripter = (scripter pe)
  selection = (selection scripter)
  if (and (notNil selection) (notEmpty selection)) {
  	return (contextMenu selection)
  }

  isInPalette = ('template' == (grabRule morph))
  if (and isInPalette (isRenamableVar this)) {
    addItem menu 'rename...' 'userRenameVariable'
    addLine menu
  }
  addItem menu 'duplicate' 'grabDuplicate' 'duplicate this block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu 'duplicate all' 'grabDuplicateAll' 'duplicate this block and all blocks below it'
  }
  addLine menu
  if (and (not isInPalette) ('reporter' != type)) {
    addItem menu 'extract block' 'extractBlock' 'pull out this block'
  }
  addLine menu
  if (hasHelpEntryFor pe this) {
    addItem menu 'help' (action 'openHelp' pe this) 'show help for this block in a browser'
    addLine menu
  }
  addItem menu 'copy to clipboard' (action 'copyToClipboard' (topBlock this)) 'copy these blocks to the clipboard'
  addItem menu 'copy to clipboard as URL' (action 'copyToClipboardAsURL' (topBlock this)) 'copy these blocks to the clipboard as a URL'
  addLine menu
  addItem menu 'save picture of script' 'exportAsImage' 'save a picture of these blocks as a PNG file'
  if (not (isPrototypeHat (topBlock this))) {
	if (or ('reporter' == (type (topBlock this))) (devMode)) {
	  addItem menu 'save picture of script with result' 'exportAsImageWithResult' 'save a picture of these blocks and their result as a PNG file'
	}
  }
  if (devMode) {
	addLine menu
    addItem menu 'show instructions' (action 'showInstructions' (smallRuntime) this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' (smallRuntime) this)
    if (and isInPalette (notNil (functionNamed (project pe) (primName expression)))) {
	  addItem menu 'show call tree' (action 'showCallTree' (smallRuntime) this)
    }

	// xxx internal testing only; remove later!:
	if (contains (commandLine) '--allowMorphMenu') {
		addItem menu 'test decompiler' (action 'testDecompiler' (smallRuntime) this) // xxx
	}
  }
  addLine menu

  if (contains (array 'v' '=' '+=') (primName expression)) {
	  addItem menu 'find variable accessors' 'findVarAccessors' 'find scripts or block definitions where this variable is being read'
	  addItem menu 'find variable modifiers' 'findVarModifiers' 'find scripts or block definitions where this variable is being set or changed'
  } else {
	  addItem menu 'find uses of this block' 'findBlockUsers' 'find scripts or block definitions using this block'
  }
  if (notNil (functionNamed (project pe) (primName expression))) {
    addItem menu 'show block definition...' 'showDefinition' 'show the definition of this block'
	if isInPalette {
	  addLine menu
	  addItem menu 'delete block definition...' 'deleteBlockDefinition' 'delete the definition of this block'
	}
  } (and (notNil blockSpec) (beginsWith (at (specs blockSpec) 1) 'obsolete')) {
	  addLine menu
	  addItem menu 'delete obsolete block...' 'deleteObsolete' 'delete this obsolete block from the project'
  }
  if ((primName expression) == 'v') {
	varNames = (allVariableNames (project scripter))
	if (and (not isInPalette) ((count varNames) > 1)) {
		for varName varNames {
			if (or ((at varName 1) != '_') (showHiddenBlocksEnabled pe)) {
				b = (toBlock (newReporter 'v' varName))
				fixLayout b
				addItem menu (fullCostume (morph b)) (action 'changeVar' this varName)
			}
		}
	}
  } else {
	alternativeOps = (alternateOperators this)
	if (and (not isInPalette) (notNil alternativeOps)) {
		addLine menu
		myOp = (primName expression)
		for op alternativeOps {
		  // create and display block morph (with translated spec)
		  spec = (specForOp (authoringSpecs) op)
		  if (and (notNil spec) (op != myOp)) {
			b = (blockForSpec spec)
			fixLayout b
			addItem menu (fullCostume (morph b)) (action 'changeOperator' this op)
		  }
		}
	}
  }
  if (not isInPalette) {
	addLine menu
	addItem menu 'delete block' 'delete' 'delete this block'
  }
  return menu
}

method extractBlock Block whileGrabbing {
  cancelSelection
  whileGrabbing = (whileGrabbing == true)
  if ('reporter' != type) { // hat or command
    nxt = (next this)
    if (and (notNil nxt) (notNil (owner morph))) {
      prev = (ownerThatIsA (owner morph) 'Block')
      cslot = (ownerThatIsA (owner morph) 'CommandSlot')
      scripts = (ownerThatIsA (owner morph) 'ScriptEditor')
      if (and (notNil prev) (=== this (next (handler prev)))) {
        setNext this nil
		if whileGrabbing {
			// needed while grabbing or we end up in an infinite recursion
			setNext (handler prev) nil
		}
		setNext (handler prev) nxt
      } (and (notNil cslot) (=== this (nested (handler cslot)))) {
        setNext this nil
		if whileGrabbing {
			// needed while grabbing or we end up in an infinite recursion
			setNested (handler cslot) nil
		}
        setNested (handler cslot) nxt
      } (notNil scripts) {
        addPart scripts (morph nxt)
        fixBlockColor nxt
      }
      setNext this nil
    }
  }
  if (not whileGrabbing) { grabTopLeft morph }
}

method exportAsImage Block { exportAsImageScaled (topBlock this) }
method exportAsImageWithResult Block { exportScriptImageWithResult (smallRuntime) this }

method exportAsImage BlockDefinition {
	exportAsImageScaled (handler (ownerThatIsA morph 'Block'))
}

method copyToClipboard Block {
  setClipboard (scriptText this)
}

method copyToClipboardAsURL Block {
  setClipboard (join
    'https://microblocksfun.cn/run/microblocks.html#scripts='
	(urlEncode (scriptText this) true)
  )
}

method scriptText Block useSemicolons {
  // Note: scriptText is also called by exportAsImageScaled when saving PNG files.

  mbScripter = (handler (ownerThatIsA morph 'MicroBlocksScripter'))
  return (scriptStringFor mbScripter this)
}

method delete Block {
  if ('reporter' != type) { // hat or command
    nxt = (next this)
    if (and (notNil nxt) (notNil (owner morph))) {
      prev = (ownerThatIsA (owner morph) 'Block')
      cslot = (ownerThatIsA (owner morph) 'CommandSlot')
      scripts = (ownerThatIsA (owner morph) 'ScriptEditor')
      if (and (notNil prev) (=== this (next (handler prev)))) {
        setNext this nil
        setNext (handler prev) nxt
      } (and (notNil cslot) (=== this (nested (handler cslot)))) {
        setNext this nil
        setNested (handler cslot) nxt
      } (notNil scripts) {
        addPart scripts (morph nxt)
      }
    }
  }
  aboutToBeGrabbed this
  removeFromOwner morph
  hideTrashcan (findMicroBlocksEditor)
}

// Inspection operations

method findBlockUsers Block {
	pe = (findProjectEditor)
	findBlockUsers (project pe) this
}

method findVarAccessors Block {
	pe = (findProjectEditor)
	findVarAccessors (project pe) this
}

method findVarModifiers Block {
	pe = (findProjectEditor)
	findVarModifiers (project pe) this
}


// Block definition operations

method showDefinition Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }
  showDefinition (scripter pe) (primName expression)
}

method deleteObsolete Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }

  // find out whether block is being used in the project
  finder = (initialize (new 'BlockFinder') (project (scripter pe)) this)
  find finder 'users'
  if (notEmpty (allEntries finder)) {
    if (not
      (confirm
	    (global 'page')
	    nil
        (join
          'This block is still being used in '
          (count (allEntries finder))
          ' scripts or functions.'
          (newline)
          (newline)
          'Are you sure you want to remove this obsolete block definition?'
        )
	  )
	) { return }
  }

  remove (blockSpecs (project (scripter pe))) (primName expression)
  updateBlocks (scripter pe)
}

method deleteBlockDefinition Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }

  confirmation = 'Are you sure you want to remove this block definition?'

  // find out whether block is being used in the project
  finder = (initialize (new 'BlockFinder') (project (scripter pe)) this)
  find finder 'users'
  if (notEmpty (allEntries finder)) {
    confirmation = (join
      'This block is still being used in '
      (count (allEntries finder))
      ' scripts or functions.'
	  (newline)
	  (newline)
	  confirmation
	)
  }

  if (not (confirm (global 'page') nil confirmation)) { return }

  deleteFunction (scripter pe) (primName expression)
}

method deleteBlockDefinition BlockDefinition {
  if (not (confirm (global 'page') nil
  	'Are you sure you want to remove this block definition?')) {
		return
  }
  pe = (findProjectEditor)
  if (isNil pe) { return }
  deleteFunction (scripter pe) op
}

method hideDefinition BlockDefinition {
  // Remove this method/function definition from the scripting area.

  pe = (findProjectEditor)
  if (isNil pe) { return }
  hideDefinition (scripter pe) op
}

method wantsDropOf BlocksPalette aHandler {
  return (isAnyClass aHandler 'Block' 'Monitor' 'MicroBlocksSelectionContents')
}

method justReceivedDrop BlocksPalette aHandler {
  // Hide a block definition when it is is dropped on the palette.
  pe = (findProjectEditor)
  if (isClass aHandler 'Block') { stopRunningBlock (smallRuntime) aHandler }
  if (and (isClass aHandler 'Block') (isPrototypeHat aHandler)) {
	proto = (editedPrototype aHandler)
	if (and (notNil pe) (notNil proto) (notNil (function proto))) {
		hideDefinition (scripter pe) op
		removeFromOwner (morph aHandler)
		return
	}
  }
  if (and (isClass aHandler 'Block') (notNil pe)) {
	recordDrop (scriptEditor (scripter pe)) aHandler
	deleteChunkFor (smallRuntime) aHandler
  }
  if (isClass aHandler 'MicroBlocksSelectionContents') {
	for part (parts (morph aHandler)) {
		justReceivedDrop this (handler part)
	}
  }
  removeFromOwner (morph aHandler)
}

method wantsDropOf CategorySelector aHandler {
	// only accept definition hat blocks
	scripter = (scripter (findProjectEditor))
	return (and
		(isClass aHandler 'Block')
		(isNil (blockSpec aHandler))
		((type aHandler) == 'hat')
	)
}

// Allow adding blocks to libraries by dropping their definitions into the
// library selector
method justReceivedDrop CategorySelector aHandler {
	pe = (findProjectEditor)
	scripter = (scripter pe)
	mainModule = (main (project pe))
	intoLibrary = (and
		((getField scripter 'libSelector') == this)
		(notNil (categoryUnderHand this)))
	intoMyBlocks = (and
		((getField scripter 'categorySelector') == this)
		((categoryUnderHand this) == 'My Blocks'))

	// accept it if dropping onto the library list or onto the category list,
	// but only if it's onto My Blocks
	if (or intoLibrary intoMyBlocks){
		block = (handler (at (parts (morph aHandler)) 2))
		function = (function block)
		for lib (values (libraries (project scripter))) {
			if (contains (functions lib) function) {
				// Block already in a library, let's remove it from there first
				removeFunction lib function
				remove (blockList lib) (functionName function)
				remove (blockSpecs lib) (blockSpecFor function)
			}
		}
		if intoLibrary {
			library = (at (libraries (project scripter)) (categoryUnderHand this))
		} else {
			library = mainModule
		}
		if (not (contains (functions library) function)) {
			globalsUsed = (globalVarsUsed function)
			if (contains (functions mainModule) function) {
				// Block is in My Blocks, let's remove it from there first
				removeFunction mainModule function
				remove (blockList mainModule) (functionName function)
				remove (blockSpecs mainModule) (blockSpecFor function)
				for var globalsUsed {
					deleteVariable mainModule var
				}
			}
			addFunction library function
			add (blockList library) (functionName function)
			add (blockSpecs library) (blockSpecFor function)
			for var globalsUsed {
				addVariable library var
			}
		}
		select this (categoryUnderHand this)
	}
	animateBackToOldOwner (hand (global 'page')) (morph aHandler) (action 'languageChanged' scripter)
}

// Input slots

method inputIndex Block anInput {
  idx = 0
  items = (flattened labelParts)

  // Note: removed special case for variable assignments

  for each items {
    if (isAnyClass each 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'MicroBitDisplaySlot') {
      idx += 1
      if (each === anInput) {return idx}
    }
  }
  return nil
}

method representsANumber String {
	// MicroBlocks only supports integers.
	if ('' == String) { return true }
	isFirst = true
	for c (letters this) {
		if ('-' == c) {
			if (not isFirst) { return false }
		} (not (isDigit c)) {
			return false
		}
		isFirst = false
	}
	return true
}

method contextMenu BlockDefinition {
  menu = (menu nil this)
  addItem menu 'hide block definition' 'hideDefinition'
  addLine menu
  addItem menu 'copy to clipboard' (action 'copyToClipboard' (handler (ownerThatIsA morph 'Block'))) 'copy these blocks to the clipboard'
  addItem menu 'copy to clipboard as URL' (action 'copyToClipboardAsURL' (handler (ownerThatIsA morph 'Block'))) 'copy these blocks to the clipboard as a URL'
  addLine menu
  addItem menu 'save picture of script' 'exportAsImage' 'save a picture of this block definition as a PNG file'
  if (devMode) {
    addLine menu
    addItem menu 'show instructions' (action 'showInstructions' this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' this)
    addItem menu 'show call tree' (action 'showCallTree' this)
  }
  addLine menu
  addItem menu 'delete block definition...' 'deleteBlockDefinition'
  popUp menu (global 'page') (left morph) (bottom morph)
}

method showInstructions BlockDefinition {
  showInstructions (smallRuntime) (handler (owner (owner morph)))
}

method showCompiledBytes BlockDefinition {
  showCompiledBytes (smallRuntime) (handler (owner (owner morph)))
}

method showCallTree BlockDefinition {
  showCallTree (smallRuntime) (handler (owner (owner morph)))
}

method initializeRepeater BlockDefinition aBlockSpec {
  if (isNil aBlockSpec) {
    isRepeating = false
  } else {
    isRepeating = (repeatLastSpec aBlockSpec)
  }
  drawer = (newBlockDrawer this nil 'vertical')
  repeater = (newAlignment 'centered-line' 0 'bounds')
  setMorph repeater (newMorph repeater)
  if isShort {
    hide (morph repeater)
  }
  setPadding repeater (5 * (global 'scale'))
return // xxx suppress the ability to make variadic user-defined blocks

  addPart (morph repeater) (morph drawer)

  scale = (global 'scale')
  labelColor = (global 'blockTextColor')
  if (isNil labelColor) { labelColor = (gray 255) }
  txt = (newText 'repeat last section:' 'Arial' (10 * scale) labelColor)
  addPart (morph repeater) (morph txt)

  corner = 5
  toggle = (toggleButton (action 'toggleRepeat' this) (action 'isRepeating' this) (scale * 20) (scale * 13) (scale * corner) (max 1 (scale / 2)) false false)
  addPart (morph repeater) (morph toggle)
}

// additions to Hand for script selection

method oldX Hand { return oldX }
method oldY Hand { return oldY }
method savePosition Hand {
	oldX = x
	oldY = y
}

// additions to Block for script selection

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

// support for script selection

method handDownOn ScriptEditor aHand {
	if (notNil (grabbedObject aHand)) { return false } // hand is not empty
	scripter = (handler (ownerThatIsA morph 'MicroBlocksScripter'))
	pe = (findProjectEditor)
	selection = (selection (scripter pe))
	if (and (notNil selection) (notEmpty selection)) {
		grabbed = (ownerThatIsA (morph (objectAt aHand)) 'Block')
		if (and (notNil grabbed) (contains selection (handler grabbed))) {
			dragBlocks selection
			return true
		}
	}
	if (isClass (objectAt aHand) 'ScriptEditor') {
		if (not (isMobile)) {
			startSelecting scripter aHand
		}
	}
	return true
}

method wantsDropOf ScriptEditor aHandler {
  return (or
    (isAnyClass aHandler 'Block' 'CommandSlot' 'MicroBlocksSelectionContents')
    (and
      (devMode)
      (isClass aHandler 'Text')
      (== 'code' (editRule aHandler))))
}

method contextMenu ScriptEditor {
  menu = (menu nil this)
  addItem menu 'set block size...' 'setBlockSize' 'make blocks bigger or smaller'
  addLine menu
  if (notNil lastDrop) {
    addItem menu 'undrop (ctrl-Z)' 'undrop' 'undo the last block drop'
  }
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  addLine menu
  addItem menu 'copy all scripts to clipboard' 'copyScriptsToClipboard'
  addItem menu 'copy all scripts to clipboard as URL' 'copyScriptsToClipboardAsURL'
  addLine menu
  clip = (readClipboard)
  if (beginsWith clip 'GP Scripts') {
	addItem menu 'paste all scripts from clipboard' 'pasteScripts'
  } (beginsWith clip 'GP Script') {
	addItem menu 'paste script from clipboard' 'pasteScripts'
  }
  addLine menu
  addItem menu 'save a picture of all visible scripts' 'saveScriptsImage'
  if (devMode) {
    addItem menu 'set exported script scale' 'setExportedScriptScale'
  }
  return menu
}

method copyScriptsToClipboard ScriptEditor {
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (isNil scripter) { return }
  setClipboard (allScriptsString (handler scripter))
}

method copyScriptsToClipboardAsURL ScriptEditor {
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (isNil scripter) { return }
  scriptsString = (allScriptsString (handler scripter))
  urlPrefix = (urlPrefix (findMicroBlocksEditor))
  setClipboard (join urlPrefix '#scripts=' (urlEncode scriptsString true))
}

// Color picker tweak

method addTransparentButton ColorPicker x y { } // don't add a transparent button

// Block colors

method blockColorForOp AuthoringSpecs op {
  if ('comment' == op) { return (colorHSV 55 0.6 0.93) }
  pe = (findProjectEditor)
  if (notNil pe) {
	cat = (categoryForOp (project pe) op) // get category from project, if possible
  }
  if (isNil cat) { cat = (at opCategory op) } // get category of a built-in block
  return (blockColorForCategory this cat)
}

method blockColorForCategory AuthoringSpecs cat {
  if (and (notNil cat) (endsWith cat '-Advanced')) {
  	cat = (substring cat 1 ((count cat) - 9))
  }
  pe = (findProjectEditor)
  if (notNil pe) {
	lib = (libraryNamed (project pe) cat) // is cat the name of a library?
	if (and (notNil lib) (notNil (moduleCategory lib))) { // if so, use that library's category
		cat = (moduleCategory lib)
	}
  }
  // old Comm color: (colorHSV 195 0.50 0.60)
  // old default color: (colorHSV 200 0.98 0.86)
  defaultColor = (colorHSV 205 0.83 0.87)
  if ('Output' == cat) { return (colorHSV 235 0.62 0.75)
  } ('Input' == cat) { return (colorHSV 296 0.60 0.65)
  } ('Pins' == cat) { return (colorHSV 195 0.45 0.60)
  } ('Comm' == cat) {  return (colorHSV 14 0.75 0.80)
  } ('Control' == cat) { return (colorHSV 36 0.70 0.87)
  } ('Operators' == cat) { return (colorHSV 100 0.75 0.65)
  } ('Variables' == cat) { return (colorHSV 26 0.80 0.83)
  } ('Data' == cat) { return (colorHSV 345 0.60 0.77)
  } ('Advanced' == cat) { return (colorHSV 30 0.70 0.70)
  } ('My Blocks' == cat) { return (colorHSV 205 0.83 0.90)
  } ('Library' == cat) {  return (colorHSV 165 0.80 0.60)
  } ('Obsolete' == cat) { return (colorHSV 4.6 1.0 0.77)
  }
  return defaultColor
}

// Scratch		1.0					2.0
// Motion	(color 102 124 236)	(color 76 111 209)
// Looks	(color 147 84 235)	(color 36 139 216)
// Sound	(color 217 43 225)	(color 185 72 193)
// Pen		(color 35 165 124)	(color 29 153 109)
// Control	(color 227 154 43)	(color 224 168 48)
// Sensing	(color 39 149 230)	(color 53 166 223) like default color
// Operators (color 99 196 44)	(color 95 181 39)
// Variables (color 226 95 27)	(color 236 125 42) variables is like 2.0
// Events						(color 199 130 57)
// More Blocks					(color 98 50 151)))

// ListBox: Support for colored blocks categories

method setOpCategory AuthoringSpecs op category {
  atPut opCategory op category
}

method normalCostume ListBox data accessor {
  scale = (global 'scale')
  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'Array') {
    return (stringImage (at dta 1) fontName fontSize txtClrNormal nil nil nil nil paddingX paddingY)
  } (isClass dta 'String') {
	// Colored categories:
	if (and (isClass onSelect 'Action') (isOneOf (function onSelect) 'categorySelected' 'librarySelected')) {
	  // add color swatch for category
	  c = (blockColorForCategory (authoringSpecs) dta)
	  stringBM = (stringImage (localized dta) fontName fontSize (gray 50))
	  bm = (newBitmap ((width stringBM) + (50 * scale)) (21 * scale))
	  fillRect bm c (4 * scale) (1 * scale) (10 * scale) ((height bm) - (4 * scale))
	  drawBitmap bm stringBM (19 * scale) (1 * scale)
	  return bm
	}
	return (stringImage dta fontName fontSize txtClrNormal nil nil nil nil paddingX paddingY)
  } (isClass dta 'Bitmap') {
    bm = (newBitmap (+ (* 2 paddingX) (width dta)) (+ (height dta) (* 2 paddingY)) bgClrNormal)
    drawBitmap bm dta paddingX paddingY normalAlpha
    return bm
  }
  return (itemCostume this dta txtClrNormal nil normalAlpha 'id')
}

method itemCostume ListBox data foregroundColor backgroundColor alpha accessor {
  scale = (global 'scale')
  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'Bitmap') {
    bm = (newBitmap (max (+ (* 2 paddingX) (width dta)) (width morph)) (+ (height dta) (* 2 paddingY)) backgroundColor)
    drawBitmap bm dta paddingX paddingY alpha
    return bm
  } (isClass dta 'Morph') {
    return (itemCostume this (fullCostume dta) foregroundColor backgroundColor alpha 'id')
  } (hasField dta 'morph') {
    return (itemCostume this (fullCostume (getField dta 'morph')) foregroundColor backgroundColor alpha 'id')
  } (isAnyClass dta 'Command' 'Reporter') {
    return (itemCostume this (fullCostume (morph (toBlock dta))) foregroundColor backgroundColor alpha 'id')
  } (isClass dta 'String') {
	// Colored categories:
	if (and (isClass onSelect 'Action') (isOneOf (function onSelect) 'categorySelected' 'librarySelected')) {
	  c = (blockColorForCategory (authoringSpecs) dta)
	  isMouseOver = (bgClrReady == backgroundColor)
	  if isMouseOver { c = (lighter c 40) }
	  bm = (newBitmap (width morph) (21 * scale))
	  fillRect bm c 0 0 (width bm) ((height bm) - (2 * scale))
	  stringBM = (stringImage (localized dta) fontName fontSize (gray 255))
	  drawBitmap bm stringBM (19 * scale) (1 * scale)
	  return bm
	}
    return (itemCostume this (stringImage dta fontName fontSize foregroundColor) foregroundColor backgroundColor alpha 'id')
  } else {
    return (itemCostume this (toString dta) foregroundColor backgroundColor alpha 'id')
  }
}
