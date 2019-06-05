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
  } else {
	fileName = (join '../gp/runtime/lib/' fileName)
  }
  return (load fileName (topLevelModule))
}

defineClass MicroBlocksEditor morph fileName scripter leftItems rightItems indicator lastStatus thingServer

method project MicroBlocksEditor { return (project scripter) }
method scripter MicroBlocksEditor { return scripter }
method thingServer MicroBlocksEditor { return thingServer }

to openMicroBlocksEditor devMode {
  if (isNil devMode) { devMode = false }
  if (isNil (global 'alanMode')) { setGlobal 'alanMode' false }
  if (and ('Browser' == (platform)) (browserIsMobile)) {
	page = (newPage 1024 640)
  } else {
	page = (newPage 1120 700)
  }
  setDevMode page devMode
  setGlobal 'page' page
  tryRetina = true
  open page tryRetina 'MicroBlocks'
  editor = (initialize (new 'MicroBlocksEditor') (emptyProject))
  addPart page editor
  if (notNil (global 'initialProject')) {
	dataAndURL = (global 'initialProject')
  	openProject editor (first dataAndURL) (last dataAndURL)
  }
  launch (global 'page') (checkLatestVersion)
  pageResized editor
  developerModeChanged editor
  startSteppingSafely page
}

to checkLatestVersion {
  latestVersion = (getLatestVersion)
  currentVersion = (splitWith (ideVersion (smallRuntime)) '.')
  for i (count latestVersion) {
    if (> (at latestVersion i) (at currentVersion i)) {
      inform (global 'page') (join
          'A new MicroBlocks version has been released (' (joinStrings latestVersion '.') ').' (newline)
          (newline)
          'Get it now at http://microblocks.fun')
    }
  }
}

to getLatestVersion {
  // Fails at the VM level if there is no network connection
  html = (httpGet 'microblocks.fun' '/download.html')
  if (isNil html) { return (array 0 0 0) }
  from = (findSubstring 'version: <strong>' html 1)
  if (isNil from) { return (array 0 0 0) }
  return (splitWith (substring html (+ from (count 'version: <strong>')) (- (findSubstring '</strong>' html from) 1)) '.')
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
  thingServer = (newMicroBlocksThingServer)
  addTopBarParts this
  scripter = (initialize (new 'MicroBlocksScripter') this)
  addPart morph (morph scripter)
  drawTopBar this
  clearProject this
  fixLayout this
  setFPS morph 200
  return this
}

// top bar parts

method addTopBarParts MicroBlocksEditor {
  scale = (global 'scale')

  leftItems = (list)
  add leftItems (addLogoButton this)
  add leftItems (5 * scale)
  add leftItems (addLanguageButton this)
  add leftItems (addSettingsButton this)
  add leftItems (addProjectButton this)

  rightItems = (list)
  add rightItems (addConnectButton this)
  add rightItems (4 * scale)
  add rightItems (makeIndicator this)
  add rightItems (50 * scale)
  add rightItems (addStopButton this)
  add rightItems (addStartButton this)
  add rightItems (12 * scale)
}

method textButton MicroBlocksEditor label selector {
  label = (localized label)
  scale = (global 'scale')
  setFont 'Arial Bold' (16 * scale)
  if ('Linux' == (platform)) {
	setFont 'Liberation Sans Bold' (13 * scale)
  }
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

method makeIndicator MicroBlocksEditor {
  scale = (global 'scale')
  indicator = (newBox (newMorph) (gray 100) 40 2)
  setExtent (morph indicator) (15 * scale) (15 * scale)
  redraw indicator
  addPart morph (morph indicator)
  lastStatus = nil // clear cache
  return indicator
}

// project operations

method newProject MicroBlocksEditor {
  ok = (confirm (global 'page') nil 'Discard current project?')
  if (not ok) { return }
  clearProject this
  fileName = ''
  updateTitle this
}

method clearProject MicroBlocksEditor {
  // Remove old project morphs and classes and reset global state.

  page = (global 'page')
  stopAll page
  for p (copy (parts (morph page))) {
	// remove explorers, table views -- everything but the MicroBlocksEditor
	if (p != morph) { removePart (morph page) p }
  }
  fileName = ''
  createEmptyProject scripter
  clearBoardIfConnected (smallRuntime) true
  if (isRunning thingServer) {
      clearVars thingServer
  }
}

method openProjectMenu MicroBlocksEditor {
  pickFileToOpen (action 'openProjectFromFile' this) (gpExamplesFolder) (array '.gpp' '.ubp')
}

method openProjectFromFile MicroBlocksEditor location {
  // Open a project with the give file path or URL.
  ok = (confirm (global 'page') nil 'Discard current project?')

  if (not ok) { return }

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

method openProject MicroBlocksEditor projectData projectName {
  clearProject this
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
	loadNewProjectFromData scripter projectData
  }
  developerModeChanged scripter
  stopAndSyncScripts (smallRuntime)
}

method saveProjectToFile MicroBlocksEditor {
  saveProject this nil
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

  result = (safelyRun (action 'saveProject' scripter fileName nil))
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

// board control buttons

method connectToBoard MicroBlocksEditor { selectPort (smallRuntime) }
method stopAndSyncScripts MicroBlocksEditor { stopAndSyncScripts (smallRuntime) }
method startAll MicroBlocksEditor { sendStartAll (smallRuntime) }

// project title

method updateTitle MicroBlocksEditor {
  projName = (withoutExtension (filePart fileName))
  setWindowTitle projName
}

// stepping

method step MicroBlocksEditor {
  if ('Browser' == (platform)) {
	checkForBrowserResize this
	processBrowserDroppedFile this
  }
  processDroppedFiles this
  updateIndicator this
  processMessages (smallRuntime)
  if (isRunning thingServer) {
      step thingServer
  }
}

method updateIndicator MicroBlocksEditor {
	status = (connectionStatus (smallRuntime))
	if (lastStatus == status) { return } // no change
	if ('connected' == status) {
		setColor indicator (color 0 200 0) // green
	} ('board not responding' == status) {
		setColor indicator (color 250 200 0) // orange
	} else {
		setColor indicator (color 200) // red
	}
	lastStatus = status
	redraw indicator
}

// browser support

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

method processBrowserDroppedFile MicroBlocksEditor {
  pair = (browserGetDroppedFile)
  if (isNil pair) { return }
  fName = (callWith 'string' (first pair))
  data = (last pair)
  processDroppedFile this fName data
}

method processDroppedFiles MicroBlocksEditor {
  for evt (droppedFiles (global 'page')) {
	fName = (at evt 'file')
	data = (readFile fName true)
	if (notNil data) {
	  processDroppedFile this fName data
	}
  }
}

method processDroppedFile MicroBlocksEditor fName data {
  if (endsWith fName '.gpp') {
	ok = (confirm (global 'page') nil 'Discard current project?')
	if (not ok) { return }
	while (notNil pair) { pair = (browserGetDroppedFile) } // clear dropped files
	openProject this data fName
  }
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

method topBarBlue MicroBlocksEditor { return (colorHSV 180 0.045 1.0) }
method topBarBlueHighlight MicroBlocksEditor { return (colorHSV 180 0.17 1.0) }
method topBarHeight MicroBlocksEditor { return (45 * (global 'scale')) }

method drawTopBar MicroBlocksEditor {
  scale = (global 'scale')
  w = (width (morph (global 'page')))
  h = (topBarHeight this)
  oldC = (costume morph)
  if (or (isNil oldC) (w != (width oldC)) (h != (height oldC))) {
	setCostume morph (newBitmap w h (gray 200))
  }
  bm = (costumeData morph)
  fill bm (topBarBlue this)
  grassHeight = (4 * scale)
  fillRect bm (color 137 169 31) 0 ((height bm) - grassHeight) (width bm) grassHeight
  costumeChanged morph
}

method fixLayout MicroBlocksEditor fromScripter {
  fixTopBarLayout this
  if (true != fromScripter) { fixScripterLayout this }
}

method fixTopBarLayout MicroBlocksEditor {
  scale = (global 'scale')
  space = 0
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
}

method fixScripterLayout MicroBlocksEditor {
  scale = (global 'scale')
  if (isNil scripter) { return } // happens during initialization
  m = (morph scripter)
  setPosition m 0 (topBarHeight this)
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
  popUpAtHand (contextMenu this) (global 'page')
  return true
}

method contextMenu MicroBlocksEditor {
  menu = (menu nil this)
  addItem menu 'about...' (action 'showAboutBox' (smallRuntime))
  addLine menu
  addItem menu 'virtual machine version' (action 'getVersion' (smallRuntime))
  addItem menu 'install MicroBlocks on board' 'installVM'
  addLine menu
  addItem menu 'graph data' 'graphData'
//  addItem menu 'show recent data' 'showRecentData' // commented out until it shows data in real-time
  addItem menu 'copy data to clipboard' 'copyDataToClipboard'
  addItem menu 'clear data' 'clearData'
  addLine menu
  addItem menu 'clear memory and variables' 'softReset'
  addLine menu

// xxx testing
// addItem menu 'dump persistent memory' (action 'sendMsg' (smallRuntime) 'systemResetMsg' 1 nil)
// addItem menu 'compact persistent memory' (action 'sendMsg' (smallRuntime) 'systemResetMsg' 2 nil)
// addLine menu

  if (not (isRunning thingServer)) {
      addItem menu 'start Mozilla WebThing server' 'startThingServer'
  } else {
      addItem menu 'stop Mozilla WebThing server' 'stopThingServer'
  }
  if (not (devMode)) {
	addLine menu
	addItem menu 'show advanced blocks' 'showAdvancedBlocks'
  } else {
	addItem menu 'export functions as library' 'exportAsLibrary'
	addLine menu
	addItem menu 'hide advanced blocks' 'hideAdvancedBlocks'
  }
  return menu
}

method graphData MicroBlocksEditor {
  openMicroBlockDataGraph
}

method showRecentData MicroBlocksEditor {
  data = (loggedData (smallRuntime) 100) // get the most recent 100 entries
  ws = (openWorkspace (global 'page') (joinStrings data (newline)))
  setTitle ws 'Recent Data'
  setFont ws 'Arial' (16 * (global 'scale'))
}

method copyDataToClipboard MicroBlocksEditor {
  data = (loggedData (smallRuntime))
  setClipboard (joinStrings data (newline))
}

method clearData MicroBlocksEditor {
  clearLoggedData (smallRuntime)
}

method showAdvancedBlocks MicroBlocksEditor {
  setDevMode (global 'page') true
  developerModeChanged this
}

method hideAdvancedBlocks MicroBlocksEditor {
  setDevMode (global 'page') false
  developerModeChanged this
}

method importLibrary MicroBlocksEditor {
  importLibrary scripter
}

method exportAsLibrary MicroBlocksEditor {
  exportAsLibrary scripter fileName
}

method softReset MicroBlocksEditor {
  softReset (smallRuntime)
}

method startThingServer MicroBlocksEditor {
  if (start thingServer) {
      inform 'MicroBlocks HTTP Server listening on port 6473'
  } else {
      inform (join 'Failed to start Mozilla WebThings server.' (newline)
                'Please make sure that no other service is running at port 6473.')
  }
}

method stopThingServer MicroBlocksEditor {
  stop thingServer
}

method installVM MicroBlocksEditor {
  installVM (smallRuntime)
}

// Logo Button

method addLogoButton MicroBlocksEditor {
  scale = (global 'scale')
  logo = (logoAndText this)
  bm1 = (newBitmap ((width logo) + (4 * scale)) (41 * scale) (topBarBlue this))
  drawBitmap bm1 logo (1 * scale) (1 * scale)
  bm2 = (newBitmap (width bm1) (height bm1) (topBarBlueHighlight this))
  drawBitmap bm2 logo (1 * scale) (1 * scale)
  button = (newButton '' (action 'rightClicked' this))
  setCostumes button bm1 bm2
  addPart morph (morph button)
  return button
}

// Language Button

method languageMenu MicroBlocksEditor {
  menu = (menu 'Language:' this)
  addItem menu 'English' (action 'setLanguage' this 'English')
  if ('Browser' == (platform)) {
	for fn (listFiles 'translations') {
	  fn = (withoutExtension fn)
	  language = (withoutExtension fn)
	  addItem menu language (action 'setLanguage' this language)
	}
  } else {
	for fn (listEmbeddedFiles) {
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

method setLanguage MicroBlocksEditor newLang {
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
  destroy (morph indicator)
  for item (join leftItems rightItems) {
	if (not (isNumber item)) { destroy (morph item) }
  }
  addTopBarParts this
  updateIndicator this
  fixLayout this
}

method addLanguageButton MicroBlocksEditor {
  return (addIconButton this (languageButtonIcon this) 'languageMenu')
}

// Iconic menus

method settingsMenu MicroBlocksEditor {
  popUpAtHand (contextMenu this) (global 'page')
}

method addIconButton MicroBlocksEditor icon selector {
  scale = (global 'scale')
  bm1 = (newBitmap (41 * scale) (41 * scale) (topBarBlue this))
  drawBitmap bm1 icon (10 * scale) (11 * scale)
  bm2 = (newBitmap (41 * scale) (41 * scale) (topBarBlueHighlight this))
  drawBitmap bm2 icon (10 * scale) (11 * scale)
  button = (newButton '' (action selector this))
  setCostumes button bm1 bm2
  addPart morph (morph button)
  return button
}

method addSettingsButton MicroBlocksEditor {
  return (addIconButton this (settingsButtonIcon this) 'settingsMenu')
}

method projectMenu MicroBlocksEditor {
  menu = (menu 'Project' this)
  addItem menu 'New' 'newProject'
  addItem menu 'Open' 'openProjectMenu'
  addItem menu 'Save' 'saveProjectToFile'
  popUpAtHand menu (global 'page')
}

method addProjectButton MicroBlocksEditor {
  return (addIconButton this (projectButtonIcon this) 'projectMenu')
}

method addConnectButton MicroBlocksEditor {
  return (addIconButton this (connectButtonIcon this) 'connectToBoard')
}

method addStopButton MicroBlocksEditor {
  return (addIconButton this (stopButtonIcon this) 'stopAndSyncScripts')
}

method addStartButton MicroBlocksEditor {
  return (addIconButton this (startButtonIcon this) 'startAll')
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
  drawString bm 'microBlocks' textColor left top
  setFont 'Futura Medium Italic' (8 * scale)
  top += (20 * scale)
  drawString bm 'Small, Fast, Human Friendly' textColor left top
}

method connectButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABkAAAAWCAYAAAA1vze2AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAFRgAABUYBwbT6GgAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAKZSURBVEiJrZPBaxNREMa/2U2wCzmIUFCraS499NLWLELD7koOgSIqVGitCKVSWkpBlOJND4LQgyDVmyYbQfAPsHioIiJb26SXLrQgFMRDzKHtMTVoTLLZ8WC3bNc0yRq/25tv3vvNvHmP8B80NTU1KAiCDqCLiO4lk8nnbl9sFzAzMzNCRIsAugBIAC7JspwzTXPTyaF2ANPT03eIaAGA4LGqAC6nUqn3/wRRVfU2EX3v7e2NA5ggIgwPD6NcLmNpacmdWmTmC7qub7QMGR0dFXd3d58y8y0AdjgcFkKhEMbHxxGNRpFKpbC1teXdtg0g1hIkFoudEAThIxH1OzEiQnd3NwYGBlAsFrGzs1N3LzMbTQcfj8cHAWwS0Rmvt7e3h1KphHK5fBDr6+uDJEkoFApOMce9AzskVVUnLcvK4M+rqVcl8vk8KpUKACCRSGB2dhaRSMSd8+TI61IUZYGI5hoV4UgQBPT09GBsbAy5XA7r6+sAUCOi+8lk8lFdiKqq7wAMtQJwJEkSIpEIiAgAfjDzDV3X3wB1PqOmaTcB3PUDAADLsmDbNkKh0LZt20PpdNpwvEOdyLIclCQpD+CkX4gjURQfLi8vP3DHDg2+o6NDbgcAgC3L+uUNBtwLIupsA2ABmMxkMq+aQb4xs+/TiagmiuJFwzA+1PO9/6STmW2fjAozJ44CAJ5OmPkaETX8oB4VAoHAecMwvjZKOoAoinIagOID8KVUKp0zTfNns0QCAE3Tosy8COCs22Rmu05nNSJ6u7KycqXVagKapl1n5pcAju3HPtu2PS+K4qlqtfopGAyOAOjfL2ijVqu9WFtba3g9f0GY+ZkL8JqZJ7LZbNGVY/o58CjIIhFdBfB4dXV1HoD/N9xEvwHaIuvRgNAXcQAAAABJRU5ErkJggg=='
  dataRetina = '
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'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method startButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAWCAYAAADAQbwGAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAJegAACXoBD0XXIwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAFWSURBVDiNrdM9axRRFMbx3x0GjaQ2pDCFRcxK2pAitpYi+QIpjQoWFoJYKbFML7EIhHwDYyobi7yInca4d0FBhC3WWKUJa0KYFJuVQTa7M84+3XnO4X+fw72XhgfqPoru+2FERSWYE8xiRdtP0ZMq4ERmPFePYVnbN9Gi99LywOBqD/8aXhv3ScPdsgmv9OlPy7wRbYvmigG5VGDuFnZEb30xMQh4ucjJ57ojFUUvfO0dpGjCvEbxXGJP3e1hALuaErzTsO67sWEAIcgsOLGvbr5jRKfn4GFoaVigrrIUx1T+wweCe2o2EvypkghrEtNqNiDFyX/CPks8MmU7byY6K5fRoeCxlpl/Yd2EZVbelHpoUvOige6l9FewJfPUTR8GjaY46tPfxzM1mwMPzQF/9/CbeKlmVXBaFNYBBr9kf+sWlo145bp2GVA+4S5uYFVq3WSld+kMPTFR1LOrihUAAAAASUVORK5CYII='
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACcAAAAsCAYAAADmZKH2AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAS9QAAEvUBKRJxDwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAALKSURBVFiFzdjNa1xVGIDx3z25UZoS8asqiuhC0klSBP+GFupCcOXSL4SgKFmEirgQdddSSqkipRRKLHbjSmihEQtudOdCJc2dmCAo+BXRQG0j6jjHxWTayaQx83Hv3DxwN+ec951n3veeM/dOAjKfY1jiHM6o+MMOILFkj5qVlrErmBUdNuGnssQgqNvbNnYbpiWWZU5Y9EAZYhBE920xN4Jpdd/KnLLsnkGK0ajcdh96C6b8Y1nVYVWjgxCDILGnw7WjotdEVVUv+sJwoWYabb23y5j7RSftNq/qqUKs1gmCO3uMHRN9KDPnsslcrdYJopE+cxwUfK3qbN6bJkj6lmvkiZ5Wsygzk9f9mEflbhDdjmN2m5c52G+6QI5yNxjDnMx5Cx7qNUlRck2ekFiQecuSW7sNDthVgFQrI3hTzZcu299NYKD7b9QjFcElmfdl7uokICAtWKqdZ7AkM7XdwoCh4n02cQdOyVyUeXirRWH9KovHMa9qWpS0TyYya4rfFJ1wSeJZFT82B8pq6804IPpK1ZPNgbLb2s7doo9kToiGEpk6m/tdOtEHO6lqGwliwL9le7QRcdxez6eol23Twq94wbjzNH4ddkrlPpF4rvUoSVErUQiu4nUV70nE1omUjQMDJbqIl0z47mbTZbV1RfSqCWf/b9Gg2xoxq+6QSb9vtzjFX8U7gQWJV1R82mlAwFqBQtbzv63usW7EaFTuz2KcwAV1L5v0fS/BqWIq9w2mjfu4nyRBkqvcqmjGNfv6FYNUzEWuhjOGveGRDf+S9kUqsdbnMTxnyIwxWU5O10nxW4+xizhk3IUcfTYQxK7b8AOm/GxfkWI02rrSYVtXRUeMeseDhR4/10k7qNyaxLv+dsSjVgch1SQV/LLF4+Y1idM42vqMNUhS9U277IrESdFRlZ43Sy403royn2m8v55TN2vS1TKlmvwHLHW8gYqPdl8AAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method stopButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAJegAACXoBD0XXIwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAC4SURBVDiN7dWxTQNBEIbRNyvcAaIC4xwsQepWHJgargRqIKITHBIh5z4KgHMHZ90SeE1Awkm3GXwFvGCCf0KpZRk0mRUujasLtgOP17xBwDvrzBMuRkI/O2Iz5zlalnidgJ3rM/cpaCpgMAuaaOmMv9lvfUbLoNyyQjlVxCBSRQz8g38FzBW9nHCoCHYp2FYEX2LPbZzmazYR6wfuUlnaB/RTMGwW7L6HYc9N2cYVrkZCH8oLWLCDL/THKtPrS3KwAAAAAElFTkSuQmCC'
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAATEwAAExMBRp68eQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAGUSURBVFiF7dmxTlNRAMfh75zIC0iUkQqFQV3UOLqYCO5ofRafQF9Eogk4o4myuLIZGTDFhkWN8AKFU4fbam3aqrnQc4f7jfee4Zc0tzf532CCA25ENnqsYxELuDTp/H86xTd8CbxNbK3wadzBMHrhkMYZz/Bk3P0L0sPLyNMlOhMD29xLbOPKjML+0OMk0lrm3eDar8DP3McO5nLEDelivcku/cBDGqfsBS5nTfvtOHJniU6EM55XKA7mU/EcCAdcD3w0uwfiX6XEzYiW6sVBjDyKgQe5S6ZYi2jkrpiiEXE1d8UUC9H5vb4uwlzMXfA3dWBZdWBZdWBZdWBZdWBZdWBZdWBZdWBZUTHkVFU3KlamqvoajaxJFdOJgTe5K6bYiYktpNwlY6TE69hfNl/lrhkV2FxlP0CbxcQe5jN3DfzA7SZHEfqz62PFeJhbF60mRwz9UTfZDcXK+j1XGY7xcLCuMvImWeZD4G6PTcWwPSupxwvcavJ++MbEXbA/bG5gDdec72eIruKXais+Q2yvsj/u4E/K7lQMQkQ6GQAAAABJRU5ErkJggg=='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method projectButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABAAAAAWCAYAAADJqhx8AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAH6QAAB+kBlHo8QAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEbSURBVDiN7ZSxaoNAAIb/hGsqlRZBChWbQicnB3c79AXyEKV5Axdx9w2cut3iEzi2QnFyL9TD1qWTgoNBQ0jQDoXSpOYS2jXf+v//Bwd3NwAH3/fHs9ksopRebURLABEh5I5sG3ued2EYxkuWZac98RGA29Vq9TDsG1uWdS1J0pumaX3jn9z8EjiOMy7LklVVdbJjDADHawLXdc/zPE8ZY1uPtsl30bZtOU3TD8bYCAAEQdhfQCkV67p+J4SMVFWFKIqYTCYAgPl8zheEYSjIsvyq6/pZXyGKIr6gKIpYUZTLJEnWgqZpEAQB4jjmCgamaXbcxg5678FBcBD8RbD4x34xBMB/LXyeh4SQ+67rnvD1Ue7LEsBj27bTTyA4XCa7dVryAAAAAElFTkSuQmCC'
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACEAAAAsCAYAAADretGxAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAP0gAAD9IB+4k7yQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAIrSURBVFiF7di9i9oAGAbwJ7lrC6IHVuxdS40UgoJIXKQZjNCl0L+lmxQRyXCCkK2HSwYHb3IWHPQ6lvqBXHEpiF81LUlPQTBwyE1K0inQw35EE7FDnjHJ++bH+yYQQsBiisWiy+fzfS4UChGTJUsAHQAXzWbzAwCQVgCiKLpZlv0ajUbNAgDAA+A1gCuO43KWEKIouhOJxDgWiz3dtQeAc47j3hzvUlkqlTzxeHzEMMyZBYCRd1tPIpvN+rxe7zebAADwcqtJpFKpx6qq3iyXy0c2AQDgxPQkBEHw393dTXu9np0AAICpSQiC4Jck6cdgMHhoNwAw8Xbkcrlnk8nkZl+AfyJ4ng8oivJ9OBw+2BcA+Ms6eJ4PzGYzaTQabVxDEMT+EZlMhppOp5PxePzb8xRF2YrYWEc+n38xn8//CGBZFslk8t4xTdMsIe7dqFKpPHG5XF8YhtkAkCSJQCAAhmE21rFYLOxBVKvV00gkMqRp2r1tk06nYx1Rq9XOQqHQkKbpk20bSJKEer1uCUGWy+Xn4XB4tAug3+8jnU5jtVpZQhyv1+uWLMseWZZNFei6DlVV0e120W63LT+UAEBwHKdb7mIxlr6s7IqDMOIgjDgIIw7CiIMw4iCMOAgjDsKIgzDy3yCWBzbckgCuD4y4JnVdvzikgCCI90eKoowpiiIAvDoA4LzRaFweAYAsyx+DwWAHwCkAPwDbf479kluCID5pmva21WpdAsBPdzu15+Xij+EAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method settingsButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAHOgAABzoBqsXEHQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAJ1SURBVDiNpZU/aBRREMZ/c7tXbBoVooFAWiNaXmO4XYwhCfgnEMXTRuxTxiSIvZWK2qW2sAoSUUlhUA/yHmqRNqCtYDwUtErA8/JZ5E7ebVYv4lftzJv53puZt98z9oE0TR8C19rmhnPuRK+cUq+AWq0WAVOB63i1Wh3ulReHRrVaHS6VSvckLTrnngM0Go0qcCiXdwZ4D5Cm6Xkzm9nZ2bnuvX/fCbDOR5qmR4HXwGDb5SV9NbOzQDlkNbOWpKeSDpjZWNvdMLOxtbW1ja4Tm9l9SYNBftXMKIKkCLiQWx8A7gDnIOixpMVCln9AyNG1ZZqmr4HRgpzPkt4BmNnJ9unycM65rGN03QpJ33LBLUkLcRwPee+nvffT29vbQ2Z2A2jlYr+GhgGMjo4ebDabk2b2iKDvkha893cLTkeWZQuSbgeupqSr5XL5Rb1e/25pmq4Cp4EoX34cx0P1ev1nEXGlUiknSfKRvW1pAa9KwHgBKcDbP5ECrK+vN4E3BUsRMNHzz/sbJBXfR3aHt8reQQCMVCqVcoEf2G2FmY0ULLWA1ZJzbjKO435JV4Cw9IG+vr7ZPxEnSTIHHAlcTeByHMf9zrnJrlKyLFuWNB3ubmY3t7a2HrR72hnaHHCL7tksO+cudowuEZKUF5tI0u0kSeazLHvbjhkBDhcU0R8aoQidB54V1r1/THVU8fetMLOZ/yTt4ghFaBb4FMR54ImkHwUcLUmPgZeBrwEs7CF2zn2QNGZmK+yWlDrnLkRRNJFnlTTvvb/knBsHpsxsRdKpjhZDTt2KUKvVos3NzS8Er4ikY+FrUYSef97S0lKL7qFu9CIF+AVCxv2ly3PtJwAAAABJRU5ErkJggg=='
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAOegAADnoBz63/KAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAU+SURBVFiFxZldiFRlGMf/z3tmRmiZAdOirHYEvSlv9KIVnPfAZNvqFOESCJJkGBhZGlokZBkUUUhgWWYFlSREgQUV1ZrZNrLvCHpRXbTd5IJOCRukwoyrzOzM++9ix9idOefMObOj/i/P8/U7H+/HeV5Bl5TNZhfWarVfAMxtMlmSLxYKhde7UUd1IwkATE5OPoJWWABQIvI0AOlGna4BA+gPsN2SyWTu6kaRrgAPDAz0iMjyIB8RCbqh0Iq1sYvrus9Za0upVOrA0NBQxcvp8uXLWQBz2uTqB7DXy5DL5eZcvHjxMQDJkZGRNwDQL0nQExat9T6Su0XkvXK5/KfWeoNXDmvtw21gAWDl4sWLW25Ka/1guVweJbmf5G6t9YdBXH4DQbTW+wA82WwgOayU2l6v18eVUlsBbADQGwIYAP4h+QHJd0VkrlJqD8n7Pfw+NsZsAmDDAPvCToO2ImLR/pPy06SIKJJOgI8ndEuA67o7AOwMqiYigtkNWCdE/LJ0Oj1RLBaPT7/YEmStLc0CpKuy1pabr7UAp1KpAwDGrglRsMYaLDPU8kmcOnWqnk6nzwBYd02wfERy4/Dw8B/N132XS631YQCrriqVv34yxnguNL6jXCm13Vr7O8IPrgmShwHklVJ/A4C19nYAWRFZDaAnTBKS1nGc7X52X+BKpXI+Ho/bEMB1AHur1eprJ0+ePOdh39fX1zcvHo+/0NgEBU1lEBFLcjwycDwe3xJkb6hEcl2hUBgKcmrcyDOZTOZHEfkcQCrAPQZgK4CXvIx+T08wtYIFyQJY3w52ugqFwpC1di2m3kqQHvVj+3/QZbPZWL1eX06yH8AggKVtku4xxjwbFna6XNd9k+S2Nm6/AfhKRI46jnMin8/XAEAymUxOKfUEySyCX9V0TVSr1bTPN9tW2Wx2fq1WO42QAxFASUTy1tr3RWtdAZCIWPMLY8zaiDEzpLX+EsBDEcOqCtFhQfJY1JhmiUi+g7BERxuYK/PsbGStPdtR7U6CSM76h1Ip1VGOToFv6ySuGzkUgGoHcdlOijXpng5iKorkoIh8AyD0PlhEVvf19c3roCCAqWkNwH0RQkoNxsFYY6Uairhw9CQSiZ0AOlo4arXaLrSZg0XkV5Jftywcfv5a69MI/rm0ANYYY76NAuu67iqS3yFgEyQixZGRkYXw+N33G3QUkU/a1FYAPs1kMrkIsA+QPBQECwAkD8CnN+E7taxYseJmx3HOkmy3Y6uLyDuVSuVVv6W6sRTvAvBUCNjJeDy+IJ/P/+tl94VxHGc+yTDTnkNyWyKR2KS1/gHAMQB/NWx3AMjWarVVAG4IkQsAHGvtrQCiAZPcg2jzdA+m9gZR9wczJCKqXq+/BeBeL7snkOu6g7h+/3MQkZWu667xtDVfyOVyc8rl8iiARVedLFhjyWRySXMDsuUJN7qI1xsWABaVSqWNzRe9PonkNYAJJaVUC0vLFFMsFo/39vbeBOBuv0SNZmAdnffXJqfac4HxHxljdqJpPvYKoDFmC4D9PrDDjuMsFZEFJF8BcCYC6DiAl2Ox2AJr7RIR+T4A9nGEbLf+b2tqu44BeN4Yc6jJT7mue5Dk+jawExcuXLhxdHR0xu5Qa90P4G0Ad7aDBYJfCY0xW0RkB8nNyWRyiQcsGok/awMLAD83wwKAMeZoMplcRnKziOzwa2RfUVeOogYGBnouXbp0DsHnHNuMMZ5nHFHUlVOkI0eOTJA8EeRD8mg3anXznC4IaLxQKLS0TjtR14BJHgRw3sNkMXXc5XuUFUX/AfHiFId5ScXEAAAAAElFTkSuQmCC'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method languageButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6
JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAACXBIWXMAAA7EAAAOxAGVKw4bAAABWWlU
WHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIg
eDp4bXB0az0iWE1QIENvcmUgNS40LjAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cu
dzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJk
ZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp0aWZmPSJodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYv
MS4wLyI+CiAgICAgICAgIDx0aWZmOk9yaWVudGF0aW9uPjE8L3RpZmY6T3JpZW50YXRpb24+CiAgICAg
IDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgpMwidZAAACPUlEQVQ4
Ea2Vy0tVURSHTxkZBhEF2Yt0FFLDppXSa6ADJwXODGoS6J/RIKNpNbyzIAty0iSoJtGDtEgCIaSwhxYU
FFiR9vi+fdfKgzRo4A++u9Zea691zz5773urakmrcFfHsBU7DKMwDd/ge/jGzDlHWWNtUUtYg7+D09gb
sBGOwjN4Ci9gAQ7DOjgLn2ECVPZY6k6wAV9gP3TDS1DnYaR4VfUaa+4gzEMDUuVJc5mXiD7KDPYBnInx
Rawol/uweM2PcYy1KntVJxm4ZJfTCQMwB73QAdcD/T54D87phCNg7SCU5fpyp8L/hPX9bIE1MAN+6zZQ
s/ALdsEifAA3axPYtAuqIbivgzY0TXUFey58zeUgQ+aco7LGHkN+ez+4JOW3qR3wvHjNj58YSZnbHoOs
sUe/DbfCWCR/hG3D1htalIVOMbdeB2WNPdrdZt/bzbAtWDkBd+EN+GSeR3ULzO+EHvCQ59P7Hnt9whXX
JB13L+v6mPG+WuwCvqTMOacue0z6hJ43N0atbZpyA/aEr/EoScrcfAyyxh5zNvRlHo9kFr1lvDdiGs+k
pMw5R2WNPcbclFaYApt/BCcsP9h5RN6R+9fB3hzxLmyR18aTfgw6YAC8Xn0x9oyJOWP1q2eNtYNQlDvt
BX8SMc098BYpfxhEDYO51ARO5kovl51q4HyFQ3AAXoEaCfRnwJ+uHnBjGpD626t0jugp7CzcBm/HHbgK
o+H7I2vO9+ncVL1Hidk9g26US7sG0/DffwF/ANFxiWdTpHhNAAAAAElFTkSuQmCC'
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6
JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAACXBIWXMAAA7EAAAOxAGVKw4bAAABWWlU
WHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIg
eDp4bXB0az0iWE1QIENvcmUgNS40LjAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cu
dzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJk
ZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp0aWZmPSJodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYv
MS4wLyI+CiAgICAgICAgIDx0aWZmOk9yaWVudGF0aW9uPjE8L3RpZmY6T3JpZW50YXRpb24+CiAgICAg
IDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgpMwidZAAAG40lEQVRY
Cc2W2auWVRTGv7KOmc1qTmigIGJRqDlkmSe7sLKrboLA/yCILuoioigHIglM+w8KCswoGiCKrAwpQ6NB
SsOwxKlUyjG16fd7v/2cs8/XOccj3fTA8661115r7fXu6X0vaA0NF+J2AfyzuHch58KFcBacDMfB8VDs
gwfhT3Ab3AS3wDNQDIN/w79s/FdcXCWYhr4C7oQOcD40xlhzBHXu2IYsnTUpxsI10BlIUd+h/1raB5CP
w6PwGFwOD0N9te0oum1zmMucoh6nbRnC0yUI7kexgBS2Ht3lXVVs9k2BDnQSnij6DGSKfA59DjQ2eYwz
d1CPGVu/snZci0cSvos+r0TcVNnnF9skpMVJddENE+9eFbfA92HsjhHUY8fWR9YOG+hJkof6eLVan5S+
pyv7tegpUD1YjWIeY2o8QiP5HSuoa4itkS5R8CqKwYdgNxQXtUXrbqR9P8Iri00xBqZA9WA0yn5ojLEi
RSxBzz6ui6xraQJ8xJhl/Q3bzaX3UuTwor+CdLCnSntkkROQKVBdpO8ZdGNe1gjMNaLRWq0FyOPQ/ix3
aikurVaOu5tWR0/izJ7eXuUaVIvwJI7tNTfaJTwdSKrXsOA/oH3m6MQcDCkyB6epyWWz2rPQAZ+H4vW2
aN2FtM8lcUbvhc7m13A6vAHa9zt0WbN0S9F/gRbq5S6/hfo/DN+Cbg/tFuKl/gZ8AFrDh1BbM5NJug6D
s3cumvRcPgP1DzXWWsQwP1/C2307tOJPoYmEA+mj9EVmQ2fFz9dRmJfzk+W+cqnE5/A0zF4y3xVwFnS2
t0JtGR+10fX32rLP2d4JG6zkaRHr281+n+OwOqinrr99dDV295FU74Qxv0H3r7kGgjVYizU16OK5A2pc
0lh6D43NXC+L0fVxhgNnILPY3z1oXz1LxprDXCK51ZtDgbQGfaypyyl1WVziXfAjKJziTkwphu+LNHao
iG9ik6uOz5jWYC3WNMfABVB8AN0fvnV/v0GTsIvdzbN3b/q2A8E+mVncXRyTqzQb4ZjWYw3WIhZocOOL
LJ0Fag+TfLxOwOMv4qcU+gfRO30Sm1zmzjjKLHlqma1hasn6VZFu4hqZzXzW9pXO+KX/FPbMprrwDhXx
3d9u9nwi01/MPX6pZaoFTiy9btLL4WUw+8Eu39IBR9kAXtSXQE+lXwff3H7zZLaTcwQ2X8BxjkBjhbm8
duzPS6E2q+ItkAMz0YS+nQb/5QbDcDpdMveIL5BiUJtBLNTChT4W1uljvD7Gn4aDwZc5a9L/PdxTTvMC
6BK7gb3TwrHoLsd7UL9l0FmI3zh09+cMeKJQXZt95tHXGGPNYS5zmjvjxM8arEW/fe6NvdAEZ+GxQsS/
cLhYTiJdwmz42tGkwpx+NWQNY4W5jhba7oS1iL0u8a5GbbVuLLILqT3Mhs1gzoqIX/rd8O45qS7sM4++
IrHJlf6MFb/UssuOrU1o+yOt6gZ2g4eZlcyYyyLipxT6B9E7fRKbXObOOEpvBTG/LVpbLXBzadyBzAnT
3ok9xXBd1ZEZq0x91M7+xCZX7eyYFmkN1iI2a/TXaCecChdD4XXQiR+KYVqRmblOv/7a8U1sctW+GdMa
rMWarK3BSp5Od/6k29a+T5fHw+Hv1tV9u5rWVTwH+90yxr1nDk/sQLAGa7GmnovUN/sGeqo/gzlFOrpM
St9wFvQAfAEdLG/t0niRD/bD6rUzE56C26CzmtxK4aGZB92LPT+sGeQFjBZyLpr4XD4D9Q81dh1jiOaX
P5vTJfwSKl+Dq+Bo6Nv4Es7YPfAJuB0+CLVLl20MfAmKZfBnmENnYU7A9XA5fBu6Jcztqh2Cj8H74EF4
U5HW1sCpFfdD394Bb4Od8AfhBHQLjOvotJjjheo1/BBYjLHm6MStGBzTsa1BpKZ2i2eqdXp1PAUXQeG+
y6DOkv0roBjZFq0JSAuQ6iJ9roYxL2oE5jKncCL8wtifpU0tmHpRGzdgNuAoXFpcXEpxJ7RvHxwFgzEo
KVA9cJt4MRuzuBiTawltbwX7HDOoa4mtkQm0kSINdn/U2EhD+7OV0asjBdbXyOria0yNR2mYQ9bF1TXU
/j167ZDlNsnHsLt4TUcmeWyTsKVAddEN4+e1IW6HG2HsazUW1GPH1q+sHd20B2ASvoPeDbOvDqP7e3Uh
PAktUt2C7DNuDVwE3yxtbebMgUDtuVPVhwQHkWIsdJDTMIXuRvfqse018SR0zx6Dy+ERaJ8n+8ei2zaH
ucwp6nHalvN81sd9GrEr4Q7oYOdDYzz55gjq3LH1kfnE9DH20/At9fXCFV1wLlwIZ8PJ0BkZD4Wn1iXc
A7fCTXALPAOFW8iX8xM5KP4BNcUd9fZ57KEAAAAASUVORK5CYII='
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
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method logoAndText MicroBlocksEditor {
  dataRetina = '
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'
  data = '
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
gg=='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}
