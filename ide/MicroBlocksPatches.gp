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
  if (notNil scripter) {
	varNames = (allVariableNames (project (handler scripter)))
	for varName varNames {
          // hide vars that start with underscore, used for libraries
          if (or ((at varName 1) != '_') (devMode)) {
            addItem menu varName (action 'setContents' this varName)
          }
	}
	if ((count varNames) > 0) { addLine menu }
  }

  // local vars
  myBlock = (handler (ownerThatIsA morph 'Block'))
  localVars = (collectLocals (expression (topBlock myBlock)))
  remove localVars ''
  for v varNames { remove localVars v }
  if (notEmpty localVars) {
	localVars = (sorted (keys localVars))
	for varName localVars {
	  addItem menu varName (action 'setContents' this varName)
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
		return true
	  } else {
		project = (project (findProjectEditor))
		choices = (choicesFor project menuSelector)
		if (notNil choices) {
		  menu = (menu nil (action 'setContents' this) true)
		  for choice choices {
			addItem menu choice
		  }
		  popUpAtHand menu (page aHand)
		}
	  }
    }
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

// List Menus

method itemOfMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu '1'
  addItem menu 'last'
  addItem menu 'random'
  return menu
}

method replaceItemMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu '1'
  addItem menu 'last'
  addItem menu 'all'
  return menu
}

// Translatable dropdown selections
method redraw Text {
  owner = (owner morph)
  if (notNil owner) {
	ownerHandler = (handler owner)
  }
  finalText = text
  if (and
		(notNil ownerHandler)
		(isClass ownerHandler 'InputSlot')
		(notNil (getField ownerHandler 'menuSelector'))
		((getField ownerHandler 'menuSelector') != 'allVarsMenu')
  ) {
	finalText = (localized text)
  }
  bm = (stringImage finalText fontName fontSize color alignment shadowColor shadowOffsetX shadowOffsetY borderX borderY bgColor minWidth minHeight isFlat)
  renderMarkedOn this bm
  setCostume morph bm true // keep former dimensions to enable editing inside scrolling panes
  if (and (notNil owner) (isClass (handler owner) 'ScrollFrame'))  {
    updateSliders (handler owner)
  } else {
    setWidth (bounds morph) (width bm)
    setHeight (bounds morph) (height bm)
  }
  if (notNil caret) {adjustSize caret}
  raise morph 'layoutChanged' this
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

to findMorph handlerClassName {
	page = (global 'page')
	if (notNil page) {
		for p (parts (morph page)) {
			if (isClass (handler p) handlerClassName) {
				return (morph (handler p))
			}
		}
	}
	return nil
}

to findProjectEditor {
  page = (global 'page')
  if (notNil page) {
	for p (parts (morph page)) {
	  if (isClass (handler p) 'MicroBlocksEditor') { return (handler p) }
	}
  }
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

method clicked Block hand {
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

method alternateOperators Block {
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
  return nil
}

method changeOperator Block newOp {
  setField expression 'primName' newOp
  // update the block (inefficient, but works):
  scripter = (scripter (findProjectEditor))
  saveScripts scripter
  restoreScripts scripter
}

method contextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
  pe = (findProjectEditor)

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
  if (and (not isInPalette) (notNil (next this))) {
    addItem menu 'extract block' 'pickUp' 'pull out this block'
  }
  addLine menu
  addItem menu 'copy to clipboard' (action 'copyToClipboard' (topBlock this) 'copy these blocks to the clipboard')
  addItem menu 'save picture of script' 'exportAsImage' 'save a picture of these blocks as a PNG file'
  if (not (isPrototypeHat (topBlock this))) {
	if (or ('reporter' == (type (topBlock this))) (devMode)) {
	  addItem menu 'save picture of script with result' 'exportAsImageWithResult' 'save a picture of these blocks and their result as a PNG file'
	}
  }
  addLine menu
  addItem menu 'delete block' 'delete' 'delete this block'

  if (devMode) {
	addLine menu
    addItem menu 'show instructions' (action 'showInstructions' (smallRuntime) this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' (smallRuntime) this)

	// xxx internal testing only; remove later!:
	if (contains (commandLine) '--allowMorphMenu') {
		addItem menu 'test decompiler' (action 'testDecompiler' (smallRuntime) this) // xxx
	}
  }
  if (notNil (functionNamed (project pe) (primName expression))) {
    addLine menu
    addItem menu 'show block definition...' 'showDefinition' 'show the definition of this block'
	if isInPalette {
	  addLine menu
	  addItem menu 'delete block definition...' 'deleteBlockDefinition' 'delete the definition of this block'
	}
  }
  alternativeOps = (alternateOperators this)
  if (and (not isInPalette) (notNil alternativeOps)) {
	addLine menu
	myOp = (primName expression)
	for op alternativeOps {
	  // create and display block morph (with translated spec)
	  spec = (specForOp (authoringSpecs) op)
	  if (and (notNil spec) (op != myOp)) {
		b = (blockForSpec spec)
		addItem menu (fullCostume (morph b)) (action 'changeOperator' this op)
	  }
	}
  }
  return menu
}

method pickUp Block {
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
        fixBlockColor nxt
      }
    }
  }
  grabCentered morph this
}

method exportAsImage Block { exportScriptAsImage (smallRuntime) (topBlock this) }
method exportAsImageWithResult Block { exportScriptImageWithResult (smallRuntime) this }

method exportAsImage BlockDefinition {
  exportScriptAsImage (smallRuntime) (handler (ownerThatIsA morph 'Block'))
}

// Block definition operations

method showDefinition Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }
  showDefinition (scripter pe) (primName expression)
}

method deleteBlockDefinition Block {
  if (not (confirm (global 'page') nil
  	'Are you sure you want to remove this block definition?')) {
		return
  }
  pe = (findProjectEditor)
  if (isNil pe) { return }
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

method justReceivedDrop BlocksPalette aHandler {
  // Hide a block definitions when it is is dropped on the palette.

  pe = (findProjectEditor)
  if (and (isClass aHandler 'Block') (isPrototypeHat aHandler)) {
	proto = (editedPrototype aHandler)
	if (and (notNil pe) (notNil proto) (notNil (function proto))) {
		hideDefinition (scripter pe) op
		return
	}
  }
  if (and (isClass aHandler 'Block') (notNil pe)) {
	recordDrop (scriptEditor (scripter pe)) aHandler
  }
  removeFromOwner (morph aHandler)
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
  addItem menu 'save picture of script' 'exportAsImage' 'save a picture of this block definition as a PNG file'
  if (devMode) {
    addLine menu
    addItem menu 'show instructions' (action 'showInstructions' this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' this)
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
  if (global 'stealthBlocks') {
    labelColor = (gray (stealthLevel 255 0))
  } else {
    labelColor = (global 'blockTextColor')
    if (isNil labelColor) { labelColor = (gray 255) }
  }
  txt = (newText 'repeat last section:' 'Arial' (10 * scale) labelColor)
  addPart (morph repeater) (morph txt)

  corner = 5
  toggle = (toggleButton (action 'toggleRepeat' this) (action 'isRepeating' this) (scale * 20) (scale * 13) (scale * corner) (max 1 (scale / 2)) false false)
  addPart (morph repeater) (morph toggle)
}

method contextMenu ScriptEditor {
  menu = (menu nil this)
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  if (and (notNil lastDrop) (isRestorable lastDrop)) {
    addItem menu 'undrop  (ctrl-Z)' 'undrop' 'undo the last block drop'
  }
  addLine menu
  addItem menu 'copy all scripts to clipboard' 'copyScriptsToClipboard'
  clip = (readClipboard)
  if (beginsWith clip 'GP Scripts') {
	addItem menu 'paste all scripts from clipboard' 'pasteScripts'
  } (beginsWith clip 'GP Script') {
	addItem menu 'paste script from clipboard' 'pasteScripts'
  }
  addLine menu
  addItem menu 'save a picture of all scripts' 'saveScriptsImage'
  return menu
}

method copyScriptsToClipboard ScriptEditor {
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (isNil scripter) { return }
  setClipboard (join 'GP Scripts' (newline) (allScriptsString (handler scripter)))
}

// Block layout tweak

method fixLayout Block {
  space = 3
  vSpace = 3

  break = 450
  lineHeights = (list)
  lines = (list)
  lineArgCount = 0

  left = (left morph)
  blockWidth = 0
  blockHeight = 0
  h = 0
  w = 0

  if (global 'stealthBlocks') {
    if (type == 'hat') {
      indentation = (stealthLevel (* scale (+ border space)) 0)
    } (type == 'reporter') {
      indentation = (stealthLevel (* scale rounding) (width (stealthText this '(')))
    } (type == 'command') {
      indentation = (stealthLevel (* scale (+ border inset dent (corner * 2))) 0)
    }
  } else {
    if (type == 'hat') {
      indentation = (* scale (+ border space))
    } (type == 'reporter') {
      indentation = (* scale rounding)
    } (type == 'command') {
      indentation = (* scale (+ border inset dent (corner * 2)))
    }
  }

  // arrange label parts horizontally and break up into lines
  breakLineBeforeFirstArg = ((count (argList expression)) >= 5)
  currentLine = (list)
  for group labelParts {
    for each group {
      if (isVisible (morph each)) {
        if (isClass each 'CommandSlot') {
          add lines currentLine
          add lineHeights h
          setLeft (morph each) (+ left (* scale (+ border corner)))
          add lines (list each)
          add lineHeights (height (morph each))
          currentLine = (list)
          w = 0
          h = 0
        } else {
          x = (+ left indentation w)
          w += (width (fullBounds (morph each)))
          w += (space * scale)
          if (and breakLineBeforeFirstArg (not (isClass each 'Text'))) {
			breakLineBeforeFirstArg = false // only do this once
 			lineArgCount = 10 // force a line break before first arg for blocks with >=5 args
         }
		  if (and ('[display:mbDisplay]' == (primName expression)) (each == (first group))) {
			lineArgCount = 10 // force a line break after first item of block
		  }
		  if (and (or (w > (break * scale)) (lineArgCount >= 5)) (notEmpty currentLine)) {
			add lines currentLine
			add lineHeights h
			currentLine = (list)
			h = 0
			x = (+ left indentation)
			w = ((width (fullBounds (morph each))) + (space * scale))
			lineArgCount = 0
          }
          add currentLine each
          h = (max h (height (morph each)))
          setLeft (morph each) x
		  if (not (isClass each 'Text')) { lineArgCount += 1 }
        }
      }
    }
  }

  // add the block drawer, if any
  drawer = (drawer this)
  if (notNil drawer) {
    x = (+ left indentation w)
    w += (width (fullBounds (morph drawer)))
    w += (space * scale)
    if (and (w > (break * scale)) (notEmpty currentLine)) {
      add lines currentLine
      add lineHeights h
      currentLine = (list)
      h = 0
      x = (+ left indentation)
      w = ((width (fullBounds (morph drawer))) + (space * scale))
    }
    add currentLine drawer
    h = (max h (height (morph drawer)))
    setLeft (morph drawer) x
  }

  // add last label line
  add lines currentLine
  add lineHeights h

  // purge empty lines
  // to do: prevent empty lines from being added in the first place
  for i (count lines) {
    if (isEmpty (at lines i)) {
      removeAt lines i
      removeAt lineHeights i
    }
  }

  // determine block dimensions from line data
  blockWidth = 0
  for each lines {
    if (notEmpty each) {
      elem = (last each)
      if (not (isClass elem 'CommandSlot')) {
        blockWidth = (max blockWidth ((right (fullBounds (morph elem))) - left))
      }
    }
  }
  blockWidth = (- blockWidth (space * scale))
  blockHeight = (callWith + (toArray lineHeights))
  blockHeight += (* (count lines) vSpace scale)

  // arrange label parts vertically
  if (global 'stealthBlocks') {
    tp = (+ (top morph) (stealthLevel (* 2 scale border) 0))
  } else {
    tp =  (+ (top morph) (* 2 scale border))
  }
  if (type == 'hat') {
    tp += (hatHeight this)
  }
  line = 0
  for eachLine lines {
    line += 1
    bottom = (+ tp (at lineHeights line) (vSpace * scale))
    for each eachLine {
      setYCenterWithin (morph each) tp bottom
    }
    tp = bottom
  }

  // add extra space below the bottom-most c-slot
  extraSpace = 0
  if (and (isNil drawer) (isClass (last (last labelParts)) 'CommandSlot')) {
    extraSpace = (scale * corner)
  }

  // set block dimensions
  blockWidth += (* -1 scale space)
  blockWidth += (* scale border)

  if (global 'stealthBlocks') {
    if (type == 'command') {
      setWidth (bounds morph) (+ blockWidth indentation (stealthLevel (scale * corner) 0))
      setHeight (bounds morph) (stealthLevel (+ blockHeight (* scale corner) (* scale border 4) extraSpace) blockHeight)
    } (type == 'hat') {
      setWidth (bounds morph) (max (scale * (+ hatWidth 20)) (+ blockWidth indentation (stealthLevel (scale * corner) 0)))
      setHeight (bounds morph) (stealthLevel (+ blockHeight (* scale corner 2) (* scale border) (hatHeight this) extraSpace) (+ blockHeight (hatHeight this)))
    } (type == 'reporter') {
      setWidth (bounds morph) (+ blockWidth (2 * indentation) (stealthLevel (scale * rounding) 0))
      setHeight (bounds morph) (stealthLevel (+ blockHeight (* scale border 4) extraSpace) blockHeight)
    }
  } else {
    if (type == 'command') {
      setWidth (bounds morph) (max (scale * 50) (+ blockWidth indentation (scale * corner)))
      setHeight (bounds morph) (+ blockHeight (* scale corner) (* scale border 4) extraSpace)
    } (type == 'hat') {
      setWidth (bounds morph) (max (scale * (+ hatWidth 20)) (+ blockWidth indentation (scale * corner)))
      setHeight (bounds morph) (+ blockHeight (* scale corner 2) (* scale border) (hatHeight this) extraSpace)
    } (type == 'reporter') {
      setWidth (bounds morph) (max (scale * 20) (+ blockWidth indentation (scale * rounding)))
      setHeight (bounds morph) (+ blockHeight (* scale border 4) extraSpace)
    }
  }

  for group labelParts {
    for each group {
      if (isClass each 'CommandSlot') {fixLayout each true}
    }
  }
  if ((localized 'RTL') == 'true') { fixLayoutRTL this }
  redraw this
  nb = (next this)
  if (notNil nb) {
    setPosition (morph nb) (left morph) (- (+ (top morph) (height morph)) (scale * corner))
  }
  raise morph 'layoutChanged' this
}

//Right-to-Left Support
method fixLayoutRTL Block {
	block_width = (width morph)
	block_left = (left (fullBounds morph ))
	drawer = (drawer this)
	if (notNil drawer) {
		block_width = (block_width - (width (fullBounds (morph drawer))))
		block_width = (block_width - (3 * scale))
	}

	for group labelParts {
		for each group {
			if (isVisible (morph each)) {
				word_left = ((left (fullBounds (morph each))) - block_left)
				w = (width (fullBounds (morph each)))
				if (not (isClass each 'CommandSlot')) {
					setLeft (morph each) (block_left + ((block_width - word_left) - w ))
				}
			}
		}
	}
}

// Make ColorSlots be round

method redraw ColorSlot {
  scale = (global 'scale')
  border = (1 * scale)
  center = (9 * scale)
  radius = (center - 1)
  size = (2 * center)
  bm = (costume morph)
  bm = nil
  if (isNil bm) { bm = (newBitmap size size) }
  fill bm (gray 0 0)
  drawCircle (newShapeMaker bm) center center radius contents border (gray 0)
  setCostume morph bm
}

// Color picker tweaks

to newColorPicker action initialColor {
  // If there is already a ColorPicker on the screen, return it.
  // Otherwise, create and return a new one.

  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'ColorPicker') {
	  setAction (handler m) action
	  return (handler m)
	}
  }
  return (initialize (new 'ColorPicker') action initialColor)
}

method addTransparentButton ColorPicker x y { } // don't add a transparent button
method setAction ColorPicker anAction { action = anAction }

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

method normalCostume ListBox data accessor {
  scale = (global 'scale')
  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'String') {
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
	  if isMouseOver { c = (shiftSaturation (lighter c 20) -30) }
	  bm = (newBitmap ((width morph) + (20 * scale)) (21 * scale))
	  fillRect bm c 0 0 (width bm) ((height bm) - (2 * scale))
	  stringBM = (stringImage (localized dta) fontName fontSize (gray 255))
	  drawBitmap bm stringBM (29 * scale) (1 * scale)
	  return bm
	}
    return (itemCostume this (stringImage dta fontName fontSize foregroundColor) foregroundColor backgroundColor alpha 'id')
  } else {
    return (itemCostume this (toString dta) foregroundColor backgroundColor alpha 'id')
  }
}

method processEvent Keyboard evt {
  type = (at evt 'type')
  key = (at evt 'keycode')
  updateModifiedKeys this (at evt 'modifierKeys')
  if (and (1 <= key) (key <= 255)) {
	if (type == 'keyUp') {
	  atPut currentKeys key false
	} (type == 'keyDown') {
		// Arrow key navigation in scrollable morph under mouse pointer
	  if (and (key >= 37) (key <= 40) (isNil focus)) {
		morph = (ownerThatIsA (morph (objectAt (hand (global 'page')))) 'ScrollFrame')
		if (notNil morph) {
			if (37 === key) { // left arrow
				swipe (handler morph) 1 0
			} (38 === key) { // up arrow
				swipe (handler morph) 0 1
			} (39 === key) { // right arrow
				swipe (handler morph) -1 0
			} (40 === key) { // down arrow
				swipe (handler morph) 0 -1
			}
		}
	  }

	  if (at currentKeys key) { return } // suppress duplicated keyDown events on Gnome and some other Linux desktops
	  atPut currentKeys key true

	  if (isNil focus) {
		if (27 == key) { // escape key
			if (notNil (flasher (smallRuntime))) {
				confirmRemoveFlasher (smallRuntime)
			} (not (decompilerDone (smallRuntime))) {
				stopDecompilation (smallRuntime)
			} (notNil (findMorph 'MicroBlocksFilePicker')) {
				destroy (findMorph 'MicroBlocksFilePicker')
			} (notNil (findMorph 'Prompter')) {
				cancel (handler (findMorph 'Prompter'))
			} else {
				stopAndSyncScripts (smallRuntime)
			}
		} (13 == key) { // enter key
			if (notNil (findMorph 'Prompter')) {
				accept (handler (findMorph 'Prompter'))
			}
		}
		if (and (111 == (at evt 'char')) (or (controlKeyDown this) (commandKeyDown this))) {
			// cmd-O or ctrl-O - open file dialog
			(openProjectMenu (findProjectEditor))
		}
		if (and (115 == (at evt 'char')) (or (controlKeyDown this) (commandKeyDown this))) {
			// cmd-S or ctrl-S - save file dialog
			(saveProjectToFile (findProjectEditor))
		}
		if (and (122 == (at evt 'char'))
			(or (controlKeyDown this) (commandKeyDown this))
			(isNil (grabbedObject (hand (global 'page'))))) {
				// cmd-Z or ctrl-Z - undo last drop
				pe = (findProjectEditor)
				if (notNil pe) { undrop (scriptEditor (scripter pe)) }
		}
	  }
	}
  }
  if (notNil focus) {
	call type focus evt this
  }
}

// "say" block formatting

method initialize SpeechBubble someData bubbleWidth dir isErrorFlag {
  scale = (global 'scale')
  font = 'Arial'
  fontSize = (18 * scale)
  if ('Linux' == (platform)) { fontSize = (13 * scale) }
  maxLines = 30
  shadowOffset = 3 // optional; if nil, no shadow is drawn

  if (isNil someData) {someData = 'hint!'}
  if (isNil bubbleWidth) {bubbleWidth = (175 * scale) }
  if (isNil dir) {dir = 'right'}
  direction = dir
  isError = false
  if (true == isErrorFlag) { isError = true }

  setFont font fontSize
  if (isClass someData 'Boolean') {
    contents = (newBooleanSlot someData)
  } else {
    someData = (toString someData)
    lines = (toList (wordWrapped someData bubbleWidth))
    if ((count lines) > maxLines) {
      lines = (copyFromTo lines 1 maxLines)
      add lines '...'
    }
    contents = (newText (joinStrings lines (newline)) font fontSize (gray 0) 'center')
  }

  morph = (newMorph this)
  addPart morph (morph contents)
  fixLayout this
  return this
}

// Increase font size in confirm dialogs

method initializeForConfirm Prompter label question yesLabel noLabel anAction {
  answer = false
  isDone = false
  if (isNil label) {label = 'Confirm'}
  if (isNil question) {question = ''}
  if (isNil yesLabel) {yesLabel = 'Yes'}
  if (isNil noLabel) {noLabel = 'No'}
  callback = anAction // optional

  window = (window (localized label))
  hide (morph (getField window 'resizer'))
  border = (border window)
  morph = (morph window)
  setHandler morph this

  lbl = (getField window 'label')
  fontSize = (16 * (global 'scale'))
  if ('Linux' == (platform)) { fontSize = (13 * (global 'scale')) }
  textFrame = (newText (localized question) (fontName lbl) fontSize (gray 0) 'center')
  addPart morph (morph textFrame)
  createButtons this (localized yesLabel) (localized noLabel)

  textWidth = (width (morph textFrame))
  buttonWidth = (width buttons)
  labelWidth = (width (morph lbl))
  xBtnWidth = (width (morph (getField window 'closeBtn')))
  w = (max textWidth buttonWidth labelWidth)
  setExtent morph (+ w xBtnWidth (4 * border)) (+ (height (morph lbl)) (height (morph textFrame)) (height (bounds buttons)) (8 * border))
  setMinExtent morph (width morph) (height morph)
}
