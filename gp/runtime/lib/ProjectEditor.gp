defineClass ProjectEditor morph fileName project imagesFolder soundsFolder stage scripter library viewer viewerWidth tabs leftItems rightItems rightItemsRow2 stealthSlider title connectorToggle fpsReadout lastFrameTime frameCount

method project ProjectEditor { return project }
method stage ProjectEditor { return stage }
method library ProjectEditor { return library }
method scripter ProjectEditor { return scripter }

to recover baseFilename {
  // Save any projects in memory (usually only one) to files.
  if (isNil baseFilename) { baseFilename = 'recovered' }
  baseFilename = (withoutExtension (filePart baseFilename))
  gc // dispose of unreachable projects
  for editor (allInstances 'ProjectEditor') {
	fileName = (uniqueNameNotIn (listFiles (gpFolder)) baseFilename 'gpp')
	saveProject (project editor) (join (gpFolder) '/' fileName)
  }
}

to startProjectEditorFromMorphic {
  // Start the project editor from the morphic background menu.
  page = (global 'page')
  if (not (confirm (global 'page') nil 'Enter project editor (current morphs will be lost)?')) {
  	return
  }
  removeAllParts (morph page)
  editor = (initialize (new 'ProjectEditor') (emptyProject))
  addPart page editor
  pageResized editor
  developerModeChanged editor
}

to o tryRetina devMode { openProjectEditor tryRetina devMode } // shortcut, because Jens needs it so often :-)

to openProjectEditor tryRetina devMode presentFlag {
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
  editor = (initialize (new 'ProjectEditor') (emptyProject))
  addPart page editor
  if (notNil (global 'initialProject')) {
	dataAndURL = (global 'initialProject')
  	openProject editor (first dataAndURL) (last dataAndURL)
  }
  pageResized editor
  developerModeChanged editor
  if presentFlag {
	enterPresentation editor
  }
  startSteppingSafely page presentFlag
}

to findProjectEditor {
  page = (global 'page')
  if (notNil page) {
	for p (parts (morph page)) {
	  if (isClass (handler p) 'ProjectEditor') { return (handler p) }
	}
  }
  return nil
}

method initialize ProjectEditor aProject {
  scale = (global 'scale')
  morph = (newMorph this)
  project = aProject
  viewerWidth = ((width (global 'page')) - (800 * scale))
  viewerWidth = (max viewerWidth (235 * scale))
  addTopBarParts this
  scripter = (initialize (new 'Scripter') this)
  addPart morph (morph scripter)
  stage = (newStage 16 10)
  addPart morph (morph stage)
  library = (initialize (new 'SpriteLibrary') scripter)
  addPart morph (morph library)
  setStageMorph scripter (morph stage)
  tabs = (tabBar (list 'Scripts' 'Images' 'Sounds' 'Notes') nil (action 'showTab' this) (transparent) 12)
  setBGColors tabs (gray 240) (gray 150) (gray 100) // match tab colors to Scripter border and class pane colors
  addPart morph (morph tabs)

  select tabs 'Scripts'
  drawTopBar this
  clearProject this
  createInitialClass scripter
  fixLayout this
  return this
}

// top bar parts

method addTopBarParts ProjectEditor {
  scale = (global 'scale')
  page = (global 'page')
  space = (15 * scale)

  title = (newText '' 'Arial Bold' (14 * scale))
  addPart morph (morph title)

  connectorLabel = (newText 'Show arrows:' 'Arial' (11 * scale))
  connectorToggle = (toggleButton
	(action 'toggleConnectors' page) (action 'isShowingConnectors' page)
	(scale * 20) (scale * 13) (scale * 5) (max 1 (scale / 2)) false)
  addPart morph (morph connectorLabel)
  addPart morph (morph connectorToggle)

  stealthSlider = (slider 'horizontal' (* scale 50) (action 'setBlocksStealthLevel' this) nil -50 110 (global 'stealthLevel'))
  addPart morph (morph stealthSlider)

  leftItems = (list)
  add leftItems (textButton this 'New' 'newProject')
  add leftItems (textButton this 'Open' 'openProjectMenu')
  add leftItems (textButton this 'Save' 'saveProject')
  if (not (isOneOf (platform) 'Browser' 'iOS')) {
	add leftItems (textButton this 'Export as App' 'exportProjectAsApp')
	if (canExportToWeb this) {
	  add leftItems (textButton this 'Export to Web' 'exportProjectToWeb')
	}
  }

  rightItems = (list)
  add rightItems (textButton this 'Present' 'enterPresentation')
  add rightItems space
  add rightItems (textButton this 'Go' (action 'broadcastGo' page))
  add rightItems (textButton this 'Stop' (action 'stopAll' page))

  rightItemsRow2 = (list)
  add rightItemsRow2 connectorLabel
  add rightItemsRow2 connectorToggle
  add rightItemsRow2 space
  add rightItemsRow2 (clickLabel this 'Blocks' 'slideToBlocks')
  add rightItemsRow2 stealthSlider
  add rightItemsRow2 (clickLabel this 'Text' 'slideToText')
  add rightItemsRow2 space
  add rightItemsRow2 (addFPSReadout this)
}

method textButton ProjectEditor label selectorOrAction {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (pushButton label (color 130 130 130) selectorOrAction)
  addPart morph (morph result)
  return result
}

method clickLabel ProjectEditor label selectorOrAction {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (newText label 'Arial' (11 * (global 'scale')))
  tr = (new 'Trigger' (morph result) selectorOrAction)
  setHandler (morph tr) tr
  addPart morph (morph result)
  return result
}

// project operations

method newProject ProjectEditor {
  ok = (confirm (global 'page') nil 'Discard current project?')
  if (not ok) { return }
  select tabs 'Scripts'
  clearProject this
  createInitialClass scripter
}

method clearProject ProjectEditor {
  // Remove old project morphs and classes and reset global state.

  page = (global 'page')
  stopAll page
  setTargetObj scripter nil
  removeAllParts (morph stage)
  for p (copy (parts (morph page))) {
	// remove explorers, table views -- everything but the ProjectEditor
	if (p != morph) { removePart (morph page) p }
  }
  clearLibrary library

  fileName = ''
  setText title ''
  project = (emptyProject)
  developerModeChanged scripter // clear extensions

  // reset global state (pen trails, stage color, connector state)
  deletePenTrails (morph stage)
  setColor (handler (morph stage)) (gray 240)
  if (true == (global 'alanMode')) { setColor (handler (morph stage)) (gray 255) }
  setIsShowingConnectors page (not ('Browser' == (platform))) // show arrows
  refresh connectorToggle
}

method openProjectMenu ProjectEditor {
  examplesPath = (join (absolutePath '.') '/Examples')
  pickFileToOpen (action 'openProjectFromFile' this) examplesPath (array '.gpp' '.gpe')
}

method openProjectFromFile ProjectEditor location {
  // Open a project with the give file path or URL.

  data = (readData (new 'Project') location)
  if (isNil data) {
	error (join 'Could not read: ' location)
  }
  openProject this data location
}

method openProject ProjectEditor projectData projectName {
  clearProject this
  project = (readProject (emptyProject) projectData)
  fileName = projectName
  updateTitle this
  loadPage stage (first (pages project))
  if ((notes project) != '') {
    select tabs 'Notes'
  } else {
	refreshTab this
  }
  developerModeChanged scripter
}

method selectClassAndInstance ProjectEditor aTargetClass {
  // Select an arbitrary instance of a user class to show in the scriptor.
  // if aTargetClass is specified, select an arbitrary instance of it
  if (isNil scripter) { return }
  for m (parts (morph stage)) {
    cl = (classOf (handler m))
    if (or (cl == aTargetClass) (isNil aTargetClass)) {
      if (notNil (scripts cl)) {
        setTargetObj scripter (handler m)
        return
      }
    }
  }
  setTargetObj scripter nil
}

method saveProject ProjectEditor fName {
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
  if (isClass viewer 'MediaViewer') { saveNotes viewer }
  currentPage = (first (pages project))
  thumbnail = (takeThumbnail (morph stage) 400 400)

  unloadPage stage currentPage
  result = (safelyRun (action 'saveProject' project fileName thumbnail))
  loadPage stage currentPage
  if (isClass result 'Task') { // saveProject encountered an error
	addPart (global 'page') (new 'Debugger' result) // open debugger on the task
	return false
  }
  return true
}

method isAbsolutePath ProjectEditor fName {
  // Return true if this string is an absolute file path.
  letters = (letters fName)
  count = (count letters)
  if (and (count >= 1) ('/' == (first letters))) { return true } // Mac, Linux
  if (and (count >= 3) (':' == (at letters 2)) (isOneOf (at letters 3) '/' '\')) {
  	return true // Win
  }
  return false
}

method exportProjectAsApp ProjectEditor {
  extensions = nil
  if ('Mac' == (platform)) { extensions = (array '.app') }
  fName = (fileToWrite (withoutExtension (filePart fileName)) extensions)
  if ('' == fName) { return }

  if (isClass viewer 'MediaViewer') { saveNotes viewer }

  currentPage = (first (pages project))
  unloadPage stage currentPage
  exportApp (new 'AppMaker') project fName
  loadPage stage currentPage
}

method canExportToWeb ProjectEditor {
  conf = (gpServerConfiguration)
  if (isNil conf) { return false }
  user = (at conf 'username')
  serverDirectory = (at conf 'serverDirectory')
  return (and (notNil user) (notNil serverDirectory))
}

method exportProjectToWeb ProjectEditor {
  // Save this project to the web repository via DAV.

  conf = (gpServerConfiguration)
  if (isNil conf) { return }

  user = (at conf 'username')
  serverDirectory = (at conf 'serverDirectory')
  url = (join serverDirectory user '/' (withoutExtension (filePart fileName)))

  fName = (prompt (global 'page') 'Web app name:' (filePart fileName))
  if ('' == fName) { return }
  fName = (join serverDirectory user '/' fName)
  ok = (saveProject this fName)
  if (not ok) { return }

  if (beginsWith fName 'http://') {
	fName = (substring fName 8)
  }
  playURL = (join 'http://gpblocks.org/run/go.html#' fName)
  msg = (join
	(cr) playURL (cr) (cr)
	'Copy URL to clipboard?')
  if (confirm (global 'page') nil msg) {
	setClipboard playURL
  }
}

// project title

method updateTitle ProjectEditor {
  setText title (withoutExtension (filePart fileName))
  redraw title
  centerTitle this
}

method centerTitle ProjectEditor {
  m = (morph title)
  setLeft m (((width morph) - (width m)) / 2)
}

// tabs

method refreshTab ProjectEditor {
  // Update the contents of the current tab.
  select tabs (selection tabs)
}

method showTab ProjectEditor newTab {
  if (notNil viewer) {
	if (isClass viewer 'MediaViewer') { saveNotes viewer }
	removePart morph (morph viewer)
	viewer = nil
  }
  newTab = (selection tabs)
  if ('Scripts' == newTab) {
	newViewer = scripter
	restoreScripts scripter
  } ('Images' == newTab) {
	newViewer = (newMediaViewer project newTab)
  } ('Sounds' == newTab) {
	newViewer = (newMediaViewer project newTab)
  } ('Notes' == newTab) {
	newViewer = (newMediaViewer project newTab)
  }
  if (notNil newViewer) {
	viewer = newViewer
	setWidth (bounds (morph viewer)) viewerWidth
	redraw viewer
	addPart morph (morph viewer)
	addPart morph (morph tabs) // ensure tabs are in front
	fixLayout this
  }
}

// presentation mode

method enterPresentation ProjectEditor {
	page = (global 'page')
	if (notNil (focus (keyboard page))) {
	  cancel (focus (keyboard page))
	  focusOn (keyboard page) nil
	}
	setColor page (gray 0)
	addPart page (morph stage)
	hide morph
	hide (morph scripter) // disable arrows to the scripter
	pageResized stage
}

method exitPresentation ProjectEditor {
	page = (global 'page')
	setColor page (gray 250)
	addPart morph (morph stage)
	goBackBy (morph stage) 100
	show (morph scripter) // enable arrows to the scripter
	show morph
	pageResized this
}

// browser support

method processImportedFiles ProjectEditor {
	pair = (browserGetDroppedFile)
	if (isNil pair) { return }
	fName = (callWith 'string' (first pair))
	data = (last pair)
	processDroppedFile this fName data
}

method processDroppedFiles ProjectEditor {
	for evt (droppedFiles (global 'page')) {
	  fName = (at evt 'file')
	  data = (readFile fName true)
	  if (notNil data) {
		processDroppedFile this fName data
	  }
	}
}

method processDroppedFile ProjectEditor fName data {
	if (endsWith fName '.wav') {
	  addSoundToProject this data fName
	  showTab this 'Sounds'
	} (endsWith fName '.gpp') {
	  ok = (confirm (global 'page') nil 'Discard current project?')
	  if (not ok) { return }
	  while (notNil pair) { pair = (browserGetDroppedFile) } // clear dropped files
	  openProject this data fName
	} (endsWith fName '.mp3') {
	  inform (global 'page') 'Imported sound files must be WAV format.'
	} (endsWith fName '.gp') {
	  eval (toString data) nil (topLevelModule)
	  developerModeChanged scripter  // update block categories (after loading extension)
	} (endsWith fName '.gpe') {
		extension = (readProject (new 'Project') data)
		extensionName = (withoutExtension (filePart fName))
		importExtension project extensionName extension
		developerModeChanged this // update palette
	} else {
	  addImageToProject this data fName
	  showTab this 'Sounds'
	}
}

method checkForBrowserResize ProjectEditor {
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

// media management

method importMediaFile ProjectEditor type {
  if ('Browser' == (platform)) {
	browserFileImport
  } else {
	if ('image' == type) {
	  if (isNil imagesFolder) { imagesFolder = (gpFolder) }
	  pickFileToOpen (action 'importImageNamed' this) imagesFolder (array '.png' '.jpg' '.jpeg')
	} ('sound' == type) {
	  if (isNil soundsFolder) { soundsFolder = (gpFolder) }
	  pickFileToOpen (action 'importSoundNamed' this) soundsFolder '.wav'
	}
  }
}

method importImageNamed ProjectEditor fName {
  data = (readFile fName true)
  if (isNil data) { error 'Could not read file' fName }
  addImageToProject this data fName
}

method addImageToProject ProjectEditor data fName {
  // Save an image with the given image data and file name.

  if (isNil data) { return }
  if (isNil fName) { fName = 'Unnamed' }
  imagesFolder = (directoryPart fName)
  if (isPNG data) {
	bm = (readFrom (new 'PNGReader') data)
  } (isJPEG data) {
	bm = (jpegDecode data)
  } else {
	error 'Unrecognized image format'
  }
  desiredSize = 500
  if (or ((width bm) > desiredSize) ((height bm) > desiredSize)) {
	if (confirm (global 'page') nil 'Reduce image size?') {
	  bm = (cropTransparent (thumbnail bm desiredSize desiredSize))
	}
  }
  baseName = (withoutExtension (filePart fName))
  setName bm (uniqueNameNotIn (imageNames project) baseName)
  add (images project) bm
  refreshTab this
}

method saveEditedImage ProjectEditor bm {
  // Save an image from the paint editor.

  imageName = (name bm)
  if (isEmpty imageName){
	imageName = (uniqueNameNotIn (imageNames project) 'image')
	setName bm imageName
  }
  images = (images project)
  oldIndex = nil
  for i (count images) {
	if ((name (at images i)) == imageName) { oldIndex = i }
  }
  if (notNil oldIndex) { // replace existing image
	atPut images oldIndex bm
  } else {
	add (images project) bm
  }
  refreshTab this
}

method importSoundNamed ProjectEditor fName {
  data = (readFile fName true)
  if (isNil data) { error 'Could not read file' fName }
  addSoundToProject this data fName
}

method addSoundToProject ProjectEditor data fName {
  // Import an image with the given file name.

  if (isNil data) { return }
  if (isNil fName) { fName = 'Unnamed' }
  soundsFolder = (directoryPart fName)
  snd = (decodeWAV data)
  if (isNil snd) { error 'Could not read WAV file' fName }
  snd = (shrinkSound snd)
  baseName = (withoutExtension (filePart fName))
  setName snd (uniqueNameNotIn (soundNames project) baseName)
  add (sounds project) snd
  refreshTab this
}

// blocks stealth level

method setBlocksStealthLevel ProjectEditor level {
  level = (max (min level 100) -50)
  setGlobal 'stealthLevel' level
  if (level < -19) {
	setBlocksMode 'normal'
  } (level < 0) {
	setBlocksMode 'flat'
  } (level > 99) {
	setBlocksMode 'stealth'
  } else {
	setBlocksMode 'stealth'
  }
  if (and (notNil scripter) ('Scripts' == (selection tabs))) { restoreScripts scripter }
}

method animateStealth ProjectEditor level {
  setBlocksStealthLevel this level
  setValue stealthSlider level
}

method slideToText ProjectEditor {
  time = 5000
  already = ((+ 50 (global 'stealthLevel')) / 150.0)
  addSchedule (global 'page') (newAnimation (global 'stealthLevel') 120 (time - (toInteger (* already time))) (action 'animateStealth' this) nil false)
}

method slideToBlocks ProjectEditor {
  time = 5000
  already = ((+ 50 (global 'stealthLevel')) / 150.0)
  addSchedule (global 'page') (newAnimation (global 'stealthLevel') -50 (toInteger (* already time)) (action 'animateStealth' this) nil false)
}

// FPS readout

method addFPSReadout ProjectEditor {
  fpsReadout = (newText '00.0 fps' 'Arial' (10 * (global 'scale')))
  setColor fpsReadout (gray 50)
  addPart morph (morph fpsReadout)
  lastFrameTime = (msecsSinceStart)
  frameCount = 0
  return fpsReadout
}

method step ProjectEditor {
  if ('Browser' == (platform)) {
  	processImportedFiles this
  	checkForBrowserResize this
  }
  processDroppedFiles this
  if (isNil fpsReadout) { return }
  frameCount += 1
  msecs = ((msecsSinceStart) - lastFrameTime)
  if (and (frameCount > 2) (msecs > 200)) {
	fps = ((1000 * frameCount) / msecs)
	setText fpsReadout (join '' (round fps 0.1) ' fps')
	lastFrameTime = (msecsSinceStart)
	frameCount = 0
  }
}

// handle drops

method wantsDropOf ProjectEditor aHandler { return true }

method justReceivedDrop ProjectEditor aHandler {
  if (or (isAnyClass aHandler 'ColorPicker' 'Monitor') (hasField aHandler 'window')) {
	addPart (morph (global 'page')) (morph aHandler)
  } else {
	animateBackToOldOwner (hand (global 'page')) (morph aHandler)
  }
}

// developer mode

method developerModeChanged ProjectEditor {
  devModeParts = (copyFromTo rightItemsRow2 3)
  for p devModeParts {
	if (not (isNumber p)) {
	  if (devMode) {
		show (morph p)
	  } else {
		hide (morph p)
	  }
	}
  }
  developerModeChanged scripter
  fixLayout this
}

// layout

method normalStageSize ProjectEditor {
  scale = (global 'scale')
  viewerWidth = ((width (global 'page')) - (800 * scale))
  viewerWidth = (max viewerWidth (100 * scale))
  setExtent (morph viewer) viewerWidth nil
  fixStageLayout this
}

method pageResized ProjectEditor {
  scale = (global 'scale')
  page = (global 'page')
  newWidth = (width (morph page))
  if (viewerWidth > (newWidth / 2)) {
	viewerWidth = (truncate (newWidth / 2))
  }
  if (newWidth == (1280 * scale)) {
	viewerWidth = (560 * scale)
	setExtent (morph viewer) viewerWidth nil
  }
  viewerWidth = (max viewerWidth (235 * (global 'scale')))
  if (not (isVisible morph)) { // presentation mode
	scaleToFit stage (width page) (height page)
	gotoCenterOf (morph stage) (morph page)
  } else {
	drawTopBar this
	fixLayout this
  }
  if ('Win' == (platform)) {
	// workaround for a Windows graphics issue: when resizing a window it seems to clear
	// some or all textures. this forces them to be updated from the underlying bitmap.
	for m (allMorphs (morph page)) { costumeChanged m }
  }
}

method drawTopBar ProjectEditor {
  w = (width (morph (global 'page')))
  h = (48 * (global 'scale'))
  if ('iOS' == (platform)) { h += (13 * (global 'scale')) }
  oldC = (costume morph)
  if (or (isNil oldC) (w != (width oldC)) (h != (height oldC))) {
	setCostume morph (newBitmap w h (gray 200))
  if ('iOS' == (platform)) {
	fillRect (costumeData morph) (gray 255) 0 0 w (16 * (global 'scale')) }
  }
}

method fixLayout ProjectEditor {
  if (isNil tabs) { return }
  setBottom (morph tabs) ((height morph) + (2 * (global 'scale')))
  fixTopBarLayout this
  fixViewerLayout this
  fixStageLayout this
  fixLibraryLayout this
  viewerWidth = (width (morph viewer))
}

method fixTopBarLayout ProjectEditor {
  scale = (global 'scale')
  space = (5 * scale)
  centerTitle this
  setTop (morph title) (5 * scale)
  centerY = (17 * scale)
  if ('iOS' == (platform)) {
	setTop (morph title) (18 * scale)
	centerY += (13 * scale)
  }

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
  x = ((width morph) - (10 * scale))
  centerY += (20 * scale)
  if (devMode) {
	items = rightItemsRow2
  } else {
	items = (copyFromTo rightItemsRow2 1 2)
  }
  for item (reversed items) {
	if (isNumber item) {
	  x += (0 - item)
	} else {
	  m = (morph item)
	  if (isVisible m) {
		y = (centerY - ((height m) / 2))
		setPosition m (x - (width m)) y
		if (item == fpsReadout) {
		  x = (x - (8 * space))
		} else {
		  x = ((x - (width m)) - space)
		}
	  }
	}
  }
}

method fixViewerLayout ProjectEditor {
  m = (morph viewer)
  setPosition m 0 (bottom morph)
  maxW = (round (4096 / (global 'scale')))
  if ((width m) > maxW) {
	setExtent m maxW (height m)
	viewerWidth = maxW
  }
  newH = (max 1 ((height (morph (global 'page'))) - (top m)))
  if (newH != (height m)) {
	setExtent m viewerWidth newH
  }
}

method fixStageLayout ProjectEditor {
  viewerM = (morph viewer)
  pageM = (morph (global 'page'))
  newW = (max 1 ((width pageM) - (right viewerM)))
  newH = (max 1 ((height pageM) - (top viewerM)))
  scaleToFit stage newW newH
  setPosition (morph stage) (right viewerM) (bottom morph) true
}

method fixLibraryLayout ProjectEditor {
  viewerM = (morph viewer)
  stageM = (morph stage)
  pageM = (morph (global 'page'))
  setPosition (morph library) (right viewerM) (bottom stageM) true
  newH = (((height pageM) - (top viewerM)) - (height stageM))
  setExtent (morph library) (width stageM) newH
}
