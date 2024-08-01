// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksEditor.gp - Top-level window for the MicroBlocks IDE
// John Maloney, January, 2018

to startup { openMicroBlocksEditor } // run at startup if not in interactive mode

to uload fileName {
  // Reload a top level module file when working on MicroBlocks. The 'lib/' prefix and '.gp'
  // suffix can be omitted. Example: "reload 'List'"

  if (not (endsWith fileName '.gp')) { fileName = (join fileName '.gp') }
  if (contains (listFiles '../ide') fileName) {
	fileName = (join '../ide/' fileName)
  } (contains (listFiles 'ide') fileName) {
	fileName = (join 'ide/' fileName)
  } else {
	fileName = (join '../gp/runtime/lib/' fileName)
  }
  return (load fileName (topLevelModule))
}

defineClass MicroBlocksEditor morph fileName scripter leftItems title rightItems tipBar zoomButtons indicator nextIndicatorUpdateMSecs progressIndicator lastStatus httpServer lastProjectFolder lastScriptPicFolder boardLibAutoLoadDisabled autoDecompile showHiddenBlocks frameRate frameCount lastFrameTime newerVersion putNextDroppedFileOnBoard isDownloading trashcan overlay isPilot

method fileName MicroBlocksEditor { return fileName }
method project MicroBlocksEditor { return (project scripter) }
method scripter MicroBlocksEditor { return scripter }
method httpServer MicroBlocksEditor { return httpServer }
method lastScriptPicFolder MicroBlocksEditor { return lastScriptPicFolder }
method setLastScriptPicFolder MicroBlocksEditor dir { lastScriptPicFolder = dir }

to openMicroBlocksEditor devMode {
  if (isNil devMode) { devMode = false }
  page = (newPage 1000 600)
  setDevMode page devMode
  toggleMorphicMenu (hand page) (contains (commandLine) '--allowMorphMenu')
  setGlobal 'page' page
  tryRetina = true
  open page tryRetina 'MicroBlocks'
  editor = (initialize (new 'MicroBlocksEditor') (emptyProject))
  addPart page editor
  redrawAll (global 'page')
  readVersionFile (smallRuntime)
  applyUserPreferences editor
  pageResized editor
  developerModeChanged editor
  if ('Browser' == (platform)) {
    // attempt to extra project or scripts from URL; does nothing if absent
    importFromURL editor (browserURL)
  }
  startSteppingSafely page
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

method initialize MicroBlocksEditor {
  scale = (global 'scale')
  morph = (newMorph this)
  httpServer = (newMicroBlocksHTTPServer)
  addTopBarParts this
  scripter = (initialize (new 'MicroBlocksScripter') this)
  lastProjectFolder = 'Examples'
  addPart morph (morph scripter)
  addTipBar this
  addZoomButtons this
  clearProject this
  fixLayout this
  nextIndicatorUpdateMSecs = 0
  setFPS morph 200
  newerVersion = 'unknown'
  putNextDroppedFileOnBoard = false
  return this
}

method scaleChanged MicroBlocksEditor {
  // Called when the window resolution changes.

  removeHint (global 'page')
  removeAllParts morph

  // save the state of the current scripter
  if (2 == (global 'scale')) { oldScale = 1 } else { oldScale = 2 }
  saveScripts scripter (oldScale * (global 'blockScale'))
  oldProject = (project scripter)
  oldCategory = (currentCategory scripter)
  oldLibrary = (currentLibrary scripter)

  // make a new scripter and restore old scripter state
  scripter = (initialize (new 'MicroBlocksScripter') this)
  setProject scripter oldProject
  updateLibraryList scripter
  if (notNil oldCategory) { selectCategory scripter oldCategory }
  if (notNil oldLibrary) { selectLibrary scripter oldLibrary }
  languageChanged scripter
  sendStopAll (smallRuntime)
  initialize (smallRuntime) scripter

  // rebuild the editor
  addLogo this
  addTopBarParts this
  addPart morph (morph title)
  addPart morph (morph scripter)
  addTipBar this
  addZoomButtons this

  fixLayout scripter
  lastStatus = nil // force update
  fixLayout this
}

// trashcan

method showTrashcan MicroBlocksEditor purpose {
  hideTrashcan this // just in case, prevent trashcans from stacking
  palette = (blockPalette (scripter this))
  paletteArea = (clientArea (handler (owner (morph palette))))
  trashcan = (newMorph)
  overlay = (newMorph)
  if (purpose == 'hide') {
	  setCostume trashcan (hideDefinitionIcon this)
  } (purpose == 'delete') {
	  setCostume trashcan (trashcanIcon this)
  } (purpose == 'hideAndDelete') {
	  setCostume trashcan (hideAndDeleteIcon this)
  }
  addPart (morph palette) overlay
  addPart (morph palette) trashcan
  setCenter trashcan (((width paletteArea) / 2) + (left paletteArea)) (((height paletteArea) / 2) + (top paletteArea))
  setPosition overlay (left paletteArea) (top paletteArea)
  setExtent overlay (width paletteArea) (height paletteArea)
  setCostume overlay (gray 0 20)
}

method hideTrashcan MicroBlocksEditor {
  if (notNil trashcan) { destroy trashcan }
  if (notNil overlay) { destroy overlay }
}

// top bar parts

method addTopBarParts MicroBlocksEditor {
  scale = (global 'scale')

  leftItems = (list)
  add leftItems (140 * scale)
  add leftItems (addIconButton this (languageButtonIcon this) 'languageMenu' 'Language')
  add leftItems (addIconButton this (settingsButtonIcon this) 'settingsMenu' 'MicroBlocks')
  add leftItems (addIconButton this (projectButtonIcon this) 'projectMenu' 'File')
  add leftItems (addIconButton this (graphIcon this) 'showGraph' 'Graph')
  add leftItems (addIconButton this (connectButtonIcon this) 'connectToBoard' 'Connect')
  indicator = (last leftItems)

  if (isNil title) {
    // only add the logo and title the first time
    addLogo this
    title = (newText '' 'Arial' (17 * scale))
    addPart morph (morph title)
  }

  rightItems = (list)

  addFrameRate = (contains (commandLine) '--allowMorphMenu')
  if addFrameRate {
	frameRate = (newText '0 fps' 'Arial' (14 * scale))
	addPart morph (morph frameRate)
	add rightItems frameRate
	add rightItems (16 * scale)
  }

  add rightItems (addIconButton this (newBitmap 0 0) 'noop' 'Progress' 36)
  progressIndicator = (last rightItems)
  add rightItems (3 * scale)

  add rightItems (addIconButton this (startButtonIcon this) 'startAll' 'Start' 36)
  add rightItems (addIconButton this (stopButtonIcon this) 'stopAndSyncScripts' 'Stop' 36)
  add rightItems (7 * scale)
}

method addLogo MicroBlocksEditor {
  logoM = (newMorph)
  setCostume logoM (logoAndText this)
  setPosition logoM 0 0
  addPart morph logoM
}

method textButton MicroBlocksEditor label selector {
  label = (localized label)
  scale = (global 'scale')
  setFont 'Arial Bold' (16 * scale)
  if ('Linux' == (platform)) { setFont 'Arial Bold' (13 * scale) }
  w = ((stringWidth label) + (10 * scale))
  h = (41 * scale)
  labelY = (12 * scale)
  bm1 = (newBitmap w h (topBarBlue this))
  drawString bm1 label (gray 60) (5 * scale) labelY
  bm2 = (newBitmap w h (topBarBlueHighlight this))
  drawString bm2 label (gray 40) (5 * scale) labelY
  button = (newButton '' (action selector this))
  setCostumes button bm1 bm2
  addPart morph (morph button)
  return button
}

// zoom buttons

method addZoomButtons MicroBlocksEditor {
  zoomButtons = (array
	(newZoomButton this 'zoomIn')
	(newZoomButton this 'restoreZoom')
	(newZoomButton this 'zoomOut'))
  for button zoomButtons {
	addPart morph (morph button)
  }
  addZoomButtonHints this
  fixZoomButtonsLayout this
}

method newZoomButton MicroBlocksEditor selector action {
  if (isNil action) {
    action = (action selector this)
  }
  scale = (global 'scale')
  icon = (call (action (join selector 'Icon') this))
  w = (30 * scale)
  h = (30 * scale)
  x = (half (w - (width icon)))
  y = (5 * scale)
  bm1 = (newBitmap w h (transparent))
  drawBitmap bm1 icon x y
  //bm2 = (newBitmap w h (topBarBlueHighlight this))
  //drawBitmap bm2 icon x y
  button = (newButton '' action)
  setCostumes button bm1
  return button
}

method addZoomButtonHints MicroBlocksEditor {
  // add zoom button hints in current language
  setHint (at zoomButtons 1) (localized 'Increase block size')
  setHint (at zoomButtons 2) (localized 'Restore block size to 100%')
  setHint (at zoomButtons 3) (localized 'Decrease block size')
}

method restoreZoom MicroBlocksEditor {
  setBlockScalePercent this 100
}

method zoomIn MicroBlocksEditor {
  zoomLevels = (list 50 75 100 125 150 200 250)
  currentZoom = ((global 'blockScale') * 100)
  for percent zoomLevels {
  	if (percent > currentZoom) { // first entry greater than current zoom level
      setBlockScalePercent this percent
      return
    }
  }
}

method zoomOut MicroBlocksEditor {
  zoomLevels = (list 50 75 100 125 150 200 250)
  currentZoom = ((global 'blockScale') * 100)
  for percent (reversed zoomLevels) {
  	if (percent < currentZoom) { // first entry less than current zoom level
      setBlockScalePercent this percent
      return
    }
  }
}

method setBlockScalePercent MicroBlocksEditor newPercent {
  setBlockScalePercent (scriptEditor scripter) newPercent
  syncScripts (smallRuntime)
}

method fixZoomButtonsLayout MicroBlocksEditor {
  right = ((right morph) - 15)
  bottom = (((bottom morph) - (height (morph tipBar))) - 10)
  for button zoomButtons {
	right = (right - (width (morph button)))
    setLeft (morph button) right
    setTop (morph button) ((bottom - (height (morph button))) - 5)
  }
}

// tip bar

method addTipBar MicroBlocksEditor {
  tipBar = (initialize (new 'MicroBlocksTipBar'))
  setGlobal 'tipBar' tipBar
  setTitle tipBar 'an element'
  setTip tipBar 'some tip about it'
  addPart morph (morph tipBar)
}

// project operations

method downloadInProgress MicroBlocksEditor {
  if isDownloading {
    existingPrompt = (findMorph 'Prompter')
    if (notNil existingPrompt) { cancel (handler existingPrompt) }
    inform 'Downloading code to board. Please wait.' nil nil true
  }
  return isDownloading
}

method canReplaceCurrentProject MicroBlocksEditor {
  if (downloadInProgress this) {return false }
  return (or
	(not (hasUserCode (project scripter)))
	(confirm (global 'page') nil 'Discard current project?'))
}

method newProject MicroBlocksEditor {
  if (not (canReplaceCurrentProject this)) { return }
  clearProject this
  installBoardSpecificBlocks (smallRuntime)
  updateLibraryList scripter
  fileName = ''
  updateTitle this
}

method clearProject MicroBlocksEditor {
  // Remove old project morphs and classes and reset global state.

  closeAllDialogs this
  setText title ''
  fileName = ''
  createEmptyProject scripter
  if (isRunning httpServer) {
	clearVars httpServer
  }
  clearLoggedData (smallRuntime)
}

method closeAllDialogs MicroBlocksEditor {
  pageM = (morph (global 'page'))
  for p (copy (parts pageM)) {
	// remove explorers, table views -- everything but the MicroBlocksEditor
	if (p != morph) { removePart pageM p }
  }
  doOneCycle (global 'page') // force redisplay
}

method openProjectMenu MicroBlocksEditor {
  if (downloadInProgress this) {return }

  fp = (findMorph 'MicroBlocksFilePicker')
  if (notNil fp) { destroy fp }
  pickFileToOpen (action 'openProjectFromFile' this) lastProjectFolder (array '.ubp' '.gpp')
}

method openProjectFromFile MicroBlocksEditor location {
  // Open a project with the given file path or URL.
  if (beginsWith location '//') {
    lastProjectFolder = 'Examples'
  } else {
    lastProjectFolder = (directoryPart location)
  }

  if (not (canReplaceCurrentProject this)) { return }

  if (beginsWith location '//') {
	data = (readEmbeddedFile (substring location 3) true)
  } else {
	data = (readFile location true)
  }
  if (isNil data) {
	error (join (localized 'Could not read: ') location)
  }
  openProject this data location
}

method openProject MicroBlocksEditor projectData projectName updateLibraries {
  if (downloadInProgress this) { return }
  fileName = projectName
  updateTitle this
  if (endsWith projectName '.gpp') {
	// read old project
	mainClass = nil
	proj = (readProject (emptyProject) projectData)
	if ((count (classes (module proj))) > 0) {
		mainClass = (first (classes (module proj)))
	}
	loadOldProjectFromClass scripter mainClass (blockSpecs proj)
  } else {
	loadNewProjectFromData scripter (toString projectData) updateLibraries
  }
  updateLibraryList scripter
  developerModeChanged scripter
  saveAllChunksAfterLoad (smallRuntime)
}

method openFromBoard MicroBlocksEditor {
  if (not (canReplaceCurrentProject this)) { return }
  clearProject this
  fileName = ''
  updateTitle this
  updateLibraryList scripter
  readCodeFromNextBoardConnected (smallRuntime)
}

method saveProjectToFile MicroBlocksEditor {
  fp = (findMorph 'MicroBlocksFilePicker')
  if (notNil fp) { destroy fp }
  saveProject this nil
}

method urlPrefix MicroBlocksEditor {
  if ('Browser' == (platform)) {
    url = (browserURL)
    i = (findSubstring '.html' url)
    if (notNil i) {
      return (substring url 1 (i + 4))
    }
  }

  // stand-alone app
  urlPrefix = 'https://microblocks.fun/run/microblocks.html'
  if (isPilot this) {
    urlPrefix = 'https://microblocks.fun/run-pilot/microblocks.html'
  }
  return urlPrefix
}

method copyProjectURLToClipboard MicroBlocksEditor {
  // Copy a URL encoding of this project to the clipboard.

  saveScripts scripter
  codeString = (codeString (project scripter))
  if (notNil title) {
    projName = (text title)
    codeString = (join 'projectName ''' projName '''' (newline) (newline) codeString)
  }
  setClipboard (join (urlPrefix this) '#project='(urlEncode codeString true))
}

method saveProject MicroBlocksEditor fName {
  saveScripts scripter

  if (and (isNil fName) (notNil fileName)) {
	fName = fileName
	if (beginsWith fName '//Examples') {
	  // if an example was opened, do a "save as" into the Microblocks folder
	  fName = (join (gpFolder) '/' (filePart fileName))
	}
  }

  if ('Browser' == (platform)) {
	if (or (isNil fName) ('' == fName)) { fName = 'Untitled' }
	i = (findLast fName '/')
	if (notNil i) { fName = (substring fName (i + 1)) }
	if (not (endsWith fName '.ubp')) { fName = (join fName '.ubp') }
	browserWriteFile (codeString (project scripter)) fName 'project'
	return
  }

  fName = (fileToWrite (withoutExtension fName) (array '.ubp'))
  if ('' == (filePart fName)) { return false }

  if (and
	(not (isAbsolutePath this fName))
	(not (beginsWith fName (gpFolder)))) {
	  fName = (join (gpFolder) '/' fName)
  }
  if (not (endsWith fName '.ubp')) { fName = (join fName '.ubp') }

  fileName = fName

  lastProjectFolder = (directoryPart fileName)

  updateTitle this
  if (canWriteProject this fileName) {
    writeFile fileName (codeString (project scripter))
  }
}

method canWriteProject MicroBlocksEditor fName {
  return (or
   (isNil (readFile fName))
   (confirm (global 'page') nil 'Overwrite project?'))
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

// board control buttons

method connectToBoard MicroBlocksEditor { selectPort (smallRuntime) }
method stopAndSyncScripts MicroBlocksEditor { stopAndSyncScripts (smallRuntime) }
method startAll MicroBlocksEditor { sendStartAll (smallRuntime) }

// project title

method updateTitle MicroBlocksEditor {
  projName = (withoutExtension (filePart fileName))
  setText title projName
  redraw title
  centerTitle this
}

method centerTitle MicroBlocksEditor {
  scale = (global 'scale')
  left = (right (morph (last leftItems)))
  right = (left (morph (first rightItems)))
  titleM = (morph title)
  setCenter titleM (half (left + right)) (21 * scale)

  // hide title if insufficient space
  if (((width titleM) + (8 * scale)) > (right - left)) {
	hide titleM
  } else {
	show titleM
  }
}

// stepping

method step MicroBlocksEditor {
  if ('Browser' == (platform)) {
	checkForBrowserResize this
	processBrowserDroppedFile this
	processBrowserFileSave this
  }
  processDroppedFiles this

  if (((msecsSinceStart) > nextIndicatorUpdateMSecs)) {
    updateIndicator this
    nextIndicatorUpdateMSecs = ((msecsSinceStart) + 200)
  }

  if (not (busy (smallRuntime))) { processMessages (smallRuntime) }
  if (isRunning httpServer) {
	step httpServer
  }
  if ('unknown' == newerVersion) {
    // launch (global 'page') (newCommand 'checkLatestVersion' this) // start version check
    // newerVersion = nil
  } (notNil newerVersion) {
    reportNewerVersion this
    newerVersion = nil
  }
  if (notNil frameRate) {
	updateFPS this
  }
}

method updateFPS MicroBlocksEditor {
	if (isNil lastFrameTime) { lastFrameTime = 0 }
	if (isNil frameCount) { frameCount = 0 }
	if (frameCount > 5) {
		now = (msecsSinceStart)
		frameMSecs = (now - lastFrameTime)
		msecsPerFrame = (round ((frameCount * 1000) / frameMSecs))
		setText frameRate (join '' msecsPerFrame ' fps')
		frameCount = 1
		lastFrameTime = now
	} else {
		frameCount += 1
	}
}

// Progress indicator

method drawProgressIndicator MicroBlocksEditor bm phase downloadProgress {
	scale = (global 'scale')
	radius = (13 * scale)
	cx = (half (width bm))
	cy = ((half (height bm)) + scale)
	bgColor = (topBarBlue this)
	if (1 == phase) {
		lightGray = (mixed (gray 0) 5 bgColor)
		darkGray = (mixed (gray 0) 15 bgColor)
	} (2 == phase) {
		lightGray = (mixed (gray 0) 10 bgColor)
		darkGray = (mixed (gray 0) 25 bgColor)
	} (3 == phase) {
		lightGray = (mixed (gray 0) 25 bgColor)
		darkGray = (mixed (gray 0) 50 bgColor)
	}

	fill bm bgColor
	if (and (3 == phase) (downloadProgress >= 1)) { return }

	// background circle
	drawCircle (newShapeMaker bm) cx cy radius lightGray

	// draw progress pie chart
	degrees = (round (360 * downloadProgress))
	oneDegreeDistance = ((* 2 (pi) radius) / 360.0)
	pen = (pen (newShapeMaker bm))
	beginPath pen cx cy
	setHeading pen 270
	forward pen radius
	turn pen 90
	repeat degrees {
	  forward pen oneDegreeDistance
	  turn pen 1
	}
	goto pen cx cy
	fill pen darkGray
}

method showDownloadProgress MicroBlocksEditor phase downloadProgress {
	isDownloading = (downloadProgress < 1)
	bm1 = (getField progressIndicator 'offCostume')
	drawProgressIndicator this bm1 phase downloadProgress
	bm2 = (getField progressIndicator 'onCostume')
	drawProgressIndicator this bm2 phase downloadProgress
	costumeChanged (morph progressIndicator)
	updateDisplay (global 'page') // update the display
}

// Connection indicator

method drawIndicator MicroBlocksEditor bm bgColor isConnected {
	scale = (global 'scale')
	fill bm bgColor
	if isConnected {
		cx = (half (width bm))
		cy = ((half (height bm)) + scale)
		radius = (13 * scale)
		green = (mixed (color 0 200 0) 70 bgColor)
		drawCircle (newShapeMaker bm) cx cy radius green
	}
	icon = (connectButtonIcon this)
	drawBitmap bm icon (10 * scale) (10 * scale)
}

method updateIndicator MicroBlocksEditor forcefully {
	if (busy (smallRuntime)) { return } // do nothing during file transfer

	status = (updateConnection (smallRuntime))
	if (and (lastStatus == status) (forcefully != true)) { return } // no change
	isConnected = ('connected' == status)

	bm1 = (getField indicator 'offCostume')
	drawIndicator this bm1 (topBarBlue this) isConnected
	bm2 = (getField indicator 'onCostume')
	drawIndicator this bm2 (topBarBlueHighlight this) isConnected

	costumeChanged (morph indicator)
	lastStatus = status
}

// browser support

method checkForBrowserResize MicroBlocksEditor {
  browserSize = (browserSize)
  w = (first browserSize)
  h = (last browserSize)
  winSize = (windowSize)

  dx = (abs ((at winSize 1) - w))
  dy = (abs ((at winSize 2) - h))
  if (and (dx <= 1) (dy <= 1)) {
    // At the smallest browser zoom levels, sizes can differ by one pixel
    return // no change
  }

  openWindow w h true
  page = (global 'page')
  oldScale = (global 'scale')
  updateScale page
  scale = (global 'scale')
  pageM = (morph page)
  setExtent pageM (w * scale) (h * scale)
  for each (parts pageM) { pageResized (handler each) w h this }
  if (scale != oldScale) {
	for m (allMorphs pageM) { scaleChanged (handler m) }
  }
}

method putNextDroppedFileOnBoard MicroBlocksEditor {
  putNextDroppedFileOnBoard = true
}

method processBrowserDroppedFile MicroBlocksEditor {
  pair = (browserGetDroppedFile)
  if (isNil pair) { return }
  fName = (callWith 'string' (first pair))
  data = (last pair)
  if putNextDroppedFileOnBoard {
    putNextDroppedFileOnBoard = false // clear flag
	sendFileData (smallRuntime) fName data
  } else {
    processDroppedFile this fName data
  }
}

method processBrowserFileSave MicroBlocksEditor {
	lastSavedName = (browserLastSaveName)
	if (notNil lastSavedName) {
		if (endsWith lastSavedName '.hex') {
			startFirmwareCountdown (smallRuntime) lastSavedName
		} (endsWith lastSavedName '.ubp') {
			// Update the title (note: updateTitle will remove the extension)
			fileName = lastSavedName
			updateTitle this
		}
		if ('_no_file_selected_' == lastSavedName) {
			startFirmwareCountdown (smallRuntime) lastSavedName
		}
	}
}

// dropped files

method processDroppedFiles MicroBlocksEditor {
  for evt (droppedFiles (global 'page')) {
	fName = (toUnixPath (at evt 'file'))
	data = (readFile fName true)
	if (notNil data) {
	  processDroppedFile this fName data
	}
  }
  for evt (droppedTexts (global 'page')) {
	text = (at evt 'file')
	processDroppedText this text
  }
}

method processDroppedFile MicroBlocksEditor fName data {
  lcFilename = (toLowerCase fName)
  if (endsWith lcFilename '.ubp') {
	if (not (canReplaceCurrentProject this)) { return }
	openProject this data fName
  } (endsWith lcFilename '.ubl') {
	importLibraryFromFile scripter fName data
  } (endsWith lcFilename '.csv') {
	if (isNil data) { return } // could not read file
	data = (joinStrings (splitWith (toString data) ',')) // remove commas
	clearLoggedData (smallRuntime)
	for entry (lines data) { addLoggedData (smallRuntime) entry }
  } (endsWith lcFilename '.png') {
    importFromPNG this data
  } (endsWith lcFilename '.bin') {
    // install ESP firmware file
	if (isNil data) { return } // could not read file
    installESPFirmwareFromFile (smallRuntime) fName data
  } (endsWith lcFilename '.gp') {
    // xxx for testing:
    eval (toString data) nil (topLevelModule)
  }	else {
	// load file into board, if possible
	if ('Browser' == (platform)) {
		sendFileData (smallRuntime) fName data
	} else {
		writeFileToBoard (smallRuntime) fName
	}
  }
}

method processDroppedText MicroBlocksEditor text {
  if (beginsWith text 'http') {
    text = (first (lines text))
    url = (substring text ((findFirst text ':') + 3))
    host = (substring url 1 ((findFirst url '/') - 1))
    path = (substring url (findFirst url '/'))
    fileName = (substring path ((findLast path '/') + 1) ((findLast path '.') - 1))

    if (or ((findSubstring 'scripts=' url) > 0) ((findSubstring 'project=' url) > 0)) {
      importFromURL this url
      return
    }

    if (endsWith url '.ubp') {
      if (not (canReplaceCurrentProject this)) { return }
      openProject this (httpBody (httpGet host path)) fileName
    } (endsWith url '.ubl') {
      importLibraryFromString scripter (httpBody (httpGet host path)) fileName fileName
      saveAllChunksAfterLoad (smallRuntime)
    } (and (or (notNil json) (endsWith url '.png')) ('Browser' == (platform))) {
      data = (httpBody (basicHTTPGetBinary host path))
      if ('' == data) { return }
      importFromPNG this data
    }
  } else {
	spec = (specForOp (authoringSpecs) 'comment')
	block = (blockForSpec spec)
	setContents (first (inputs block)) text
	// doesn't work because hand position isn't updated until the drop is done
	setLeft (morph block) (x (hand (global 'page')))
	setTop (morph block) (y (hand (global 'page')))
	addPart (morph (scriptEditor scripter)) (morph block)
  }
}

method importFromURL MicroBlocksEditor url {
  i = (findSubstring 'scripts=' url)
  if (notNil i) { // import scripts embedded in URL
    scriptString = (urlDecode (substring url (i + 8)))
    pasteScripts scripter scriptString
    return
  }
  i = (findSubstring 'project=' url)
  if (notNil i) { // open a complete project
    urlOrData = (substring url (i + 8))
    if (beginsWith urlOrData 'http') {
      // project link
      fileName = (substring urlOrData ((findLast urlOrData '/') + 1) ((findLast urlOrData '.') - 1))
      if (not (canReplaceCurrentProject this)) { return }
      openProject this (httpBody (httpGetInBrowser urlOrData)) fileName
   } else {
      // project embedded in URL
      projectString = (urlDecode (substring url (i + 8)))
      if (not (canReplaceCurrentProject this)) { return }
      projName = (extractProjectName this projectString)
      if (not (canReplaceCurrentProject this)) { return }
      openProject this projectString projName
    }
    return
  }
}

method extractProjectName MicroBlocksEditor projectString {
  for line (lines projectString) {
    if (beginsWith line 'projectName') {
      return (first (argList (first (parse line))))
    }
  }
  return '' // no name found
}

method importFromPNG MicroBlocksEditor pngData {
  scriptString = (getScriptText (new 'PNGReader') pngData)
  if (isNil scriptString) { return } // no script in this PNG file
  i = (find (letters scriptString) (newline))
  scriptString = (substring scriptString i)
  pasteScripts scripter scriptString
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

// version check

method isPilot MicroBlocksEditor { return (true == isPilot) }

method checkLatestVersion MicroBlocksEditor {
  latestVersion = (fetchLatestVersionNumber this) // fetch version, even in browser, to log useage
  if ('Browser' == (platform)) {
    // skip version check in browser/Chromebook but set isPilot based on URL
    isPilot = (notNil (findSubstring 'run-pilot' (browserURL)))
    return
  }

  currentVersion = (splitWith (ideVersionNumber (smallRuntime)) '.')

  // sanity checks -- both versions should be lists/arrays of strings representing integers
  // can get garbage if the HTTP request fails
  for n latestVersion { if (not (representsAnInteger n)) { return }}
  for n currentVersion { if (not (representsAnInteger n)) { return }}

  for i (count latestVersion) {
	latest = (toInteger (at latestVersion i))
	current = (toInteger (at currentVersion i))
	isPilot = (current > latest)
	if isPilot {
      // we're running a pilot release, lets check the latest one
      latestVersion = (fetchLatestPilotVersionNumber this)
      for n latestVersion { if (not (representsAnInteger n)) { return }} // sanity check
      latest = (toInteger (at latestVersion i))
	}
	if (latest > current) {
	  newerVersion = latestVersion
	} (current > latest) {
      // if this subpart of the current version number is > latest, don't check following parts
      // (e.g. 2.0.0 is later than 1.9.9)
      return
	}
  }
}

method fetchLatestVersionNumber MicroBlocksEditor {
  platform = (platform)
  if ('Browser' == platform) {
    if (browserIsChromeOS) {
      suffix = '?C='
    } else {
      suffix = '?B='
    }
  } ('Mac' == (platform)) {
    suffix = '?M='
  } ('Linux' == (platform)) {
    suffix = '?L='
  } ('Win' == (platform)) {
    suffix = '?W='
  } else {
    suffix = '?R='
  }
  url = (join '/downloads/latest/VERSION.txt' suffix (rand 100000 999999))
  versionText = (basicHTTPGet 'microblocksfun.cn' url)
  if (isNil versionText) { return (array 0 0 0) }
  return (splitWith (substring (first (lines versionText)) 1) '.')
}

method fetchLatestPilotVersionNumber MicroBlocksEditor {
  versionText = (basicHTTPGet 'microblocks.fun' '/downloads/pilot/VERSION.txt')
  if (isNil versionText) { return (array 0 0 0) }
  versionLine = (first (lines versionText))
  // take out "-pilot" first
  return (splitWith (substring versionLine 1 ((count versionLine) - 6)) '.')
}

method reportNewerVersion MicroBlocksEditor {
  versionString = (joinStrings newerVersion '.')
  newerVersion = nil // clear this to avoid repeated calls from step
  (inform (global 'page') (join
      'A new MicroBlocks version has been released (' versionString ').' (newline)
      (newline)
      'Get it now at http://microblocks.fun')
    'New version available')
}

// user preferences

method readUserPreferences MicroBlocksEditor {
  result = (dictionary)
  if ('Browser' == (platform)) {
    jsonString = (browserReadPrefs)
    waitMSecs 20 // timer for callback in ChromeOS
    jsonString = (browserReadPrefs) // will have result the second time
  } else {
    path = (join (gpFolder) '/preferences.json')
    jsonString = (readFile path)
  }
  if (notNil jsonString) {
	result = (jsonParse jsonString)
	if (not (isClass result 'Dictionary')) { result = (dictionary) }
  }
  return result
}

method isChineseWebapp MicroBlocksEditor {
	if ('Browser' != (platform)) { return false }
	url = (browserURL)
	return (or
		((containsSubString url 'microblocksfun.cn') > 0)
		((containsSubString url 'blocks.aimaker.space') > 0)
		(browserHasLanguage 'zh')
	)
}

method applyUserPreferences MicroBlocksEditor {
	prefs = (readUserPreferences this)
	if (notNil (at prefs 'locale')) {
		setLanguage this (at prefs 'locale')
	} (isChineseWebapp this) {
		setLanguage this '简体中文'
	}
	if (notNil (at prefs 'boardLibAutoLoadDisabled')) {
		boardLibAutoLoadDisabled = (at prefs 'boardLibAutoLoadDisabled')
	}
	if (notNil (at prefs 'autoDecompile')) {
		autoDecompile = (at prefs 'autoDecompile')
	}
	if (notNil (at prefs 'blockSizePercent')) {
		percent = (at prefs 'blockSizePercent')
		setGlobal 'blockScale' ((clamp percent 25 500) / 100)
	}
	if (notNil (at prefs 'devMode')) {
		setDevMode (global 'page') (at prefs 'devMode')
		developerModeChanged this
	}
	if (notNil (at prefs 'showImplementationBlocks')) {
		showHiddenBlocks = (at prefs 'showImplementationBlocks')
	}
}

method saveToUserPreferences MicroBlocksEditor key value {
	prefs = (readUserPreferences this)
	if (isNil value) {
		remove prefs key
	} else {
		atPut prefs key value
	}
    if ('Browser' == (platform)) {
		browserWritePrefs (jsonStringify prefs)
	} else {
		path = (join (gpFolder) '/preferences.json')
		writeFile path (jsonStringify prefs)
	}
}

method toggleBoardLibAutoLoad MicroBlocksEditor flag {
	boardLibAutoLoadDisabled = (not flag)
	saveToUserPreferences this 'boardLibAutoLoadDisabled' boardLibAutoLoadDisabled
}

method boardLibAutoLoadDisabled MicroBlocksEditor {
	return (boardLibAutoLoadDisabled == true)
}

method toggleAutoDecompile MicroBlocksEditor flag {
	autoDecompile = flag
	saveToUserPreferences this 'autoDecompile' autoDecompile
}

method autoDecompileEnabled MicroBlocksEditor {
	return (autoDecompile == true)
}

method toggleShowHiddenBlocks MicroBlocksEditor flag {
	showHiddenBlocks = flag
	saveToUserPreferences this 'showImplementationBlocks' showHiddenBlocks
	developerModeChanged this // updates the palette
}

method showHiddenBlocksEnabled MicroBlocksEditor {
	return (and (devMode) (showHiddenBlocks == true))
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
  fixLayout this
  if ('Win' == (platform)) {
	// workaround for a Windows graphics issue: when resizing a window it seems to clear
	// some or all textures. this forces them to be updated from the underlying bitmap.
	for m (allMorphs (morph page)) { costumeChanged m }
  }
}

// top bar drawing

method topBarBlue MicroBlocksEditor { return (colorHSV 180 0.045 1.0) }
method topBarBlueHighlight MicroBlocksEditor { return (colorHSV 180 0.17 1.0) }
method topBarHeight MicroBlocksEditor { return (46 * (global 'scale')) }

method drawOn MicroBlocksEditor aContext {
  scale = (global 'scale')
  x = (left morph)
  y = (top morph)
  w = (width morph)
  topBarH = (topBarHeight this)
  fillRect aContext (topBarBlue this) x y w topBarH
  grassColor = (color 137 169 31)
  grassH = (5 * scale)
  fillRect aContext grassColor x ((y + topBarH) - grassH) w grassH
}

// layout

method fixLayout MicroBlocksEditor fromScripter {
  setExtent morph (width (morph (global 'page'))) (height (morph (global 'page')))
  fixTopBarLayout this
  fixTipBarLayout this
  fixZoomButtonsLayout this
  if (true != fromScripter) { fixScripterLayout this }
}

method fixTopBarLayout MicroBlocksEditor {
  scale = (global 'scale')
  space = 0

  // Optimization: report one damage rectangle for the entire top bar
  reportDamage morph (rect (left morph) (top morph) (width morph) (topBarHeight this))

  centerY = (20 * scale)
  x = 0
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
  x = (width morph)
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
  centerTitle this
}

method fixTipBarLayout MicroBlocksEditor {
	fixLayout tipBar
	setLeft (morph tipBar) 0
	setBottom (morph tipBar) (bottom morph)
}

method fixScripterLayout MicroBlocksEditor {
  scale = (global 'scale')
  if (isNil scripter) { return } // happens during initialization
  m = (morph scripter)
  setPosition m 0 (topBarHeight this)
  w = (width (morph (global 'page')))
  h = (max 1 (((height (morph (global 'page'))) - (top m)) - (height (morph tipBar))))
  setExtent m w h
  fixLayout scripter
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
  popUpAtHand (contextMenu this) (global 'page')
  return true
}

method contextMenu MicroBlocksEditor {
  menu = (menu 'MicroBlocks' this)
  addItem menu 'about...' (action 'showAboutBox' (smallRuntime))
  addLine menu
  addItem menu 'update firmware on board' (action 'installVM' (smallRuntime) false false) // do not wipe flash, do not download VM from server

if (contains (commandLine) '--allowMorphMenu') { // xxx testing (used by John)
// addItem menu 'decompile all' (action 'decompileAll' (smallRuntime))
// addLine menu
// addItem menu 'dump persistent memory' (action 'sendMsg' (smallRuntime) 'systemResetMsg' 1 nil)
// addItem menu 'compact persistent memory' (action 'sendMsg' (smallRuntime) 'systemResetMsg' 2 nil)
// addLine menu
}

  if (boardIsBLECapable (smallRuntime)) {
    addItem menu 'enable or disable BLE' (action 'setBLEFlag' (smallRuntime))
  }

  addLine menu
  if (not (devMode)) {
	addItem menu 'show advanced blocks' 'showAdvancedBlocks'
  } else {
	addItem menu 'firmware version' (action 'getVersion' (smallRuntime))
	addLine menu
// Commented out for now since all precompiled VM's are already included in IDE
//	addItem menu 'download and install latest VM' (action 'installVM' (smallRuntime) false true) // do not wipe flash, download latest VM from server
	addItem menu 'erase flash and update firmware on ESP board' (action 'installVM' (smallRuntime) true false) // wipe flash first, do not download VM from server
	addItem menu 'install ESP firmware from URL' (action 'installESPFirmwareFromURL' (smallRuntime)) // wipe flash first, do not download VM from server

	if ('Browser' != (platform)) {
	  addLine menu
	  if (not (isRunning httpServer)) {
		addItem menu 'start HTTP server' 'startHTTPServer'
	  } else {
		addItem menu 'stop HTTP server' 'stopHTTPServer'
	  }
	}
	addItem menu 'compact code store' (action 'sendMsg' (smallRuntime) 'systemResetMsg' 2 nil)
	addLine menu
	if (boardLibAutoLoadDisabled this) {
		addItem menu 'enable autoloading board libraries' (action 'toggleBoardLibAutoLoad' this true)
	} else {
		addItem menu 'disable autoloading board libraries' (action 'toggleBoardLibAutoLoad' this false)
	}

	if (autoDecompileEnabled this) {
		addItem menu 'disable PlugShare when project empty' (action 'toggleAutoDecompile' this false) 'when plugging a board, do not automatically read its contents into the IDE even if the current project is empty'
	} else {
		addItem menu 'enable PlugShare when project empty' (action 'toggleAutoDecompile' this true) 'when plugging a board, automatically read its contents into the IDE if the current project is empty'
	}

// xxx for testing blend in browser...
// addItem menu 'time redraw' (action 'timeRedraw' this)
// addLine menu
// addItem menu 'cursorTest' cursorTest
// addItem menu 'benchmark' (action 'runBenchmarks' (global 'page'))

	addLine menu
	addItem menu 'hide advanced blocks' 'hideAdvancedBlocks'
	if (showHiddenBlocksEnabled this) {
		addItem menu 'hide implementation blocks' (action 'toggleShowHiddenBlocks' this false) 'do not show blocks and variables that are internal to libraries (i.e. those whose name begins with underscore)'
	} else {
		addItem menu 'show implementation blocks' (action 'toggleShowHiddenBlocks' this true) 'show blocks and variables that are internal to libraries (i.e. those whose name begins with underscore)'
	}
  }
  return menu
}

method downloadTest MicroBlocksEditor {
  fileName = (trim (freshPrompt (global 'page') 'URL?' 'vm_esp32.bin'))
  t = (newTimer)
  data = (httpGetBinary 'microblocks.fun' (join '/downloads/pilot/vm/' fileName))
  print 'got' (byteCount data) 'bytes in' (msecs t) 'msecs'
}

method hasHelpEntryFor MicroBlocksEditor aBlock {
  return (notNil (helpEntry tipBar (primName (expression aBlock))))
}

method openHelp MicroBlocksEditor aBlock {
  entry = (helpEntry tipBar (primName (expression aBlock)))
  if (isNil entry) { return }
  helpPath = (at entry 2)
  if (beginsWith helpPath '/') {
    url = (join 'https://wiki.microblocks.fun' helpPath)
  } else {
    url = (join 'https://wiki.microblocks.fun/reference_manual/' helpPath)
  }
  openURL url
}

// Pretty Printer test

method ppTest MicroBlocksEditor {
	// Test the pretty printer by loading each example project and then generating its
	// code string. The result should match the original file.

	for fn (listEmbeddedFiles) {
		if (beginsWith fn 'Examples') {
			data1 = (readEmbeddedFile fn)
			proj = (loadFromString (newMicroBlocksProject) data1)
			data2 = (codeString proj)
			if (data2 != data1) {
				showMismatches this fn data1 data2
			}
		}
	}
}

method showMismatches MicroBlocksEditor fn s1 s2 {
	print 'MISMATCH!' (filePart fn)
	lines1 = (nonEmptyLines this s1)
	lines2 = (nonEmptyLines this s2)
	if ((count lines1) != (count lines2)) {
		print '  Line counts do not match' (count lines1) (count lines2)
	}
	mismatchCount = 0
	for i (min (count lines1) (count lines2)) {
		l1 = (at lines1 i)
		l2 = (at lines2 i)
		if (l1 != l2) {
			print '    A: ' l1; print '    B: ' l2
			mismatchCount += 1
		}
	}
	print '  Mismatched lines:' mismatchCount
}

method nonEmptyLines MicroBlocksEditor s {
	result = (list)
	for line (lines s) {
		if (line != '') { add result line }
	}
	return result
}

method cursorTest MicroBlocksEditor {
  menu = (menu 'Cursor Test' this)
  addItem menu 'default'		(action 'setCursor' 'default')
  addItem menu 'text'			(action 'setCursor' 'text')
  addItem menu 'wait'			(action 'setCursor' 'wait')
  addItem menu 'crosshair'		(action 'setCursor' 'crosshair')

  addItem menu 'nwse-resize'	(action 'setCursor' 'nwse-resize')
  addItem menu 'nesw-resize'	(action 'setCursor' 'nesw-resize')
  addItem menu 'ew-resize'		(action 'setCursor' 'ew-resize')
  addItem menu 'ns-resize'		(action 'setCursor' 'ns-resize')

  addItem menu 'move'			(action 'setCursor' 'move')
  addItem menu 'not-allowed'	(action 'setCursor' 'not-allowed')
  addItem menu 'pointer'		(action 'setCursor' 'pointer')

  popUpAtHand menu (global 'page')
}

method showGraph MicroBlocksEditor {
	graph = (findMorph 'MicroBlocksDataGraph')
	if (notNil graph) { destroy graph }
	page = (global 'page')
	graph = (newMicroBlocksDataGraph)
	setPosition (morph graph) (x (hand page)) (y (hand page))
	addPart page graph
}

method showAdvancedBlocks MicroBlocksEditor {
  setDevMode (global 'page') true
  saveToUserPreferences this 'devMode' true
  developerModeChanged this
}

method hideAdvancedBlocks MicroBlocksEditor {
  setDevMode (global 'page') false
  saveToUserPreferences this 'devMode' false
  developerModeChanged this
}

method startHTTPServer MicroBlocksEditor {
  if (start httpServer) {
	(inform (join 'MicroBlocks HTTP Server listening on port ' (port httpServer)) 'HTTP Server')
  } ('' == (port httpServer)) {
	return // user did not supply a port number
  } else {
	(inform (join
		'Failed to start HTTP server.' (newline)
		'Please make sure that no other service is running at port 6473.')
		'HTTP Server')
  }
}

method stopHTTPServer MicroBlocksEditor {
  stop httpServer
}

// Language Button

method languageMenu MicroBlocksEditor {
  menu = (menu 'Language' this)
  addItem menu 'English' (action 'setLanguage' this 'English')
  if ('Browser' == (platform)) {
	for fn (sorted (listFiles 'translations')) {
	  fn = (withoutExtension fn)
	  language = (withoutExtension fn)
	  addItem menu language (action 'setLanguage' this language)
	}
  } else {
	for fn (sorted (listEmbeddedFiles)) {
	  fn = (withoutExtension fn)
	  if (beginsWith fn 'translations/') {
		language = (withoutExtension (substring fn 14))
		addItem menu language (action 'setLanguage' this language)
	  }
	}
  }
  if (devMode) {
	addLine menu
	addItem menu 'Custom...' (action 'readCustomTranslationFile' this)
  }
  popUpAtHand menu (global 'page')
}

method setLanguage MicroBlocksEditor newLangOrCode {
  newLang = (languageNameForCode (authoringSpecs) newLangOrCode)
  saveToUserPreferences this 'locale' newLang
  setLanguage (authoringSpecs) newLang
  languageChanged this
}

method readCustomTranslationFile MicroBlocksEditor {
  pickFileToOpen (action 'readCustomTranslation' this) nil (array '.txt')
}

method readCustomTranslation MicroBlocksEditor fName {
  languageName = (withoutExtension (filePart fName))
  translationData = (readFile fName)
  if (notNil translationData) {
	installTranslation (authoringSpecs) translationData languageName
	languageChanged this
  }
}

method languageChanged MicroBlocksEditor {
  languageChanged scripter

  // update items in top-bar
  for item (join leftItems rightItems) {
	if (not (isNumber item)) { destroy (morph item) }
  }
  addTopBarParts this
  addZoomButtonHints this
  updateIndicator this true
  fixLayout this
}

// Iconic menus

method settingsMenu MicroBlocksEditor {
  popUpAtHand (contextMenu this) (global 'page')
}

method addIconButton MicroBlocksEditor icon selector hint width {
  scale = (global 'scale')
  w = (43 * scale)
  if (notNil width) { w = (width * scale) }
  h = (42 * scale)
  x = (half (w - (width icon)))
  y = (11 * scale)
  bm1 = (newBitmap w h (topBarBlue this))
  drawBitmap bm1 icon x y
  bm2 = (newBitmap w h (topBarBlueHighlight this))
  drawBitmap bm2 icon x y
  button = (newButton '' (action selector this))
  if (notNil hint) { setHint button (localized hint) }
  setCostumes button bm1 bm2
  addPart morph (morph button)
  return button
}

method projectMenu MicroBlocksEditor {
  menu = (menu 'File' this)
  addItem menu 'Save' 'saveProjectToFile'
  addLine menu
  addItem menu 'New' 'newProject'
  addItem menu 'Open' 'openProjectMenu'
  if ('connected' != (updateConnection (smallRuntime))) {
	addItem menu 'Open from board' 'openFromBoard'
  } else {
  	checkBoardType (smallRuntime)
  }
  addLine menu
  addItem menu 'Copy project URL to clipboard' 'copyProjectURLToClipboard'
  if (devMode) {
	if ((count (functions (main (project scripter)))) > 0) {
		addLine menu
		addItem menu 'export functions as library' (action 'exportAsLibrary' scripter fileName)
	}
	if (boardHasFileSystem (smallRuntime)) {
		addLine menu
		addItem menu 'put file on board' (action 'putFileOnBoard' (smallRuntime))
		addItem menu 'get file from board' (action 'getFileFromBoard' (smallRuntime))
	}
  }
  popUpAtHand menu (global 'page')
}

// Internal graphics performance tests

to timeRedraw { timeRedraw (first (allInstances 'MicroBlocksEditor')) }

method timeRedraw MicroBlocksEditor {
  page = (global 'page')
  scriptsM = (morph (scriptEditor scripter))
  count = 100
  t = (newTimer)
  repeat count {
    changed scriptsM
    fixDamages page true
  }
  msecs = (msecs t)
  print msecs 'msecs' ((1000 * count) / msecs) 'fps'
}

method redrawnMorphs MicroBlocksEditor {
  // Shows the number of each type of morph redrawn by timeRedraw.

  stats = (dictionary)
  scriptsM = (morph (scriptEditor scripter))
  for m (allMorphs scriptsM) {
    add stats (className (classOf (handler m)))
  }
  for p (reversed (sortedPairs stats)) {
    print p
  }
}

// Script image utility

method fixScriptsInFolderTree MicroBlocksEditor language countryCode rootPath {
  scriptEditor = (scriptEditor scripter)
  setBlockScalePercent this 150
  setExportScale scriptEditor 200
  setLanguage this language

  pattern = (join 'locales/' countryCode '/files/')
  for pngFilePath (allFiles rootPath '.png') {
    if (notNil (findSubstring pattern pngFilePath)) {
      fixPNGScriptImage this pngFilePath
    }
  }
}

method fixPNGScriptImage MicroBlocksEditor pngFile {
  scriptEditor = (scriptEditor scripter)

  // load scripts from file
  clearProject this
  importFromPNG this (readFile pngFile true)

  scriptCount = (count (parts (morph scriptEditor)))
  if (0 == scriptCount) { return }

  updateLibraryList scripter
  if (1 == scriptCount) {
    block = (handler (first (parts (morph scriptEditor))))
    exportAsImageScaled block nil false pngFile
  } else {
    saveScriptsImage scriptEditor pngFile true
  }
}

// UI image resources

method makeLogoPNG MicroBlocksEditor {
  // Used to generate images for the logo images in both normal and retina resolution.
  // Must be run on a computer with the necessary fonts.

  bm = (newBitmap 276 80 (gray 0 0))
  drawBitmap bm (bunnyIcon this 2) -6 4
  drawLogoText this bm 2
  writeFile 'logoAndTextRetina.png' (encodePNG bm)
  writeFile 'logoAndTextRetina.txt' (base64Encode (encodePNG bm))

  bm = (newBitmap 138 40 (gray 0 0))
  drawBitmap bm (bunnyIcon this 1) -3 2
  drawLogoText this bm 1
  writeFile 'logoAndText.png' (encodePNG bm)
  writeFile 'logoAndText.txt' (base64Encode (encodePNG bm))
}

method drawLogoText MicroBlocksEditor bm scale {
  // Used to create a logo images.
  // Must be run on a computer with the necessary fonts (e.g. MacOS).

  textColor = (gray 50)
  left = (31 * scale)
  top = (5 * scale)
  setFont 'Trebuchet MS' (18 * scale)
  drawString bm 'MicroBlocks' textColor left top
  setFont 'Futura Medium Italic' (8 * scale)
  top += (20 * scale)
  drawString bm 'Small, Fast, Human Friendly' textColor left top
}

method connectButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABkAAAAWCAYAAAA1vze2AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAF
RgAABUYBwbT6GgAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAKZSURBVEiJrZPB
axNREMa/2U2wCzmIUFCraS499NLWLELD7koOgSIqVGitCKVSWkpBlOJND4LQgyDVmyYbQfAPsHioIiJb
26SXLrQgFMRDzKHtMTVoTLLZ8WC3bNc0yRq/25tv3vvNvHmP8B80NTU1KAiCDqCLiO4lk8nnbl9sFzAz
MzNCRIsAugBIAC7JspwzTXPTyaF2ANPT03eIaAGA4LGqAC6nUqn3/wRRVfU2EX3v7e2NA5ggIgwPD6Nc
LmNpacmdWmTmC7qub7QMGR0dFXd3d58y8y0AdjgcFkKhEMbHxxGNRpFKpbC1teXdtg0g1hIkFoudEATh
IxH1OzEiQnd3NwYGBlAsFrGzs1N3LzMbTQcfj8cHAWwS0Rmvt7e3h1KphHK5fBDr6+uDJEkoFApOMce9
AzskVVUnLcvK4M+rqVcl8vk8KpUKACCRSGB2dhaRSMSd8+TI61IUZYGI5hoV4UgQBPT09GBsbAy5XA7r
6+sAUCOi+8lk8lFdiKqq7wAMtQJwJEkSIpEIiAgAfjDzDV3X3wB1PqOmaTcB3PUDAADLsmDbNkKh0LZt
20PpdNpwvEOdyLIclCQpD+CkX4gjURQfLi8vP3DHDg2+o6NDbgcAgC3L+uUNBtwLIupsA2ABmMxkMq+a
Qb4xs+/TiagmiuJFwzA+1PO9/6STmW2fjAozJ44CAJ5OmPkaETX8oB4VAoHAecMwvjZKOoAoinIagOID
8KVUKp0zTfNns0QCAE3Tosy8COCs22Rmu05nNSJ6u7KycqXVagKapl1n5pcAju3HPtu2PS+K4qlqtfop
GAyOAOjfL2ijVqu9WFtba3g9f0GY+ZkL8JqZJ7LZbNGVY/o58CjIIhFdBfB4dXV1HoD/N9xEvwHaIuvR
gNAXcQAAAABJRU5ErkJggg=='
  dataRetina = '
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
TkSuQmCC'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method startButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAWCAYAAADAQbwGAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAJ
egAACXoBD0XXIwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAFWSURBVDiNrdM9
axRRFMbx3x0GjaQ2pDCFRcxK2pAitpYi+QIpjQoWFoJYKbFML7EIhHwDYyobi7yInca4d0FBhC3WWKUJ
a0KYFJuVQTa7M84+3XnO4X+fw72XhgfqPoru+2FERSWYE8xiRdtP0ZMq4ERmPFePYVnbN9Gi99LywOBq
D/8aXhv3ScPdsgmv9OlPy7wRbYvmigG5VGDuFnZEb30xMQh4ucjJ57ojFUUvfO0dpGjCvEbxXGJP3e1h
ALuaErzTsO67sWEAIcgsOLGvbr5jRKfn4GFoaVigrrIUx1T+wweCe2o2EvypkghrEtNqNiDFyX/CPks8
MmU7byY6K5fRoeCxlpl/Yd2EZVbelHpoUvOige6l9FewJfPUTR8GjaY46tPfxzM1mwMPzQF/9/CbeKlm
VXBaFNYBBr9kf+sWlo145bp2GVA+4S5uYFVq3WSld+kMPTFR1LOrihUAAAAASUVORK5CYII='
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACcAAAAsCAYAAADmZKH2AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAS
9QAAEvUBKRJxDwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAALKSURBVFiFzdjN
a1xVGIDx3z25UZoS8asqiuhC0klSBP+GFupCcOXSL4SgKFmEirgQdddSSqkipRRKLHbjSmihEQtudOdC
Jc2dmCAo+BXRQG0j6jjHxWTayaQx83Hv3DxwN+ec951n3veeM/dOAjKfY1jiHM6o+MMOILFkj5qVlrEr
mBUdNuGnssQgqNvbNnYbpiWWZU5Y9EAZYhBE920xN4Jpdd/KnLLsnkGK0ajcdh96C6b8Y1nVYVWjgxCD
ILGnw7WjotdEVVUv+sJwoWYabb23y5j7RSftNq/qqUKs1gmCO3uMHRN9KDPnsslcrdYJopE+cxwUfK3q
bN6bJkj6lmvkiZ5Wsygzk9f9mEflbhDdjmN2m5c52G+6QI5yNxjDnMx5Cx7qNUlRck2ekFiQecuSW7sN
DthVgFQrI3hTzZcu299NYKD7b9QjFcElmfdl7uokICAtWKqdZ7AkM7XdwoCh4n02cQdOyVyUeXirRWH9
KovHMa9qWpS0TyYya4rfFJ1wSeJZFT82B8pq6804IPpK1ZPNgbLb2s7doo9kToiGEpk6m/tdOtEHO6lq
GwliwL9le7QRcdxez6eol23Twq94wbjzNH4ddkrlPpF4rvUoSVErUQiu4nUV70nE1omUjQMDJbqIl0z4
7mbTZbV1RfSqCWf/b9Gg2xoxq+6QSb9vtzjFX8U7gQWJV1R82mlAwFqBQtbzv63usW7EaFTuz2KcwAV1
L5v0fS/BqWIq9w2mjfu4nyRBkqvcqmjGNfv6FYNUzEWuhjOGveGRDf+S9kUqsdbnMTxnyIwxWU5O10nx
W4+xizhk3IUcfTYQxK7b8AOm/GxfkWI02rrSYVtXRUeMeseDhR4/10k7qNyaxLv+dsSjVgch1SQV/LLF
4+Y1idM42vqMNUhS9U277IrESdFRlZ43Sy403royn2m8v55TN2vS1TKlmvwHLHW8gYqPdl8AAAAASUVO
RK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method stopButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAI
+gAACPoBjcM6MwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAACFSURBVDiN7dU9
DkAwGIfx5zW7Re9lZpE4iY+NweBcnIK9pjZVEgnvxjO2yW/rv0KUBVmgBrL4LmoyUAnY8FAusAYobzDX
YCAPUQ8+wC5ReYmdUFHAjugMrQLm6mSGFUiVwC1Rgnw/+BVwVPRGzafXGyi0xsFhVmO+PAbvB/aAncAA
ffwF7ItnNpUpNqZKAAAAAElFTkSuQmCC'
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAR
8wAAEfMBmr+RUAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAIaSURBVFiF7dkx
TxRBGIfx39wqh1fZ2JBQWFDZ8gWUGDUIBDWCojHxgxkIMSGCgIKCBuMXsKUCtMBQ0ECFnHiuxR16HHvr
GY7bM+HpdubNzpPZyebd/wYN8pFz3TzD7YTpiwg1YzF2E2oXN3l6lR+NrFt700RionUmAmON1Dew6MwO
D3s5aKA2nVU68kxhuBlyVbyJudtDMa0oVbAi9wJDTVX7w1LEncvs1yuoK7hGHjMh+cw1k3d5hrv5ljSZ
SxrcohB40wI5uFFkYYtC0uSxHdzkQpFFXDt1taN8yDNQu5NHdnCVjiLTWi8Hffu8+kJn9eBvwVU6OplB
f8vVKgSul5irnH9UBGOiPJMxA1nJVXEzMPWJ8xBiog0m8SBjsVpmNxkJ64zjSdY2dZgI62zjUtYmddjO
xURZW6QQ5UK7CzoTPBFngiclyqnT0bQJUTvLobx7P7OWSKGUQylrixTOBE/KfyAYt7tgaHdBvM3aIoWl
tm35Y15+ZTRULqINnmMkY69D5ne538tBDgKlXR7jdcZisBwzeph8HUkWKmHRrIy+jQPvcwxVh0nHoo81
8oE53GqpHSt5Bmujj8R0a4vCXvlx97VEjZUCQ13s1U4ktltd7MX0BxZO381ynsEkOVKa1R6K+9zD/Kmp
lQPMutkgf+mmr/C9WH71zDbbLGYxZjgtXeUfQvTPjMc8aoZcYHqHsaaE6Idk9RviFzG4jSVrWs+wAAAA
AElFTkSuQmCC'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method projectButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABAAAAAWCAYAAADJqhx8AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAH
6QAAB+kBlHo8QAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEbSURBVDiN7ZSx
aoNAAIb/hGsqlRZBChWbQicnB3c79AXyEKV5Axdx9w2cut3iEzi2QnFyL9TD1qWTgoNBQ0jQDoXSpOYS
2jXf+v//Bwd3NwAH3/fHs9ksopRebURLABEh5I5sG3ued2EYxkuWZac98RGA29Vq9TDsG1uWdS1J0pum
aX3jn9z8EjiOMy7LklVVdbJjDADHawLXdc/zPE8ZY1uPtsl30bZtOU3TD8bYCAAEQdhfQCkV67p+J4SM
VFWFKIqYTCYAgPl8zheEYSjIsvyq6/pZXyGKIr6gKIpYUZTLJEnWgqZpEAQB4jjmCgamaXbcxg5678FB
cBD8RbD4x34xBMB/LXyeh4SQ+67rnvD1Ue7LEsBj27bTTyA4XCa7dVryAAAAAElFTkSuQmCC'
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACEAAAAsCAYAAADretGxAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAP
0gAAD9IB+4k7yQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAIrSURBVFiF7di9
i9oAGAbwJ7lrC6IHVuxdS40UgoJIXKQZjNCl0L+lmxQRyXCCkK2HSwYHb3IWHPQ6lvqBXHEpiF81LUlP
QTBwyE1K0inQw35EE7FDnjHJ++bH+yYQQsBiisWiy+fzfS4UChGTJUsAHQAXzWbzAwCQVgCiKLpZlv0a
jUbNAgDAA+A1gCuO43KWEKIouhOJxDgWiz3dtQeAc47j3hzvUlkqlTzxeHzEMMyZBYCRd1tPIpvN+rxe
7zebAADwcqtJpFKpx6qq3iyXy0c2AQDgxPQkBEHw393dTXu9np0AAICpSQiC4Jck6cdgMHhoNwAw8Xbk
crlnk8nkZl+AfyJ4ng8oivJ9OBw+2BcA+Ms6eJ4PzGYzaTQabVxDEMT+EZlMhppOp5PxePzb8xRF2YrY
WEc+n38xn8//CGBZFslk8t4xTdMsIe7dqFKpPHG5XF8YhtkAkCSJQCAAhmE21rFYLOxBVKvV00gkMqRp
2r1tk06nYx1Rq9XOQqHQkKbpk20bSJKEer1uCUGWy+Xn4XB4tAug3+8jnU5jtVpZQhyv1+uWLMseWZZN
Fei6DlVV0e120W63LT+UAEBwHKdb7mIxlr6s7IqDMOIgjDgIIw7CiIMw4iCMOAgjDsKIgzDy3yCWBzbc
kgCuD4y4JnVdvzikgCCI90eKoowpiiIAvDoA4LzRaFweAYAsyx+DwWAHwCkAPwDbf479kluCID5pmva2
1WpdAsBPdzu15+Xij+EAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method settingsButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAH
OgAABzoBqsXEHQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAJ1SURBVDiNpZU/
aBRREMZ/c7tXbBoVooFAWiNaXmO4XYwhCfgnEMXTRuxTxiSIvZWK2qW2sAoSUUlhUA/yHmqRNqCtYDwU
tErA8/JZ5E7ebVYv4lftzJv53puZt98z9oE0TR8C19rmhnPuRK+cUq+AWq0WAVOB63i1Wh3ulReHRrVa
HS6VSvckLTrnngM0Go0qcCiXdwZ4D5Cm6Xkzm9nZ2bnuvX/fCbDOR5qmR4HXwGDb5SV9NbOzQDlkNbOW
pKeSDpjZWNvdMLOxtbW1ja4Tm9l9SYNBftXMKIKkCLiQWx8A7gDnIOixpMVCln9AyNG1ZZqmr4HRgpzP
kt4BmNnJ9unycM65rGN03QpJ33LBLUkLcRwPee+nvffT29vbQ2Z2A2jlYr+GhgGMjo4ebDabk2b2iKDv
kha893cLTkeWZQuSbgeupqSr5XL5Rb1e/25pmq4Cp4EoX34cx0P1ev1nEXGlUiknSfKRvW1pAa9KwHgB
KcDbP5ECrK+vN4E3BUsRMNHzz/sbJBXfR3aHt8reQQCMVCqVcoEf2G2FmY0ULLWA1ZJzbjKO435JV4Cw
9IG+vr7ZPxEnSTIHHAlcTeByHMf9zrnJrlKyLFuWNB3ubmY3t7a2HrR72hnaHHCL7tksO+cudowuEZKU
F5tI0u0kSeazLHvbjhkBDhcU0R8aoQidB54V1r1/THVU8fetMLOZ/yTt4ghFaBb4FMR54ImkHwUcLUmP
gZeBrwEs7CF2zn2QNGZmK+yWlDrnLkRRNJFnlTTvvb/knBsHpsxsRdKpjhZDTt2KUKvVos3NzS8Er4ik
Y+FrUYSef97S0lKL7qFu9CIF+AVCxv2ly3PtJwAAAABJRU5ErkJggg=='
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
egAADnoBz63/KAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAU+SURBVFiFxZld
iFRlGMf/z3tmRmiZAdOirHYEvSlv9KIVnPfAZNvqFOESCJJkGBhZGlokZBkUUUhgWWYFlSREgQUV1ZrZ
NrLvCHpRXbTd5IJOCRukwoyrzOzM++9ix9idOefMObOj/i/P8/U7H+/HeV5Bl5TNZhfWarVfAMxtMlmS
LxYKhde7UUd1IwkATE5OPoJWWABQIvI0AOlGna4BA+gPsN2SyWTu6kaRrgAPDAz0iMjyIB8RCbqh0Iq1
sYvrus9Za0upVOrA0NBQxcvp8uXLWQBz2uTqB7DXy5DL5eZcvHjxMQDJkZGRNwDQL0nQExat9T6Su0Xk
vXK5/KfWeoNXDmvtw21gAWDl4sWLW25Ka/1guVweJbmf5G6t9YdBXH4DQbTW+wA82WwgOayU2l6v18eV
UlsBbADQGwIYAP4h+QHJd0VkrlJqD8n7Pfw+NsZsAmDDAPvCToO2ImLR/pPy06SIKJJOgI8ndEuA67o7
AOwMqiYigtkNWCdE/LJ0Oj1RLBaPT7/YEmStLc0CpKuy1pabr7UAp1KpAwDGrglRsMYaLDPU8kmcOnWq
nk6nzwBYd02wfERy4/Dw8B/N132XS631YQCrriqVv34yxnguNL6jXCm13Vr7O8IPrgmShwHklVJ/A4C1
9nYAWRFZDaAnTBKS1nGc7X52X+BKpXI+Ho/bEMB1AHur1eprJ0+ePOdh39fX1zcvHo+/0NgEBU1lEBFL
cjwycDwe3xJkb6hEcl2hUBgKcmrcyDOZTOZHEfkcQCrAPQZgK4CXvIx+T08wtYIFyQJY3w52ugqFwpC1
di2m3kqQHvVj+3/QZbPZWL1eX06yH8AggKVtku4xxjwbFna6XNd9k+S2Nm6/AfhKRI46jnMin8/XAEAy
mUxOKfUEySyCX9V0TVSr1bTPN9tW2Wx2fq1WO42QAxFASUTy1tr3RWtdAZCIWPMLY8zaiDEzpLX+EsBD
EcOqCtFhQfJY1JhmiUi+g7BERxuYK/PsbGStPdtR7U6CSM76h1Ip1VGOToFv6ySuGzkUgGoHcdlOijXp
ng5iKorkoIh8AyD0PlhEVvf19c3roCCAqWkNwH0RQkoNxsFYY6Uairhw9CQSiZ0AOlo4arXaLrSZg0Xk
V5Jftywcfv5a69MI/rm0ANYYY76NAuu67iqS3yFgEyQixZGRkYXw+N33G3QUkU/a1FYAPs1kMrkIsA+Q
PBQECwAkD8CnN+E7taxYseJmx3HOkmy3Y6uLyDuVSuVVv6W6sRTvAvBUCNjJeDy+IJ/P/+tl94VxHGc+
yTDTnkNyWyKR2KS1/gHAMQB/NWx3AMjWarVVAG4IkQsAHGvtrQCiAZPcg2jzdA+m9gZR9wczJCKqXq+/
BeBeL7snkOu6g7h+/3MQkZWu667xtDVfyOVyc8rl8iiARVedLFhjyWRySXMDsuUJN7qI1xsWABaVSqWN
zRe9PonkNYAJJaVUC0vLFFMsFo/39vbeBOBuv0SNZmAdnffXJqfac4HxHxljdqJpPvYKoDFmC4D9PrDD
juMsFZEFJF8BcCYC6DiAl2Ox2AJr7RIR+T4A9nGEbLf+b2tqu44BeN4Yc6jJT7mue5Dk+jawExcuXLhx
dHR0xu5Qa90P4G0Ad7aDBYJfCY0xW0RkB8nNyWRyiQcsGok/awMLAD83wwKAMeZoMplcRnKziOzwa2Rf
UVeOogYGBnouXbp0DsHnHNuMMZ5nHFHUlVOkI0eOTJA8EeRD8mg3anXznC4IaLxQKLS0TjtR14BJHgRw
3sNkMXXc5XuUFUX/AfHiFId5ScXEAAAAAElFTkSuQmCC'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method languageButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAH
qAAAB6gBuRybzQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAANXSURBVDiNlZXd
axxlGMV/z8wkrMZNDRRlNbdqQQrFoDXZeWHRJmJiRXrhjSB6IxXphaAgSKshopGCF+K3f4DI3pS2KqZV
w84sKdFFxAYpih/UYnrlNonZfMzM8WJnZbMEis/NMGfeczhznvd9XmP38sIwPAocBfZJ6gMwsy3gkpm9
F0XRR0DWS7RewDl3TNIbwEAObZpZIskkBWbWn+NrwEtxHL+7w0n3SxiGn0t6G0jNbMPMPm21WsUsy85L
OtdsNotA1cw2cnfvOOfO7ipYLpe/Ah4GvgBqkn5PkuTpRqOx3VmztLS01Wq1npL0h5nNS5qTNBWG4dwO
wXK5PG1mD5jZYhAEbwFTZnZ8YWGh1RtJo9FYl3RC0uEgCGaB74Bx59xxAKtUKoUkSa7l4kHOy4DvJV0z
sxVgpKMnadDMbgYOdAyZWZplWdrX17cnSNN0BuiXNGVmC8ACsArUgEFgD1DIBbeBX4EVQJIGsiwr+75f
NrPTSZK8as653yTtjeO4WKlUgiRJViU9X6/XP+jK9xRAvV5/rKuBzwEnS6VSsVqtps65NUlXPUm3ARcB
Njc3bwUKZvZLb3a9lWXZz8ANy8vLt9C2exEYtjAMJemKmS0CReAQMA/83cW/P39e6MKGgApwPo/oIFDy
AF3Pzf+pANg2s8txHB8ZHR293ff9PyW9Xq/Xz3UWdWV4pIONjY1NeJ5XMbMnoyj6KwzDC8BeD7gC7AcY
Hh5eBtbN7I7rOTGzO4F/oii6mkP7gcvmnDsp6QUze2R9ff2bQqHwred5TUlf0850EHgoJ31JO69V4EFJ
xYGBgYNra2uHPM87Bcx2b2yjvVF92rleoj0AmsDdueCSme3JsqxoZnflnJT2QchKpdKgNz8/vyHpNaAP
+CFN08M5+UQcx/fGcTwuaVHSYhzH41EU3ed53jSA7/uTwI8595Vqtbrl5WHP5L94j+/7LwNngZmRkZEb
e7ObmJgYkDQt6XSapseAA5Lm4jh+E3rmoXPuM0mTwIqZ9Us602q1nigUClWAZrP5+NDQ0CfAJO1jWATO
xHH86H/N6nWQH6lZ4CZJnSmd5J8DoD/v8qqZvVir1T7c0f1ewbw859wzkp6VtK8zpSVtmdlPnue9X6vV
PmaXK+Bf79GQ6SIwG1kAAAAASUVORK5CYII='
  dataRetina = '
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
s+gAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method graphIcon MicroBlocksEditor scale {
  data = 'iVBORw0KGgoAAAANSUhEUgAAABgAAAAWCAYAAADafVyIAAAABHNCSVQICAgIfAhkiAAAAA
lwSFlzAAAKkAAACpABL6VQZQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAMLSU
RBVEiJrZVPaBxVHMc/b/bNZHtYk01MnIZYUohFTVzbxNBbCwXxYObS4sGLWFvYgydbK43R5TUmYMHutR
baXkTIoYey7oZStM2hBD1EF3PomiZUs6FLsgfJkj+QmZ3nYXfCmiZ0W/Z7enx/v/f9Pt7vO/PE0NDQZS
HEZ4BJY+ECSVkVd4UQfzZSXWv9BnBOUjn5bCqVeqeRBo7jzAD9xosKKKVO7MK9PDo6+nYtJxzH0cDvoV
DolOd5++sRtyzL7Ovru10sFs/n8/lcwMdisYumaQ6VSqWT8/PzCaBfBkXP87qFEEfqMejo6DhiGEa0ub
n586WlpesAbW1tByzLcra2tv6em5srGUblcrYN0un0FDBVj4FSagogHA6/OTg4+MD3/RlgGvAtyzqZyW
SyjuMA8NwzUEq9DhwDsoD2fT8hhDgDHAWuKaWytf17GiilPhkfH99tJnFAABeAFPC+1vo7oNjU1PTVzu
a9DATwheu647VkMpncB3wEPFJK/QKMVksvAV8ODw//+5RQkKJyuXxGSvkaQGdn51u2bX8N6Hw+f7FYLD
4G6O7uPt7a2vrp6urqDwsLCz8B9Pb2XpBSRmdnZ0d839cAnuc9CoVCN9jrO4hGo+8BGsC27Y8DPhKJvA
u4hUJhKuBWVlZuLS8v3wjEd2I7RZOTk1kgOzY29qrnef3APWDRNM3TAwMDaK3/Ag4BP05MTNzcTawWQY
rkzoLneXFACiGuSimnXdf9QGt9mWqEDcO49izxWvzvipRSFnAWeGLbdmpkZKQghPgWOAicBh4mEokHL2
wghDgFvCKE+D4ej7sAkUgkCfxTrV+lOpt6sZ0irfX5WCx207KsA7lc7pv19fVS0NTV1XW4vb39w1wupz
Y3NzefJaq1/kMIcYXaf1FPT88+y7IOuq7789ra2t3aDYuLi7+Fw+EnGxsb9+s5tZSyUC6XK+uAbGlpmQ
EumaZ5J51O/7pzUyaTma5HPMBTKVJKrQDqeUTqgXAcZ4vKk/mwkcLVJ9OUQBI4p7UeaKQBlUf/yn/9gR
oIgZwg6gAAAABJRU5ErkJggg=='
  dataRetina = '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'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method zoomOutIcon MicroBlocksEditor scale {
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAACXBIWXMAABx2AAAcdgH7OYqmAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAy5JREFUWIXN2EtoXVUUBuAvMU0Uan3Vtj5A
FFqtigNtpa0jpT4gOnCggtDSgkMfOFHEgUUQCk7EFkQdtBOtYBxWMSNBUetjKlofQSltBtKmRmxq08bB
ziXnrnvuPY97LvGHPdgc1r/+vdfae691hjSHy/EAxnEzrsMazOM4pvEtDuNz/Nug7564FRM4h4WS4zRe
x1WDFLYaB6QdKissjhm8jJGmxd2B3wqcz+EPKbxFi5jElU2JewSzOU7O4UPsxDXBZhi34Hl80UXkz9jQ
r7jNOJND/gHWV+DZLh2YPJG1d/JaHAuEZ7CjJt8I9uWInFQzJycD0d/YVlNcFs/miHypKsn2QHABTzQg
roU3A/+MCqEewpFA8EaD4kgh/S742FvW+O5geNpgLtj7g59TWFHG8NVg+NoAxLXwZfB173AJo4fDfKJp
VRl8FObjRQYjOG9pRcelnBwUNmrfwc+K7pu10ivQwk+Lhi1cJr0sdTGnPSJHpQ25aHEeX6QObNK+okPh
+23he9XxZ47P6cz32aIcjDs8X7SiBpCtE1cUhXg6zNeF+Um824eY2TAfCj5OFBFcrD0kR/sQUwbXB39f
FYV4DlOZ+XrcOBhtSC1DFj+UuQcPh3k/p7YI8c79uIzRQ9q3fQpjzepCarSyfc1ZXFrGcEwq3bMinx6A
wIngI15pPfFUMP5HKu2bws7APy+1CKUxgh8DyXmdOVMH90iHMcv9Th2izTp73wvY3Ye4x6XKPOb46qpE
V+DTQJQN9zMYrcB3NfZLC8xy/YXbq4rbKHVbRe/qFJ7DTV14hqUo7F0UkrfQjpQpKp3G8T5W5XzLVh0R
v+B3qTwblTrCDVJ1lIdjeFQq+0thCC8uiohhWJDCvU3nwakzPtH5xvfEGA5aOgR5oWz1JMN4DL/WEPY1
7qsijBSK2MFlT+ysVANGjOJBqRHvJnYe3+AV3FVVGGyRyptu4qrce2O4AVtxp1QZl3n3u+JJ+f9csuOF
fhz0gz2651trvGewzVJPzPQQtiD9hbpkucTB2zmiWjt6QqpylxUr8b1OcWelJP9fYK1OkbuWU1AeVuIt
qVPbs7xSlvAfCj2QzoDCDrQAAAAASUVORK5CYII='
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAACXBIWXMAAA6QAAAOkAHc49yqAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAYFJREFUOI2l1L9LVWEcx/HXjaRMLRquJQi5
ZDlHe4M0REsNQqND/0AQ7bVas+Bi0BAKTtEWzYkRUaDiIoRDOfij8t5SvA3nq/fpeO85V/zA4ZznfD/f
9/P9nvM8D+W6iUksYwe/8AUvcK2D/EP14BX20YhrB/VkvBvg02WwPnyMpO94hMEkfhVPsR2et2XQuTB+
wKUC3zBWwvu8nWk0DN9QLeyjCf0pa3+4qLrxDmAHehY5E/lAJWaro/cYwOsB/FzJBar4gSWM4DymC0B/
8CAKqeFv/s+cinsjGV8pANaS50aS/x+wht84WwDKayiAi3niPt7jHO4eAzgW93etgvdjtmUMdAAbwHoU
c6OVoYL5gG6XQPsT78t2ptvY1NyvK7KWuhPPBTzEWngWZHv/iJ4ksA3Z1jsA17EYE+wm72e0WLNn8DqB
beJOtH8Pb2QnTSOJz+JWq6qq+JQkbOFxm8/Rj4ttYodaxZ7meTdTllCmKdlC3sNXWfsnUldAV3H5pLB/
foZsC5ZTyFQAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method restoreZoomIcon MicroBlocksEditor scale {
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAACXBIWXMAABx2AAAcdgH7OYqmAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAA0lJREFUWIXN2EmIXFUUBuCv2rY7QpRoYuIE
opDExAEcIhpdSYxCzMKFCgGDgsskIooiLnQZ0IWoILrRjQOYbRTbjRAhzrgSjUOjhKQXDh3b2Ind6XZx
q+hXp17Ve69eFe0PF+rUrfuf/95zh3OqYXBYhe3YgY24FGsxj2OYwhc4iEP4d4C+e2IzDmAOiyXbCTyP
1cMUtgZvSCtUVlhs03gGo4MWdx1+LnB+Cr9K4S2axAQuGJS4nZjJcTKH97AbF4cxI7gKj+GTLiJ/wIa6
4rZgNof8XayvwLNNOjB5IvteyUtwNBDO4sE++Ubxco7ICX3uyYlA9De29ikui305Ip+uSrItECzggQGI
a+GlwD+tQqgb+CwQvDhAcaSQfhl87C87+OYw8IThXLB3Bj9/4uwym/GeYL+C35uf12JvDVEnLa3URziM
W5v2KtxehuRr7TO7PtN3tc4NXqX9Fnw9HvpfKBI3ijOZAcekPTksgZtC/8dFIV4nvQItfN8c2MIUniia
ZQ/MBvuItCBnNe34InXgJu0zeqeGmLKYyvibGSn4cVzh+aFIakc2Tyw8xVPBvijYK3BtDTFz+CZjN4KP
40UEK7SH+EjoH/QhuSz0Hy4K8SlMZuz1uKJoVjWwPdjflrmoD2JPxt4pvZ2ki/ZQDUHTwY6PwvtlSO7W
vuyTGK8hqhs2aq9rTuPcMgPHpdQ9K3JPzxH94UDwUelKeyQM/kdK7QeF3YF/XioRSmMU3wWSMzr3TD+4
TTqMWe7X+yHaorP2XcDDNcTdL2XmcY+vqUp0Pj4MRNlw78VYBb4LpbRtIXD9hWuqitskVVtFl+4kHsWV
XXhGpCjsbwrJm2jHlmnELwJ24G2cl9OXzToifsQvUno2JlWEG6TsKA9Hca+U9pdCA081RcQwLErh3qrz
4PTTPtD5xvfEON60dAjyQtmqSUZwH37qQ9inuKOKMFIoYgWXPbEzUoIQMYa7pEK8m9h5fI5ncWNVYXCL
lN50E1fl3hvH5VIBdIOUGRclJj2xS/5/Ltn2ZB0HdfCc7vut1d5SfOKHhukewhalf6HOWS5x8FqOqNaK
Hpey3GXFSnylU9xpS1X+smOdTpEPLaegPKzEq/hDOjj/C/wH9uC4M441HhwAAAAASUVORK5CYII='
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAACXBIWXMAAA6QAAAOkAHc49yqAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAZVJREFUOI2l079rlEEQxvFPgmLEH40mZ8BC
C6O9pLKKSECxCugfIGhhKUiakMJesRSsBAtJwEZiF8RSUUQUNaY5EAuxMDF6OWO8s9h54+a8e99ABpZ5
991nvjuzO0u1jeIOFtDAD7zBLRzfQvyG7cF9tNCO0UAzm/8O8I4q2D68jKAvuIbD2fox3MD30Dyugj4M
4TPUSnQjWAztzV6iMyH4hMHSOv5BV6TyR7qleTX8NJZwugT2B09xG1O40inoi92a2BsZtktGI+JOxPx1
Z4YHA/RBao8mTlVkSGqpXzjaCewP3w7fQr0E2Mq+21n8JuAqfmLA1ks+EvP3nRm28ARncR6PcKkkw/Xw
F8PPdxNNxG4LGC6BFTaMr5HMyW6CPjwP6EoFdCjT3uslGpf6rzinRVzA7kyzH5fxOTQvpLf/n01msG/S
0yvAq3iHj1jL/s9Ib3+T7cKDDLaEc1H+BOakGy0gy5jFWLesBvEqC1jG9R7HUcOBHmsbVpeuv+irmaqA
KrsrNfI63krlb8t2BrSOQ9uF/QUd5IF+Y39L9AAAAABJRU5ErkJggg=='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method zoomInIcon MicroBlocksEditor scale {
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAACXBIWXMAABx2AAAcdgH7OYqmAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAA2pJREFUWIXN2EuIXEUUBuCvx86MQtREo/ER
8EUePoigiWgUFxKjMLpwEUXBaECXKm4UcWE2QsCNaEBUUDc+wOguiuNCQSE+wZVoog5qcGZhdOKImZjJ
jIvqJtV1b/e91dNh/KHgHm6dU/+tU3Uet2FwWIYtGMVanI+zMYvfMIkvsQef4N8Brt0Tl2E3jmK+5jiE
Z3DmiSS2Aq8KO1SXWDqm8CSagya3Hj9VLD6DXwT3Vn3EGM4YFLnbMV2yyFG8jW04N9EZwjo8ik+7kNyP
NQsltxGHS4y/hdUZdjYLF6aMZN87eR4OJAYP494+7TXxfAnJMX2eybHE0N/Y1Ce5GA+XkHwi18jmxMAc
7qrQ2SXc0incXTH3ucT+lAxXN/B5YuDZGnqvRPPvq5jbxFfJGjvrErwmUTykXoDNIQg3J+v8iSVDNRRv
S+RdOFhDLxcfYm8kL8MN/RDcPTBKRbyTyKNVBJu4MpIn8M1AKXXivUTeUBVvVgpZoI3vhfPRxulCZinD
JdHzdThWMmdGp0f2tead1JLTjFTABp0H983k/eWKMSxn/F6y5mT0frqOi2PMVn3RABDXiUuqXDyZyOck
8h94uYvujULhCh8LeTbFdCI3kjUmKvg5WadL9lUpRMiNg7AqWW9vlYtnMB7Jq3FRBslcbEnkb+vEwT2J
3O3WDgJpzE3DTilu1bnt4xipoZfr4rU6+5ojOLXODn6EXyP5QjxYQy8XT+uMGu8qXqKueEDnLv4jlPa9
kLOD2xL7s0KLUBtNfJcYOaZ4ZmKsEpqr9VjeY971wmWMbb+UQ66NjYq97xy292OshTuFyjw94ytyDS3H
B4mh2N0PYTjD3llC2TaX2PoLV+SSu1TIAlV5dRyP4OIudoYEL+xsESn70MKRaVSQG8UbOK3kXVx1pPgB
PwtN+7DQEa4RqqMyHMAdQtlfCw083iKRumFecPcmxYvTz3hfMcf3xAhec/wSlLmy3ZMMYSt+7IPYZ7gp
hxjBFWkHF9/YaaEGTDGMW4RGvBvZWXyBp3B1LjG4VihvupGrinsxRnCBUElfJVTGdbJWV9yj/J9LPB5b
yAILwQ7dz1t7vK76xp8wTPUgNi/8hTplscjBiyWk2js6IeTURcVSfK1I7ohwyP8XWKlI8v7FJFSGpXhB
6NR2LC6V4/gPU86YtMg9uoAAAAAASUVORK5CYII='
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAACXBIWXMAAA6QAAAOkAHc49yqAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAaJJREFUOI2l1L1rVEEUBfDfihq/g8JGA4I2
Rq3FXkQsxEYLwT9AC0tB0lnYK5aCjYKFRBALsRPbKIqIQoxpAmKhFolRsxsTdi3mbjI+57mRXHgMM+fc
c++Zj0f/OIpbmMQ8fuAtbuDgKvKXYyvuoYNufPNoZ/PFEF7fT2w7XkXSZ1zG3gw/gGuYC86TfqIPg/gc
u//BG8FUcK/XkU4E4SOaFWwcYwXR75L9kXUFwUsxXsXXCjaAjZW1D7gpWb5YFWtEtTa2FYq9xqPC+iHJ
1ZtGBWjiC97jMHbgToYfl056POYLOB+NtPCrejK9Lehm830Z3rPbW2tlWDfL/0OwhZ/YVLBWZ3l/CE5U
FTt4hi04XUisi3MxPi2BZ6PaJIZX0eGwdBs6OFISbOBFiM5VRHdhMJsPZdy7de2fxIyV9zoVljZnnEFc
wKfgvJTe/l8xitkgzUhPryfcxkQUWMzWxxTu7ADuZ2KzOBX2z+CxdP+6Gf4Ax0pdNaXN7iV8w5Wa7RjC
zhpsOaaxZOV/V338/x23pYu8hHeS/TXFhhCdxp61iv0GkDZz2QEPwisAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method bunnyIcon MicroBlocksEditor scale {
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAYAAABV7bNHAAAAAXNSR0IArs4c6QAAAAlwSFlzAAALEwAA
CxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRv
YmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRm
PSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpE
ZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFk
b2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVu
dGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4K
TMInWQAAEIhJREFUeAHdXAeQVFUW/ROAUTCBZJC4rDiyarlYiogwAmKJirqKpEUoQDFgQLQMqJhRCiOW
CpIkLCoYMayCJJUsLCAgMENmyEEEptPbc+68++tPT7dMT890z/iqfr//X77n33fffffd346ToPD000+n
oqv0k3V3yy23pEUrZ4xJOVn9ks5PSIdt27ZNnzNnToCDB5EZL7zwQrP09PS8Rx55ZL0SRGA++ugjPgY1
7f3336+zefPm2qFQqGG1atVWPvjggxsJEoLRMuU6tlxDznGmT59eu3fv3sNxm40rdMUVV5ghQ4Z0ZB4A
zGDM8Nprr/29R48ew+rVq7cEj7/jMqeccopp06ZN4JlnnmnJMpbLeFt+A8Bxp9Pjjz8+AJQcwGUAgAEn
kAPM888/304pfO+99zI7dOgwBc/kIPPwww+bGTNmmNWrV5vHHntM0kaNGvXXAEjBwXSofNNNN80gwQ89
9JDZunVrHtLyBgwYYKpUqfKdggMwBuM+UL16dTN58mSzc+dOH8r5cQUDgUBely5dTIsWLSbb8pRR5TdQ
3nD0a9asqdqpU6fVuDVffvmlD3IkCILNqlWrKItMnz59urHc7bffPo7PTz75pNm/fz8BDLFcMCjFQ199
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
'
  data = '
iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAAAXNSR0IArs4c6QAAAAlwSFlzAAALEwAA
CxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRv
YmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRm
PSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpE
ZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFk
b2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVu
dGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4K
TMInWQAABmlJREFUWAmtWFtolEcUnt1cLGmK0kvWSmIjiNi8KJgGDWq0okUhitJCoC1IQNMmUCtYii2I
D4U8SPHBkrRaioRCJdoGETSKxJpUqYlpNSohMSqJuWiqMYm57m36fZM565+su9nVHJidmTNnzvnmzJyZ
869S8VGiQzxt7969b6DvcvBS0X734MGDcyzPOeYQm5mmgHk7PT3956KiIr1y5cofreoVqH8tLS1tR9FZ
WVnfW77MmRkEDi2i+P0dO3YMPH78WFdXV2uMf4DyVXl5ue7t7dWkEydOkJ9n5ybYekYrAfMetkj7/X5j
eN++fQ2w8u358+dNHz+j4+PjevPmzX/NqPUpyuQMJG/durV1eHiYxkfpIcj9uX///k6Lhii9HR0d5JdS
x7Jly5JYzzSJd76or6+n7XH+tLa20nBTbW2t6ft8viDYvmvXrpH/iQUhc+PC5I4mDSMBjn8EWrJkCZvm
TAwMDATRHkxNTXWeEZfX66XMMH9elKIBcrtcLq7Yk5OTk5WcnKwA0GwhzooffG7XpPmBgMHvBBk3rkkK
nbNxPqQ7e+7cua+yEwwGDSCcJXYHx8bG6Ckh19OnT9keE8aL1LEACjB6nMoBjPNGsHXGJdaT7sHBQYp1
W9lJcyxv2ioiIMfMof7+fuMSt9ttjAAg57XBIyOUE/6jR48o10seaMYBicL/uru7e2gBnjBbNDQ0NI5u
E/jGJcJ/+PBhH/j9lAXJ/IlejL/RPKQRXDygwStXrrQCBFUaQPfv3+c5udHe3t5BJijIA41+M9pGEPcQ
w/6lDjgVTyW5S75paWlBUOlRhLbeuXNnjRX8CV4hf+TOnTv0SAVKCorzUiSoaAvH8DMSg884z2/9fevW
LbVo0aKke/fuqcOHD3sKCgp+x1atwPlSaWlpr3DaoUOHClDlNzc3d5WVldWh/QsKnxgSgZkgML0X+cHK
5el4De+YeSYAwE9vMfIQbfQOKlOzbQjbp3t6evSRI0foNYJKtvZffgvXrFkjXizr6uqiQR+KeSpsTV4I
nOWZt43ttrY2vWrVqn+gR3KkmLcvqhPXrVtX8+TJE9rGg+83AKZ6hoPksdBLqAl8rLOzU2dmZtY6DIjn
HazYmuKdD0+fPk17fmuE7WmJeGy6Mnb58mVu39fWrOiNDYVIwaJZyaZNmy7Z1MM3sehpsYQErHyAjD17
9vCeesvqj2/r7B3EuXnHjh2jvkA83uEEIW4fyHv9+nV66UsqdZxNdmMiiYgf7GH2WsViJ+baesnHyNy2
bZu5wzCZ3g87S5HcRkFzZxQWFubgnuEKcO2EzWdKYgoFhACAmYF0pXYzhVm+fDkTqzehi94KUxgJkCiZ
PX/+/PTERHMGw2QJhiBZ2CaxxmNriijhOAAa4/hieR38d+xYzIBEMBFZYegZoGIhAcMskfmRNWpqpLLq
3LlzIuqsg3PmmOuIoEjPFE70I74xE8vFtsFY6LoXL3CutCsrK9Xq1avNFtEzpJs3byryhQQ8+q7R0VGy
TdqCWuyQF5VCyPEd1ogkHjrNHcR6Et29e1cjGwhdiDzAvHueEwAm1PDeMWfKsNbDjkE0VBJl5ch7CGJS
lPHVdxI/gfg1W1JSom0GEBq2sj4C3b59e73DaGjhwouIEPeQyFTW1dWxbWQlem7fvq1qakwEG7mMjAy1
ceNGtXjxYr7+hseUtqqqSkkuhUdZHT16tIqD9h6KecuMQvyYFWRnZ9f09fVxxZO81NTUpI8fP64bGxs1
En599epVferUKQ0gGmDNZzVffZCfW7hr165pb2rZFgEwtea4xpb9O2vWrM/Wrl2bgGiC7gDOr1t5PB61
cOFC9eDBA1VRUaHoETyk6uzZsyo3N1fl5eUpRCm9EDh58mTC7t27S9C+hMJ7JBQsaIdoOkBUxsk9Fy9e
7FiwYMGWpUuXEowPoBKwcpWUlKTmzZunkDEaMOzjrlHr16/nFUCjQTysSRs2bOA/Jd+hcOufCwb8mEmA
f37gwAE9MjJitgE/DD9GTxBeZO4TRFizT76XEQfPcFHlDkthB9kxFldTQOVitY1nzpzRyB5hN5wASjc0
NOji4mJ+rXzqsBIxiEQmXrTcPn5Gk7bgj6mP8/Pzs/G8eFJSUhSAuPkphD8hbly4cOEPyPyGws9ZAqGn
WKJSvICojJ5yngEm+B4U6mJhJA2gCDkXIbyI9f8PmQ4SvBAaOwAAAABJRU5ErkJggg=='
  if (2 == scale) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method logoAndText MicroBlocksEditor {
  dataRetina = '
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
QmCC'
  data = '
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'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method trashcanIcon MicroBlocksEditor {
	dataRetina = '
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
'
	data = '
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
Vnv/D5+W/VhX9GaCAAAAAElFTkSuQmCC'

  if (2 == scale) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method hideDefinitionIcon MicroBlocksEditor {
	dataRetina = '
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
AElFTkSuQmCC'

	data = '
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
AABJRU5ErkJggg=='

  if (2 == scale) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method hideAndDeleteIcon MicroBlocksEditor {
	dataRetina = '
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
IpJSjo1M5f8DJH/nomvuU2YAAAAASUVORK5CYII='

	data = '
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'

  if (2 == scale) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}
