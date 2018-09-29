// Stage.gp - Application stage

defineClass Stage morph color backgroundImage project

method backgroundImage Stage { return backgroundImage }
method color Stage { return color }
method project Stage { return project }
method setProject Stage p { project = p }

method setBackgroundImage Stage bm {
  backgroundImage = bm
  setColor this color // redraws background
}

method setColor Stage aColor {
  if (isNil aColor) { aColor = (gray 240) }
  color = aColor
  costume = (costumeData morph)
  fill costume color
  if (notNil backgroundImage) {
	x = (half ((width costume) - (width backgroundImage)))
	y = (half ((height costume) - (height backgroundImage)))
	drawBitmap costume backgroundImage x y
  }
  updateCostume morph
}

to newStage w h {
  return (initialize (new 'Stage') w h)
}

method initialize Stage w h {
  morph = (newMorph this)
  setClipping morph true
  setTransparentTouch morph true
  color = (gray 240)
  setAspectRatio this w h
  return this
}

method setAspectRatio Stage w h {
  majorAxis = 800
  if (or (isNil w) (isNil h)) {
	w = 16
	h = 10
  }
  if (w > h) {
	newW = majorAxis
    newH = (round ((h * majorAxis) / w) 2)
  } else {
	newW = (round ((w * majorAxis) / h) 2)
	newH = majorAxis
  }
  oldW = (width morph)
  oldH = (height morph)
  bm = (costumeData morph)
  if (or (isNil bm) ((width bm) != newW) ((height bm) != newH)) {
	setCostume morph (newBitmap newW newH color)
  }
  if (or (oldW == 0) (oldH == 0)) {
	oldW = newW
	oldH = newH
  }
  scaleToFit this oldW oldH
}

method scaleToFit Stage w h {
  bm = (costumeData morph)
  newScale = (min (w / (width bm)) (h / (height bm)))
  if (or (newScale != (scaleX morph)) (newScale != (scaleY morph))) {
    setScale morph newScale
  }
}

method wantsDropOf Stage aHandler {
  if (isAnyClass aHandler 'Block' 'ColorPicker') { return false }
  if (and (hasField aHandler 'window') (isClass (getField aHandler 'window') 'Window')) {
	return false
  }
  return true
}

// load/unload

method openProjectFromFile Stage fileName {
  // Open a project with the give file path or URL.
  // First try reading the project from the embedded file system.
  // If that does not exist, try to read it from app's directory.

  data = (readEmbeddedFile fileName true)
  if (isNil data) {
	prefix = (appPath)
	i = (findLast prefix '/')
	prefix = (substring prefix 1 (i - 1))
	fileName = (join prefix '/' fileName)
	data = (readFile fileName true)
  }
  if (isNil data) {
	error (join 'Could not read: ' fileName)
  }
  openProject this data
}

method openProject Stage projectData {
  page = (global 'page')
  setColor page (gray 0)
  addPart page morph
  scaleToFit this (width page) (height page)
  gotoCenterOf morph (morph page)
  if (notNil (focus (keyboard page))) {
	cancel (focus (keyboard page))
	focusOn (keyboard page) nil
  }
  project = (readProject (emptyProject) projectData)
  loadPage this (first (pages project))
}

method loadPage Stage projectPage {
  // Add the morphs of the given page to the stage.

  stageScale = (scale morph)
  originX = (hCenter (bounds morph))
  originY = (vCenter (bounds morph))
  removeAllParts morph
  for m (morphs projectPage) {
	postSerialize m
	p = (rotationCenter m)
	x = (originX + (stageScale * (first p)))
	y = (originY + (stageScale * (last p)))
	setScale m ((scale m) * stageScale)
	if (isClass (handler m) 'Monitor') { fixLayout (handler m) }
	placeRotationCenter m x y
	addPart morph m
  }
}

method unloadPage Stage projectPage {
  // Remove all morphs from the stage and save them in the given page.

  stageScale = (scale morph)
  originX = (hCenter (bounds morph))
  originY = (vCenter (bounds morph))
  mlist = (toArray (parts morph))
  for m mlist {
	removePart morph m
	p = (rotationCenter m)
	x = (((first p) - originX) / stageScale)
	y = (((last p) - originY) / stageScale)
	setScale m ((scale m) / stageScale)
	placeRotationCenter m x y
	preSerialize m
  }
  setMorphs projectPage mlist
}

// window resizing

method pageResized Stage {
  page = (global 'page')
  scaleToFit this (width page) (height page)
  gotoCenterOf morph (morph page)
  if ('Win' == (platform)) {
	// workaround for a Windows graphics issue: when resizing a window it seems to clear
	// some or all textures. this forces them to be updated from the underlying bitmap.
	for m (allMorphs (morph page)) { costumeChanged m }
  }
  if (and ('iOS' == (platform)) ((height page) > (width page)) (isPresenting this)) {
	setTop morph (100 * (global 'scale'))
	showKeyboard true
  }
}

// menu

method rightClicked Stage {
  if (isPresenting this) {
	menu = (presentationModeMenu this)
  } else {
	menu = (scriptingModeMenu this)
  }
  popUpAtHand menu (global 'page')
  return true
}

method isPresenting Stage {
  return (isClass (handler (owner morph)) 'Page')
}

method presentationModeMenu Stage {
  page = (global 'page')
  menu = (menu 'Presentation Menu' page)
  addItem menu 'broadcast "go"' 'broadcastGo'
  addItem menu 'stop all' 'stopAll' 'halt all currently running threads'
  if (hasEditor this) {
	addLine menu
	addItem menu 'exit presentation mode' (action 'exitPresentationMode' this) 'return to the project editor'
  }
  return menu
}

method hasEditor Stage {
  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'ProjectEditor') {
	  return true
	}
  }
  return false
}

method exitPresentationMode Stage {
  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'ProjectEditor') {
	  exitPresentation (handler m)
	  return
	}
  }
}

method scriptingModeMenu Stage {
  page = (global 'page')
  menu = (menu 'Stage Menu' page)
  addItem menu 'GP version...' 'showGPVersion'
  addLine menu
  addItem menu 'show all' (action 'showAll' this) 'move any offscreen objects back into view'
  addItem menu 'normal stage size' (action 'normalStageSize' this) 'make the stage be normal size'
  addItem menu 'grab image from screen' (action 'grabImageFromScreen' this) 'copy a part of of this window as an image'
  addLine menu
  addItem menu 'load extension...' (action 'loadExtension' this) 'load GP extension file'
  addLine menu
  if (not (devMode)) {
	addItem menu 'enter developer mode' 'enterDeveloperMode'
  } else {
	addItem menu 'exit developer mode' 'exitDeveloperMode'
	addLine menu
	addItem menu 'workspace...' 'openWorkspace' 'open a text window'
	addItem menu 'presentation...' 'openPresentation' 'open a window for presenting big, centered text'
	addItem menu 'system palette...' (action 'openSystemPalette' nil) 'open a palette of blocks for all methods in the system'
	addItem menu 'Parts Bin...' (action 'openPartsBin' 'runtime/parts/') 'Open the Parts Viewer'
	addLine menu
	addItem menu 'load source file...' (action 'loadSourceFile' this) '(re)load a .gp source file'
	addLine menu
	addItem menu 'benchmark...' 'runBenchmarks' 'run some simple compute-speed benchmarks'
	addItem menu 'start profiling' 'startProfiling'
	addItem menu 'end profiling' 'endProfiling'
	addLine menu
	if (vectorTrails) {
	  addItem menu 'use sharp-edged pen' 'toggleVectorTrails'
	} else {
	  addItem menu 'use smooth-edged pen' 'toggleVectorTrails'
	}
// 	if (fakeVectors) {
// 	  addItem menu 'use vector primitives' 'toggleFakeVectors'
// 	} else {
// 	  addItem menu 'simulate vector primitives' 'toggleFakeVectors'
// 	}
	addItem menu 'resize window to 720p' (action 'setWindowSize' (global 'page') 1280 720)
//	addItem menu 'resize window to 780p' (action 'setWindowSize' (global 'page') 1038 778)
  }
  addLine menu
  addItem menu 'quit' 'confirmToQuit'
  return menu
}

method showAll Stage {
  for m (parts morph) {
    keepWithin m (bounds morph)
    setAlpha m 255
	show m
  }
}

method normalStageSize Stage {
  editor = (handler (owner morph))
  if (isClass editor 'ProjectEditor') {
	normalStageSize editor
  }
}

method loadExtension Stage {
  pickFileToOpen (action 'loadExtensionFileNamed' this) (gpFolder)  (array '.gpp' '.gpe')
}

method loadExtensionFileNamed Stage fName {
  // Load an extension with the give full path name.

  editor = (ownerThatIsA morph 'ProjectEditor')
  if (isNil editor) { return }
  editor = (handler editor)

  data = (readFile fName true)
  if (isNil data) {
	error (join 'Could not read: ' fName)
  }
  extProject = (readProject (new 'Project') data)
  projName = (withoutExtension (filePart fName))
  importExtension (project editor) projName extProject
  developerModeChanged editor // update palette
}

method loadSourceFile Stage {
  pickFileToOpen (action 'reloadSourceFileNamed' this) (gpFolder) '.gp'
}

method reloadSourceFileNamed Stage fName {
  // Reload a source with the give full path name.

  reload fName
  editor = (ownerThatIsA morph 'ProjectEditor')
  if (notNil editor) {
	developerModeChanged (scripter (handler editor)) // update block categories
  }
}

method grabImageFromScreen Stage {
  screenGrab (action 'imageGrabbed' this)
}

method imageGrabbed Stage bm {
  editor = (handler (owner morph))
  if (isClass editor 'ProjectEditor') {
	proj = (project editor)
	name = (uniqueNameNotIn (imageNames proj) 'screenshot')
	saveImageAs proj bm name
	inform (join name ' saved in "images" tab')
  }
}

// let the user switch between vector trails and conventional ones

to vectorTrails {return (!= false (global 'vectorTrails'))}
to toggleVectorTrails {setGlobal 'vectorTrails' (not (vectorTrails))}

to fakeVectors {return (== true (global 'fakeVectors'))}
to toggleFakeVectors {setGlobal 'fakeVectors' (not (fakeVectors))}
