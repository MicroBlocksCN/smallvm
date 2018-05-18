// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

//Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksScripter.gp - authoring-level MicroBlocksScripter w/ built-in palette

defineClass MicroBlocksScripter morph targetObj projectEditor saveNeeded categoriesFrame catWidth catResizer blocksFrame blocksWidth blocksResizer scriptsFrame nextX nextY

method targetClass MicroBlocksScripter { return (classOf targetObj) }
method targetObj MicroBlocksScripter { return targetObj }

method setTargetObj MicroBlocksScripter obj {
  if (targetObj === obj) { return }
  oldClass = (classOf targetObj)
  targetObj = obj
  if ((classOf obj) != oldClass) {
    restoreScripts this
    saveScripts this
  }
  if ('Variables' == (selection (contents categoriesFrame))) {
	updateBlocks this
  }
}

method targetModule MicroBlocksScripter {
  if (notNil targetObj) { return (module (classOf targetObj)) }
  return (module (project projectEditor))
}

method scriptEditor MicroBlocksScripter {
  return (contents scriptsFrame)
}

method blockPalette MicroBlocksScripter {
  return (contents blocksFrame)
}

method createInitialClass MicroBlocksScripter {
  module = (targetModule this)
  newClassName = (unusedClassName module 'MyClass')
  cl = (defineClassInModule module newClassName)
  removeAllParts (morph (contents scriptsFrame))
  targetObj = (instantiate cl)
  restoreScripts this
  saveScripts this
}

// initialization

method initialize MicroBlocksScripter aProjectEditor {
  targetObj = nil
  projectEditor = aProjectEditor
  scale = (global 'scale')
  morph = (newMorph this)
  setCostume morph (gray 150) // border color
  listColor = (gray 240)
  fontName = 'Arial'
  fontSize = 13
  nextX = 0
  nextY = 0

  // how often to check for script changes
  setFPS morph 4
  saveNeeded = false

  lbox = (listBox (categories this) nil (action 'updateBlocks' this) listColor)
  setFont lbox fontName fontSize
  categoriesFrame = (scrollFrame lbox listColor)
  setExtent (morph categoriesFrame) (82 * scale) // initial width
  addPart morph (morph categoriesFrame)

  blocksPane = (newBlocksPalette)
  setSortingOrder (alignment blocksPane) nil
  setPadding (alignment blocksPane) (15 * scale) // inter-column space
  setFramePadding (alignment blocksPane) (10 * scale) (10 * scale)
  blocksFrame = (scrollFrame blocksPane (gray 220))
  setAutoScroll blocksFrame false
  setExtent (morph blocksFrame) (200 * scale) // initial width
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

// layout

method redraw MicroBlocksScripter {
  fixLayout this
}

method fixLayout MicroBlocksScripter {
  catWidth = (max (toInteger ((width (morph categoriesFrame)) / (global 'scale'))) 75)
  blocksWidth = (max (toInteger ((width (morph blocksFrame)) / (global 'scale'))) 125)

  innerBorder = 2
  outerBorder = 2
  packer = (newPanePacker (bounds morph) innerBorder outerBorder)
  packPanesH packer categoriesFrame catWidth blocksFrame blocksWidth scriptsFrame '100%'
  packPanesV packer categoriesFrame '100%'
  packPanesV packer blocksFrame '100%'
  packPanesV packer scriptsFrame '100%'
  finishPacking packer
  fixResizerLayout this

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

// animation

method slideOpen MicroBlocksScripter end {
  show morph
  if (isNil end) { end = 50 }
  start = (- (height morph))
  addSchedule (global 'page') (newAnimation start end 250 (action 'setTop' morph))
}

method slideClosed MicroBlocksScripter {
  start = (top morph)
  end = (-5 - (height morph)) // off the top of the screen
  addSchedule (global 'page') (newAnimation start end 250 (action 'setTop' morph) (action 'hide' morph))
}

// MicroBlocksScripter UI support

method developerModeChanged MicroBlocksScripter {
  catList = (contents categoriesFrame)
  setCollection catList (categories this)
  if (not (contains (collection catList) (selection catList))) {
    select catList 'Output'
  } else {
    updateBlocks this
  }
}

method categories MicroBlocksScripter {
  initMicroBlocksSpecs (new 'SmallCompiler')
  result = (list 'Output' 'Input' 'Pins' 'Control' 'Math' 'Variables' 'Lists' 'Advanced' 'Functions')
  if (not (devMode)) {
  	removeAll result (list 'Lists' 'Advanced')
  }
  result = (join result (extraCategories (project projectEditor)))
  return result
}

method selectCategory MicroBlocksScripter aCategory {
  select (contents categoriesFrame) aCategory
}

method currentCategory MicroBlocksScripter {
  return (selection (contents categoriesFrame))
}

method updateBlocks MicroBlocksScripter {
  blocksPane = (contents blocksFrame)
  removeAllParts (morph blocksPane)

  cat = (selection (contents categoriesFrame))
  setRule (alignment blocksPane) 'multi-column'
  if ('Variables' == cat) {
	setRule (alignment blocksPane) 'none'
	addVariableBlocks this
  } ('Functions' == cat) {
	setRule (alignment blocksPane) 'none'
    addMyBlocks this
  } else {
    specs = (specsFor (authoringSpecs) cat)
    for spec specs {
	  addBlock this (blockForSpec spec) spec
    }
  }
  cleanUp blocksPane
}

method addVariableBlocks MicroBlocksScripter {
  scale = (global 'scale')
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (16 * scale))

  addButton this 'Add a variable' (action 'createSharedVariable' this) 'Variables are visible to all scripts.'
  sharedVars = (sharedVars this)
  if (notEmpty sharedVars) {
	addButton this 'Delete a variable' (action 'deleteSharedVariable' this)
	nextY += (8 * scale)
	for varName sharedVars {
	  lastY = nextY
	  b = (toBlock (newReporter 'v' varName))
	  addBlock this b nil // true xxx
//	  readout = (makeMonitor b)
// 	  setGrabRule (morph readout) 'ignore'
// 	  setStyle readout 'varPane'
// 	  setPosition (morph readout) nextX lastY
// 	  addPart (morph (contents blocksFrame)) (morph readout)
// 	  step readout
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
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (16 * scale))

  addButton this 'Add a function' (action 'createSharedBlock' this)
  nextY += (8 * scale)

  for f (functions (targetModule this)) {
	if (or (devMode) (not (beginsWith (functionName f) '_'))) {
	  spec = (specForOp (authoringSpecs) (functionName f))
	  if (isNil spec) { spec = (blockSpecFor f) }
	  addBlock this (blockForSpec spec) spec
	}
  }
}

method addSharedBlocks MicroBlocksScripter {
  scriptsPane = (contents scriptsFrame)
  for m (parts (morph scriptsPane)) {
    if (isClass (handler m) 'Block') {
      script = (expression (handler m) (className (classOf targetObj)))
      if ('to' == (primName script)) {
        op = (first (argList script))
        spec = (specForOp (authoringSpecs) op)
        if (isNil spec) {spec = (blockSpecFor (functionNamed op))}
        addBlock this (blockForSpec spec) spec
      }
    }
  }
}

method addButton MicroBlocksScripter label action hint {
  btn = (pushButton label (gray 130) action)
  if (notNil hint) { setHint btn hint }
  setPosition (morph btn) nextX nextY
  addPart (morph (contents blocksFrame)) (morph btn)
  nextY += ((height (morph btn)) + (7 * (global 'scale')))
}

method addSectionLabel MicroBlocksScripter label {
  scale = (global 'scale')
  labelColor = (gray 60)
  fontSize = (14 * scale)
  label = (newText label nil fontSize labelColor)
  nextY += (15 * scale)
  setPosition (morph label) (nextX - (10 * scale)) nextY
  addPart (morph (contents blocksFrame)) (morph label)
  nextY += ((height (morph label)) + (8 * scale))
}

method addBlock MicroBlocksScripter b spec isVarReporter {
  // install a 'morph' variable reporter for any slot that has 'morph' or 'Morph' as a hint
  if (isNil spec) { spec = (blockSpec b) }
  if (isNil isVarReporter) { isVarReporter = false }
  scale = (global 'scale')
  targetClass = (classOf targetObj)
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
	  if (or ('this' == hint) (and ('list' != hint) ((className targetClass) == hint))) {
		replaceInput b (at inputs i) (toBlock (newReporter 'v' 'this'))
	  }
	}
  }
  setGrabRule (morph b) 'template'
  setPosition (morph b) nextX nextY
  if isVarReporter { setLeft (morph b) (nextX + (135 * scale)) }
  addPart (morph (contents blocksFrame)) (morph b)
  nextY += ((height (morph b)) + (4 * (global 'scale')))
}

// variable operations

method sharedVars MicroBlocksScripter {
  return (copyWithout (variableNames (targetModule this)) 'extensions')
}

method createSharedVariable MicroBlocksScripter {
  // Temporary hack. Create shared variables in the session module.
  varName = (prompt (global 'page') 'New shared variable name?' '')
  if (varName != '') {
	setShared (uniqueVarName this varName) 0 (targetModule this)
	saveVariableNames (smallRuntime)
	updateBlocks this
  }
}

method uniqueVarName MicroBlocksScripter varName forScriptVar {
  // If varName matches an instance or shared variable, return a unique variant of it.
  // Otherwise, return varName unchanged.

  if (isNil forScriptVar) { forScriptVar = false }
  existingVars = (toList (join (sharedVars this) (fieldNames (classOf targetObj))))
  scripts = (scripts (classOf targetObj))
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

method deleteSharedVariable MicroBlocksScripter {
  if (isEmpty (sharedVars this)) { return }
  menu = (menu nil (action 'removeSharedVariable' this) true)
  for v (sharedVars this) { addItem menu v }
  popUpAtHand menu (global 'page')
}

method removeSharedVariable MicroBlocksScripter varName {
  deleteSharedVarMonitors this (targetModule this) varName
  deleteVar (targetModule this) varName
  clearVariableNames (smallRuntime)
  updateBlocks this
}

method deleteSharedVarMonitors MicroBlocksScripter module sharedVarName {
  for m (allMorphs (morph (global 'page'))) {
	if (isClass (handler m) 'Monitor') {
	  monitorAction = (getAction (handler m))
	  if (and (notNil monitorAction) ((count (arguments monitorAction)) >= 2)) {
		args = (arguments monitorAction)
		if (and (sharedVarName == (at args 1)) (module == (at args 2))) {
		  removeFromOwner m
		}
	  }
	}
  }
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
  if (isNil targetObj) { return }
  scriptsPane = (contents scriptsFrame)
  paneX = (left (morph scriptsPane))
  paneY = (top (morph scriptsPane))
  scriptsCopy = (list)
  for m (parts (morph scriptsPane)) {
    if (isClass (handler m) 'Block') {
      x = (((left m) - paneX) / scale)
      y = (((top m) - paneY) / scale)
      script = (expression (handler m) (className (classOf targetObj)))
      if (isOneOf (primName script) 'method' 'to') {
        updateFunctionOrMethod this script
        args = (argList script)
        // only store the stub for a method or function in scripts
        if ('method' == (primName script)) {
          script = (newCommand (primName script) (first args) (at args 2))
        } else {
	      script = (newCommand (primName script) (first args))
        }
      }
      add scriptsCopy (array x y script)
    }
  }
  setScripts (classOf targetObj) scriptsCopy
}

method updateFunctionOrMethod MicroBlocksScripter script {
  args = (argList script)
  functionName = (first args)
  newCmdList = (last args)
  if ('to' == (primName script)) {
    f = (functionNamed functionName)
  } ('method' == (primName script)) {
    f = (methodNamed (classOf targetObj) functionName)
  }
  if (notNil f) { updateCmdList f newCmdList }
}

method restoreScripts MicroBlocksScripter {
  scale = (global 'scale')
  scriptsPane = (contents scriptsFrame)
  removeAllParts (morph scriptsPane)
  clearDropHistory scriptsPane
  updateSliders scriptsFrame
  if (isNil targetObj) { return }
  targetClass = (classOf targetObj)
  scripts = (scripts targetClass)
  if (notNil scripts) {
    paneX = (left (morph scriptsPane))
    paneY = (top (morph scriptsPane))
    for entry (reversed scripts) {
      dta = (last entry)
      if ('method' == (primName dta)) {
        func = (methodNamed targetClass (first (argList dta)))
        block = (scriptForFunction func)
      } ('to' == (primName dta)) {
        func = (functionNamed (first (argList dta)))
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
		if  ('method' == (primName script)) {
		  targetClass = (classOf targetObj)
		  cmd = (copyMethodOrFunction this script targetClass)
		  block = (scriptForFunction (methodNamed targetClass (first (argList cmd))))
		} ('to' == (primName script)) {
		  cmd = (copyMethodOrFunction this script nil)
		  block = (scriptForFunction (functionNamed (first (argList cmd))))
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

method scrollToDefinitionOf MicroBlocksScripter aFunctionName {
  for m (parts (morph (contents scriptsFrame))) {
    if (isClass (handler m) 'Block') {
      def = (editedDefinition (handler m))
      if (notNil def) {
        if ((op def) == aFunctionName) {
          scrollIntoView scriptsFrame (fullBounds m) true // favorTopLeft
        }
      }
    }
  }
}

// Build Your Own Blocks

method createSharedBlock MicroBlocksScripter {
  page = (global 'page')
  cls = (classOf targetObj)
  name = (prompt page 'Enter a new block name:' 'myBlock')
  if (name == '') {return}
  opName = (uniqueMethodOrFunctionName this name)
  func = (defineFunctionInModule (targetModule this) opName (array) nil)
  spec = (blockSpecFromStrings opName ' ' name '')
  recordBlockSpec (authoringSpecs) opName spec
  addToBottom this (scriptForFunction func)
  updateBlocks this
}

method copyMethodOrFunction MicroBlocksScripter definition targetClass {
  primName = (primName definition)
  args = (argList definition)
  body = (last args)
  if (notNil body) { body = (copy body) }
  oldOp = (first args)
  oldSpec = (specForOp (authoringSpecs) oldOp)
  if ('method' == primName) {
	newOp = (uniqueMethodOrFunctionName this oldOp targetClass)
	parameterNames = (copyFromTo args 3 ((count args) - 1))
	addMethod targetClass newOp parameterNames body
	if (notNil oldSpec) {
	  oldClassName = (at args 2)
	  newSpec = (copyWithOp oldSpec newOp oldClassName (className targetClass))
	} else {
	  newSpec = (blockSpecFor (methodNamed targetClass newOp))
	}
  } else {
	newOp = (uniqueMethodOrFunctionName this oldOp)
	parameterNames = (copyFromTo args 2 ((count args) - 1))
	defineFunctionInModule (targetModule this) newOp parameterNames body
	if (notNil oldSpec) {
	oldLabel = (first (specs oldSpec))
	newLabel = (uniqueFunctionName this oldLabel)
	newSpec = (copyWithOp oldSpec newOp oldLabel newLabel)
	} else {
	  newSpec = (blockSpecFor (functionNamed (targetModule this) newOp))
	}
  }
  recordBlockSpec (authoringSpecs) newOp newSpec
  return (newCommand primName newOp)
}

method uniqueFunctionName MicroBlocksScripter baseSpec {
  existingNames = (list)
  for spec (values (blockSpecs (project projectEditor))) {
	add existingNames (first (words (first (specs spec))))
  }
  specWords = (words baseSpec)
  firstWord = (first specWords)
  if ('_' == firstWord) {
	firstWord = 'f'
	specWords = (join (array 'f') specWords)
  }
  atPut specWords 1 (uniqueNameNotIn existingNames firstWord)
  return (joinStrings specWords ' ')
}

method removedUserDefinedBlock MicroBlocksScripter function {
  // Remove the given user-defined function or method.

  if (isMethod function) {
	removeMethodNamed (class (classIndex function)) (functionName function)
  } else {
	removeFunction (module function) function
  }

  blockDeleted (project projectEditor) (functionName function)
}

method uniqueMethodOrFunctionName MicroBlocksScripter baseName aClass {
  baseName = (withoutTrailingDigits baseName)
  if (baseName == '') { baseName = 'm' }
  existingNames = (list)
  addAll existingNames (allOpNames (authoringSpecs))
  if (isNil aClass) {
	for f (globalFuncs) { add existingNames (functionName f) }
	for f (functions (targetModule this)) { add existingNames (functionName f) }
  } else {
	addAll existingNames (methodNames aClass)
  }
  return (uniqueNameNotIn existingNames baseName)
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
	if (and (isNil defaultValue) ('color' == typeStr)) {
      defaultValue = (color 35 190 30)
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
  m = (module (project projectEditor))
  result = (dictionary)
  for f (functions m) {
	addAll result (allBlocks (cmdList f))
  }
  for c (classes m) {
	for m (methods c) {
	  addAll result (allBlocks (cmdList m))
	}
	scripts = (scripts c)
	if (notNil (scripts c)) {
	  for s (scripts c) {
		addAll result (allBlocks (at s 3))
	  }
	}
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
	if ('method' == (primName expr)) {
	  func = (methodNamed (classOf targetObj) (first (argList expr)))
	  block = (scriptForFunction func)
	} ('to' == (primName expr)) {
	  func = (functionNamed (first (argList expr)))
	  block = (scriptForFunction func)
	} else {
	  block = (toBlock expr)
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
  pickFileToOpen (action 'importLibraryFromFile' this) (gpExamplesFolder) (array '.ulib')
}

method importLibraryFromFile MicroBlocksScripter fileName {
  // Import a library with the give file path.

  data = (readFile fileName)
  if (isNil data) { error (join 'Could not read: ' fileName) }

  myModule = (targetModule this)
  for cmd (parse data) {
	op = (primName cmd)
	args = (argList cmd)
	if ('sharedVariables' == op) {
	  for v args { addVar myModule v }
	} ('spec' == op) {
	  blockType = (at args 1)
	  blockOp = (at args 2)
	  specString = (at args 3)
	  slotTypes = ''
	  if ((count args) > 3) { slotTypes = (at args 4) }
	  slotDefaults = (copyFromTo args 5)
	  spec = (blockSpecFromStrings blockOp blockType specString slotTypes slotDefaults)
	  recordBlockSpec (authoringSpecs) blockOp spec
	} ('to' == op) {
	  args = (toList args)
	  fName = (removeFirst args)
	  fBody = nil
	  if (isClass (last args) 'Command') { fBody = (removeLast args) }
	  func = (newFunction fName args fBody myModule)
	  oldFunc = (functionNamed myModule fName)
	  if (notNil oldFunc) { removeFunction myModule oldFunc }
	  addFunction myModule func
	}
  }
  select (contents categoriesFrame) 'Functions'
  updateBlocks this
}

method exportAsLibrary MicroBlocksScripter defaultFileName {
  fileName = (fileToWrite (withoutExtension defaultFileName) '.ulib')
  if (isEmpty fileName) { return }
  if (not (endsWith fileName '.ulib' )) { fileName = (join fileName '.ulib') }

  result = (list)

  // Add shared variable declaration, if needed
  sharedVars = (variableNames (targetModule this))
  if ((count sharedVars) > 0) {
	varDeclaration = (list 'sharedVariables')
	for v sharedVars { add varDeclaration (printString v) }
	add result (joinStrings varDeclaration ' ')
	add result (newline)
	add result (newline)
  }

  // Add block specs
  for func (functions (targetModule this)) {
	spec = (specForOp (authoringSpecs) (functionName func))
	if (notNil spec) {
	  add result (specDefinitionString spec)
	}
	add result (newline)
  }
  add result (newline)

  // Add function definitions
  pp = (new 'PrettyPrinter')
  for func (functions (targetModule this)) {
	add result (prettyPrintFunction pp func)
	add result (newline)
  }

  writeFile fileName (joinStrings result)
}

// drop handling

method wantsDropOf MicroBlocksScripter aHandler {
  return (isAnyClass aHandler 'Block' 'Monitor')
}

method justReceivedDrop MicroBlocksScripter aHandler {
  // Delete Blocks or Monitors dropped anywhere but the scripting area.

  if (not (userDestroy (morph aHandler))) { // abort drop-to-delete
    grab (hand (global 'page')) aHandler
    return
  }
  if ('Functions' == (selection (contents categoriesFrame))) {
	// May have just deleted a function, so update the palette
	updateBlocks this
  }
}
