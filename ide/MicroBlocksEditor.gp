// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksEditor.gp - Top-level window for the MicroBlocks IDE
// John Maloney, January, 2018

to isMicroBlocks { return true }

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

defineClass MicroBlocksEditor morph fileName scripter leftItems title rightItems tipBar zoomButtons indicator nextIndicatorUpdateMSecs progressIndicator lastStatus httpServer lastProjectFolder lastScriptPicFolder boardLibAutoLoadDisabled autoDecompile showHiddenBlocks frameRate frameCount lastFrameTime newerVersion putNextDroppedFileOnBoard isDownloading isPilot darkMode

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
  setExtent (morph separator) scale (topBarHeight this)
  addPart morph (morph separator)
  return separator
}

method addLogo MicroBlocksEditor {
  logoM = (newMorph)
  setCostume logoM (readSVGIcon 'logo')
  setPosition logoM 8 4
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
  iconScale = (1.33 * (global 'scale'))
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
    right = (right - ((width (morph button)) + (10 * scale)))
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

  centerY = (24 * scale)
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

// gear menu

method gearMenu MicroBlocksEditor {
  menu = (menu 'MicroBlocks' this)
  setIsTopMenu menu true
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
    graphM = (morph graph)
    setPosition graphM (half ((width (morph page)) - (width graphM))) (50 * (global 'scale'))
    restoreSettings graph
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
  setIsTopMenu menu true
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
  popUpAtHand (gearMenu this) (global 'page')
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
  setIsTopMenu menu true
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
