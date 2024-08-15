// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksEditor.gp - Top-level window for the MicroBlocks IDE
// John Maloney, January, 2018

to isMicroBlocks { return true }

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

defineClass MicroBlocksEditor morph fileName scripter leftItems title rightItems tipBar zoomButtons indicator nextIndicatorUpdateMSecs progressIndicator lastStatus httpServer lastProjectFolder lastScriptPicFolder boardLibAutoLoadDisabled autoDecompile showHiddenBlocks frameRate frameCount lastFrameTime newerVersion putNextDroppedFileOnBoard isDownloading trashcan overlay isPilot darkMode

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
  addLogo this
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
  addTopBarParts this
  addPart morph (morph title)
  addPart morph (morph scripter)
  addLogo this
  addTipBar this
  addZoomButtons this

  fixLayout scripter
  lastStatus = nil // force update
  fixLayout this
}

// trashcan

method showTrashcan MicroBlocksEditor purpose {
  // Hide trashcan icon if purpose is nil.

  hideTrashcan this // just in case, prevent trashcans from stacking
  palette = (blockPalette (scripter this))
  paletteArea = (clientArea (handler (owner (morph palette))))
  trashcan = (newMorph)
  overlay = (newMorph)
  if (purpose == 'hide') {
	  setCostume trashcan (readSVGIcon 'trashcan-hide' nil nil 1.5)
  } (purpose == 'delete') {
	  setCostume trashcan (readSVGIcon 'trashcan-delete' nil nil 1.5)
  } (purpose == 'hideAndDelete') {
	  setCostume trashcan (readSVGIcon 'trashcan-both' nil nil 1.5)
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
  add leftItems (175 * scale)
  add leftItems (addSVGIconButtonOldStyle this 'icon-globe' 'languageMenu' 'Language')
  add leftItems (12 * scale)
  add leftItems (addSVGIconButtonOldStyle this 'icon-gear' 'settingsMenu' 'MicroBlocks')
  add leftItems (12 * scale)
  add leftItems (addSVGIconButtonOldStyle this 'icon-file' 'projectMenu' 'File')

  if (isNil title) {
    // only add title the first time
    title = (newText '' 'Arial' (17 * scale) (microBlocksColor 'blueGray' 50))
    addPart morph (morph title)
  }

  rightItems = (list)

  addFrameRate = (contains (commandLine) '--allowMorphMenu')
  if addFrameRate {
	frameRate = (newText '0 fps' 'Arial' (14 * scale) (microBlocksColor 'blueGray' 50))
	addPart morph (morph frameRate)
	add rightItems frameRate
	add rightItems (18 * scale)
  }

  progressW = (36 * scale)
  progressIndicator = (newImageBox (newBitmap progressW progressW))
  addPart morph (morph progressIndicator)
  add rightItems progressIndicator
  add rightItems (12 * scale)

  add rightItems (addSVGIconButtonOldStyle this 'icon-graph' 'showGraph' 'Graph')
  add rightItems (12 * scale)
  add rightItems (vSeparator this)
  add rightItems (12 * scale)
  add rightItems (addSVGIconButtonOldStyle this 'icon-usb' 'connectToBoard' 'Connect')
  indicator = (last rightItems)
  add rightItems (12 * scale)
  add rightItems (vSeparator this)
  add rightItems (12 * scale)
  add rightItems (addSVGIconButton this 'icon-start' 'startAll' 'Start')
  add rightItems (12 * scale)
  add rightItems (addSVGIconButton this 'icon-stop' 'stopAndSyncScripts' 'Stop')
  add rightItems (7 * scale)
}

method vSeparator MicroBlocksEditor {
  scale = (global 'scale')
  separator = (newBox (newMorph) (microBlocksColor 'blueGray' 700) 0 0 false false)
  setExtent (morph separator) scale ((topBarHeight this) + (4 * scale))
  addPart morph (morph separator)
  return separator
}

method addLogo MicroBlocksEditor {
  logoM = (newMorph)
  setCostume logoM (readSVGIcon 'logo')
  setPosition logoM 8 8
  addPart morph logoM
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

method newZoomButton MicroBlocksEditor iconName action {
  if (isNil action) { // use the selector name as the action
    action = (action iconName this)
  }
  iconScale = (0.5 * (global 'scale'))
  normalColor = (microBlocksColor 'blueGray' 400)
  highlightColor = (microBlocksColor 'yellow')
  button = (newButton '' action)
  bm1 = (readSVGIcon iconName normalColor nil iconScale)
  bm2 = (readSVGIcon iconName highlightColor nil iconScale)
  setCostumes button bm1 bm2
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
  scale = (global 'scale')
  right = ((right morph) - (15 * scale))
  bottom = (((bottom morph) - (height (morph tipBar))) - (20 * scale))
  for button zoomButtons {
    right = (right - ((width (morph button)) + (5 * scale)))
    setLeft (morph button) right
    setTop (morph button) (bottom - (height (morph button)))
  }
}

// tip bar

method addTipBar MicroBlocksEditor {
  tipBar = (initialize (new 'MicroBlocksTipBar') this)
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
  placeTitle this
}

method placeTitle MicroBlocksEditor {
  scale = (global 'scale')
  left = (right (morph (last leftItems)))
  right = (left (morph (first rightItems)))
  titleM = (morph title)
  setLeft titleM (left + (18 * scale))
  setTop titleM (12 * scale)

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
    launch (global 'page') (newCommand 'checkLatestVersion' this) // start version check
    newerVersion = nil
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

method showDownloadProgress MicroBlocksEditor phase downloadProgress {
	isDownloading = (downloadProgress < 1)
	bm = (costumeData (morph progressIndicator))
	drawProgressIndicator this bm phase downloadProgress
	costumeChanged (morph progressIndicator)
	updateDisplay (global 'page') // update the display
}

method drawProgressIndicator MicroBlocksEditor bm phase downloadProgress {
	scale = (global 'scale')
	radius = (13 * scale)
	cx = (half (width bm))
	cy = ((half (height bm)) + scale)
	bgColor = (topBarBlue this)
	if (1 == phase) {
		lightGray = (microBlocksColor 'blueGray' 50)
		darkGray = (microBlocksColor 'blueGray' 100)
	} (2 == phase) {
		lightGray = (microBlocksColor 'blueGray' 100)
		darkGray = (microBlocksColor 'blueGray' 300)
	} (3 == phase) {
		lightGray = (microBlocksColor 'blueGray' 300)
		darkGray = (microBlocksColor 'blueGray' 500)
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

// Connection indicator

method updateIndicator MicroBlocksEditor forcefully {
	if (busy (smallRuntime)) { return } // do nothing during file transfer

	status = (updateConnection (smallRuntime))
	if (and (lastStatus == status) (forcefully != true)) { return } // no change
	isConnected = ('connected' == status)

    iconColor = (microBlocksColor 'blueGray' 500)
    if isConnected { iconColor = (color 0 200 0) }

    offBM = (readSVGIcon 'icon-usb' iconColor (topBarBlue this))
    onBM = (getField indicator 'onCostume')
    setCostumes indicator offBM onBM

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
  versionText = (basicHTTPGet 'microblocks.fun' url)
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
	if (notNil (at prefs 'darkMode')) {
		darkMode = (at prefs 'darkMode')
		darkModeChanged scripter
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

method toggleDarkMode MicroBlocksEditor flag {
	darkMode = flag
	saveToUserPreferences this 'darkMode' darkMode
	darkModeChanged scripter
}

method darkModeEnabled MicroBlocksEditor {
	return (darkMode == true)
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

method topBarBlue MicroBlocksEditor { return (microBlocksColor 'blueGray' 900) }
method topBarHeight MicroBlocksEditor { return (48 * (global 'scale')) }

method drawOn MicroBlocksEditor aContext {
  scale = (global 'scale')
  x = (left morph)
  y = (top morph)
  w = (width morph)
  topBarH = (topBarHeight this)
  fillRect aContext (topBarBlue this) x y w topBarH

  // bottom border
  fillRect aContext (microBlocksColor 'blueGray' 700) x ((y + topBarH) - scale) w scale
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
  placeTitle this
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
		addLine menu
	} else {
		addItem menu 'show implementation blocks' (action 'toggleShowHiddenBlocks' this true) 'show blocks and variables that are internal to libraries (i.e. those whose name begins with underscore)'
		addLine menu
	}
  	if (darkModeEnabled this) {
		addItem menu 'light mode' (action 'toggleDarkMode' this false) 'make the IDE brighter'
	} else {
		addItem menu 'dark mode' (action 'toggleDarkMode' this true) 'make the IDE darker'
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

method addSVGIconButton MicroBlocksEditor iconName selector hint {
  normalColor = (microBlocksColor 'blueGray' 500)
  highlightColor = (microBlocksColor 'yellow')
  button = (newButton '' (action selector this))
  setCostumes button (readSVGIcon iconName normalColor) (readSVGIcon iconName highlightColor)
  if (notNil hint) { setHint button (localized hint) }
  addPart morph (morph button)
  return button
}

method addSVGIconButtonOldStyle MicroBlocksEditor iconName selector hint {
  highlightColor = (microBlocksColor 'yellow')
  bgColor = (topBarBlue this)
  iconScale = (global 'scale')
  button = (newButton '' (action selector this))
  bm1 = (readSVGIcon iconName nil bgColor iconScale false)
  bm2 = (readSVGIcon iconName highlightColor bgColor iconScale false)
  setCostumes button bm1 bm2
  if (notNil hint) { setHint button (localized hint) }
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
iVBORw0KGgoAAAANSUhEUgAAAEYAAABGCAYAAABxLuKEAAAACXBIWXMAAAhrAAAIawEzo0SOAAAA
GXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAACytJREFUeJzdnF1sFNcVx393bVjb
WWPH608w4DjGGwgGqlRWaE0CWJAYMLSENMVJWqXkJUGgKJWiPPoxSh9oIoFUtWkRD04KhBQRPgoh
FFkogB0pEH+tU0rABn/gBbwLu9jYe/owXuP17szO7tpeyF+yrJ05c+fMf+6Ze8/HvYopgogoYCHw
c6AUcAAlgA3IHPkPcAe4PfL/v4ATaAcagSallEyFvmoyGxeRTGATsBpYDuTE2eQN4D/Av4HPlVK3
42xv6iAiSkTWiMheEfHJ5MEnIv8cudekvuC4ICIWEakWkW8nkQw9NInI70QkOdE8BEFEqkTEmQBC
xqNNRF5MNB+IyEwR2ZNgMsLhkIjMTRQpvxaRWwkmwAj9IvLKVBJiFZGPEvzQ0WCPiKRG+5xRfc2v
X78+x+fznSkqKiq0WCzR3iuROAusU0q5zF5gmpiOjo6ymzdvnvP5fKnp6ek4HA6SkpJi0jJBaAZe
VEp1mhE2RUxnZ+eSGzdunB8YGJgWODZjxgwcDgePWM/5H7BMKXU9kmBEYjo7OwtdLle7z+cLsdNH
tOc0Ac8ppW4ZCRm+bhFJGRgYOBuOFACPx0N7ezt+vz8OPaccC4F/iYjVSCiSHewoKiqalZGRoSvg
drtpa2tjeHg4Bh0ThueAPxkJ6JqSiLwM7AXw+/20t7fT39+v29AjalY1SqlPw50IS4yIzAG+B2YE
jv1EyekHFoYbqfRM6c+MIQXAYrFQWlqKkVl5PB6cTuejZFYZwI5wJ0J6jIi8ABzTa+kn2nPWKqWO
jD0QRIyIJAEtaBE2XfwEyWlDM6nRrj7elF4hAikwsWYlIni9XlwuFy6XC6/Xi8iURC/H4im0SOMo
RnuMaFGwC0CZ2dai7Tm9vb04nU6uXr1Kd3c3XV1deDwe3esKCgrIz89n7ty5OBwOcnLijYwaohlY
pJTyQzAxa4DD0bZmhhyfz8eJEyfo6+uLQd8HyMrKYtGiRZSXl1NcXIxSEx7RrFJKHYNgYvYCL8fS
mhlyuru7OX78OENDQ0HHCwoKyM7OZsYMbRB0u9309fXR1dVleE+73c6yZctYtmwZNpvNUDYKfKaU
2gwjxIhIBtAFRB23CMDv99Pc3IzX69WVCZCTmZlJZWUlixcvxm63h5V1uVxcuHCBkydPGva0adOm
sXTpUqqqqsjKyopV/QDuAQVKqdsBYt4E/hprax6Ph0OHDnH27FlWrFjBzJkzdWWHh4d55plnsFoN
XZVRDA0Ncfr0aQ4ePMjAwICuXHJyMhUVFVRXV8fbg/6glPpHgJh9jPsqm4GIcO7cOfbt28edO3cA
SEpKYtWqVYbkxDKUX7t2jV27dkX8TqWlpbFu3TpWrlwZ6zfoM6XUZjUyGvUQZTKsp6eHuro62tra
Qs5NFjlut5sPPvgAlytyIK6kpIRXX33VUAcd9AL5SkQWoQ3TpuD3+zl8+DBHjx41nKOYISctLY3e
3l5aW1tHH9ZutzN//nzKy8tJT08Puaazs5MPP/zQ0KzG6lBVVcXatWujDaiVKRF5A/i7GWmPx8Mn
n3xCa2urqdaTkpJ47bXXDHuF3miVkpLChg0bWLlyZcg1X331Ffv27TOlA0BpaSlbtmwhMzPT7CW/
T6qtrf0tUBFJ0ul0smPHDq5du2ZaIbvdTk1NDT6fT/cN22w28vLyuHz5clDAa2hoiObmZjweD2Vl
wXPOOXPmcP78ecMRcCxcLhfnzp1j1qxZ5ObmmrmkNam2tnYr2pRYF8eOHWP37t2muu9YVFdXU1JS
QlZWFnfv3o2aHIArV65gs9l44oknRo8FzKK5udm0LoODg5w/f55p06ZRUlISSbzXAhTrnfX7/dTV
1fHFF19E7b8opVi8eDHwwLcyGkbz8/NZvXo1ycmh6eeDBw+OjnoBLFmyJCp9QBtFDxw4wJ49eyL5
cE9a0GISIRgcHGTnzp2cPn06agVAe9CxkzeLxUJ3dzfXr+sH6PXI8fl8NDQ0BB2z2+3k5+fHpNuZ
M2fYtWsXg4ODeiIZFiDk0x8gpampKaYbA2FntC0tLZw4cSImclpaWkzdwyyampr4+OOP9cw73cKD
SibgASnh5ifRINwIcPPmTYaHh2MiJ9zcJYpRJix++OEHPXLSJy1bFu6bFJiJxkLOJHjShu1a0Grd
RjF9+nS2bt3KU08ZDlQREc7THuvkRUtOOAfRyJs3g3nz5rFt27ZwfpvHAoREigLkLFy4MOabhuv6
8+fPD/odDTkLFiwIORdPfKesrIzt27frObMeC1oKIQQBcpYvXx7Tjbu6ukLIKS8vJyUlJeiYWXKy
s7ODhti+vj66u7tj0q2iooK3336b6dOn64n0W9AS3WFhsVjYvHkzL730Ukw2fuFCsAuWnp7O+vXr
Q+TMkOP1eoNiyN99913U+lgsFjZt2sTrr78eyXe6ZEGrozXE6tWreffddw2D3+Fw8uTJEB+osrKS
559/PkTWDDmBAPvAwABff/11VLqkp6ezbds2Vq1aZUbcmVRbWzsb2BBJ0m638+yzz9LR0WHatr1e
LzabjeLi4Ml1WVkZNpuNS5cuBREnIly+fJnc3NywnjVo04nOzk4aGxtNFxOUlpbyzjvvMHv2bFPy
wN+UiJQBF81e4ff7OXLkCEePHg3pDeFgtVp57733KCwsDDl3584dGhoaaGlpGSU7OzubBQsWkJub
G+IGjIWeVz4WycnJVFVVsWbNmmjDDgsDgapuwJTbGUBvby91dXWmQhB2u533339/NOBtBvEE2EEb
imtqamIPVEHsGYJAaHP//v26+aEAHn/8cd566y3mzjVfZRoLOWlpaWzcuJGKiopYJ4WfKqVqAsRs
Af4WSyugmcSXX35JfX29Yde2Wq2sX7+e5cuXh/Wiw2FwcJDGxsaIwa5Tp06xdOlS1q1bx2OPPRb1
M4zBG0qp3ROWPgG4desWR44c4ZtvvuH+/fu6cna7ncrKSpYsWaLrCPb19Y2mT27fvh0xTJqamsrT
Tz8db648OH0C8SXcxuPu3bvU19dTX18fcQTLy8sjJyeHjIwMRAS3282NGzfo6ekJkpusAPs4BCfc
IPYUrRECw29DQwMXL16MO0Wbl5dHZWVlyOx5LOIkJ2yKNuqkfrTo6+vD6XRy5cqV0aS+2+0OK5uR
kUFBQQF5eXkUFRXhcDiw2+2TWYJyAfhZYKHY+PqYzUBdNK1NBLxeL/fu3QO07EBaWpqh/CSR84pS
am/gR7jCoWa0ZXkPNSaYnFa0wqHRqXTQdHCkomh7HPpOGSa4JvCPY0mBMMWJSqnjwOexKDvVmCBy
9iqljo4/qFfOOhutnDU6dzpBiMOsbqOZUEgWMaxnpZTqAN6MU98pQ4w9R4At4UgBg5J5pdR+YGcc
+k4pYiDnI6XUAT1ZQy9rZCHCcbTa+0cCfr8fp9OpOz8CyMnJuVpcXDxPKaWbcTMMUiilBoBqIPo4
YoJgsVhwOBy6PSc1NfVeamrqc0akQOTVJyil3MBaDGLDDxsCZjU+/mO1Wu9nZWWVz5w580rENszc
aGRF2C95hHtOSkrKvaysrKWzZ8/+3sz1UUVyRNur4SCP2Dfnxx9/7LBarb8oLCw0tR4yJsiD5cX+
yVoPPMH4i4joJpAmg6BficjNBD+0EfpF5DdTRsg4ch7mLQzmJISUcQS9ICKtCSZDRKRFRExl1KYM
8mCblMYEEHJRtG1SHt7FUaJtrPOiiHwmIt5JJMMrIp+O3GvCi2cmeyumDGAj2lZMK4C8OJvsAU6h
bcV0YGTyOSmYsi2MRt7qArTNuxxoK+meRFuUGm7zrn602bZz5O9bpZT5+tU48X90nMccQUXLVwAA
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
