// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksScripter.gp - MicroBlocks script editor w/ built-in palette

defineClass MicroBlocksScripter morph mbProject projectEditor saveNeeded categorySelector catResizer libHeader libSelector lastLibraryFolder blocksFrame blocksResizer scriptsFrame nextX nextY embeddedLibraries trashcan selection

method blockPalette MicroBlocksScripter { return (contents blocksFrame) }
method scriptEditor MicroBlocksScripter { return (contents scriptsFrame) }
method scriptsFrame MicroBlocksScripter { return scriptsFrame }
method project MicroBlocksScripter { return mbProject }
method httpServer MicroBlocksScripter { return (httpServer projectEditor) }

method selection MicroBlocksScripter { return selection }
method setSelection MicroBlocksScripter aSelection { selection = aSelection }

// initialization

method initialize MicroBlocksScripter aProjectEditor {
  mbProject = (newMicroBlocksProject)
  projectEditor = aProjectEditor
  scale = (global 'scale')
  morph = (newMorph this)
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
  lastLibraryFolder = 'Libraries'

  categorySelector = (newCategorySelector (categories this) (action 'categorySelected' this))
  setFont categorySelector fontName fontSize
  setExtent (morph categorySelector) (140 * scale) 100
  addPart morph (morph categorySelector)

  libSelector = (newCategorySelector (array) (action 'librarySelected' this))
  setFont libSelector fontName fontSize
  addPart morph (morph libSelector)

  blocksPane = (newBlocksPalette)
  setSortingOrder (alignment blocksPane) nil
  setPadding (alignment blocksPane) (15 * scale) // inter-column space
  setFramePadding (alignment blocksPane) (10 * scale) (10 * scale)
  blocksFrame = (scrollFrame blocksPane (gray 220))
  setExtent (morph blocksFrame) (260 * scale) (100 * scale)
  setAutoScroll blocksFrame false
  addPart morph (morph blocksFrame)

  scriptsPane = (newScriptEditor 10 10 nil)
  scriptsFrame = (scrollFrame scriptsPane (gray 220))
  addPart morph (morph scriptsFrame)

  // add resizers last so they are in front
  catResizer = (newPaneResizer (morph categorySelector) 'horizontal')
  addPart morph (morph catResizer)

  blocksResizer = (newPaneResizer (morph blocksFrame) 'horizontal')
  addPart morph (morph blocksResizer)

  setGrabRule morph 'ignore'
  for m (parts morph) { setGrabRule m 'ignore' }

  setMinExtent morph (scale * 235) (scale * 200)
  setExtent morph (scale * 600) (scale * 700)
  restoreScripts this

  smallRuntime this // create a SmallRuntime instance
  if (isNil projectEditor) { select categorySelector 'Control' }
  return this
}

method languageChanged MicroBlocksScripter {
  updateLibraryHeader this

  // update the scripts
  updateBlocks this
  saveScripts this
  restoreScripts this
  scriptChanged this
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

  addButton = (handler (last (parts (morph libHeader))))
  setHint addButton (localized 'Add Library')
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

  button = (newButton '' (action 'importLibrary' this))
  setHint button (localized 'Add Library')
  setCostumes button bm1 bm2
  return button
}

// library item menu

method handleListContextRequest MicroBlocksScripter anArray {
  if (and ((first anArray) == categorySelector) ('My Blocks' == (last anArray))) {
    menu = (menu)
	addItem menu 'show all block definitions' (action 'showAllMyBlocks' this)
	addItem menu 'hide all block definitions' (action 'hideAllMyBlocks' this)
    popUpAtHand menu (global 'page')
    return
  }
  if ((first anArray) != libSelector) { return } // not a library list entry; ignore
  libName = (last anArray)
  menu = (menu)
  addItem menu 'library information' (action 'showLibraryInfo' this libName)
  if (devMode) {
	addItem menu 'show all block definitions' (action 'showAllLibraryDefinitions' this libName)
	addItem menu 'hide all block definitions' (action 'hideAllLibraryDefinitions' this libName)
	addItem menu 'export this library' (action 'exportLibrary' this libName)
  }
  addLine menu
  addItem menu 'delete library' (action 'removeLibraryNamed' this libName)
  popUpAtHand menu (global 'page')
}

method showAllMyBlocks MicroBlocksScripter libName {
  newY = (height (morph (contents scriptsFrame))) // current bottom
  for f (functions (main mbProject)) {
	internalShowDefinition this (functionName f)
  }
  saveScripts this
  updateSliders scriptsFrame
  scrollToY scriptsFrame newY
}

method scrollToXY MicroBlocksScripter x y {
	scrollToX scriptsFrame (x + (left (morph scriptsFrame)))
	scrollToY scriptsFrame (y + (top (morph scriptsFrame)))
}

method hideAllMyBlocks MicroBlocksScripter {
  for f (functions (main mbProject)) {
	internalHideDefinition this (functionName f)
  }
  saveScripts this
  scrollToX scriptsFrame 0
  scrollToY scriptsFrame 0
  updateSliders scriptsFrame
}

method removeLibraryNamed MicroBlocksScripter libName {
  removeLibraryNamed mbProject libName
  variablesChanged (smallRuntime)
  updateLibraryList this
  languageChanged this
}

method showLibraryInfo MicroBlocksScripter libName {
	library = (libraryNamed mbProject libName)
	showLibraryInfo library (devMode)
}

method showAllLibraryDefinitions MicroBlocksScripter libName {
  lib = (libraryNamed mbProject libName)
  if (isNil lib) { return }
  newY = (height (morph (contents scriptsFrame))) // current bottom
  for f (functions lib) {
	internalShowDefinition this (functionName f)
  }
  saveScripts this
  updateSliders scriptsFrame
  scrollToY scriptsFrame newY
}

method hideAllLibraryDefinitions MicroBlocksScripter libName {
  lib = (libraryNamed mbProject libName)
  if (isNil lib) { return }
  for f (functions lib) {
	internalHideDefinition this (functionName f)
  }
  saveScripts this
  scrollToX scriptsFrame 0
  scrollToY scriptsFrame 0
  updateSliders scriptsFrame
}

method exportLibrary MicroBlocksScripter libName {
  lib = (libraryNamed mbProject libName)
  if (isNil lib) { return }

  if ('Browser' == (platform)) {
	fName = (join (moduleName lib) '.ubl')
	browserWriteFile (codeString lib mbProject) fName 'library'
  } else {
	fName = (fileToWrite (moduleName lib) (array '.ubl'))
	if ('' == fName) { return false }
	if (not (endsWith fName '.ubl' )) { fName = (join fName '.ubl') }
	writeFile fName (codeString lib mbProject)
  }
}

// layout

method fixLayout MicroBlocksScripter {
  scale = (global 'scale')
  catWidth = (max (toInteger ((width (morph categorySelector)) / scale)) (20 * scale))
  catHeight = ((heightForItems categorySelector) / scale)
  blocksWidth = (max (toInteger ((width (morph blocksFrame)) / scale)) (20 * scale))
  columnHeaderHeight = 33

  // prevent pane dividers from going off right side
  catWidth = (min catWidth ((width morph) - (20 * scale)))
  blocksWidth = (min blocksWidth ((width morph) - (catWidth + (20 * scale))))

  packer = (newPanePacker (bounds morph) scale)
  packPanesH packer categorySelector catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesH packer libHeader catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesH packer libSelector catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesV packer categorySelector catHeight libHeader columnHeaderHeight libSelector '100%'
  packPanesV packer blocksFrame '100%'
  packPanesV packer scriptsFrame '100%'
  finishPacking packer

  // extra damage report for area below libSelector
  libSelectorM = (morph libSelector)
  reportDamage morph (rect 0 (bottom libSelectorM) (width libSelectorM) (height morph))

  fixResizerLayout this
  fixLibraryHeaderLayout this
  updateSliders blocksFrame
  updateSliders scriptsFrame
}

method fixResizerLayout MicroBlocksScripter {
  resizerWidth = (10 * (global 'scale'))

  // categories pane resizer
  setLeft (morph catResizer) (right (morph categorySelector))
  setTop (morph catResizer) (top morph)
  setExtent (morph catResizer) resizerWidth (height morph)

  // blocks pane resizer
  setLeft (morph blocksResizer) (right (morph blocksFrame))
  setTop (morph blocksResizer) (top morph)
  setExtent (morph blocksResizer) resizerWidth (height morph)
}

method hideScrollbars MicroBlocksScripter {
  hideSliders blocksFrame
  hideSliders scriptsFrame
}

method showScrollbars MicroBlocksScripter {
  showSliders blocksFrame
  showSliders scriptsFrame
}

// drawing

method drawOn MicroBlocksScripter ctx {
  scale = (global 'scale')
  borderColor = (gray 150)
  borderWidth = (2 * scale)
  x = (right (morph categorySelector))
  fillRect ctx (gray 240) 0 (top morph) x (height morph) // bg color for category/lib panes
  fillRect ctx borderColor x (top morph) borderWidth (height morph)
  x = (right (morph blocksFrame))
  fillRect ctx borderColor x (top morph) borderWidth (height morph)
  r = (bounds (morph libHeader))
  fillRect ctx borderColor (left r) ((top r) - borderWidth) (width r) borderWidth
  fillRect ctx borderColor (left r) (bottom r) (width r) borderWidth
}

// MicroBlocksScripter UI support

method developerModeChanged MicroBlocksScripter {
  catList = categorySelector
  setCollection catList (categories this)
  if (not (or (contains (collection catList) (selection catList))
  			  (notNil (selection libSelector)))) {
    select catList 'Output'
  } else {
    updateBlocks this
  }
}

method categories MicroBlocksScripter {
  initMicroBlocksSpecs (new 'SmallCompiler')
  result = (list 'Output' 'Input' 'Pins' 'Comm' 'Control' 'Operators' 'Variables' 'Data' 'My Blocks')
  if (not (devMode)) {
  	removeAll result (list 'Comm')
  }
  return result
}

method selectCategory MicroBlocksScripter aCategory {
  select categorySelector aCategory
  categorySelected this
}

method currentCategory MicroBlocksScripter {
  return (selection categorySelector)
}

method categorySelected MicroBlocksScripter {
   select libSelector nil // deselect library
   updateBlocks this
}

method selectLibrary MicroBlocksScripter aLibrary {
  select libSelector aLibrary
  librarySelected this
}

method currentLibrary MicroBlocksScripter {
  return (selection libSelector)
}

method librarySelected MicroBlocksScripter {
   select categorySelector nil // deselect category
   updateBlocks this
}

method updateBlocks MicroBlocksScripter {
  scale = (global 'scale')
  blocksPane = (contents blocksFrame)
  hide (morph blocksPane) // suppress damage reports while adding blocks
  removeAllParts (morph blocksPane)
  setRule (alignment blocksPane) 'none'

  nextX = ((left (morph (contents blocksFrame))) + (16 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (16 * scale))

  cat = (selection categorySelector)
  if (isNil cat) {
	addBlocksForLibrary this (selection libSelector)
  } ('Variables' == cat) {
	addVariableBlocks this
    addAdvancedBlocksForCategory this cat
  } ('My Blocks' == cat) {
    addMyBlocks this
  } else {
	addBlocksForCategory this cat
  }
  cleanUp blocksPane
  show (morph blocksPane) // show after adding blocks
  updateSliders blocksFrame
}

method addBlocksForCategory MicroBlocksScripter cat {
  addBlocksForSpecs this (specsFor (authoringSpecs) cat)
  addAdvancedBlocksForCategory this cat
}

method addAdvancedBlocksForCategory MicroBlocksScripter cat {
  advancedSpecs = (specsFor (authoringSpecs) (join cat '-Advanced'))
  if (and (devMode) (not (isEmpty advancedSpecs))) {
	addSectionLabel this (localized 'Advanced:')
	addBlocksForSpecs this advancedSpecs
  }
}

method addBlocksForSpecs MicroBlocksScripter specList {
  for spec specList {
	if ('-' == spec) {
	  // add some vertical space
	   nextY += (20 * (blockScale))
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
	} (or (showHiddenBlocksEnabled projectEditor) (not (beginsWith op '_'))) {
	  spec = (specForOp (authoringSpecs) op)
	  if (notNil spec) {
	  	addBlock this (blockForSpec spec) spec
	  }
	}
  }
}

to caseInsensitiveLessThan s1 s2 {
  return ((toUpperCase s1) < (toUpperCase s2))
}

method addVariableBlocks MicroBlocksScripter {
  scale = (global 'scale')

  addButton this (localized 'Add a variable') (action 'createVariable' this)
  visibleVars = (visibleVars this)
  if (notEmpty visibleVars) {
	addButton this (localized 'Delete a variable') (action 'deleteVariableMenu' this)
  }

  // add set/change variable
  nextY += (20 * scale)
  defaultVarName = ''
  if (notEmpty visibleVars) { defaultVarName = (first visibleVars) }

  addBlock this (toBlock (newCommand '=' defaultVarName 0)) nil false
  addBlock this (toBlock (newCommand '+=' defaultVarName 1)) nil false
  if (or (devMode) (contains (commandLine) '--allowMorphMenu')) {
    nextY += (10 * scale)
    addBlock this (toBlock (newCommand 'local' 'var' 0)) nil false
  }

  nextY += (20 * scale)

  if (notEmpty visibleVars) {
    visibleVars = (sorted (toArray visibleVars) 'caseInsensitiveLessThan')
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

}

method addMyBlocks MicroBlocksScripter {
  scale = (global 'scale')

  addButton this (localized 'Add a command block') (action 'createFunction' this false)
  addButton this (localized 'Add a reporter block') (action 'createFunction' this true)
  nextY += (8 * scale)

  for f (functions (main mbProject)) {
	if (or (showHiddenBlocksEnabled projectEditor) (not (beginsWith (functionName f) '_'))) {
	  spec = (specForOp (authoringSpecs) (functionName f))
	  if (isNil spec) { spec = (blockSpecFor f) }
	  addBlock this (blockForSpec spec) spec
	}
  }
}

method addButton MicroBlocksScripter label action hint {
  btn = (newButton label action)
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
  fixLayout b
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
  clearBoardIfConnected (smallRuntime) true
  if (notNil scriptsFrame) {
	removeAllParts (morph (contents scriptsFrame))
	restoreScripts this
	saveScripts this
  }
}

method loadOldProjectFromClass MicroBlocksScripter aClass specs {
  // Load an old-style (GP-format) MicroBlocks project from the given class and spec list.

  mbProject = (newMicroBlocksProject)
  clearBoardIfConnected (smallRuntime) true
  if (notNil aClass) {
	loadFromOldProjectClassAndSpecs mbProject aClass specs
  }
  restoreScripts this
}

method loadNewProjectFromData MicroBlocksScripter aString updateLibraries {
  // Load an new-style MicroBlocks project from the given string.

  mbProject = (newMicroBlocksProject)
  clearBoardIfConnected (smallRuntime) true
  saveNeeded = false // don't save scripts while project is loading
  loadFromString mbProject aString updateLibraries
  restoreScripts this
}

method setProject MicroBlocksScripter aMicroBlocksProject {
  mbProject = aMicroBlocksProject
  restoreScripts this
}

// variable operations

method visibleVars MicroBlocksScripter {
  // Include vars that start with underscore only in dev mode.

  allVars = (allVariableNames mbProject)
  if (showHiddenBlocksEnabled projectEditor) {
    return allVars
  } else {
    return (filter
      (function each { return (not (beginsWith each '_')) })
      allVars)
  }
}

method createVariable MicroBlocksScripter srcObj {
  varName = (trim (freshPrompt (global 'page') 'New variable name?' ''))
  if (varName != '') {
	addVariable (main mbProject) (uniqueVarName this varName)
	variablesChanged (smallRuntime)
	updateBlocks this
	if (isClass srcObj 'InputSlot') {
	  setContents srcObj varName
	}
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
		if (isOneOf (primName b) 'local' 'for') {
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
  variablesChanged (smallRuntime)
  updateBlocks this
}

// save and restore scripts in class

method scriptChanged MicroBlocksScripter {
  runtime = (smallRuntime)
  updateHighlights runtime
  saveNeeded = true
// Check whether the block has just been moved.
// Commented out for now, since it seems to not be reliable enough, causing some
// changes to fail to propagate to the board.
//  for m (parts (morph (contents scriptsFrame))) {
//	b = (handler m)
//    if (isClass b 'Block') {
//	  entry = (chunkEntryForBlock runtime b)
//	  saveNeeded = (or (isNil entry) ((sourceForChunk runtime b) != (at entry 4)))
//	}
//  }
}

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
  updateStopping (smallRuntime)
}

method saveScripts MicroBlocksScripter oldScale {
  scale = (blockScale)
  if (notNil oldScale) { scale = oldScale }
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
  if (notNil f) {
    updateCmdList f newCmdList
    removeFieldsFromLocals f (allVariableNames mbProject)
  }
}

method restoreScripts MicroBlocksScripter {
  scale = (blockScale)
  scriptsPane = (contents scriptsFrame)
  removeAllParts (morph scriptsPane)
  clearDropHistory scriptsPane

  scripts = (scripts (main mbProject))
  if (notNil scripts) {
	editor = (findMicroBlocksEditor)
    scriptCount = (count scripts)
    paneX = (left (morph scriptsPane))
    paneY = (top (morph scriptsPane))
    for i scriptCount {
      entry = (at scripts i)
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
        isReporter = ('r' == (blockType (specForOp (authoringSpecs) (primName dta))))
        if (and isReporter (isClass dta 'Command')) { dta = (toReporter dta) }
        if (and (not isReporter) (isClass dta 'Reporter')) { dta = (toCommand dta) }
        block = (toBlock dta)
      }
      if (notNil block) {
		x = (paneX + ((at entry 1) * scale))
		y = (paneY + ((at entry 2) * scale))
		fastMoveBy (morph block) x y
		addPart (morph scriptsPane) (morph block)
		fixBlockColor block
	  }
    }
  }
  updateSliders scriptsFrame
  updateBlocks this
}

method updateScriptAfterOperatorChange MicroBlocksScripter aBlock {
  // Rebuild the script containing aBlock after switching operators.

  topBlock = (topBlock aBlock)
  expr = (expression topBlock 'main')
  if ('to' == (primName expr)) {
    updateFunctionOrMethod this expr
    func = (functionNamed mbProject (first (argList expr)))
    newBlock = (scriptForFunction func)
  } else {
    newBlock = (toBlock expr)
  }
  removeFromOwner (morph topBlock)
  fastMoveBy (morph newBlock) (left (morph topBlock)) (top (morph topBlock))
  addPart (morph (contents scriptsFrame)) (morph newBlock)
  scriptChanged this
}

// hide/show block definition

method hideDefinition MicroBlocksScripter funcName {
  // Hide the given method/function definition.

  internalHideDefinition this funcName
  saveScripts this
  updateSliders scriptsFrame
}

method internalHideDefinition MicroBlocksScripter funcName {
  // Internal helper method.
  // Hide the given method/function definition but does not save the scripts.

  scriptsPaneM = (morph (contents scriptsFrame))
  for m (parts scriptsPaneM) {
    b = (handler m)
    if (isClass b 'Block') {
      proto = (editedPrototype b)
      if (and (notNil proto) (funcName == (functionName (function proto)))) {
        removeFromOwner m
      }
    }
  }
}

method showDefinition MicroBlocksScripter funcName {
  if (not (isShowingDefinition this funcName)) {
    internalShowDefinition this funcName
    saveScripts this
    updateSliders scriptsFrame
  }
  scrollToDefinitionOf this funcName
}

method internalShowDefinition MicroBlocksScripter funcName {
  // Internal helper method.
  // Adds function definition to scripts pane but does not save the scripts.

  if (isShowingDefinition this funcName) { return } // already showing
  f = (functionNamed mbProject funcName)
  if (isNil f) { return }
  scale = (blockScale)
  scriptsPaneM = (morph (contents scriptsFrame))

  // find a position for the defintion below all other scripts
  x = ((left scriptsPaneM) + (50 * scale))
  y = ((top scriptsPaneM) + (50 * scale))
  for m (parts scriptsPaneM) {
    if (isClass (handler m) 'Block') {
	  mBnds = (fullBounds m)
	  if ((left mBnds) < x) { x = (left mBnds) }
	  if ((bottom mBnds) > y) { y = (bottom mBnds) }
    }
  }

  // add the definition and save the scripts
  block = (scriptForFunction f)
  fastSetPosition (morph block) x y
  addPart scriptsPaneM (morph block)
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

method findDefinitionOf MicroBlocksScripter funcName {
  for m (parts (morph (contents scriptsFrame))) {
    if (isClass (handler m) 'Block') {
      def = (editedDefinition (handler m))
      if (notNil def) {
        if ((op def) == funcName) {
          return m
        }
      }
    }
  }
  return nil
}

method scrollToDefinitionOf MicroBlocksScripter funcName {
  m = (findDefinitionOf this funcName)
  if (notNil m) {
	scrollIntoView scriptsFrame (fullBounds m) true
  }
}

// Build Your Own Blocks

method createFunction MicroBlocksScripter isReporter {
  name = (freshPrompt (global 'page') 'Enter function name:' 'myBlock')
  if (name == '') {return}
  opName = (uniqueFunctionName this name)
  func = (defineFunctionInModule (main mbProject) opName (array) nil)
  blockType = ' '
  if isReporter { blockType = 'r' }
  spec = (blockSpecFromStrings opName blockType opName '')
  recordBlockSpec mbProject opName spec
  addToBottom this (scriptForFunction func)
  updateBlocks this
  saveScripts this
  restoreScripts this
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
  saveNeeded = true
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
	if (and ('auto' == typeStr) (isClass defaultValue 'String') (representsANumber defaultValue)) {
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
	setField result 'nextBlock' (nextBlock oldCmd)
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

  // Workaround for recursive structure crash bug:
  offsetX = (left (morph (contents scriptsFrame)))
  offsetY = (top (morph (contents scriptsFrame)))
  restoreScripts this
  setLeft (morph (contents scriptsFrame)) offsetX
  setTop (morph (contents scriptsFrame)) offsetY
  return

// Caution: the following code can create recursive structure that crash!
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
  if (downloadInProgress (findProjectEditor)) { return }
  libraryWindow = (findMorph 'MicroBlocksLibraryImportDialog')
  if (notNil libraryWindow) { destroy libraryWindow }
  pickLibraryToOpen (action 'openLibraryFile' this) lastLibraryFolder (array '.ubl')
}

method openLibraryFile MicroBlocksScripter fileName {
	importLibraryFromFile this fileName
	saveAllChunksAfterLoad (smallRuntime)
}

method allFilesInDir MicroBlocksScripter rootDir {
	// Return a list of all files below the given directory.

	result = (list)
	todo = (list rootDir)
	while (notEmpty todo) {
		dir = (removeFirst todo)
		for fName (listFiles dir) {
			add result (join dir '/' fName)
		}
		for dirName (listDirectories dir) {
			add todo (join dir '/' dirName)
		}
	}
	return result
}

method importEmbeddedLibrary MicroBlocksScripter libName {
	if ('Browser' == (platform)) {
		libFileName = (join libName '.ubl')
		for filePath (allFilesInDir this 'Libraries') {
			if (endsWith filePath libFileName) {
				importLibraryFromFile this filePath
				return
			}
		}
		return
	}
	for filePath (listEmbeddedFiles) {
		if (endsWith filePath (join libName '.ubl')) {
			importLibraryFromFile this (join '//' filePath)
			return
		}
	}
}

method importLibraryFromFile MicroBlocksScripter fileName data {
  // Import a library with the given file path. If data is not nil, it came from
  // a browser upload or file drop. Use it rather than attempting to read the file.

  if (isNil data) {
	if (beginsWith fileName '//') {
	  data = (readEmbeddedFile (substring fileName 3))
      lastLibraryFolder = 'Libraries'
	} else {
	  data = (readFile fileName)
      lastLibraryFolder = (directoryPart fileName)
	}
	if (isNil data) { return } // could not read file
  }

  libName = (withoutExtension (filePart fileName))
  if (notNil (libraryNamed mbProject libName)) {
    // replacing library; first hide its block definitions
    hideAllLibraryDefinitions this libName
  }
  importLibraryFromString this (toString data) libName fileName
}

method importLibraryFromUrl MicroBlocksScripter fullUrl {
	if (beginsWith fullUrl 'http://') {
		url = (substring fullUrl 8)
	} (beginsWith fullUrl 'https://') {
		// HTTPS is not supported, but we'll try to fetch the lib via HTTP, just
		// in case the remote server supports both SSL and plain HTTP
		url = (substring fullUrl 9)
	} else {
		url = fullUrl
	}
	host = (substring url 1 ((findFirst url '/') - 1))
	libPath = (substring url (findFirst url '/'))
	libName = (substring libPath ((findLast libPath '/') + 1) ((findLast libPath '.') - 1))
	libSource = (httpGet host libPath)

	// Check if response is valid
	if (isEmpty libSource) {
		(inform (global 'page')
			(localized 'Host does not exist or is currently down.')
			'Could not fetch library')
		return false
	} ((findSubstring '404' (first (lines libSource))) > 0) {
		// 404 not found. Host seems okay, but file can't be fetched.
		(inform (global 'page')
			(localized 'File not found in server.')
			'Could not fetch library')
		return false
	} ((findSubstring '301' (first (lines libSource))) > 0) {
		// Moved permanently. Normally returned when we try to access a URL by
		// HTTP and are redirected to the HTTPS equivalent
		(inform (global 'page')
			(localized 'Server expects HTTPS, and MicroBlocks doesn''t currently support it.')
			'Could not fetch library')
		return false
	}

	importLibraryFromString this libSource libName fullUrl
	return true
}

method importLibraryFromString MicroBlocksScripter data libName fileName {
	addLibraryFromString mbProject (toString data) libName fileName
	variablesChanged (smallRuntime)

	// update library list and select the new library
	updateLibraryList this
	select categorySelector nil
	select libSelector libName
	updateBlocks this
	saveScripts this
	restoreScripts this
}

method updateLibraryList MicroBlocksScripter {
  libNames = (sorted (keys (libraries mbProject)))
  setCollection libSelector libNames
  oldSelection = (selection libSelector)
  if (not (contains libNames oldSelection)) {
	selectCategory this 'Control'
  }
}

method justGrabbedPart MicroBlocksScripter part {
	print 'scripter part grabbed'
	print part
}

method setLibsDraggable MicroBlocksScripter flag {
	// deprecated; do nothing
}

method exportAsLibrary MicroBlocksScripter defaultFileName {
  if ('Browser' == (platform)) {
	if (or (isNil defaultFileName) ('' == defaultFileName)) {
		defaultFileName = (localized 'my library')
	}
	libName = (freshPrompt (global 'page') (localized 'Library name?') defaultFileName)
	fName = (join libName '.ubl')
	browserWriteFile (codeString (main mbProject) mbProject libName) fName 'library'
  } else {
	fName = (fileToWrite (withoutExtension defaultFileName) '.ubl')
	if (isEmpty fName) { return }
	if (not (endsWith fName '.ubl' )) { fName = (join fName '.ubl') }
	libName = (withoutExtension (filePart fName))
	writeFile fName (codeString (main mbProject) mbProject libName)
  }
}

// importing libraries for dropped scripts

method installLibraryNamed MicroBlocksScripter libName {
  if (notNil (libraryNamed mbProject libName)) { return } // library already installed
  fileName = (fileNameForLibraryNamed this libName)
  if (isNil fileName) {
    print 'Unknown library:' libName
    return
  }
  if (not (endsWith fileName '.ubl')) { fileName = (join fileName '.ubl') }
  if ('Browser' != (platform)) { fileName = (join '//' fileName) }
  importLibraryFromFile this fileName
}

method fileNameForLibraryNamed MicroBlocksScripter libName {
  if (isNil embeddedLibraries) {
	// build a dictionary mapping libName -> fileName
	embeddedLibraries = (dictionary)
	if ('Browser' == (platform)) {
	  for filePath (allFilesInDir this 'Libraries') {
		if (endsWith filePath '.ubl') {
		  name = (extractLibraryName this (readFile filePath))
		  if (notNil name) {
			atPut embeddedLibraries name filePath
		  }
		}
	  }
	} else {
	  for filePath (listEmbeddedFiles) {
		if (endsWith filePath '.ubl') {
		  name = (extractLibraryName this (readEmbeddedFile filePath))
		  if (notNil name) {
			atPut embeddedLibraries name (withoutExtension filePath)
		  }
		}
	  }
	}
  }
  return (at embeddedLibraries libName)
}

method extractLibraryName MicroBlocksScripter libData {
  if (isNil libData) { return nil }
  for line (lines libData) {
    if (beginsWith line 'module') {
      i = (findFirst line '''')
      if (notNil i) { // quoted library name
        j = (findLast line '''')
        if ((j - i) > 2) { return (substring line (i + 1) (j - 1)) }
      }
      return (at (words line) 2)
    }
  }
  return nil
}

// support for script copy-paste via clipboard or embedding in a PNG files

method scriptStringFor MicroBlocksScripter aBlock {
  // Return a script string for the given script.

  return (join
  	'GP Script' (newline)
  	(exportScripts (newMicroBlocksExchange) this (list (morph (topBlock aBlock)))))
}

method allScriptsString MicroBlocksScripter {
  // Return a string with all scripts in the scripting area.

  scriptsPaneM = (morph (contents scriptsFrame))
  paneX = (left scriptsPaneM)
  paneY = (top scriptsPaneM)
  return (join
    'GP Scripts' (newline)
    (exportScripts (newMicroBlocksExchange) this (parts scriptsPaneM) paneX paneY))
}

method pasteScripts MicroBlocksScripter scriptString atHand {
  // hide the definitions of functions that will be pasted
  scriptString = (normalizeLineEndings scriptString)
  for entry (parse scriptString) {
    args = (argList entry)
    if (and ('script' == (primName entry)) ((count args) >= 3) (notNil (last args))) {
      script = (last args)
      if ('to' == (primName script)) {
        funcName = (first (argList script))
        internalHideDefinition this funcName
      }
    }
  }

  // find destination position for scripts
  if (isNil atHand) { atHand = false }
  if atHand {
  	// current hand position, adjusted for approximate menu offset
    hand = (hand (global 'page'))
    dstX = ((x hand) - (40 * (global 'scale')))
    dstY = ((y hand) - (90 * (global 'scale')))
  } else {
    dstX = ((left (morph (contents scriptsFrame))) + (100 * (global 'scale')))
    dstY = ((scriptsBottom this) + (30 * (blockScale)))
  }

  scriptsPane = (contents scriptsFrame)
  clearDropHistory scriptsPane
  importScripts (newMicroBlocksExchange) this scriptString dstX dstY
  scriptChanged this
  updateBlocks this
  saveScripts this
  updateSliders scriptsFrame
  if (notNil block) {
    scrollIntoView scriptsFrame (fullBounds (morph block)) true // favorTopLeft
  }
}

method scriptsBottom MicroBlocksScripter {
  // Return the vertical position of the bottom-most script in the scripting area.

  scriptsM = (morph (contents scriptsFrame))
  result = (top scriptsM)
  for m (parts scriptsM) {
    if (isClass (handler m) 'Block') {
	  mBnds = (fullBounds m)
	  if ((bottom mBnds) > result) { result = (bottom mBnds) }
    }
  }
  return result
}
