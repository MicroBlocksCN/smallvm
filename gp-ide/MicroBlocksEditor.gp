// MicroBlocksEditor.gp - Top-level window for the MicroBlocks IDE
//
// To use, load both the standard GP library the MicroBlocks IDE files using a command like:
//
//	./gp runtime/lib/* microBlocks/GP-IDE/* -
//
// Then type "o" (for "open") to start open the MicroBlocks IDE.
//
// John Maloney, January, 2018

// To do:
//	Pane resizing
//	Button to select serial port (readout for port status?)
//	Make go/stop give warning if port not open
//	Try to reconnect to serial port? when? on go/script click?

to o tryRetina devMode { openMicroBlocksEditor tryRetina devMode } // shortcut to open IDE

defineClass MicroBlocksEditor morph fileName project scripter leftItems rightItems title

method project MicroBlocksEditor { return project }
method scripter MicroBlocksEditor { return scripter }
method stage MicroBlocksEditor { return (global 'Page') }

to openMicroBlocksEditor tryRetina devMode presentFlag {
  if (isNil tryRetina) { tryRetina = true }
  if (isNil devMode) { devMode = true }
  if (isNil (global 'alanMode')) { setGlobal 'alanMode' false }
  if (isNil (global 'vectorTrails')) { setGlobal 'vectorTrails' false }
  if (and ('Browser' == (platform)) (browserIsMobile)) {
	page = (newPage 1024 640)
  } else {
	page = (newPage 1120 700)
  }
  setDevMode page devMode
  setGlobal 'page' page
  open page tryRetina
  editor = (initialize (new 'MicroBlocksEditor') (emptyProject))
  addPart page editor
  if (notNil (global 'initialProject')) {
	dataAndURL = (global 'initialProject')
  	openProject editor (first dataAndURL) (last dataAndURL)
  }
  pageResized editor
  developerModeChanged editor
  startSteppingSafely page presentFlag
}

to findMicroBlocksEditor {
  page = (global 'page')
  if (notNil page) {
	for p (parts (morph page)) {
	  if (isClass (handler p) 'MicroBlocksEditor') { return (handler p) }
	}
  }
  return nil
}

method initialize MicroBlocksEditor aProject {
  scale = (global 'scale')
  morph = (newMorph this)
  project = aProject
  addTopBarParts this
  scripter = (initialize (new 'MicroBlocksScripter') this)
  addPart morph (morph scripter)
  drawTopBar this
  clearProject this
  createInitialClass scripter
  fixLayout this
  return this
}

// top bar parts

method addTopBarParts MicroBlocksEditor {
  scale = (global 'scale')
  page = (global 'page')
  space = (15 * scale)

  title = (newText '' 'Arial Bold' (14 * scale))
  addPart morph (morph title)

  leftItems = (list)
  add leftItems (textButton this 'New' 'newProject')
  add leftItems (textButton this 'Open' 'openProjectMenu')
  add leftItems (textButton this 'Save' 'saveProject')

  rightItems = (list)
  add rightItems (textButton this 'Go' 'startAll')
  add rightItems (textButton this 'Stop' 'stopAll')
}

method textButton MicroBlocksEditor label selectorOrAction {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (pushButton label (color 130 130 130) selectorOrAction)
  addPart morph (morph result)
  return result
}

// project operations

method newProject MicroBlocksEditor {
  ok = (confirm (global 'page') nil 'Discard current project?')
  if (not ok) { return }
  clearProject this
  createInitialClass scripter
}

method clearProject MicroBlocksEditor {
  // Remove old project morphs and classes and reset global state.

  page = (global 'page')
  stopAll page
  setTargetObj scripter nil
  for p (copy (parts (morph page))) {
	// remove explorers, table views -- everything but the MicroBlocksEditor
	if (p != morph) { removePart (morph page) p }
  }

  isStarting = (isNil fileName)
  fileName = ''
  setText title ''
  project = (emptyProject)
  developerModeChanged scripter // clear extensions
  clearBoardIfConnected (smallRuntime)
}

method openProjectMenu MicroBlocksEditor {
  examplesPath = (join (absolutePath '.') '/Examples')
  pickFileToOpen (action 'openProjectFromFile' this) examplesPath (array '.gpp' '.gpe')
}

method openProjectFromFile MicroBlocksEditor location {
  // Open a project with the give file path or URL.

  data = (readData (new 'Project') location)
  if (isNil data) {
	error (join 'Could not read: ' location)
  }
  openProject this data location
}

method openProject MicroBlocksEditor projectData projectName {
  clearProject this
  project = (readProject (emptyProject) projectData)
  fileName = projectName
  updateTitle this
  targetObj = nil
  if ((count (classes (module project))) > 0) {
	targetObj = (new (first (classes (module project))))
  }
  setTargetObj scripter targetObj
  developerModeChanged scripter
}

method saveProject MicroBlocksEditor fName {
  saveScripts scripter

  if (and (isNil fName) (notNil fileName)) {
	fName = fileName
	if (beginsWith fName (gpExamplesFolder)) {
	  fName = (join (gpFolder) '/' (filePart fileName))
	}
  }

  if (isNil fName) {
	conf = (gpServerConfiguration)
    if (and (notNil conf) ((at conf 'beDefaultSaveLocation') == true)) {
      user = (at conf 'username')
      serverDirectory = (at conf 'serverDirectory')
      fName = (join serverDirectory user '/' (filePart fileName))
    } else {
	  fName = ''
	}
  }
  fName = (fileToWrite fName (array '.gpp' '.gpe'))
  if ('' == fName) { return false }

  if (and
	(not (isAbsolutePath this fName))
	(not (beginsWith fName 'http://'))
	(not (beginsWith fName (gpFolder)))) {
	  fName = (join (gpFolder) '/' fName)
  }
  if (not (or (endsWith fName '.gpp') (endsWith fName '.gpe'))) { fName = (join fName '.gpp') }

  fileName = fName
  updateTitle this

  result = (safelyRun (action 'saveProject' project fileName nil))
  if (isClass result 'Task') { // saveProject encountered an error
	addPart (global 'page') (new 'Debugger' result) // open debugger on the task
	return false
  }
  return true
}

method isAbsolutePath MicroBlocksEditor fName {
  // Return true if this string is an absolute file path.
  letters = (letters fName)
  count = (count letters)
  if (and (count >= 1) ('/' == (first letters))) { return true } // Mac, Linux
  if (and (count >= 3) (':' == (at letters 2)) (isOneOf (at letters 3) '/' '\')) {
  	return true // Win
  }
  return false
}

// go and stop buttons

method startAll MicroBlocksEditor {
  sendStartAll (smallRuntime)
}

method stopAll MicroBlocksEditor {
  sendStopAll (smallRuntime)
}

// project title

method updateTitle MicroBlocksEditor {
  setText title (withoutExtension (filePart fileName))
  redraw title
  centerTitle this
}

method centerTitle MicroBlocksEditor {
  m = (morph title)
  setLeft m (((width morph) - (width m)) / 2)
}

// stepping

method step MicroBlocksEditor {
  if ('Browser' == (platform)) {
	checkForBrowserResize this
  }
  processMessages (smallRuntime)
}

method checkForBrowserResize MicroBlocksEditor {
  browserSize = (browserSize)
  w = (first browserSize)
  h = (last browserSize)
  winSize = (windowSize)
  if (and (w == (at winSize 1)) (h == (at winSize 2))) { return }
  openWindow w h
  pageM = (morph (global 'page'))
  setExtent pageM w h
  for each (parts pageM) { pageResized (handler each) w h this }
}

// handle drops

method wantsDropOf MicroBlocksEditor aHandler { return true }

method justReceivedDrop MicroBlocksEditor aHandler {
  if (or (isAnyClass aHandler 'ColorPicker' 'Monitor') (hasField aHandler 'window')) {
	addPart (morph (global 'page')) (morph aHandler)
  } else {
	animateBackToOldOwner (hand (global 'page')) (morph aHandler)
  }
}

// developer mode

method developerModeChanged MicroBlocksEditor {
  developerModeChanged scripter
  fixLayout this
}

// layout

method pageResized MicroBlocksEditor {
  scale = (global 'scale')
  page = (global 'page')
  drawTopBar this
  fixLayout this
  if ('Win' == (platform)) {
	// workaround for a Windows graphics issue: when resizing a window it seems to clear
	// some or all textures. this forces them to be updated from the underlying bitmap.
	for m (allMorphs (morph page)) { costumeChanged m }
  }
}

method drawTopBar MicroBlocksEditor {
  w = (width (morph (global 'page')))
  h = (28 * (global 'scale'))
  oldC = (costume morph)
  if (or (isNil oldC) (w != (width oldC)) (h != (height oldC))) {
	setCostume morph (newBitmap w h (gray 200))
  }
}

method fixLayout MicroBlocksEditor fromScripter {
  fixTopBarLayout this
  if (true != fromScripter) { fixScripterLayout this }
}

method fixTopBarLayout MicroBlocksEditor {
  scale = (global 'scale')
  space = (5 * scale)
  centerTitle this
  setTop (morph title) (5 * scale)
  centerY = (15 * scale)

  x = (10 * scale)
  for item leftItems {
	if (isNumber item) {
	  x += item
	} else {
	  m = (morph item)
	  y = (centerY - ((height m) / 2))
	  setPosition m x y
	  x += ((width m) + space)
	}
  }
  x = ((width morph) - (10 * scale))
  for item (reversed rightItems) {
	if (isNumber item) {
	  x += (0 - item)
	} else {
	  m = (morph item)
	  y = (centerY - ((height m) / 2))
	  setPosition m (x - (width m)) y
	  x = ((x - (width m)) - space)
	}
  }
}

method fixScripterLayout MicroBlocksEditor {
  scale = (global 'scale')
  if (isNil scripter) { return } // happens during initialization
  m = (morph scripter)
  setPosition m 0 (28 * scale)
  w = (width (morph (global 'page')))
  h = (max 1 ((height (morph (global 'page'))) - (top m)))
  setExtent m w h
}

method drawIcon MicroBlocksEditor {
	h = 200
	w = ((2 / 3) * h)
	r = (h / 28)

	bm = (newBitmap (w + 5) (h + 5)) // add a bit for line width
	pen = (newVectorPen bm)

	beginPath pen (0.632 * w) (0.012 * h)
	cubicCurveTo pen (0.562 * w) (0.013 * h) (0.342 * w) (0.046 * h) (0.342 * w) (0.165 * h)
	cubicCurveTo pen (0.342 * w) (0.241 * h) (0.356 * w) (0.337 * h) (0.392 * w) (0.401 * h)
	cubicCurveTo pen (0.316 * w) (0.405 * h) (0.299 * w) (0.410 * h) (0.240 * w) (0.417 * h)
	cubicCurveTo pen (0.282 * w) (0.365 * h) (0.298 * w) (0.313 * h) (0.298 * w) (0.251 * h)
	cubicCurveTo pen (0.298 * w) (0.029 * h) (0.390 * w) (0.013 * h) (0.344 * w) (0.013 * h)
	cubicCurveTo pen (0.298 * w) (0.013 * h) (0.035 * w) (0.087 * h) (0.054 * w) (0.251 * h)
	cubicCurveTo pen (0.081 * w) (0.323 * h) (0.104 * w) (0.426 * h) (0.138 * w) (0.474 * h)
	cubicCurveTo pen (0.077 * w) (0.550 * h) (0.030 * w) (0.620 * h) (0.030 * w) (0.697 * h)
	cubicCurveTo pen (0.030 * w) (0.864 * h) (0.241 * w) (1.000 * h) (0.503 * w) (1.000 * h)
	cubicCurveTo pen (0.791 * w) (1.000 * h) (1.000 * w) (0.864 * h) (1.000 * w) (0.697 * h)
	cubicCurveTo pen (1.000 * w) (0.643 * h) (0.965 * w) (0.395 * h) (0.517 * w) (0.395 * h)
	cubicCurveTo pen (0.554 * w) (0.331 * h) (0.569 * w) (0.238 * h) (0.569 * w) (0.165 * h)
	cubicCurveTo pen (0.569 * w) (0.042 * h) (0.695 * w) (0.012 * h) (0.628 * w) (0.012 * h)
	cubicCurveTo pen (0.630 * w) (0.012 * h) (0.630 * w) (0.012 * h) (0.632 * w) (0.012 * h)
	fill pen (gray 250)
	stroke pen (gray 0) 3
	return bm
}

// context menu

method rightClicked MicroBlocksEditor aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method contextMenu MicroBlocksEditor {
  menu = (menu nil this)
  addItem menu 'select port' (action 'selectPort' (smallRuntime))
  addItem menu 'reset board' (action 'resetArduino' (smallRuntime))
  addLine menu
  addItem menu 'delete all scripts from board' (action 'sendDeleteAll' (smallRuntime))
  addLine menu
  addItem menu 'get VM version' (action 'getVersion' (smallRuntime))
  addItem menu 'get var 0' (action 'getVar' (smallRuntime) 0)
  return menu
}
