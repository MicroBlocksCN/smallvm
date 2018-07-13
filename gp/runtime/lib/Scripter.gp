// Scripter.gp - authoring-level scripter w/ built-in palette

defineClass Scripter morph targetObj projectEditor stageMorph saveNeeded classPane classReadout searchBox classMenuButton newInstanceButton categoriesFrame catResizer blocksFrame blocksResizer scriptsFrame resizer nextX nextY

method targetModule Scripter {
  if (notNil targetObj) { return (module (classOf targetObj)) }
  return (module (project projectEditor))
}

method targetObj Scripter { return targetObj }
method targetClass Scripter { return (classOf targetObj) }

method setTargetObj Scripter obj {
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

to showInScripter targetObj {
  if (and (not (isUserDefined (classOf targetObj))) (not (shiftKeyDown (keyboard (global 'page'))))) {return}
  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'Scripter') { scripter = (handler m) }
	if (isClass (handler m) 'ProjectEditor') { scripter = (scripter (handler m)) }
  }
  if (isNil scripter) {
    page = (global 'page')
    scripter = (initialize (new 'Scripter'))
	top = ((25 * (global 'scale')) + 7)
    setPosition (morph scripter) 5 top
	h = (((height (morph page)) - top) - 5)
	w = (clamp ((width (morph page)) / 2) 500 1200)
	setExtent (morph scripter) w h
    addPart page scripter
  }
  setTargetObj scripter targetObj
}

to startEditingScripts {
  page = (global 'page')
  for m (parts (morph page)) {
    if (isClass (handler m) 'Scripter') { scripter = (handler m) }
    if (isClass (handler m) 'ProjectEditor') { scripter = (scripter (handler m)) }
  }
  if (or (isNil scripter) (not (isVisible (morph scripter)))) {
    // don't initiate editing scripts in presentation mode
    return
  }
  startEditing (contents (getField scripter 'scriptsFrame'))
  (focus (keyboard page))
}

to showBlockCategory aCategory {
  page = (global 'page')
  for m (parts (morph page)) {
    if (isClass (handler m) 'Scripter') { scripter = (handler m) }
    if (isClass (handler m) 'ProjectEditor') { scripter = (scripter (handler m)) }
    if (isClass (handler m) 'MicroBlocksScripter') { scripter = (handler m) }
  }
  if (isNil scripter) {return}
  selectCategory scripter aCategory
}

// initialization

method initialize Scripter aProjectEditor {
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

  // save scripts once a second, if they could have changed
  setFPS morph 1
  saveNeeded = false

  classPane = (makeClassPane this)
  addPart morph (morph classPane)

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
  setExtent (morph blocksFrame) nil (285 * scale) // initial height
  addPart morph (morph blocksFrame)

  scriptsPane = (newScriptEditor 10 10 nil)
  scriptsFrame = (scrollFrame scriptsPane (gray 220))
  addPart morph (morph scriptsFrame)

  // add resizers last so they are in front
  catResizer = (resizeHandle categoriesFrame 'horizontal')
  addPart morph (morph catResizer)

  blocksResizer = (resizeHandle blocksFrame 'vertical')
  addPart morph (morph blocksResizer)

  resizer = (resizeHandle this 'horizontal')

  setGrabRule morph 'ignore'
  for m (parts morph) { setGrabRule m 'ignore' }

  setMinExtent morph (scale * 235) (scale * 200)
  setExtent morph (scale * 600) (scale * 700)
  restoreScripts this

  if (isNil projectEditor) { select (contents categoriesFrame) 'Control' }
  return this
}

method makeClassPane Scripter {
  scale = (global 'scale')
  space = (5 * scale)
  labelTop = (7 * scale)

  classPane = (newBox nil (gray 220) nil nil false false)
  setCorner classPane 0

  classReadout = (newText '---' 'Arial Bold' (14 * scale))
  setPosition (morph classReadout) (2 * space) labelTop
  addPart (morph classPane) (morph classReadout)

  classMenuButton = (makeMenuButton this (action 'classMenu' this))
  addPart (morph classPane) (morph classMenuButton)
  if (notNil projectEditor) { hide (morph classMenuButton) }

  newInstanceButton = (pushButton 'New instance' (color 130 130 130) (action 'addInstance' this))
  setHint newInstanceButton 'Add a new instance of this class to the page'
  addPart (morph classPane) (morph newInstanceButton)
  if (notNil projectEditor) { hide (morph newInstanceButton) }

  searchBox = (newBlockSearchBox 90 19)
  addPart (morph classPane) (morph searchBox)

  return classPane
}

method makeMenuButton Scripter action {
  scale = (global 'scale')
  w = (17 * scale)
  h = (13 * scale)
  hCenter = (w / 2)
  arrowW = (9 * scale)
  arrowH = (7 * scale)
  arrowX = ((w / 2) - (arrowW / 2))
  arrowY = (3 * scale)
  arrowRect = (rect arrowX arrowY arrowW arrowH)

  normalBM = (newBitmap w h (gray 210))
  fillArrow (newShapeMaker normalBM) arrowRect 'down' (gray 80)

  highlightBM = (newBitmap w h (gray 210))
  fillArrow (newShapeMaker highlightBM) arrowRect 'down' (gray 150)

  btn = (new 'Trigger' (newMorph) action)
  setHandler (morph btn) btn
  replaceCostumes btn normalBM highlightBM highlightBM
  setCostume (morph btn) normalBM
  return btn
}

// layout

method redraw Scripter {
  fixLayout this
}

method fixLayout Scripter {
  innerBorder = 2
  outerBorder = 2
  catWidth = (max (toInteger ((width (morph categoriesFrame)) / (global 'scale'))) 20)
  blocksHeight = (max (toInteger ((height (morph blocksFrame)) / (global 'scale'))) 5)
  packer = (newPanePacker (bounds morph) innerBorder outerBorder)
  packPanesH packer classPane '100%'
  packPanesH packer categoriesFrame catWidth blocksFrame '100%'
  packPanesH packer scriptsFrame '100%'
  packPanesV packer classPane 28 categoriesFrame blocksHeight scriptsFrame '100%'
  packPanesV packer classPane 28 blocksFrame blocksHeight
  finishPacking packer
  fixClassPaneLayout this
  fixResizerLayout this
  if (notNil projectEditor) { fixLayout projectEditor true }
}

method fixClassPaneLayout Scripter {
  scale = (global 'scale')

  m = (morph newInstanceButton)
  x = ((right (morph classPane)) - ((width m) + (10 * scale)))
  y = ((top (morph classPane)) + ((((height (morph classPane))) - (height m)) / 2))
  setPosition m x y

  m = (morph classMenuButton)
  x = ((right (morph classReadout)) + (3 * scale))
  y = ((top (morph classReadout)) + (1 * scale))
  setPosition m x y

  m = (morph searchBox)
  x = ((right (morph classPane)) - ((width m) + (5 * scale)))
  y = ((top (morph classPane)) + ((((height (morph classPane))) - (height m)) / 2))
  setPosition m x y
}

method fixResizerLayout Scripter {
  scale = (global 'scale')
  size = (10 * scale)
  border = (2 * scale)

  // categories pane resizer
  setLeft (morph catResizer) (right (morph categoriesFrame))
  setTop (morph catResizer) (top (morph categoriesFrame))
  setExtent (morph catResizer) size (height (morph categoriesFrame))
  drawPaneResizingCostumes catResizer

  // blocks pane resizer
  setLeft (morph blocksResizer) (left morph) // ((bottom (morph blocksFrame)) - extra)
  setTop (morph blocksResizer) (bottom (morph blocksFrame))
  setExtent (morph blocksResizer) (width morph) size
  drawPaneResizingCostumes blocksResizer

  // scripter width resizer
  setLeft (morph resizer) ((right morph) - border)
  setTop (morph resizer) (top morph)
  setExtent (morph resizer) size (height morph)
  drawPaneResizingCostumes resizer
  addPart morph (morph resizer) // bring to front
}

// animation

method slideOpen Scripter end {
  show morph
  if (isNil end) { end = 50 }
  start = (- (height morph))
  addSchedule (global 'page') (newAnimation start end 250 (action 'setTop' morph))
}

method slideClosed Scripter {
  start = (top morph)
  end = (-5 - (height morph)) // off the top of the screen
  addSchedule (global 'page') (newAnimation start end 250 (action 'setTop' morph) (action 'hide' morph))
}

// scripter UI support

method developerModeChanged Scripter {
  catList = (contents categoriesFrame)
  setCollection catList (categories this)
  if (not (contains (collection catList) (selection catList))) {
    select catList 'Control'
  } else {
    updateBlocks this
  }
}

method updateClassName Scripter {
  setText classReadout (className (classOf targetObj))
  redraw classReadout
  fixClassPaneLayout this
}

method devModeCategories Scripter {
  return (array 'Control' 'Motion' 'Looks' 'Drawing' 'Drawing - Paths' 'Color' 'Pixels' 'Sensing' 'Pen' 'Sound' 'Music' 'Operators' 'Variables' 'Words' 'Data' 'Table' 'Structure' 'Network' 'Functions' 'Serial Port' 'File Stream' 'Debugging' 'My Blocks')
}

method userModeCategories Scripter {
  return (array 'Control' 'Motion' 'Looks' 'Drawing' 'Color' 'Pixels' 'Sensing' 'Pen' 'Sound' 'Operators' 'Variables' 'Words' 'Data' 'Structure' 'Network' 'My Blocks')
}

method categories Scripter {
  if (devMode) {
	result = (devModeCategories this)
  } else {
	result = (userModeCategories this)
  }
  result = (join result (extraCategories (project projectEditor)))
  return result
}

method selectCategory Scripter aCategory {
  select (contents categoriesFrame) aCategory
}

method currentCategory Scripter {
  return (selection (contents categoriesFrame))
}

method isUserBlock Scripter spec {
  // Return true if the given block should be shown in the palette  in user mode.

  devOnlyBlocks = (array
	'whenPageResized' 'whenTracking' 'whenScrolled'
	'stageWidth' 'stageHeight'
	'ln' 'exp' 'toFloat' 'maxInt' 'minInt'
	'&' '|' '^' '<<' '>>' '>>>'
	'gather' 'canonicalizedWord' 'string'
	'self_addPart' 'self_owner' 'self_stage' 'self_parts'
	'httpGet' 'jsonFormat' 'jsonStringify' 'jsonParse' 'openExplorer' 'print' 'points' 'showText'
	'self_localMouseX' 'self_localMouseY' 'self_setPinXY' 'self_floodFill'
	'fftOfSamples' 'clamp' 'isAnyClass' 'allInstances')
  return (not (contains devOnlyBlocks (blockOp spec)))
}

method updateBlocks Scripter {
  blocksPane = (contents blocksFrame)
  removeAllParts (morph blocksPane)

  cat = (selection (contents categoriesFrame))
  setRule (alignment blocksPane) 'multi-column'
  if ('Variables' == cat) {
	setRule (alignment blocksPane) 'none'
	addVariableBlocks this
  } ('My Blocks' == cat) {
	setRule (alignment blocksPane) 'none'
    addMyBlocks this
  } else {
    specs = (specsFor (authoringSpecs) cat)
    for spec specs {
      if (or (devMode) (isUserBlock this spec)) {
        addBlock this (blockForSpec spec) spec
      }
    }
  }
  cleanUp blocksPane
}

method addVariableBlocks Scripter {
  scale = (global 'scale')
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (-3 * scale))

  addSectionLabel this 'Shared Variables'
  addButton this 'Add a shared variable' (action 'createSharedVariable' this) 'A shared variable is visible to all scripts in all classes. Any script can view or change shared variables, making them useful for things like game scores.'
  sharedVars = (sharedVars this)
  if (notEmpty sharedVars) {
	addButton this 'Delete a shared variable' (action 'deleteSharedVariable' this)
	nextY += (8 * scale)
	for varName sharedVars {
	  lastY = nextY
	  b = (toBlock (newReporter 'shared' varName))
	  addBlock this b nil true
	  readout = (makeMonitor b)
	  setGrabRule (morph readout) 'ignore'
	  setStyle readout 'varPane'
	  setPosition (morph readout) nextX lastY
	  addPart (morph (contents blocksFrame)) (morph readout)
	  step readout
	  refIcon = (initialize (new 'MorphRefIcon') varName nil (targetModule this))
	  setPosition (morph refIcon) (nextX + (114 * scale)) (lastY + (5 * scale))
	  addPart (morph (contents blocksFrame)) (morph refIcon)
	}
	nextY += (5 * scale)
	addBlock this (toBlock (newCommand 'setShared' (first sharedVars) 0)) nil false
	addBlock this (toBlock (newCommand 'increaseShared' (first sharedVars) 1)) nil false
  }

  if (notNil targetObj) {
	localVars = (toList (fieldNames (classOf targetObj)))
	if (devMode) {
	  addFirst localVars 'this'
	} else {
	  remove localVars 'morph'
	}
	removeableVars = (copyWithout (toArray localVars) 'morph')

	addSectionLabel this 'Instance Variables'
	addButton this 'Add an instance variable' (action 'createInstanceVariable' this) 'An instance variable stores a value specific to that instance. Every instance has its own value for each instance variable. For example, in a racing game instances of "Car" might have different values for their "speed" instance variable.'
	if (notEmpty removeableVars) {
	  addButton this 'Delete an instance variable' (action 'deleteInstanceVariable' this)
	}
	nextY += (8 * scale)

	if ((count localVars) > 0) {
	  firstVar = (first localVars)
	  if (devMode) {
		if ((count localVars) > 2) {
		  firstVar = (at localVars 3) // first user instance variable
		} else {
		  firstVar = 'n' // no user instance variables; use 'n' as placeholder
		}
	  }
	  for varName localVars {
		lastY = nextY
		if ('this' == varName) {
		  b = (toBlock (newReporter 'v' varName))
		} else {
		  b = (toBlock (newReporter 'my' varName))
		}
		addBlock this b nil true
		readout = (makeMonitor b)
		setGrabRule (morph readout) 'ignore'
		setStyle readout 'varPane'
		setPosition (morph readout) nextX lastY
		addPart (morph (contents blocksFrame)) (morph readout)
		step readout
		refIcon = (initialize (new 'MorphRefIcon') varName targetObj)
		setPosition (morph refIcon) (nextX + (114 * scale)) (lastY + (5 * scale))
		addPart (morph (contents blocksFrame)) (morph refIcon)
	  }
	  nextY += (5 * scale)
	  addBlock this (toBlock (newCommand 'setMy' firstVar 0)) nil false
	  addBlock this (toBlock (newCommand 'increaseMy' firstVar 1)) nil false
	}
  }

  if (devMode) {
	addSectionLabel this 'Script Variables'
	nextY += (2 * scale)
	addBlock this (toBlock (newCommand 'local' 'var' 0)) nil false
	addBlock this (toBlock (newCommand '=' 'var' 0)) nil false
	addBlock this (toBlock (newCommand '+=' 'var' 1)) nil false
  }
}

method addMyBlocks Scripter {
  scale = (global 'scale')
  nextX = ((left (morph (contents blocksFrame))) + (20 * scale))
  nextY = ((top (morph (contents blocksFrame))) + (-3 * scale))
  if (isNil targetObj) { return }

  addSectionLabel this 'Shared Blocks'
  addButton this 'Make a shared block' (action 'createSharedBlock' this)
  nextY += (8 * scale)

  for f (functions (targetModule this)) {
	spec = (specForOp (authoringSpecs) (functionName f))
	if (isNil spec) { spec = (blockSpecFor f) }
	addBlock this (blockForSpec spec) spec
  }

  addSectionLabel this 'Methods (i.e blocks for this class only)'
  addButton this 'Make a method' (action 'createMethodBlock' this)
  if (not (implements targetObj 'initialize')) {
	addButton this 'Make an initialize method' (action 'createInitializeMethodBlock' this)
  }
  nextY += (8 * scale)

  // add method blocks
  for m (methods (classOf targetObj)) {
    op = (functionName m)
    spec = (specForOp (authoringSpecs) op)
    if (isNil spec) {spec = (blockSpecFor m)}
    addBlock this (blockForSpec spec) spec
  }
}

method addSharedBlocks Scripter {
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

method addButton Scripter label action hint {
  btn = (pushButton label (gray 130) action)
  if (notNil hint) { setHint btn hint }
  setPosition (morph btn) nextX nextY
  addPart (morph (contents blocksFrame)) (morph btn)
  nextY += ((height (morph btn)) + (7 * (global 'scale')))
}

method addSectionLabel Scripter label {
  scale = (global 'scale')
  labelColor = (gray 60)
  fontSize = (14 * scale)
  label = (newText label nil fontSize labelColor)
  nextY += (15 * scale)
  setPosition (morph label) (nextX - (10 * scale)) nextY
  addPart (morph (contents blocksFrame)) (morph label)
  nextY += ((height (morph label)) + (8 * scale))
}

method addBlock Scripter b spec isVarReporter {
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

method sharedVars Scripter {
  return (copyWithout (variableNames (targetModule this)) 'extensions')
}

method createInstanceVariable Scripter {
  varName = (prompt (global 'page') 'New variable name?' '')
  if (varName != '') {
	addVariable this (uniqueVarName this varName)
	updateBlocks this
  }
}

method createSharedVariable Scripter {
  // Temporary hack. Create shared variables in the session module.
  varName = (prompt (global 'page') 'New shared variable name?' '')
  if (varName != '') {
	setShared (uniqueVarName this varName) 0 (targetModule this)
	updateBlocks this
  }
}

method uniqueVarName Scripter varName forScriptVar {
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

method deleteInstanceVariable Scripter {
  removeableVars = (toList (fieldNames (classOf targetObj)))
  remove removeableVars 'morph'
  if (isEmpty removeableVars) { return }

  menu = (menu nil (action 'removeInstanceVariable' this) true)
  for v removeableVars { addItem menu v }
  popUpAtHand menu (global 'page')
}

method removeInstanceVariable Scripter varName {
  deleteInstVarMonitors this (classOf targetObj) varName
  if (hasField targetObj varName) {
	deleteField (classOf targetObj) varName
  }
  updateBlocks this
}

method deleteInstVarMonitors Scripter class instVarName {
  for m (allMorphs (morph (global 'page'))) {
	if (isClass (handler m) 'Monitor') {
	  monitorAction = (getAction (handler m))
	  if (and (notNil monitorAction) ((count (arguments monitorAction)) >= 2)) {
		args = (arguments monitorAction)
		if (and (instVarName == (at args 2)) (class == (classOf (first args)))) {
		  removeFromOwner m
		}
	  }
	}
  }
}

method deleteSharedVariable Scripter {
  if (isEmpty (sharedVars this)) { return }
  menu = (menu nil (action 'removeSharedVariable' this) true)
  for v (sharedVars this) { addItem menu v }
  popUpAtHand menu (global 'page')
}

method removeSharedVariable Scripter varName {
  deleteSharedVarMonitors this (targetModule this) varName
  deleteVar (targetModule this) varName
  updateBlocks this
}

method deleteSharedVarMonitors Scripter module sharedVarName {
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

method addVariable Scripter varName {
  if (isNil targetObj) { error 'No target object' }
  addField (classOf targetObj) varName
  for each (allInstances (classOf targetObj)) {
	setField each varName 0
  }
  updateBlocks this
}

method renameInstanceVariable Scripter oldName newName {
  if (isNil targetObj) { error 'No target object' }
  renameField (classOf targetObj) oldName newName
  updateBlocks this
}

// morph reference arrow support

method drawMorphRefLinks Scripter pen {
  if (or (isNil (owner morph)) (isHidden morph)) { return }
  if ('Variables' != (currentCategory this)) { return }
  arrowColor = (gray 100)
  for m (parts (morph (contents blocksFrame))) {
	h = (handler m)
	if (isClass h 'MorphRefIcon') {
	  if (isActive h) {
		targetM = (targetMorph h)
		if (notNil targetM) {
		  startX = (hCenter (bounds m))
		  startY = (vCenter (bounds m))
		  endX = (hCenter (bounds targetM))
		  endY = (vCenter (bounds targetM))
		  drawArrow pen startX startY endX endY arrowColor
		}
	  }
	}
  }
}

// handle drops

method wantsDropOf Scripter aHandler {
  return (and
	('Variables' == (currentCategory this))
	(not (hasField aHandler 'window'))
	(intersects (bounds (morph aHandler)) (bounds (morph blocksFrame))))
}

method justReceivedDrop Scripter aHandler {
  hand = (hand (global 'page'))
  dropX = (x hand)
  dropY = (y hand)
  for m (parts (morph (contents blocksFrame))) {
	h = (handler m)
	if (isClass h 'Monitor') {
	  if (containsPoint (bounds m) dropX dropY) {
		getter = (getField h 'getAction')
		getterArgs = (arguments getter)
		if ('shared' == (function getter)) {
		  setShared (first getterArgs) aHandler (last getterArgs)
		} ('getFieldOrNil' == (function getter)) {
		  varName = (last getterArgs)
		  if ('morph' != varName) {
			setField (first getterArgs) varName aHandler
		  }
		}
	  }
	}
  }
  animateBackToOldOwner (hand (global 'page')) (morph aHandler)
}

// instance creation

method addInstance Scripter {
  if (isNil targetObj) { return }
  setTargetObj this (instantiate (classOf targetObj) (stageMorph this))
}

// class operations

method classMenu Scripter {
  menu = (menu nil (action 'viewClassNamed' this) true)
  for className (sortedUserClassNames this) {
	addItem menu className
  }
  addLine menu
  addItem menu 'create a new class' '_createClass'
  addItem menu 'rename this class' '_renameClass'
  popUpAtHand menu (global 'page')
}

method sortedUserClassNames Scripter {
  result = (list)
  for cl (classes (targetModule this)) {
    if (notNil (scripts cl)) { add result (className cl) }
  }
  return (sorted result)
}

method viewClassNamed Scripter className {
  if (beginsWith className '_') { // class operation
	if ('_createClass' == className) { createClass this }
	if ('_renameClass' == className) { renameClass this (classOf targetObj) }
	return
  }
  if (isNil (class className)) { return }
  if (not (isClass targetObj className)) {
	setTargetObj this (findInstance this (classOf targetObj))
  }
}

method createClass Scripter isHelperClass {
  newClassName = (prompt (global 'page') 'Class name?' 'MyClass')
  if (or (isNil newClassName) (newClassName == '')) { return }
  cl = (makeNewClass this newClassName isHelperClass)
  removeAllParts (morph (contents scriptsFrame))
  setTargetObj this (instantiate cl (stageMorph this))
}

method createInitialClass Scripter {
  cl = (makeNewClass this 'MyClass')
  removeAllParts (morph (contents scriptsFrame))
  targetObj = (instantiate cl (stageMorph this))
  restoreScripts this
  saveScripts this
}

method setStageMorph Scripter stageM { stageMorph = stageM }

method stageMorph Scripter {
  // Return the morph of the stage, if there is one, or the morph of the page.
  if (notNil stageMorph) { return stageMorph }
  if (notNil projectEditor) { return (morph (stage projectEditor)) }
  return (morph (global 'page'))
}

method makeNewClass Scripter baseName isHelperClass {
  if (isNil isHelperClass) { isHelperClass = false }
  module = (targetModule this)
  newClassName = (unusedClassName module baseName)
  if isHelperClass {
	result = (defineClassInModule module newClassName)
  } else {
	result = (defineClassInModule module newClassName 'morph')
  }
  return result
}

method findInstance Scripter aClass {
  for m (allMorphs (morph (global 'page'))) {
    if (isClass (handler m) aClass) { return (handler m) }
  }
  return nil
}

method renameClass Scripter aClass {
  if ((module aClass) === (topLevelModule)) { return }
  oldClassName = (className aClass)
  newClassName = (prompt (global 'page') 'New class name?' oldClassName)
  if (or (newClassName == '') (newClassName == oldClassName)) { return }
  if (notNil (classNamed (module aClass) newClassName)) {
	inform (global 'page') (join 'Sorry, "' newClassName '" is already used')
	return
  }
  setName aClass newClassName
  if (aClass == (classOf targetObj)) {
	updateClassName this
  }
}

method exportClass Scripter aClass {
  fileName = (fileToWrite (className aClass) '.gp')
  if (isEmpty fileName) { return }
  pp = (new 'PrettyPrinter')
  contents = (join
	(specStringForFunctionsAndMethodsDefinedInClass aClass)
	(defStringForFunctionsDefinedInClass aClass)
	(prettyPrintClass pp aClass)
	(newline)
	(scriptString aClass))
  writeFile fileName contents
}

method importClass Scripter {
  pickFileToOpen (action 'importClassFromFile' this) (gpFolder) '.gp'
}

method importClassFromFile Scripter fileName {
  // Import a class from the given source file.

  projectModule = (targetModule this)
  s = (readFile fileName)
  m = (loadModuleFromString (initialize (new 'Module')) s)

  // import classes
  existingClassNames = (list)
  for c (classes projectModule) {
	add existingClassNames (className c)
  }
  classNameMap = (dictionary)
  for c (classes m) {
    newName = (uniqueNameNotIn existingClassNames (className c))
    atPut classNameMap (className c) newName
	setName c newName
	setField c 'module' projectModule
	addClass projectModule c
  }

  // import global functions
  // xxx later: deal with name conflicts (need to rename both the function and it's block spec)
  for f (functions m) {
	addFunction projectModule f
  }

  // add specs
  specDB = (authoringSpecs)
  for expr (parse s) {
	if (and (isClass expr 'Reporter') ('spec' == (primName expr))) {
	  spec = (specForEntry specDB (argList expr))
	  updateClassHint spec classNameMap
	  // xxx if block spec already exists, need to rename both spec and underlying method name
	  recordBlockSpec specDB (blockOp spec) spec
	}
  }

  // select imported class
  if ((count classNameMap) > 0) {
 	newClassName = (first (keys classNameMap))
	setTargetObj this (instantiate (classNamed projectModule newClassName) (stageMorph this))
  }
}

method deleteClass Scripter aClass {
  if ((module aClass) === (topLevelModule)) { return }
  if ('Variables' == (currentCategory this)) { selectCategory this 'Control' }
  className = (className aClass)
  targetObj = nil
  clearLibrary (library projectEditor)
  removeClassFromPages (project projectEditor) aClass
  deleteInstances this (allInstances aClass)
  gc
  instCount = (count (allInstances aClass))
  if (instCount > 0) {
	inform (global 'page') (join 'There are still ' instCount ' references to instances of this class; cannot delete')
	return
  }
  if (not (beginsWith className 'Obsolete')) {
	setField aClass 'className' (join 'Obsolete ' className)
  }
  setField aClass 'scripts' nil
  setField aClass 'comments' (array)
  removeClass (module aClass) aClass
  showAnotherClass this
}

method deleteInstances Scripter instances {
  // Remove the given list of instances from their owners.
  for obj instances {
	if (hasField obj 'morph') {
	  m = (morph obj)
	  o = (owner m)
	  if (notNil o) { removePart o m }
	}
  }
}

method showAnotherClass Scripter {
  // Try to view an existing instance of an existing user-defined class.
  // If no classes have instances, create one.
  // If there are no user-defined classes, view nil.
  module = (targetModule this)
  otherClasses = (sortedUserClassNames this)
  for className otherClasses {
	cl = (classNamed module className)
	if ((count (allInstances cl)) > 0) {
	  	setTargetObj this (findInstance this cl)
		return
	}
  }
  if ((count otherClasses) > 0) {
    cls = (classNamed module (first otherClasses))
    setTargetObj = (instantiate cls (stageMorph this))
  } else {
	setTargetObj this nil
  }
}

// save and restore scripts in class

method scriptChanged Scripter { saveNeeded = true }

method step Scripter {
  // Note: Sometimes get bursts of multiple 'changed' events, but those
  // events merely set the saveNeeded flag. This method does the actual
  // saveScripts if the saveNeeded flag is true.

  if saveNeeded {
	clearMethodCaches  // reset all cached after any programming change (probably only needs to be done for my scripts)
    saveScripts this
    saveNeeded = false
  }
}

method saveScripts Scripter {
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

method renameScriptToAPublicName Scripter from to {
  if (isNil targetObj) { return }
  cl = (classOf targetObj)
  scripts = (scripts cl)
  for s scripts {
    cmd = (at s 3)
    if (and ((primName cmd) == 'method') ((getField cmd 7) == from) ((getField cmd 8) == (className cl))) {
      setField cmd 7 to
    }
  }
  updateBlocks this
}

method updateFunctionOrMethod Scripter script {
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

method restoreScripts Scripter {
  scale = (global 'scale')
  updateClassName this
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

method pasteScripts Scripter scriptString {
  scale = (global 'scale')
  updateClassName this
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

method scrollToDefinitionOf Scripter aFunctionName {
  for m (parts (morph (contents scriptsFrame))) {
    if (isClass (handler m) 'Block') {
      def = (editedDefinition (handler m))
      if (notNil def) {
        if (== (op def) aFunctionName) {
          scrollIntoView scriptsFrame (fullBounds m) true // favorTopLeft
        }
      }
    }
  }
}

// Build Your Own Blocks

method createSharedBlock Scripter {
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

method createMethodBlock Scripter {
  page = (global 'page')
  cls = (classOf targetObj)
  name = (prompt page 'Enter a new block name:' 'myBlock')
  if (name == '') {return}
  opName = (uniqueMethodOrFunctionName this name cls)
  func = (addMethod cls opName)
  spec = (blockSpecFromStrings opName ' ' (join name ' _') (className cls))
  recordBlockSpec (authoringSpecs) opName spec
  addToBottom this (scriptForFunction func)
  updateBlocks this
}

method copyMethodOrFunction Scripter definition targetClass {
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

method uniqueMethodName Scripter targetClass baseSpec {
  existingNames = (list)
  allSpecs = (blockSpecs (project projectEditor))
  for method (methods targetClass) {
	methodSpec = (at allSpecs (functionName method)) // should always find a spec
	if (notNil methodSpec) {
	  add existingNames (first (words (first (specs methodSpec))))
	}
  }
  specWords = (words baseSpec)
  firstWord = (first specWords)
  if ('_' == firstWord) {
	firstWord = 'm'
	specWords = (join (array 'm') specWords)
  }
  atPut specWords 1 (uniqueNameNotIn existingNames firstWord)
  return (joinStrings specWords ' ')
}

method uniqueFunctionName Scripter baseSpec {
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

method createInitializeMethodBlock Scripter {
  opName = 'initialize'
  cls = (classOf targetObj)
  func = (addMethod cls opName (array 'this'))
  addToBottom this (scriptForFunction func)
  updateBlocks this
}

method removedUserDefinedBlock Scripter function {
  // Remove the given user-defined function or method.

  if (isMethod function) {
	removeMethodNamed (class (classIndex function)) (functionName function)
  } else {
	removeFunction (module function) function
  }

  blockDeleted (project projectEditor) (functionName function)
}

method uniqueMethodOrFunctionName Scripter baseName aClass {
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

method addToBottom Scripter aBlock noScroll {
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

method reactToMethodDelete Scripter aPalette {
  if (== 'My Blocks' (selection (contents categoriesFrame))) {
    updateBlocks this
  }
}

method blockPrototypeChanged Scripter aBlock {
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

method updateCallsOf Scripter op {
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

method allCmdsInProject Scripter {
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

method fixedCmd Scripter oldCmd minArgs argTypes argDefaults isReporter isVariadic {
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

method updateCallsInScriptingArea Scripter op {
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
