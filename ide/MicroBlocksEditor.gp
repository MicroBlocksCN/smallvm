// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

//Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

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

defineClass MicroBlocksEditor morph fileName project scripter leftItems rightItems indicator lastStatus title

method project MicroBlocksEditor { return project }
method scripter MicroBlocksEditor { return scripter }
method stage MicroBlocksEditor { return (global 'Page') }

to openMicroBlocksEditor devMode {
  if (isNil devMode) { devMode = false }
  if (isNil (global 'alanMode')) { setGlobal 'alanMode' false }
  if (isNil (global 'vectorTrails')) { setGlobal 'vectorTrails' false }
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
  // seems to block the main thread even when launched, and crashes when it can't reach the server
  // launch (global 'page') (checkLatestVersion)
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
  setFPS morph 10
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
  add leftItems (addLanguageButton this)
  add leftItems (5 * scale)
  add leftItems (textButton this 'About' 'rightClicked')
  add leftItems (textButton this 'New' 'newProject')
  add leftItems (textButton this 'Open' 'openProjectMenu')
  add leftItems (textButton this 'Save' 'saveProject')
  add leftItems (textButton this 'Library' 'importLibrary')
  add leftItems (textButton this 'Connect' 'connectToBoard')
  add leftItems (5 * scale)
  add leftItems (makeIndicator this)

  rightItems = (list)
  add rightItems (textButton this 'Stop' 'stopAndSyncScripts')
  add rightItems (textButton this 'Start' 'startAll')
}

method textButton MicroBlocksEditor label selectorOrAction {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (pushButton label (color 130 130 130) selectorOrAction)
  addPart morph (morph result)
  return result
}

method makeIndicator MicroBlocksEditor {
  scale = (global 'scale')
  indicator = (newBox (newMorph) (gray 100) 40 2)
  setExtent (morph indicator) (15 * scale) (15 * scale)
  redraw indicator
  addPart morph (morph indicator)
  return indicator
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
  pickFileToOpen (action 'openProjectFromFile' this) (gpExamplesFolder) (array '.gpp' '.gpe')
}

method openProjectFromFile MicroBlocksEditor location {
  // Open a project with the give file path or URL.

  if (beginsWith location '//') {
	data = (readEmbeddedFile (substring location 3) true)
  } else {
	data = (readFile location true)
  }
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

// board control buttons

method connectToBoard MicroBlocksEditor { selectPort (smallRuntime) }
method stopAndSyncScripts MicroBlocksEditor { stopAndSyncScripts (smallRuntime) }
method startAll MicroBlocksEditor { sendStartAll (smallRuntime) }

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
	processBrowserDroppedFile this
  }
  processDroppedFiles this
  updateIndicator this
  processMessages (smallRuntime)
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
  popUpAtHand (contextMenu this) (global 'page')
  return true
}

method contextMenu MicroBlocksEditor {
  menu = (menu nil this)
  addItem menu 'about...' (action 'showAboutBox' (smallRuntime))
  addItem menu 'virtual machine version' (action 'getVersion' (smallRuntime))
  addLine menu
  addItem menu 'install MicroBlocks on board' 'installVM'
  addItem menu 'clear memory and variables' 'softReset'
  if (not (devMode)) {
	addLine menu
	addItem menu 'show advanced blocks' 'showAdvancedBlocks'
  } else {
	addItem menu 'export functions as library' 'exportAsLibrary'
	addLine menu
	addItem menu 'hide advanced blocks' 'hideAdvancedBlocks'
  }

// testing:
//   addLine menu
//   addItem menu 'broadcast test' (action 'broadcastTest' (smallRuntime))
//   addItem menu 'set variable test' (action 'setVarTest' (smallRuntime))
//   addItem menu 'get code test' (action 'getCodeTest' (smallRuntime))
//   addItem menu 'get var names test' (action 'getAllVarNames' (smallRuntime))
  return menu
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

method installVM MicroBlocksEditor {
  installVM (smallRuntime)
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
  popUpAtHand menu (global 'page')
}

method setLanguage MicroBlocksEditor newLang {
  setLanguage (authoringSpecs) newLang
  updateBlocks scripter
  saveScripts scripter
  restoreScripts scripter
}

method addLanguageButton MicroBlocksEditor {
  button = (newButton '' (action 'languageMenu' this))
  setCostumes button (languageButtonIcon this) (languageButtonOverIcon this)
  addPart morph (morph button)
  return button
}

method languageButtonIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABEAAAARCAYAAAA7bUf6AAACLUlEQVR4nK2Sy0vqYRCG/bPMC5qX3Cgu
RFy5SFzqpo2LtiKICwmRIGzhRndiChIJEkoQppKKYqEhtFDxXt5T3pg56DnRsbM5Ay+/T/nmmXfmG4Fg
T6RSKVxfXyMSiSAYDOLs7Az77n6LTCaDdDoNgmw2G6zXa5bH48Hp6SnsdvvPsNvbW04kkYvpdIrJZIK3
tzc4nU7U63XUajWYTKa/g25ubnaARCKB+XyO5XKJxWLB5/f3d9hsNlSrVZTLZRwdHX0FRaPRHWA2myEU
CvGXkkl0JjfHx8doNpt4fHxEPB6HUqn8DQqHw9w3WSd5vV6uTMnUEmk0GsFgMDDs6ekJVPjw8PAX5Pz8
HBcXFyy/3w+32w2HwwGLxQKj0Qi9Xg+dTseiFlQqFTsggFwuh0wmg8DlcuHj44NtU7XhcAir1cpfcrPV
YDCAWq1Gp9Ph4WazWX56iUQCwcnJCVarFVuni/1+n6dP5z8hvV6PXby+vqJUKoFWIRAIQCQSQWA2mxlC
s+h2uyytVssQ6p80Ho/ZgUKhQKPRwMPDA5LJJLcvFAoh0Gg03CtZ3aftHGgGUqmUq1PyVjxcukCVX15e
WPSbbLfbbbRaLT7THAhwf3+Pq6srXoMdgIJs0mVapEqlwhXpGWlDn5+f+T8a5MHBAQN8Ph/rC4SCnopc
FAoF5HI5rlosFpHP57k6JfwI2MbW7t3dHfdN6x+LxTiZkv4J2IZYLGbbdPHy8nKnb4P83/EJ/9B4j8wl
crwAAAAASUVORK5CYII='
  return (scaledIcon this data)
}

method languageButtonOverIcon MicroBlocksEditor {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABEAAAARCAYAAAA7bUf6AAACBElEQVR4nK1SSWtiYRB8fzjuRg8SUDwI
0ZM5CIK3SAgoiqjgwZNGQgzBBdzQJC5RAtFo3LcK1cNzyGTiXKaheN/36K6urq8V5Yd4eHjA3d0dMpkM
UqkUwuEwfsr9FqVSCcViESTZ7/fY7XaC6+trBAIBXFxcHCcrFApSSFDFcrnEYrHAbDbD5eUler0e2u02
nE7n34ny+fyB4Pb2FqvVCpvNBuv1Ws7z+RxerxfPz894fHyExWL5SpTNZg8E7J5Op+XLYoJnqjk/P8dg
MECz2UQul4PZbP5NxCLOTelEKBSSzixWMZ1OYbfbhazT6YCNTSbTL5JYLIZ4PC6IRqO4urqC3++H2+2G
w+HA2dkZbDabgCOcnp6KAhIYjUYYDAYowWAQ2+1WZLPbx8cHPB6PfKlGBe8kGY1GYm61WpWn1+l0UHw+
nxhIyUycTCbi/p8k4/FYVLy+vqLVaoGrkEgkoNVqobhcLiGhF+/v7wJKJwnnV0EFHOHl5QW1Wg339/cy
/snJCRSr1Soyj0H1gR7o9XrpzmIVYi4T2Lnf7wt4p+zhcIi3tzc50wcSVCoV3NzcyBocCBiUyWQu0tPT
k3TkM3JDu92u/KORGo1GCCKRiOALCYNPRRWNRgP1el26cql4ZncWHCVQQ5VbLpdlbq4/N5PFLPongRos
pmwmJpPJA74Z+b/jE3cbtWGJekUkAAAAAElFTkSuQmCC'
  return (scaledIcon this data)
}

method scaledIcon MicroBlocksEditor data {
  scale = (global 'scale')
  bm = (readFrom (new 'PNGReader') (base64Decode data))
  if (1 != scale) { bm = (scaleAndRotate bm scale) }
  return bm
}
