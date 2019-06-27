// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksScripter.gp - MicroBlocks script editor w/ built-in palette

defineClass MicroBlocksScripter morph mbProject projectEditor saveNeeded categoriesFrame catResizer libHeader libFrame blocksFrame blocksResizer scriptsFrame nextX nextY

method blockPalette MicroBlocksScripter { return (contents blocksFrame) }
method scriptEditor MicroBlocksScripter { return (contents scriptsFrame) }
method project MicroBlocksScripter { return mbProject }
method thingServer MicroBlocksScripter { return (thingServer projectEditor) }

// initialization

method initialize MicroBlocksScripter aProjectEditor {
  mbProject = (newMicroBlocksProject)
  projectEditor = aProjectEditor
  scale = (global 'scale')
  morph = (newMorph this)
  setCostume morph (gray 150) // border color
  listColor = (gray 240)
  fontName = 'Arial Bold'
  fontSize = 16
  if ('Linux' == (platform)) {
	fontName = 'Liberation Sans Bold'
	fontSize = 13
  }
  nextX = 0
  nextY = 0

  // how often to check for script changes
  setFPS morph 4
  saveNeeded = false

  makeLibraryHeader this

  lbox = (listBox (categories this) nil (action 'categorySelected' this) listColor)
  setFont lbox fontName fontSize
  categoriesFrame = (scrollFrame lbox listColor true)
  addPart morph (morph categoriesFrame)

  lbox = (listBox (array) nil (action 'librarySelected' this) listColor)
  setFont lbox fontName fontSize
  libFrame = (scrollFrame lbox listColor true)
  addPart morph (morph libFrame)

  blocksPane = (newBlocksPalette)
  setSortingOrder (alignment blocksPane) nil
  setPadding (alignment blocksPane) (15 * scale) // inter-column space
  setFramePadding (alignment blocksPane) (10 * scale) (10 * scale)
  blocksFrame = (scrollFrame blocksPane (gray 220))
  setExtent (morph blocksFrame) (235 * scale) (100 * scale)
  setAutoScroll blocksFrame false
  addPart morph (morph blocksFrame)

  scriptsPane = (newScriptEditor 10 10 nil)
  scriptsFrame = (scrollFrame scriptsPane (gray 220))
  addPart morph (morph scriptsFrame)

  // add resizers last so they are in front
  catResizer = (resizeHandle categoriesFrame 'horizontal')
  addPart morph (morph catResizer)

  blocksResizer = (resizeHandle blocksFrame 'horizontal')
  addPart morph (morph blocksResizer)

  setGrabRule morph 'ignore'
  for m (parts morph) { setGrabRule m 'ignore' }

  setMinExtent morph (scale * 235) (scale * 200)
  setExtent morph (scale * 600) (scale * 700)
  restoreScripts this

  smallRuntime this // create a SmallRuntime instance
  if (isNil projectEditor) { select (contents categoriesFrame) 'Control' }
  return this
}

method languageChanged MicroBlocksScripter {
  updateLibraryHeader this

  // update categories and library names
  updateMorphContents (handler (first (parts (morph categoriesFrame))))
  updateMorphContents (handler (first (parts (morph libFrame))))

  // update the scripts
  updateBlocks this
  saveScripts this
  restoreScripts this
}

// library header

method makeLibraryHeader MicroBlocksScripter {
  scale = (global 'scale')
  libHeader = (newBox (newMorph) (colorHSV 180 0.045 1.0) 0 0)

  label = (newText (localized 'Libraries') 'Arial' (18 * scale) (gray 30))
  if ('Linux' == (platform)) {
	label = (newText (localized 'Libraries') 'Liberation Sans' (15 * scale) (gray 30))
  }
  setPosition (morph label) (6 * scale) (6 * scale)
  addPart (morph libHeader) (morph label)

  libAddButton = (addLibraryButton this '+' (33 * scale) (33 * scale))
  setPosition (morph libAddButton) (82 * scale) 0
  addPart (morph libHeader) (morph libAddButton)
  addPart morph (morph libHeader)
  return libHeader
}

method updateLibraryHeader MicroBlocksScripter {
  labelM = (first (parts (morph libHeader)))
  setText (handler labelM) (localized 'Libraries')
}

method fixLibraryHeaderLayout MicroBlocksScripter {
  buttonM = (last (parts (morph libHeader)))
  setRight buttonM (right (owner buttonM))
}

method addLibraryButton MicroBlocksScripter label w h {
  scale = (global 'scale')
  setFont 'Arial Bold' (24 * scale)
  halfW = (1.5 * scale)
  lineW = (2 * halfW)
  halfLen = (7 * scale)
  len = (2 * halfLen)
  centerX = (toInteger (w / 2))
  centerY = (toInteger (h / 2))

  labelY = (6 * scale)
  bm1 = (newBitmap w h (topBarBlue projectEditor))
  fillRect bm1 (gray 60) (centerX - halfLen) (centerY - halfW) len lineW
  fillRect bm1 (gray 60) (centerX - halfW) (centerY - halfLen) lineW len

  bm2 = (newBitmap w h (topBarBlueHighlight projectEditor))
  fillRect bm2 (gray 30) (centerX - halfLen) (centerY - halfW) len lineW
  fillRect bm2 (gray 30) (centerX - halfW) (centerY - halfLen) lineW len

  button = (newButton '' (action 'importLibrary' projectEditor))
  setCostumes button bm1 bm2
  return button
}

// library item menu

method handleListContextRequest MicroBlocksScripter anArray {
  if ((first anArray) != (contents libFrame)) { return } // not a library list entry; ignore
  libName = (data (last anArray))
  menu = (menu)
  if (devMode) {
	addItem menu 'show all block definitions' (action 'showAllLibraryDefinitions' this libName)
	addItem menu 'export this library' (action 'exportLibrary' this libName)
	addLine menu
  }
  addItem menu 'delete library' (action 'removeLibraryNamed' this libName)
  popUpAtHand menu (global 'page')
}

method removeLibraryNamed MicroBlocksScripter libName {
  removeLibraryNamed mbProject libName
  updateLibraryList this
}

method showAllLibraryDefinitions MicroBlocksScripter libName {
  lib = (libraryNamed mbProject libName)
  if (isNil lib) { return }
  for f (functions lib) {
	showDefinition this (functionName f)
  }
}

method exportLibrary MicroBlocksScripter libName {
  lib = (libraryNamed mbProject libName)
  if (isNil lib) { return }
  fName = (fileToWrite (moduleName lib) (array '.ubl'))
  if ('' == fName) { return false }
  if (not (endsWith fName '.ubl' )) { fName = (join fName '.ubl') }
  writeFile fName (codeString lib mbProject)
}

// layout

method redraw MicroBlocksScripter {
  fixLayout this
}

method fixLayout MicroBlocksScripter {
  scale = (global 'scale')
  catWidth = (max (toInteger ((width (morph categoriesFrame)) / scale)) 130)
  blocksWidth = (max (toInteger ((width (morph blocksFrame)) / scale)) 130)
  catHeight = (((height (morph (contents categoriesFrame))) / scale) + 4)
  columnHeaderHeight = 33

  packer = (newPanePacker (bounds morph) scale scale)
  packPanesH packer blocksFrame blocksWidth scriptsFrame '100%'
  packPanesH packer categoriesFrame catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesH packer libHeader catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesH packer libFrame catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesV packer categoriesFrame catHeight libHeader columnHeaderHeight libFrame '100%'
  packPanesV packer blocksFrame '100%'
  packPanesV packer scriptsFrame '100%'
  finishPacking packer

  fixResizerLayout this
  fixLibraryHeaderLayout this

  if (notNil projectEditor) { fixLayout projectEditor true }
}

method fixResizerLayout MicroBlocksScripter {
  resizerWidth = (10 * (global 'scale'))

  // categories pane resizer
  setLeft (morph catResizer) (right (morph categoriesFrame))
  setTop (morph catResizer) (top morph)
  setExtent (morph catResizer) resizerWidth (height morph)
  drawPaneResizingCostumes catResizer

  // blocks pane resizer
  setLeft (morph blocksResizer) (right (morph blocksFrame))
  setTop (morph blocksResizer) (top morph)
  setExtent (morph blocksResizer) resizerWidth (height morph)
  drawPaneResizingCostumes blocksResizer
}

// MicroBlocksScripter UI support

method developerModeChanged MicroBlocksScripter {
  catList = (contents categoriesFrame)
  setCollection catList (categories this)
  if (not (or (contains (collection catList) (selection catList))
  			  (notNil (selection (contents libFrame))))) {
    select catList 'Output'
  } else {
    updateBlocks this
  }
}

method categories MicroBlocksScripter {
  initMicroBlocksSpecs (new 'SmallCompiler')
  result = (list 'Output' 'Input' 'Pins' 'Comm' 'Control' 'Math' 'Variables' 'Lists' 'My Blocks')
  if (not (devMode)) {
  	removeAll result (list 'Comm' 'Lists')
  }
  return result
}

method selectCategory MicroBlocksScripter aCategory {
  select (contents categoriesFrame) aCategory
}

method currentCategory MicroBlocksScripter {
  return (selection (contents categoriesFrame))
}

method categorySelected MicroBlocksScripter {
   select (contents libFrame) nil // deselect library
   updateBlocks this
}

method librarySelected MicroBlocksScripter {
   select (contents categoriesFrame) nil // deselect category
   updateBlocks this
}

method updateBlocks MicroBlocksScripter {
  scale = (global 'scale')
  blocksPane = (contents blocksFrame)
  removeAllParts (morph blocksPane)
  setRule (alignment blocksPane) 'none'

  nextX = ((left (morph (contents blocksFrame))) + (16 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (16 * scale))

  cat = (selection (contents categoriesFrame))
  if (isNil cat) {
	addBlocksForLibrary this (selection (contents libFrame))
  } ('Variables' == cat) {
	addVariableBlocks this
  } ('My Blocks' == cat) {
    addMyBlocks this
  } else {
	addBlocksForCategory this cat
  }
  cleanUp blocksPane
}

method addBlocksForCategory MicroBlocksScripter cat {
  addBlocksForSpecs this (specsFor (authoringSpecs) cat)
  advancedSpecs = (specsFor (authoringSpecs) (join cat '-Advanced'))
  if (and (devMode) (not (isEmpty advancedSpecs))) {
	addSectionLabel this 'Advanced:'
	addBlocksForSpecs this advancedSpecs
  }
}

method addBlocksForSpecs MicroBlocksScripter specList {
  for spec specList {
	if ('-' == spec) {
	  // add some vertical space
	   nextY += (20 * (global 'scale'))
	} else {
	  addBlock this (blockForSpec spec) spec
	}
  }
}

method addBlocksForLibrary MicroBlocksScripter libName {
  if (isNil libName) { return }
  lib = (at (libraries mbProject) libName)
  if (isNil lib) { return }

  for op (blockList lib) {
	if ('-' == op) {
	  // add some vertical space
	   nextY += (20 * (global 'scale'))
	} (or (devMode) (not (beginsWith op '_'))) {
	  spec = (specForOp (authoringSpecs) op)
	  if (notNil spec) {
	  	addBlock this (blockForSpec spec) spec
	  }
	}
  }
}

method addVariableBlocks MicroBlocksScripter {
  scale = (global 'scale')

  addButton this (localized 'Add a variable') (action 'createVariable' this) 'Create a global variable (i.e. visible in all scripts).'
  visibleVars = (visibleVars this)
  if (notEmpty visibleVars) {
	addButton this (localized 'Delete a variable') (action 'deleteVariableMenu' this)
	nextY += (8 * scale)
	for varName visibleVars {
	    lastY = nextY
	    b = (toBlock (newReporter 'v' varName))
	    addBlock this b nil // true xxx
//	    readout = (makeMonitor b)
// 	    setGrabRule (morph readout) 'ignore'
// 	    setStyle readout 'varPane'
// 	    setPosition (morph readout) nextX lastY
// 	    addPart (morph (contents blocksFrame)) (morph readout)
// 	    step readout
	}
	nextY += (5 * scale)
  }

  nextY += (10 * scale)
  addBlock this (toBlock (newCommand 'local' 'var' 0)) nil false
  addBlock this (toBlock (newCommand '=' 'var' 0)) nil false
  addBlock this (toBlock (newCommand '+=' 'var' 1)) nil false
}

method addMyBlocks MicroBlocksScripter {
  scale = (global 'scale')

  addButton this (localized 'Add a command') (action 'createFunction' this false)
  addButton this (localized 'Add a reporter') (action 'createFunction' this true)
  nextY += (8 * scale)

  for f (functions (main mbProject)) {
	if (or (devMode) (not (beginsWith (functionName f) '_'))) {
	  spec = (specForOp (authoringSpecs) (functionName f))
	  if (isNil spec) { spec = (blockSpecFor f) }
	  addBlock this (blockForSpec spec) spec
	}
  }
}

method addButton MicroBlocksScripter label action hint {
  btn = (pushButton label (gray 130) action 120 30)
  if (notNil hint) { setHint btn hint }
  setPosition (morph btn) nextX nextY
  addPart (morph (contents blocksFrame)) (morph btn)
  nextY += ((height (morph btn)) + (7 * (global 'scale')))
}

method addBlock MicroBlocksScripter b spec isVarReporter {
  // install a 'morph' variable reporter for any slot that has 'morph' or 'Morph' as a hint

  if (isNil spec) { spec = (blockSpec b) }
  if (isNil isVarReporter) { isVarReporter = false }
  scale = (global 'scale')
  if (notNil spec) {
	inputs = (inputs b)
	for i (slotCount spec) {
	  hint = (hintAt spec i)
	  if (and (isClass hint 'String') (endsWith hint 'orph')) {
		replaceInput b (at inputs i) (toBlock (newReporter 'v' 'morph'))
	  }
	  if ('page' == hint) {
		replaceInput b (at inputs i) (toBlock (newReporter 'v' 'page'))
	  }
	}
  }
  setGrabRule (morph b) 'template'
  setPosition (morph b) nextX nextY
  if isVarReporter { setLeft (morph b) (nextX + (135 * scale)) }
  addPart (morph (contents blocksFrame)) (morph b)
  nextY += ((height (morph b)) + (4 * (global 'scale')))
}

// Palette Section Labels

method addSectionLabel MicroBlocksScripter label {
  scale = (global 'scale')
  labelColor = (gray 80)
  fontSize = (14 * scale)
  label = (newText label 'Arial Bold' fontSize labelColor)
  nextY += (12 * scale)
  setPosition (morph label) (nextX - (10 * scale)) nextY
  addPart (morph (contents blocksFrame)) (morph label)
  nextY += ((height (morph label)) + (12 * scale))
}

// project creation and loading

method createEmptyProject MicroBlocksScripter {
  mbProject = (newMicroBlocksProject)
  if (notNil scriptsFrame) {
	removeAllParts (morph (contents scriptsFrame))
	restoreScripts this
	saveScripts this
  }
}

method loadOldProjectFromClass MicroBlocksScripter aClass specs {
  // Load an old-style (GP-format) MicroBlocks project from the given class and spec list.

  mbProject = (newMicroBlocksProject)
  if (notNil aClass) {
	loadFromOldProjectClassAndSpecs mbProject aClass specs
  }
  restoreScripts this
}

method loadNewProjectFromData MicroBlocksScripter aString {
  // Load an new-style MicroBlocks project from the given string.

  mbProject = (newMicroBlocksProject)
  loadFromString mbProject aString
  restoreScripts this
}

// variable operations

method visibleVars MicroBlocksScripter {
  // Include vars that start with underscore only in dev mode.

  allVars = (allVariableNames mbProject)
  if (devMode) {
    return allVars
  } else {
    return (filter
      (function each { return (not (beginsWith each '_')) })
      allVars)
  }
}

method createVariable MicroBlocksScripter {
  varName = (prompt (global 'page') 'New variable name?' '')
  if (varName != '') {
	addVariable (main mbProject) (uniqueVarName this varName)
	saveVariableNames (smallRuntime)
	updateBlocks this
  }
}

method uniqueVarName MicroBlocksScripter varName forScriptVar {
  // If varName matches global variable, return a unique variant of it.
  // Otherwise, return varName unchanged.

  if (isNil forScriptVar) { forScriptVar = false }
  existingVars = (toList (allVariableNames mbProject))
  scripts = (scripts (main mbProject))
  if (and (notNil scripts) (not forScriptVar)) {
	for entry scripts {
	  for b (allBlocks (at entry 3)) {
		if (isOneOf (primName b) 'v' '=' '+=' 'local' 'for') {
		  add existingVars (first (argList b))
		}
	  }
	}
  }
  return (uniqueNameNotIn existingVars varName)
}

method deleteVariableMenu MicroBlocksScripter {
  if (isEmpty (visibleVars this)) { return }
  menu = (menu nil (action 'deleteVariable' this) true)
  for v (visibleVars this) {
    addItem menu v
  }
  popUpAtHand menu (global 'page')
}

method deleteVariable MicroBlocksScripter varName {
  deleteVariable (main mbProject) varName
  clearVariableNames (smallRuntime)
  updateBlocks this
}

// save and restore scripts in class

method scriptChanged MicroBlocksScripter { saveNeeded = true }
method functionBodyChanged  MicroBlocksScripter { saveNeeded = true }

method step MicroBlocksScripter {
  // Note: Sometimes get bursts of multiple 'changed' events, but those
  // events merely set the saveNeeded flag. This method does the actual
  // saveScripts if the saveNeeded flag is true.

  if saveNeeded {
    saveScripts this
	syncScripts (smallRuntime)
    saveNeeded = false
  }
}

method saveScripts MicroBlocksScripter {
  scale = (global 'scale')
  scriptsPane = (contents scriptsFrame)
  paneX = (left (morph scriptsPane))
  paneY = (top (morph scriptsPane))
  scriptsCopy = (list)
  for m (parts (morph scriptsPane)) {
    if (isClass (handler m) 'Block') {
      x = (((left m) - paneX) / scale)
      y = (((top m) - paneY) / scale)
      script = (expression (handler m) 'main')
      if ('to' == (primName script)) {
        updateFunctionOrMethod this script
        args = (argList script)
        // only store the stub for a function in scripts
		script = (newCommand (primName script) (first args))
      }
      add scriptsCopy (array x y script)
    }
  }
  setScripts (main mbProject) scriptsCopy
}

method updateFunctionOrMethod MicroBlocksScripter script {
  args = (argList script)
  functionName = (first args)
  newCmdList = (last args)
  if ('to' == (primName script)) {
    f = (functionNamed mbProject functionName)
  }
  if (notNil f) { updateCmdList f newCmdList }
}

method restoreScripts MicroBlocksScripter {
  scale = (global 'scale')
  scriptsPane = (contents scriptsFrame)
  removeAllParts (morph scriptsPane)
  clearDropHistory scriptsPane
  updateSliders scriptsFrame
  scripts = (scripts (main mbProject))
  if (notNil scripts) {
    paneX = (left (morph scriptsPane))
    paneY = (top (morph scriptsPane))
    for entry (reversed scripts) {
      dta = (last entry)
      if ('to' == (primName dta)) {
        func = (functionNamed mbProject (first (argList dta)))
        if (notNil func) {
		  block = (scriptForFunction func)
		} else {
		  // can arise when viewing a class from an imported module; just skip it for now
		  block = nil
		}
      } else {
        block = (toBlock dta)
      }
      if (notNil block) {
		x = (paneX + ((at entry 1) * scale))
		y = (paneY + ((at entry 2) * scale))
		moveBy (morph block) x y
		addPart (morph scriptsPane) (morph block)
		fixBlockColor block
	  }
    }
  }
  updateSliders scriptsFrame
  updateBlocks this
}

method pasteScripts MicroBlocksScripter scriptString {
  scale = (global 'scale')
  scriptsPane = (contents scriptsFrame)
  clearDropHistory scriptsPane
  scripts = (parse scriptString)
  if (notNil scripts) {
	hand = (hand (global 'page'))
    x = (x hand)
    y = ((y hand) - (40 * scale)) // adjust for menu offset
    for entry scripts {
      if ('script' == (primName entry)) {
		script = (last (argList entry))
		if ('to' == (primName script)) {
		  cmd = (copyFunction this script nil)
		  block = (scriptForFunction (functionNamed mbProject (first (argList cmd))))
		} else {
		  block = (toBlock script)
		}
		moveBy (morph block) x y
		y += ((height (fullBounds (morph block))) + (10 * scale))
		addPart (morph scriptsPane) (morph block)
		fixBlockColor block
      }
    }
    scriptChanged this
  }
  updateSliders scriptsFrame
  updateBlocks this
}

// hide/show block definition

method hideDefinition MicroBlocksScripter funcName {
  // Hide the given method/function definition.

  saveScripts this
  newScripts = (list)
  for entry (scripts (main mbProject)) {
	cmd = (at entry 3)
	if ('to' == (primName cmd)) {
	  if (funcName != (first (argList cmd))) { add newScripts entry }
	} else {
	  add newScripts entry
	}
  }
  setScripts (main mbProject) newScripts
  restoreScripts this
}

method showDefinition MicroBlocksScripter funcName {
  if (not (isShowingDefinition this funcName)) {
	f = (functionNamed mbProject funcName)
	if (isNil f) { return } // shouldn't happen
	ref = (newCommand 'to' funcName)

	// add the method/function definition to the scripts
	entry = (array (rand 50 200) (rand 50 200) ref)
	setScripts (main mbProject) (join (array entry) (scripts (main mbProject)))
	restoreScripts this
  }
  scrollToDefinitionOf this funcName
}

method isShowingDefinition MicroBlocksScripter funcName {
  for entry (scripts (main mbProject)) {
	cmd = (at entry 3) // third item of entry is command
	if ('to' ==  (primName cmd)) {
	  if (funcName == (first (argList cmd))) { return true }
	}
  }
  return false // not found
}

method scrollToDefinitionOf MicroBlocksScripter funcName {
  for m (parts (morph (contents scriptsFrame))) {
    if (isClass (handler m) 'Block') {
      def = (editedDefinition (handler m))
      if (notNil def) {
        if ((op def) == funcName) {
          scrollIntoView scriptsFrame (fullBounds m) true // favorTopLeft
        }
      }
    }
  }
}

// Build Your Own Blocks

method createFunction MicroBlocksScripter isReporter {
  name = (prompt (global 'page') 'Enter function name:' 'myBlock')
  if (name == '') {return}
  opName = (uniqueFunctionName this name)
  func = (defineFunctionInModule (main mbProject) opName (array) nil)
  blockType = ' '
  if isReporter { blockType = 'r' }
  spec = (blockSpecFromStrings opName blockType opName '')
  recordBlockSpec mbProject opName spec
  addToBottom this (scriptForFunction func)
  updateBlocks this
}

method copyFunction MicroBlocksScripter definition {
  primName = (primName definition)
  args = (argList definition)
  body = (last args)
  if (notNil body) { body = (copy body) }
  oldOp = (first args)
  oldSpec = (specForOp (authoringSpecs) oldOp)
  if ('to' == primName) {
	newOp = (uniqueFunctionName this oldOp)
	parameterNames = (copyFromTo args 2 ((count args) - 1))
	defineFunctionInModule (main mbProject) newOp parameterNames body
	if (notNil oldSpec) {
	  oldLabel = (first (specs oldSpec))
	  newLabel = (uniqueFunctionName this oldLabel)
	  newSpec = (copyWithOp oldSpec newOp oldLabel newLabel)
	} else {
	  newSpec = (blockSpecFor (functionNamed mbProject newOp))
	}
  }
  recordBlockSpec mbProject newOp newSpec
  return (newCommand primName newOp)
}

method uniqueFunctionName MicroBlocksScripter baseSpec {
  existingNames = (list)
  addAll existingNames (allOpNames (authoringSpecs))
  addAll existingNames (keys (blockSpecs (project projectEditor)))
  specWords = (words baseSpec)
  firstWord = (first specWords)
  if ('_' == firstWord) {
	firstWord = 'f'
	specWords = (join (array 'f') specWords)
  }
  atPut specWords 1 (uniqueNameNotIn existingNames firstWord)
  return (joinStrings specWords ' ')
}

// function deleting

method deleteFunction MicroBlocksScripter funcName {
  if (isShowingDefinition this funcName) { hideDefinition this funcName }
  f = (functionNamed mbProject funcName)
  if (notNil f) { removedUserDefinedBlock this f }
}

method removedUserDefinedBlock MicroBlocksScripter function {
  // Remove the given user-defined function.

  removeFunction (module function) function // in MicroBlocks the function "module" is its library
  deleteBlockSpecFor (project projectEditor) (functionName function)
  updateBlocks this
}

method addToBottom MicroBlocksScripter aBlock noScroll {
  if (isNil noScroll) {noScroll = false}
  space =  ((global 'scale') * 10)
  bottom = (top (morph (contents scriptsFrame)))
  left = ((left (morph (contents scriptsFrame))) + (50 * (global 'scale')))
  for script (parts (morph (contents scriptsFrame))) {
    left = (min left (left (fullBounds script)))
    bottom = (max bottom (bottom (fullBounds script)))
  }
  setPosition (morph aBlock) left (bottom + space)
  addPart (morph (contents scriptsFrame)) (morph aBlock)
  if (not noScroll) {
    scrollIntoView scriptsFrame (fullBounds (morph aBlock))
  }
  scriptChanged this
}

method blockPrototypeChanged MicroBlocksScripter aBlock {
  saveScripts this
  scriptsPane = (contents scriptsFrame)
  op = (primName (function aBlock))

  // update the definition body
  block = (handler (owner (morph aBlock)))
  nxt = (next block)
  if (and (notNil nxt) (containsPrim nxt op)) {
    body = (toBlock (cmdList (function aBlock)))
    setNext block nil
    setNext block body
    fixBlockColor block
  }

  // update the palette template
  updateBlocks this

  // update all calls
  if ('initialize' != op) {
	updateCallsOf this op
	updateCallsInScriptingArea this op
  }
  updateSliders scriptsFrame
}

method updateCallsOf MicroBlocksScripter op {
  // Update calls of the give operation to ensure that they have the minimum number
  // of arguments specified by the prototype and that the types of any constant
  // parameters match those of the the prototype.

  // get spec and extract arg types and default values
  spec = (specForOp (authoringSpecs) op)
  if (isNil spec) { return } // should not happen
  minArgs = (countInputSlots spec (first (specs spec)))
  isReporter = (isReporter spec)
  isVariadic = (or ((count (specs spec)) > 1) (repeatLastSpec spec))
  argTypes = (list)
  argDefaults = (list)
  for i (slotCount spec) {
	info = (slotInfoForIndex spec i)
	typeStr = (at info 1)
	defaultValue = (at info 2)
	if (and ('color' == typeStr) (isNil defaultValue)) {
      defaultValue = (color 35 190 30)
	}
	if (and ('auto' == typeStr) (representsANumber defaultValue)) {
	  defaultValue = (toNumber defaultValue defaultValue)
	}
	add argTypes typeStr
	add argDefaults defaultValue
  }

  // update all calls
  s = (first (specs spec))
  origCmds = (list)
  newCmds = (list)
  gc
  for cmd (allCmdsInProject this) {
	if ((primName cmd) == op) {
	  add origCmds cmd
	  add newCmds (fixedCmd this cmd minArgs argTypes argDefaults isReporter isVariadic)
	}
  }
  // replace command/reporter objects with new versions
  replaceObjects (toArray origCmds) (toArray newCmds)
}

method allCmdsInProject MicroBlocksScripter {
  main = (main (project projectEditor))
  result = (dictionary)
  for f (functions main) {
	addAll result (allBlocks (cmdList f))
  }
  for s (scripts main) {
	addAll result (allBlocks (at s 3))
  }
  return (keys result)
}

method fixedCmd MicroBlocksScripter oldCmd minArgs argTypes argDefaults isReporter isVariadic {
  // Return an updated Command or Reporter.

  args = (toList (argList oldCmd))

  // add new arguments with default values
  while ((count args) < minArgs) {
	add args (at argDefaults ((count args) + 1))
  }

  // if not variadic, remove extra arguments
  if (not isVariadic) {
	while ((count args) > minArgs) {
	  removeLast args
	}
  }

  // fix type inconsistencies for non-expression arguments
 for i (min minArgs (count args) (count argTypes) (count argDefaults)) {
	arg = (at args i)
	if (not (isClass arg 'Reporter')) {
	  desiredType = (at argTypes i)
	  if (and ('auto' == desiredType) (not (or (isNumber arg) (isClass arg 'String')))) {
		atPut args i (at argDefaults i)
	  }
	  if (and ('bool' == desiredType) (not (isClass arg 'Boolean'))) {
		atPut args i (at argDefaults i)
	  }
	  if (and ('color' == desiredType) (not (isClass arg 'Color'))) {
		atPut args i (at argDefaults i)
	  }
	}
  }

  // create a new command/reporter with new args list
  if isReporter {
	result = (newIndexable 'Reporter' (count args))
  } else {
	result = (newIndexable 'Command' (count args))
  }
  fixedFields = (fieldNameCount (classOf result))
  setField result 'primName' (primName oldCmd)
  for i (count args) {
    setField result (fixedFields + i) (at args i)
  }
  return result
}

method updateCallsInScriptingArea MicroBlocksScripter op {
  // Update scripts in the scripting pane that contain calls to the give op.

  scriptsPane = (contents scriptsFrame)
  affected = (list)
  for m (parts (morph scriptsPane)) {
	b = (handler m)
	if (and (isClass b 'Block') (containsPrim b op)) {
	  add affected b
	}
  }
  for each affected {
	expr = (expression each)
	if ('to' == (primName expr)) {
	  func = (functionNamed mbProject (first (argList expr)))
	  block = (scriptForFunction func)
	} else {
	  block = (toBlock expr)
	  setNext block (next each)
	}
	x = (left (morph each))
	y = (top (morph each))
	destroy (morph each)
	setPosition (morph block) x y
	addPart (morph scriptsPane) (morph block)
	fixBlockColor block
  }
}

// Library import/export

method importLibrary MicroBlocksScripter {
  pickFileToOpen (action 'importLibraryFromFile' this) 'Libraries' (array '.ulib' '.ubl')
}

method importLibraryFromFile MicroBlocksScripter fileName {
  // Import a library with the give file path.

  if (beginsWith fileName '//') {
	data = (readEmbeddedFile (substring fileName 3))
  } else {
	data = (readFile fileName)
  }
  if (isNil data) { error (join 'Could not read: ' fileName) }

  libName = (withoutExtension (filePart fileName))
  addLibraryFromString mbProject data libName

  // update library list and select the new library
  updateLibraryList this
  select (contents categoriesFrame) nil
  select (contents libFrame) libName
  updateBlocks this
}

method updateLibraryList MicroBlocksScripter {
  libNames = (sorted (keys (libraries mbProject)))
  setCollection (contents libFrame) libNames
  oldSelection = (selection (contents libFrame))
  if (not (contains libNames oldSelection)) {
	selectCategory this 'Control'
  }
}

method exportAsLibrary MicroBlocksScripter defaultFileName {
  fileName = (fileToWrite (withoutExtension defaultFileName) '.ubl')
  if (isEmpty fileName) { return }
  if (not (endsWith fileName '.ubl' )) { fileName = (join fileName '.ubl') }

  libName = (withoutExtension (filePart fileName))
  writeFile fileName (codeString (main mbProject) mbProject libName)
}
