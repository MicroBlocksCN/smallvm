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
    'https://microblocks.fun/run/microblocks.html#scripts='
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
